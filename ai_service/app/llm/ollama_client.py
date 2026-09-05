from typing import Any

import httpx

from config import settings
from ..telemetry import logger, request_id, model_calls


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
                "options": {
                    "num_ctx": settings.OLLAMA_CONTEXT_LENGTH,
                },
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
        think: bool = False,
    ) -> str:
        model_calls.set(model_calls.get() + 1)
        response = await self.client.post(
            self.api_url,
            json={
                "model": settings.MODEL_NAME,
                "messages": messages,
                "stream": False,
                "think": think,
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
        metrics = {key: result.get(key) for key in ("load_duration", "prompt_eval_duration", "eval_duration", "prompt_eval_count", "eval_count", "done_reason")}
        logger.info("ai_model request_id=%s metrics=%s", request_id.get(), metrics)
        if not result.get("done") or result.get("done_reason") == "length":
            raise ValueError("Incomplete model response")
        return result.get("message", {}).get("content", "").strip()
