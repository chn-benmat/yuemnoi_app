import json
import logging
import uvicorn
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import Any, List, Optional
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.agent.executor import AgentExecutor


agent_executor = AgentExecutor()
logger = logging.getLogger("uvicorn.error")

MAX_LOGGED_BODY_CHARS = 16 * 1024
SENSITIVE_LOG_KEY_FRAGMENTS = (
    "authorization",
    "password",
    "token",
    "otp",
    "secret",
    "api_key",
    "apikey",
    "email",
    "phone",
    "full_name",
    "fullname",
    "display_name",
    "displayname",
    "user_id",
    "userid",
    "user_image",
    "profile_image",
    "owner_id",
    "ownerid",
    "latitude",
    "longitude",
    "address",
    "service_role",
    "supabase_key",
    "serper_api",
)


def _is_sensitive_log_key(key: str) -> bool:
    normalized_key = key.lower()
    return any(
        fragment in normalized_key for fragment in SENSITIVE_LOG_KEY_FRAGMENTS
    )


def _redact_sensitive_log_values(value: Any) -> Any:
    if isinstance(value, dict):
        return {
            key: (
                "[REDACTED]"
                if _is_sensitive_log_key(str(key))
                else _redact_sensitive_log_values(child)
            )
            for key, child in value.items()
        }
    if isinstance(value, list):
        return [_redact_sensitive_log_values(child) for child in value]
    return value


def _safe_body_for_log(body: bytes, content_type: str) -> str:
    if not body:
        return "<empty>"
    if "json" not in content_type.lower():
        return f"<non-JSON body omitted: {len(body)} bytes>"

    try:
        payload = json.loads(body)
    except (UnicodeDecodeError, json.JSONDecodeError):
        return f"<invalid JSON body omitted: {len(body)} bytes>"

    serialized = json.dumps(
        _redact_sensitive_log_values(payload),
        ensure_ascii=False,
        separators=(",", ":"),
    )
    if len(serialized) > MAX_LOGGED_BODY_CHARS:
        return serialized[:MAX_LOGGED_BODY_CHARS] + "...<truncated>"
    return serialized


class RequestResponseLoggingMiddleware:
    def __init__(self, app: ASGIApp):
        self.app = app

    async def __call__(
        self,
        scope: Scope,
        receive: Receive,
        send: Send,
    ) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        request_body = bytearray()
        response_body = bytearray()
        response_status: int | str = "unhandled_exception"
        response_content_type = ""

        async def receive_with_logging() -> Message:
            message = await receive()
            if message["type"] == "http.request":
                request_body.extend(message.get("body", b""))
            return message

        async def send_with_logging(message: Message) -> None:
            nonlocal response_status, response_content_type
            if message["type"] == "http.response.start":
                response_status = message["status"]
                headers = {
                    key.decode("latin-1").lower(): value.decode("latin-1")
                    for key, value in message.get("headers", [])
                }
                response_content_type = headers.get("content-type", "")
            elif message["type"] == "http.response.body":
                response_body.extend(message.get("body", b""))
            await send(message)

        try:
            await self.app(scope, receive_with_logging, send_with_logging)
        finally:
            request_headers = {
                key.decode("latin-1").lower(): value.decode("latin-1")
                for key, value in scope.get("headers", [])
            }
            logger.info(
                "ai_http method=%s path=%s status=%s request_body=%s response_body=%s",
                scope.get("method", ""),
                scope.get("path", ""),
                response_status,
                _safe_body_for_log(
                    bytes(request_body),
                    request_headers.get("content-type", ""),
                ),
                _safe_body_for_log(bytes(response_body), response_content_type),
            )


@asynccontextmanager
async def lifespan(_app: FastAPI):
    await agent_executor.warmup_model()
    yield
    await agent_executor.aclose()


app = FastAPI(
    title="yuemnoi AI Core Service",
    version="1.1.0",
    lifespan=lifespan,
)

# เปิดสิทธิ์ CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(RequestResponseLoggingMiddleware)


@app.get("/health")
async def health_check():
    return {"status": "ok"}


class ChatMessage(BaseModel):
    role: str = Field(..., description="บทบาทผู้ส่ง: 'user' หรือ 'assistant'")
    content: str = Field(..., description="ข้อความแชท")


class ChatRequest(BaseModel):
    query: str = Field(
        ..., min_length=1, max_length=200, description="คำถามล่าสุดจากลูกค้า"
    )
    history: Optional[List[ChatMessage]] = Field(
        default_factory=list, description="ประวัติการสนทนาก่อนหน้านี้ทั้งหมด"
    )


@app.post("/api/ai/chat")
async def stream_ai_response(payload: ChatRequest):
    user_query = payload.query
    chat_history_list = [msg.model_dump() for msg in payload.history]

    # ส่งค่าทั้งคำถามใหม่และข้อความประวัติแชทเก่าเข้าไป Pipeline
    res = await agent_executor.run_pipeline_non_stream(
        user_query, history=chat_history_list
    )
    return res


if __name__ == "__main__":
    # สั่งรันเซิร์ฟเวอร์ AI ที่พอร์ต 8000 เป็นค่าตั้งต้น
    uvicorn.run(app, host="0.0.0.0", port=8000)
