import logging
from typing import Any, AsyncGenerator, Dict, List, Optional
import httpx

from config import settings
from .service import YuemnoiConsultantService
from ..llm.ollama_client import OllamaClient
from ..tools.database_tool import DatabaseTool
from ..tools.google_tool import GoogleTool

logger = logging.getLogger("uvicorn.error")


from ..learning.feedback_store import FeedbackStore


class AgentExecutor:
    """
    Streamlined facade wrapping YuemnoiConsultantService.
    Provides backward-compatible interface for main.py.
    """

    def __init__(self):
        self._http_client: Optional[httpx.AsyncClient] = None
        self._service: Optional[YuemnoiConsultantService] = None

    def _ensure_initialized(self) -> YuemnoiConsultantService:
        if self._service is None or self._http_client is None:
            self._http_client = httpx.AsyncClient(timeout=45.0)
            ollama = OllamaClient(self._http_client)
            db_tool = DatabaseTool(self._http_client)
            feedback_store = FeedbackStore(self._http_client)
            google_tool = GoogleTool(self._http_client)
            self._service = YuemnoiConsultantService(
                ollama=ollama,
                db_tool=db_tool,
                feedback_store=feedback_store,
                google_tool=google_tool,
            )
        return self._service

    async def warmup_model(self) -> None:
        """Pre-warmup model on server launch."""
        service = self._ensure_initialized()
        logger.info("Warming up %s model on %s...", settings.MODEL_NAME, settings.OLLAMA_ENDPOINT)
        await service.ollama.warmup()
        try:
            items = await service.db_tool.list_available_items(force_refresh=True)
            logger.info("Loaded %d available items from Supabase.", len(items))
        except Exception as e:
            logger.warning("Initial catalog loading notice: %s", e)

    async def aclose(self) -> None:
        """Clean up HTTP connections on shutdown."""
        if self._http_client is not None and not self._http_client.is_closed:
            await self._http_client.aclose()
            logger.info("AgentExecutor HTTP client closed.")

    async def run_pipeline_non_stream(
        self,
        user_query: str,
        history: Optional[List[Dict[str, str]]] = None,
    ) -> Dict[str, Any]:
        """Main chat endpoint method."""
        service = self._ensure_initialized()
        return await service.process_chat(query=user_query, history=history)

    async def run_pipeline_stream(
        self,
        user_query: str,
        history: Optional[List[Dict[str, str]]] = None,
    ) -> AsyncGenerator[Dict[str, Any], None]:
        """Streaming chat endpoint generator."""
        service = self._ensure_initialized()
        async for event in service.process_chat_stream(query=user_query, history=history):
            yield event

    async def submit_feedback(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Submits feedback and updates in-context learning store."""
        service = self._ensure_initialized()
        if service.feedback_store:
            return await service.feedback_store.save_feedback(**data)
        return {"status": "ok"}

    async def export_dpo(self) -> List[Dict[str, Any]]:
        """Exports DPO preference dataset."""
        service = self._ensure_initialized()
        if service.feedback_store:
            return await service.feedback_store.export_dpo_dataset()
        return []
