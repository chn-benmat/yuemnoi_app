from pydantic import BaseModel, Field, model_validator
from typing import Optional, List

class MessageItem(BaseModel):
    role: str = Field(..., description="user or assistant")
    content: str = Field(..., max_length=1000, description="message content")

class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=1000, description="ข้อความคำถามจากผู้ใช้")
    query: Optional[str] = Field(None, max_length=1000, description="Alias ข้อความคำถามจากผู้ใช้สำหรับ Mobile Client")
    session_id: Optional[str] = Field(None, max_length=128, description="Session ID ของบทสนทนา")
    history: List[MessageItem] = Field(default_factory=list, max_length=10, description="ประวัติข้อความก่อนหน้า")

    @model_validator(mode="before")
    @classmethod
    def populate_message_from_query(cls, data):
        if isinstance(data, dict):
            if not data.get("message") and data.get("query"):
                data["message"] = data["query"]
        return data
