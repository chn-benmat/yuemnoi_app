import json
import math
from fastapi import APIRouter, Header, HTTPException, status
from fastapi.responses import StreamingResponse

from app.application.dtos.chat_dto import ChatRequestDTO, ChatResponseDTO
from app.core.config import settings
from app.core.container import container
from app.core.logging import logger
from app.core.exceptions import AllLLMProvidersExhaustedException, DatabaseException, KnowledgeDocumentException, RuntimeConfigurationException
from app.domain.exceptions import GuidanceGenerationError

router = APIRouter()


def safe_error_code(error):
    if isinstance(error, (GuidanceGenerationError, RuntimeConfigurationException, AllLLMProvidersExhaustedException)):
        return error.code
    return "knowledge_unavailable" if isinstance(error, KnowledgeDocumentException) else "catalog_unavailable"


def verify_internal_key(x_internal_service_key: str = Header(default=None)):
    """Verifies X-Internal-Service-Key header if configured in settings."""
    if settings.INTERNAL_SERVICE_KEY:
        if not x_internal_service_key or x_internal_service_key != settings.INTERNAL_SERVICE_KEY:
            logger.warning("Unauthorized access attempt without valid X-Internal-Service-Key")
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or missing X-Internal-Service-Key",
            )


@router.post(
    "/chat",
    response_model=ChatResponseDTO,
    summary="Non-streaming chat endpoint returning complete JSON response",
)
async def chat_endpoint(
    request: ChatRequestDTO,
    x_internal_service_key: str = Header(default=None),
) -> ChatResponseDTO:
    verify_internal_key(x_internal_service_key)
    try:
        response = await container.process_chat_message_use_case.execute(request)
        return response
    except (GuidanceGenerationError, AllLLMProvidersExhaustedException, DatabaseException, KnowledgeDocumentException, RuntimeConfigurationException) as exc:
        code = safe_error_code(exc)
        retry = getattr(exc, "retry_after", None)
        headers = {"Retry-After": str(math.ceil(retry))} if retry is not None else None
        logger.warning("Chat guidance failed: %s", code)
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                            detail={"error_code": code}, headers=headers) from None
    except Exception as exc:
        logger.error("Chat processing failed: %s", type(exc).__name__)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={"error_code": "processing_failed"},
        )


@router.post(
    "/chat/stream",
    summary="Server-Sent Events (SSE) streaming endpoint for typewriter effect",
)
async def chat_stream_endpoint(
    request: ChatRequestDTO,
    x_internal_service_key: str = Header(default=None),
):
    verify_internal_key(x_internal_service_key)

    async def event_generator():
        try:
            async for sse_line in container.process_chat_message_use_case.execute_stream(request):
                yield sse_line.encode("utf-8")
        except (GuidanceGenerationError, AllLLMProvidersExhaustedException, DatabaseException, KnowledgeDocumentException, RuntimeConfigurationException) as exc:
            code = safe_error_code(exc)
            payload = {"error_code": code}
            if getattr(exc, "retry_after", None) is not None:
                payload["retry_after_seconds"] = math.ceil(exc.retry_after)
            logger.warning("Stream guidance failed: %s", code)
            yield f"event: error\ndata: {json.dumps(payload)}\n\n".encode("utf-8")
        except Exception as exc:
            logger.error("Stream processing failed: %s", type(exc).__name__)
            yield b'event: error\ndata: {"error_code": "stream_failed"}\n\n'

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
