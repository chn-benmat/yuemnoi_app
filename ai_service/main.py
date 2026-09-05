import json
import logging
from uuid import uuid4
from app.telemetry import request_id
import uvicorn
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from typing import List, Optional
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.agent.executor import AgentExecutor


agent_executor = AgentExecutor()
logger = logging.getLogger("uvicorn.error")

class RequestResponseLoggingMiddleware:
    def __init__(self, app: ASGIApp):
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        status = 500
        token = request_id.set(uuid4().hex)

        async def send_metadata(message: Message) -> None:
            nonlocal status
            if message["type"] == "http.response.start":
                status = message["status"]
            await send(message)

        try:
            await self.app(scope, receive, send_metadata)
        finally:
            logger.info("ai_http request_id=%s method=%s path=%s status=%s", request_id.get(), scope.get("method"), scope.get("path"), status)
            request_id.reset(token)


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
    chat_history_list = [msg.model_dump() for msg in (payload.history or [])]

    # ส่งค่าทั้งคำถามใหม่และข้อความประวัติแชทเก่าเข้าไป Pipeline
    res = await agent_executor.run_pipeline_non_stream(
        user_query, history=chat_history_list
    )
    return res


@app.post("/api/ai/chat/stream")
async def stream_ai_response_sse(payload: ChatRequest):
    user_query = payload.query
    chat_history_list = [msg.model_dump() for msg in (payload.history or [])]

    async def event_generator():
        async for event in agent_executor.run_pipeline_stream(
            user_query, history=chat_history_list
        ):
            event_name = event.get("event", "message")
            event_data = json.dumps(event.get("data", {}), ensure_ascii=False)
            yield f"event: {event_name}\ndata: {event_data}\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


class FeedbackRequest(BaseModel):
    message_id: str = Field(..., description="ID ของข้อความตอบกลับที่ต้องการให้ฟีดแบ็ก")
    user_query: str = Field(..., description="คำถามของผู้ใช้ที่นำไปสู่คำตอบนี้")
    ai_response: str = Field(..., description="ข้อความคำตอบของ AI")
    rating: int = Field(..., description="1 สำหรับถูกใจ (Thumbs Up), -1 สำหรับไม่ถูกใจ (Thumbs Down)")
    reason_category: Optional[str] = Field(None, description="หมวดหมู่เหตุผล เช่น 'incorrect_data', 'irrelevant_item', 'misunderstood', 'other'")
    feedback_comment: Optional[str] = Field(None, description="ข้อความความคิดเห็นเพิ่มเติมจากผู้ใช้")
    resolved_mode: Optional[str] = Field(None, description="โหมดของคำตอบ เช่น 'recommendation', 'faq', 'questionnaire'")
    user_id: Optional[str] = Field(None, description="ID ของผู้ใช้ (ถ้ามี)")
    session_id: Optional[str] = Field(None, description="Session ID (ถ้ามี)")


@app.post("/api/ai/feedback")
async def submit_feedback(payload: FeedbackRequest):
    result = await agent_executor.submit_feedback(payload.model_dump())
    return {"status": "success", "data": result}


@app.get("/api/ai/feedback/dpo-dataset")
async def get_dpo_dataset():
    dataset = await agent_executor.export_dpo()
    return {"status": "success", "count": len(dataset), "data": dataset}


if __name__ == "__main__":
    # สั่งรันเซิร์ฟเวอร์ AI ที่พอร์ต 8000 เป็นค่าตั้งต้น พร้อม auto-reload เมื่อโค้ดเปลี่ยนแปลง
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
