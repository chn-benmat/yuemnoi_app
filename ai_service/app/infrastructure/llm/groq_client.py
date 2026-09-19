import json
from typing import AsyncGenerator, Optional, Type, TypeVar
import httpx
from pydantic import BaseModel

from app.core.config import settings
from app.core.exceptions import LLMProviderException
from app.core.logging import logger

T = TypeVar("T", bound=BaseModel)


class GroqClient:
    """Asynchronous client for Groq OpenAI-compatible REST API."""

    URL = "https://api.groq.com/openai/v1/chat/completions"

    def __init__(self, api_key: Optional[str] = None, timeout: float = 25.0):
        self._api_key = api_key or settings.GROQ_API_KEY
        self._timeout = timeout

    def _headers(self) -> dict:
        return {
            "Authorization": f"Bearer {self._api_key}",
            "Content-Type": "application/json",
            "User-Agent": "Yuemnoi-AI-Service/1.0",
        }

    async def generate_text(
        self,
        model: str,
        prompt: str,
        system_instruction: Optional[str] = None,
        max_tokens: int = 1000,
        temperature: float = 0.7,
    ) -> str:
        messages = []
        if system_instruction:
            messages.append({"role": "system", "content": system_instruction})
        messages.append({"role": "user", "content": prompt})

        payload = {
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
        }

        async with httpx.AsyncClient(timeout=self._timeout) as client:
            resp = await client.post(self.URL, json=payload, headers=self._headers())
            if resp.status_code != 200:
                raise LLMProviderException("Groq", model, resp.text, status_code=resp.status_code)
            data = resp.json()
            try:
                return data["choices"][0]["message"]["content"]
            except (KeyError, IndexError) as exc:
                raise LLMProviderException("Groq", model, f"Unexpected response format: {data}") from exc

    async def generate_structured(
        self,
        model: str,
        prompt: str,
        schema: Type[T],
        system_instruction: Optional[str] = None,
        temperature: float = 0.2,
    ) -> T:
        schema_json = json.dumps(schema.model_json_schema(), ensure_ascii=False)
        sys_prompt = (
            f"{system_instruction}\n" if system_instruction else ""
        ) + f"You MUST respond ONLY with a valid JSON object strictly matching this schema:\n{schema_json}"

        messages = [
            {"role": "system", "content": sys_prompt},
            {"role": "user", "content": prompt},
        ]

        payload = {
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": 1500,
            "response_format": {"type": "json_object"},
        }

        async with httpx.AsyncClient(timeout=self._timeout) as client:
            resp = await client.post(self.URL, json=payload, headers=self._headers())
            if resp.status_code != 200:
                raise LLMProviderException("Groq", model, resp.text, status_code=resp.status_code)
            data = resp.json()
            try:
                raw_text = data["choices"][0]["message"]["content"]
                return schema.model_validate_json(raw_text)
            except Exception as exc:
                raise LLMProviderException("Groq", model, f"Schema validation error: {exc}") from exc

    async def generate_stream(
        self,
        model: str,
        prompt: str,
        system_instruction: Optional[str] = None,
        max_tokens: int = 1500,
        temperature: float = 0.7,
    ) -> AsyncGenerator[str, None]:
        messages = []
        if system_instruction:
            messages.append({"role": "system", "content": system_instruction})
        messages.append({"role": "user", "content": prompt})

        payload = {
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
            "stream": True,
        }

        async with httpx.AsyncClient(timeout=self._timeout) as client:
            async with client.stream("POST", self.URL, json=payload, headers=self._headers()) as resp:
                if resp.status_code != 200:
                    err_body = await resp.aread()
                    raise LLMProviderException("Groq", model, err_body.decode(errors="ignore"), status_code=resp.status_code)
                async for line in resp.aiter_lines():
                    trimmed = line.strip()
                    if trimmed.startswith("data:"):
                        raw_data = trimmed[5:].strip()
                        if not raw_data or raw_data == "[DONE]":
                            continue
                        try:
                            parsed = json.loads(raw_data)
                            choices = parsed.get("choices", [])
                            if choices:
                                delta = choices[0].get("delta", {})
                                text = delta.get("content", "")
                                if text:
                                    yield text
                        except Exception:
                            continue
