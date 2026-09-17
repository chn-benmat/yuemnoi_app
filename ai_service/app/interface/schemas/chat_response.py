from pydantic import BaseModel, Field
from typing import Optional, List
from app.application.dtos.item_dto import ItemDTO
from app.application.dtos.comparison_dto import ComparisonDTO, VerifiedSourceDTO
from app.application.dtos.clarification_dto import ClarificationDTO, QuestionStepDTO

class ChatResponse(BaseModel):
    response: str = Field(..., description="ข้อความคำตอบสำหรับแสดงผลให้ผู้ใช้")
    intent: str = Field(..., description="Intent ที่ระบบประเมินได้")
    confidence: float = Field(..., description="ระดับความมั่นใจ")
    ambiguity_level: float = Field(..., description="ระดับความกำกวม")
    clarification: Optional[ClarificationDTO] = Field(None, description="คำถามถามกลับพร้อมตัวเลือก (ถ้ามี)")
    questions: List[QuestionStepDTO] = Field(default_factory=list, description="ชุดคำถามช้อยส์ (ถ้ามี)")
    items: List[ItemDTO] = Field(default_factory=list, description="รายการสินค้าที่เกี่ยวข้องจาก Supabase (ถ้ามี)")
    comparison: Optional[ComparisonDTO] = Field(None, description="ข้อมูลเปรียบเทียบเชิงลึกและแหล่งอ้างอิง (ถ้ามี)")
    search_query: Optional[str] = Field(None, description="คำค้นหา Google ที่ใช้ค้นหาข้อมูลจริง")
    search_sources: List[VerifiedSourceDTO] = Field(default_factory=list, description="รายการแหล่งอ้างอิงเว็บไซต์")


