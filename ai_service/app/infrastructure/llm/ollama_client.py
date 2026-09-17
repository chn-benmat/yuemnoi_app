import json
import httpx
from typing import List, Optional, Type, TypeVar, AsyncIterator, Any
from pydantic import BaseModel
from app.domain.entities.chat import ChatMessage, ChatRole
from app.domain.interfaces.llm_service import LLMServiceInterface
from app.core.config import Settings
from app.core.exceptions import LLMServiceException
from app.core.logging import logger

T = TypeVar("T", bound=BaseModel)

class OllamaClient(LLMServiceInterface):
    """Client for local Ollama instance running Typhoon 2.5 (Qwen3)."""

    def __init__(self, settings: Settings):
        self.base_url = settings.OLLAMA_BASE_URL.rstrip('/')
        self.model = settings.OLLAMA_MODEL
        self.num_ctx = settings.OLLAMA_NUM_CTX
        self.default_temp = settings.OLLAMA_TEMPERATURE
        self.repeat_penalty = getattr(settings, "OLLAMA_REPEAT_PENALTY", 1.05)
        self.timeout = settings.OLLAMA_TIMEOUT

    def _clean_json_output(self, text: str) -> str:
        """Strip markdown json code blocks if present without regex."""
        cleaned = text.strip()
        if cleaned.startswith("```json"):
            cleaned = cleaned[7:]
        elif cleaned.startswith("```"):
            cleaned = cleaned[3:]
        if cleaned.endswith("```"):
            cleaned = cleaned[:-3]
        return cleaned.strip()

    async def generate_text(
        self,
        prompt: str,
        system_instruction: Optional[str] = None,
        temperature: float = 0.7
    ) -> str:
        url = f"{self.base_url}/api/generate"
        payload = {
            "model": self.model,
            "prompt": prompt,
            "system": system_instruction or "",
            "stream": False,
            "options": {
                "temperature": temperature,
                "num_ctx": self.num_ctx,
                "repeat_penalty": self.repeat_penalty
            }
        }
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                resp = await client.post(url, json=payload)
                resp.raise_for_status()
                data = resp.json()
                return data.get("response", "").strip()
        except Exception as e:
            logger.error(f"Ollama generate_text failed: {e}")
            raise LLMServiceException(f"Error in Ollama text generation: {e}") from e

    async def generate_structured(
        self,
        prompt: str,
        response_model: Type[T],
        system_instruction: Optional[str] = None,
        temperature: float = 0.2
    ) -> T:
        url = f"{self.base_url}/api/generate"
        schema = response_model.model_json_schema()
        payload = {
            "model": self.model,
            "prompt": prompt,
            "system": system_instruction or "",
            "stream": False,
            "format": schema,
            "options": {
                "temperature": temperature,
                "num_ctx": self.num_ctx,
                "repeat_penalty": self.repeat_penalty
            }
        }
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                resp = await client.post(url, json=payload)
                resp.raise_for_status()
                data = resp.json()
                raw_response = data.get("response", "")
                cleaned_json = self._clean_json_output(raw_response)
                return response_model.model_validate_json(cleaned_json)
        except Exception as e:
            logger.error(f"Ollama generate_structured failed for {response_model.__name__}: {e}")
            # Fallback attempt with standard JSON mode if schema format had strictness issues
            try:
                payload["format"] = "json"
                async with httpx.AsyncClient(timeout=self.timeout) as client:
                    resp = await client.post(url, json=payload)
                    resp.raise_for_status()
                    data = resp.json()
                    raw_response = data.get("response", "")
                    cleaned_json = self._clean_json_output(raw_response)
                    return response_model.model_validate_json(cleaned_json)
            except Exception as fallback_err:
                logger.error(f"Fallback structured generation also failed: {fallback_err}")
                raise LLMServiceException(f"Failed to generate structured output: {e}") from e

    async def generate_chat(
        self,
        messages: List[ChatMessage],
        system_instruction: Optional[str] = None,
        temperature: float = 0.7
    ) -> str:
        url = f"{self.base_url}/api/chat"
        formatted_messages = []
        if system_instruction:
            formatted_messages.append({
                "role": "system",
                "content": system_instruction
            })
        for msg in messages:
            formatted_messages.append({
                "role": msg.role.value,
                "content": msg.content
            })

        payload = {
            "model": self.model,
            "messages": formatted_messages,
            "stream": False,
            "options": {
                "temperature": temperature,
                "num_ctx": self.num_ctx,
                "repeat_penalty": self.repeat_penalty
            }
        }

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                resp = await client.post(url, json=payload)
                resp.raise_for_status()
                data = resp.json()
                return data.get("message", {}).get("content", "").strip()
        except Exception as e:
            logger.error(f"Ollama generate_chat failed: {e}")
            raise LLMServiceException(f"Error in Ollama chat generation: {e}") from e

    async def generate_chat_stream(
        self,
        messages: List[ChatMessage],
        system_instruction: Optional[str] = None,
        temperature: float = 0.7
    ) -> AsyncIterator[str]:
        url = f"{self.base_url}/api/chat"
        formatted_messages = []
        if system_instruction:
            formatted_messages.append({
                "role": "system",
                "content": system_instruction
            })
        for msg in messages:
            formatted_messages.append({
                "role": msg.role.value,
                "content": msg.content
            })

        payload = {
            "model": self.model,
            "messages": formatted_messages,
            "stream": True,
            "options": {
                "temperature": temperature,
                "num_ctx": self.num_ctx,
                "repeat_penalty": self.repeat_penalty
            }
        }

        async with httpx.AsyncClient(timeout=self.timeout) as client:
            async with client.stream("POST", url, json=payload) as response:
                response.raise_for_status()
                async for line in response.aiter_lines():
                    if not line:
                        continue
                    try:
                        chunk = json.loads(line)
                        content = chunk.get("message", {}).get("content", "")
                        if content:
                            yield content
                    except json.JSONDecodeError:
                        continue
