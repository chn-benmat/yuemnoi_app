from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any
from app.application.dtos.item_dto import ItemDTO
from app.application.dtos.comparison_dto import ComparisonDTO, VerifiedSourceDTO
from app.application.dtos.clarification_dto import ClarificationDTO

class ChatMessageDTO(BaseModel):
    role: str
    content: str

class ChatRequestDTO(BaseModel):
    message: str = Field(..., description="ข้อความจากผู้ใช้งาน")
    session_id: Optional[str] = Field(None, description="Session ID ของการสนทนา")
    history: List[ChatMessageDTO] = Field(default_factory=list, description="ประวัติการสนทนาก่อนหน้า")

class ChatResponseDTO(BaseModel):
    response: str
    intent: str
    confidence: float
    ambiguity_level: float
    clarification: Optional[ClarificationDTO] = None
    items: List[ItemDTO] = []
    comparison: Optional[ComparisonDTO] = None
    search_query: Optional[str] = None
    search_sources: List[VerifiedSourceDTO] = []
