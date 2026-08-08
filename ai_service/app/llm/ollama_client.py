from typing import Any

import httpx

from config import settings


class OllamaClient:
    """Small wrapper around Ollama's native API with fast local defaults."""

    def __init__(self, client: httpx.AsyncClient):
        self.client = client
        base_url = settings.OLLAMA_ENDPOINT.rstrip("/")
        if base_url.endswith("/v1"):
            base_url = base_url[:-3]
        self.api_url = f"{base_url}/api/chat"

    async def warmup(self) -> None:
        """Load the model before the first user request."""
        response = await self.client.post(
            self.api_url,
            json={
                "model": settings.MODEL_NAME,
                "messages": [],
                "stream": False,
                "keep_alive": settings.OLLAMA_KEEP_ALIVE,
            },
            timeout=120.0,
        )
        response.raise_for_status()

    async def chat_json(
        self,
        *,
        messages: list[dict[str, Any]],
        schema: dict[str, Any],
        max_tokens: int,
        timeout: float,
    ) -> str:
        response = await self.client.post(
            self.api_url,
            json={
                "model": settings.MODEL_NAME,
                "messages": messages,
                "stream": False,
                "think": False,
                "keep_alive": settings.OLLAMA_KEEP_ALIVE,
                "format": schema,
                "options": {
                    "temperature": 0.0,
                    "num_ctx": settings.OLLAMA_CONTEXT_LENGTH,
                    "num_predict": max_tokens,
                    "seed": 0,
                },
            },
            timeout=timeout,
        )
        response.raise_for_status()
        result = response.json()
        return result.get("message", {}).get("content", "").strip()

    async def chat_with_tools(
        self,
        *,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]],
        max_tokens: int,
        timeout: float,
    ) -> dict[str, Any]:
        response = await self.client.post(
            self.api_url,
            json={
                "model": settings.MODEL_NAME,
                "messages": messages,
                "tools": tools,
                "stream": False,
                "think": False,
                "keep_alive": settings.OLLAMA_KEEP_ALIVE,
                "options": {
                    "temperature": 0.0,
                    "num_ctx": settings.OLLAMA_CONTEXT_LENGTH,
                    "num_predict": max_tokens,
                    "seed": 0,
                },
            },
            timeout=timeout,
        )
        response.raise_for_status()
        result = response.json()
        return result.get("message", {})
