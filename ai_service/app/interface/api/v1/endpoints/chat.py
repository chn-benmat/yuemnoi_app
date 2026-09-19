from fastapi import APIRouter, Header, HTTPException, status
from fastapi.responses import StreamingResponse

from app.application.dtos.chat_dto import ChatRequestDTO, ChatResponseDTO
from app.core.config import settings
from app.core.container import container
from app.core.logging import logger

router = APIRouter()


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
    except Exception as exc:
        logger.error(f"Error processing chat message: {exc}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Chat processing failed: {str(exc)}",
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
        except Exception as exc:
            logger.error(f"Error during stream generation: {exc}", exc_info=True)
            yield f'event: error\ndata: {{"error_code": "stream_failed", "detail": "{str(exc)}"}}\n\n'.encode("utf-8")

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
