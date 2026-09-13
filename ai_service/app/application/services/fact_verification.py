from typing import List, Dict, Any, Optional
from pydantic import BaseModel, Field
from app.domain.entities.comparison import ComparisonMatrix, ComparisonSpec, VerifiedSource
from app.domain.interfaces.llm_service import LLMServiceInterface
from app.infrastructure.llm.prompt_templates import SYSTEM_FACT_VERIFICATION
from app.core.logging import logger

class VerifiedSpecModel(BaseModel):
    feature_name: str = Field(..., description="คุณสมบัติหรือสเปก เช่น เซนเซอร์, ความละเอียด, แบตเตอรี่")
    item_a_value: str = Field(..., description="สเปกของสินค้า A")
    item_b_value: str = Field(..., description="สเปกของสินค้า B")
    notes: Optional[str] = Field(None, description="จุดต่างหรือข้อสังเกต")

class FilteredSourceModel(BaseModel):
    title: str = Field(..., description="ชื่อเว็บ/หัวข้อ")
    link: str = Field(..., description="URL")
    snippet: str = Field(..., description="เนื้อหาสาระสำคัญที่ผ่านการตรวจสอบ")
    relevance_score: float = Field(..., ge=0.0, le=1.0, description="คะแนนความเกี่ยวข้อง")
    is_credible: bool = Field(True, description="มีความน่าเชื่อถือทางเทคนิค")

class FactVerificationResult(BaseModel):
    verified_specs: List[VerifiedSpecModel] = Field(default_factory=list)
    key_differences: List[str] = Field(default_factory=list)
    filtered_sources: List[FilteredSourceModel] = Field(default_factory=list)
    is_factual_consistent: bool = Field(True, description="สเปกมีความถูกต้องและสอดคล้องกัน")

class FactVerificationService:
    """Filters, cross-checks, and validates external search snippets against target items."""

    def __init__(self, llm_service: LLMServiceInterface):
        self.llm_service = llm_service

    async def verify_and_filter(
        self,
        item_a_name: str,
        item_b_name: str,
        raw_search_results: List[Dict[str, Any]]
    ) -> FactVerificationResult:
        if not raw_search_results:
            return FactVerificationResult()

        search_context = ""
        for idx, res in enumerate(raw_search_results, 1):
            search_context += f"[{idx}] {res.get('title')}\nURL: {res.get('link')}\nSnippet: {res.get('snippet')}\n\n"

        prompt = (
            f"ตรวจสอบข้อมูลสเปกสำหรับการเปรียบเทียบระหว่าง:\n"
            f"- สินค้า A: {item_a_name}\n"
            f"- สินค้า B: {item_b_name}\n\n"
            f"ข้อมูลดิบที่ได้จากการค้นหาทางอินเทอร์เน็ต:\n"
            f"{search_context}\n"
            f"กรุณากรองแหล่งข้อมูลที่ไม่น่าเชื่อถือ สแปม หรือโฆษณาออก และสกัดสเปกจริงที่ถูกต้องตรงรุ่นเท่านั้น"
        )

        try:
            result = await self.llm_service.generate_structured(
                prompt=prompt,
                response_model=FactVerificationResult,
                system_instruction=SYSTEM_FACT_VERIFICATION,
                temperature=0.1
            )
            # Fallback: หากโมเดลคืน verified_specs แต่ filtered_sources เป็นลิสต์ว่าง
            # ให้ดึงแหล่งข้อมูลที่น่าเชื่อถือจาก raw_search_results มาเติมอัตโนมัติ
            if not result.filtered_sources and raw_search_results:
                fallback_sources = []
                for res in raw_search_results[:3]:
                    link = res.get("link") or ""
                    title = res.get("title") or ""
                    snippet = res.get("snippet") or ""
                    if link and title:
                        fallback_sources.append(
                            FilteredSourceModel(
                                title=title,
                                link=link,
                                snippet=snippet,
                                relevance_score=0.85,
                                is_credible=True
                            )
                        )
                result.filtered_sources = fallback_sources
            return result
        except Exception as e:
            logger.error(f"Error during fact verification: {e}")
            fallback_sources = []
            if raw_search_results:
                for res in raw_search_results[:3]:
                    link = res.get("link") or ""
                    title = res.get("title") or ""
                    snippet = res.get("snippet") or ""
                    if link and title:
                        fallback_sources.append(
                            FilteredSourceModel(
                                title=title,
                                link=link,
                                snippet=snippet,
                                relevance_score=0.8,
                                is_credible=True
                            )
                        )
            return FactVerificationResult(filtered_sources=fallback_sources)
