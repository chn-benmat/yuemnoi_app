import json
from typing import AsyncGenerator, Optional, Type, TypeVar
import httpx
from pydantic import BaseModel

from app.core.config import settings
from app.core.exceptions import LLMProviderException
from app.core.logging import logger

T = TypeVar("T", bound=BaseModel)


def _sanitize_gemini_schema(schema: dict) -> dict:
    """Dereferences $defs and cleans schema for Gemini REST API OpenAPI subset."""
    import copy
    s = copy.deepcopy(schema)
    defs = s.pop("$defs", {})

    def resolve(obj):
        if isinstance(obj, dict):
            if "$ref" in obj:
                ref_name = obj["$ref"].split("/")[-1]
                if ref_name in defs:
                    resolved = copy.deepcopy(defs[ref_name])
                    return resolve(resolved)
            cleaned = {}
            for k, v in obj.items():
                if k in ("title", "default"):
                    continue
                cleaned[k] = resolve(v)
            return cleaned
        elif isinstance(obj, list):
            return [resolve(item) for item in obj]
        return obj

    return resolve(s)


class GeminiClient:
    """Asynchronous client for Google Gemini REST API."""

    BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models"

    def __init__(self, api_key: Optional[str] = None, timeout: float = 25.0):
        self._api_key = api_key or settings.GEMINI_API_KEY
        self._timeout = timeout

    def _build_payload(
        self,
        prompt: str,
        system_instruction: Optional[str] = None,
        max_tokens: int = 1000,
        temperature: float = 0.7,
        response_schema: Optional[dict] = None,
    ) -> dict:
        payload = {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {
                "temperature": temperature,
                "maxOutputTokens": max_tokens,
            },
        }
        if system_instruction:
            payload["systemInstruction"] = {"parts": [{"text": system_instruction}]}
        if response_schema:
            payload["generationConfig"]["responseMimeType"] = "application/json"
            payload["generationConfig"]["responseSchema"] = _sanitize_gemini_schema(response_schema)
        return payload

    async def generate_text(
        self,
        model: str,
        prompt: str,
        system_instruction: Optional[str] = None,
        max_tokens: int = 1000,
        temperature: float = 0.7,
    ) -> str:
        url = f"{self.BASE_URL}/{model}:generateContent?key={self._api_key}"
        payload = self._build_payload(prompt, system_instruction, max_tokens, temperature)
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            resp = await client.post(url, json=payload)
            if resp.status_code != 200:
                raise LLMProviderException("Gemini", model, resp.text, status_code=resp.status_code)
            data = resp.json()
            try:
                return data["candidates"][0]["content"]["parts"][0]["text"]
            except (KeyError, IndexError) as exc:
                raise LLMProviderException("Gemini", model, f"Unexpected response format: {data}") from exc

    async def generate_structured(
        self,
        model: str,
        prompt: str,
        schema: Type[T],
        system_instruction: Optional[str] = None,
        temperature: float = 0.2,
    ) -> T:
        url = f"{self.BASE_URL}/{model}:generateContent?key={self._api_key}"
        schema_dict = schema.model_json_schema()
        payload = self._build_payload(
            prompt,
            system_instruction,
            max_tokens=1500,
            temperature=temperature,
            response_schema=schema_dict,
        )
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            resp = await client.post(url, json=payload)
            # If 400 Bad Request on responseSchema, fallback to pure JSON mode with schema in prompt
            if resp.status_code == 400 and "response_schema" in resp.text.lower():
                logger.info(f"Gemini schema rejected, retrying with json prompt mode for {model}")
                schema_json = json.dumps(schema_dict, ensure_ascii=False)
                fallback_sys = (
                    f"{system_instruction}\n" if system_instruction else ""
                ) + f"You MUST reply with a JSON object matching this schema:\n{schema_json}"
                fallback_payload = {
                    "contents": [{"parts": [{"text": prompt}]}],
                    "systemInstruction": {"parts": [{"text": fallback_sys}]},
                    "generationConfig": {
                        "temperature": temperature,
                        "maxOutputTokens": 1500,
                        "responseMimeType": "application/json",
                    },
                }
                resp = await client.post(url, json=fallback_payload)

            if resp.status_code != 200:
                raise LLMProviderException("Gemini", model, resp.text, status_code=resp.status_code)
            data = resp.json()
            try:
                raw_text = data["candidates"][0]["content"]["parts"][0]["text"]
                return schema.model_validate_json(raw_text)
            except Exception as exc:
                raise LLMProviderException("Gemini", model, f"Schema validation error: {exc}") from exc

    async def generate_stream(
        self,
        model: str,
        prompt: str,
        system_instruction: Optional[str] = None,
        max_tokens: int = 1500,
        temperature: float = 0.7,
    ) -> AsyncGenerator[str, None]:
        url = f"{self.BASE_URL}/{model}:streamGenerateContent?alt=sse&key={self._api_key}"
        payload = self._build_payload(prompt, system_instruction, max_tokens, temperature)
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            async with client.stream("POST", url, json=payload) as resp:
                if resp.status_code != 200:
                    err_body = await resp.aread()
                    raise LLMProviderException("Gemini", model, err_body.decode(errors="ignore"), status_code=resp.status_code)
                async for line in resp.aiter_lines():
                    trimmed = line.strip()
                    if trimmed.startswith("data:"):
                        raw_data = trimmed[5:].strip()
                        if not raw_data or raw_data == "[DONE]":
                            continue
                        try:
                            parsed = json.loads(raw_data)
                            candidates = parsed.get("candidates", [])
                            if candidates:
                                parts = candidates[0].get("content", {}).get("parts", [])
                                for p in parts:
                                    text = p.get("text", "")
                                    if text:
                                        yield text
                        except Exception:
                            continue
