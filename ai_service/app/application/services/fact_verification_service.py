from typing import List, Optional
from app.domain.entities.comparison import ComparisonMatrix
from app.domain.entities.search_source import SearchSource
from app.domain.interfaces.llm_service import LLMServiceInterface
from app.infrastructure.prompts.prompt_templates import FACT_VERIFICATION_PROMPT


class FactVerificationService:
    """Service to verify and ground technical equipment facts from web searches."""

    def __init__(self, llm_service: LLMServiceInterface):
        self._llm = llm_service

    async def verify_and_synthesize(
        self,
        target_items: List[str],
        sources: List[SearchSource],
    ) -> ComparisonMatrix:
        if not sources:
            return ComparisonMatrix(
                target_items=target_items,
                specifications={},
                pros_and_cons={},
                verdict="ไม่มีข้อมูลผลการค้นหาเพิ่มเติมเพื่อยืนยันสเปกภายนอก",
            )

        snippets_text = "\n\n".join(
            f"แหล่งข้อมูล [{s.domain}]: {s.title}\n{s.snippet}" for s in sources[:4]
        )

        prompt = (
            f"อุปกรณ์เป้าหมายที่ต้องการเปรียบเทียบ/ตรวจสอบสเปก: {', '.join(target_items)}\n\n"
            f"ข้อมูลสเปกจากผลการค้นหาเว็บ:\n{snippets_text}\n\n"
            "กรุณาสกัดข้อมูลทางเทคนิคที่ถูกต้องและปราศจากอคติ โดยแยกสเปกสำคัญ ข้อดี-ข้อเสียของแต่ละรุ่น และข้อสรุปเปรียบเทียบตามลักษณะงาน"
        )

        matrix = await self._llm.generate_structured(
            prompt=prompt,
            schema=ComparisonMatrix,
            system_instruction=FACT_VERIFICATION_PROMPT,
            temperature=0.1,
        )
        return matrix
