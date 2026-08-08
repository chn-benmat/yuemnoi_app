import uvicorn
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import List, Optional

from app.agent.executor import AgentExecutor


agent_executor = AgentExecutor()


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
