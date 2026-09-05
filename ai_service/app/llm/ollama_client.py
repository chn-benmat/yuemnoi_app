import logging
from typing import Any, AsyncGenerator, Dict, List, Optional, Union
import json
import httpx

from config import settings

logger = logging.getLogger("uvicorn.error")


class OllamaClient:
    """Fast, reliable client for local Ollama models (e.g. qwen3:8b)."""

    def __init__(self, client: httpx.AsyncClient):
        self.client = client
        base_url = settings.OLLAMA_ENDPOINT.rstrip("/")
        if base_url.endswith("/v1"):
            base_url = base_url[:-3]
        self.api_url = f"{base_url}/api/chat"

    async def warmup(self) -> None:
        """Pre-load model into GPU/RAM memory on startup."""
        try:
            response = await self.client.post(
                self.api_url,
                json={
                    "model": settings.MODEL_NAME,
                    "messages": [{"role": "user", "content": "hi"}],
                    "stream": False,
                    "think": False,
                    "keep_alive": settings.OLLAMA_KEEP_ALIVE,
                    "options": {
                        "num_predict": 5,
                        "num_ctx": settings.OLLAMA_CONTEXT_LENGTH,
                    },
                },
                timeout=60.0,
            )
            response.raise_for_status()
            logger.info("Ollama model %s warmed up successfully.", settings.MODEL_NAME)
        except Exception as e:
            logger.warning("Ollama warmup warning: %s", e)

    async def chat(
        self,
        *,
        messages: List[Dict[str, Any]],
        format: Optional[Union[str, Dict[str, Any]]] = "json",
        max_tokens: int = 1500,
        temperature: float = 0.3,
        timeout: float = 45.0,
        think: bool = False,
    ) -> str:
        """Send chat messages and get response from Ollama model."""
        payload: Dict[str, Any] = {
            "model": settings.MODEL_NAME,
            "messages": messages,
            "stream": False,
            "think": think,
            "keep_alive": settings.OLLAMA_KEEP_ALIVE,
            "options": {
                "temperature": temperature,
                "num_ctx": settings.OLLAMA_CONTEXT_LENGTH,
                "num_predict": max_tokens,
            },
        }
        if format:
            payload["format"] = format

        response = await self.client.post(
            self.api_url,
            json=payload,
            timeout=timeout,
        )
        response.raise_for_status()
        result = response.json()
        content = result.get("message", {}).get("content", "").strip()
        return content

    async def stream_chat(
        self,
        *,
        messages: List[Dict[str, Any]],
        format: Optional[Union[str, Dict[str, Any]]] = "json",
        max_tokens: int = 1500,
        temperature: float = 0.3,
        timeout: float = 45.0,
        think: bool = False,
    ) -> AsyncGenerator[str, None]:
        """Send chat messages and stream response chunks from Ollama model."""
        payload: Dict[str, Any] = {
            "model": settings.MODEL_NAME,
            "messages": messages,
            "stream": True,
            "think": think,
            "keep_alive": settings.OLLAMA_KEEP_ALIVE,
            "options": {
                "temperature": temperature,
                "num_ctx": settings.OLLAMA_CONTEXT_LENGTH,
                "num_predict": max_tokens,
            },
        }
        if format:
            payload["format"] = format

        async with self.client.stream(
            "POST",
            self.api_url,
            json=payload,
            timeout=timeout,
        ) as response:
            response.raise_for_status()
            async for line in response.aiter_lines():
                if not line:
                    continue
                try:
                    chunk_data = json.loads(line)
                    content = chunk_data.get("message", {}).get("content", "")
                    if content:
                        yield content
                except Exception:
                    continue
