# main.py
import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from app.agent.executor import AgentExecutor

app = FastAPI(title="yuemnoi AI Core Service", version="1.0.0")

# เปิดสิทธิ์ CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ประกาศโครงสร้างการรับข้อมูล Input
class ChatRequest(BaseModel):
    query: str


# เรียกโครงสร้างตัวรัน Pipeline ขึ้นมาเตรียมไว้
agent_executor = AgentExecutor()


@app.post("/api/ai/chat")
async def stream_ai_response(request: ChatRequest):
    """
    Endpoint ตัวหลักสำหรับรับคำถามเรื่องการขอยืมอุปกรณ์
    จะทำการส่งผ่านการประมวลผลออกไปในรูปแบบ Server-Sent Events (SSE) ตัวต่อตัว
    """
    return StreamingResponse(
        agent_executor.run_pipeline(request.query), media_type="text/event-stream"
    )


if __name__ == "__main__":
    # สั่งรันเซิร์ฟเวอร์ AI ที่พอร์ต 8000 เป็นค่าตั้งต้น
    uvicorn.run(app, host="0.0.0.0", port=8000)
