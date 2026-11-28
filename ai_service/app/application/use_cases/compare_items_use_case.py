from typing import List, Tuple
from app.application.services.fact_verification_service import FactVerificationService
from app.domain.entities.comparison import ComparisonMatrix
from app.domain.entities.intent_decision import IntentDecision
from app.domain.entities.item import Item
from app.domain.entities.search_source import SearchSource
from app.domain.interfaces.llm_service import LLMServiceInterface
from app.domain.interfaces.search_service import SearchServiceInterface
from app.infrastructure.prompts.prompt_templates import SYSTEM_PROMPT_CHATBOT


class CompareItemsUseCase:
    """Coordinates comparison between equipment items, web fact verification, and synthesis."""

    def __init__(
        self,
        llm_service: LLMServiceInterface,
        search_service: SearchServiceInterface,
        fact_service: FactVerificationService,
    ):
        self._llm = llm_service
        self._search = search_service
        self._fact_service = fact_service

    async def execute(
        self,
        decision: IntentDecision,
        candidate_items: List[Item],
    ) -> Tuple[str, List[SearchSource]]:
        search_sources: List[SearchSource] = []
        target_names = decision.target_items or [item.name for item in candidate_items]

        from datetime import datetime
        current_year = datetime.now().year

        query = decision.search_query or (
            f"compare {' vs '.join(target_names)} specs" if len(target_names) >= 2 else f"{' '.join(target_names)} specs"
        )
        if any(w in query.lower() for w in ["ล่าสุด", "latest"]) and str(current_year) not in query:
            query = f"{query} {current_year}"

        if not decision.search_query:
            decision.search_query = query

        search_sources = await self._search.search(query=query, max_results=3)
        matrix: ComparisonMatrix = await self._fact_service.verify_and_synthesize(
            target_items=target_names,
            sources=search_sources,
        )

        catalog_context = "\n".join(
            f"- {i.name} (หมวดหมู่: {i.category}, ค่าเช่า: {', '.join(f'{rate} บาท/{unit}' for unit, rate in i.rates.items())}, สถานะ: {i.status}"
            + (f", รายละเอียด: {i.description}" if i.description else "")
            + ")"
            for i in candidate_items
        ) if candidate_items else "ไม่มีอุปกรณ์รุ่นนี้ในแคตตาล็อกร้านโดยตรง"

        prompt = (
            f"บริบทเวลาปัจจุบัน: ปี ค.ศ. {current_year} (พ.ศ. {current_year + 543})\n\n"
            f"ผู้ใช้ต้องการเปรียบเทียบอุปกรณ์: {', '.join(target_names)}\n\n"
            f"ข้อมูลสเปกที่ผ่านการยืนยัน:\n{matrix.model_dump_json(indent=2)}\n\n"
            f"ข้อมูลสินค้าในระบบยืมหน่อย:\n{catalog_context}\n\n"
            "คำแนะนำในการสรุปเปรียบเทียบ:\n"
            "- เกริ่นนำสั้นๆ 1 บรรทัด (เช่น ทั้ง 2 รุ่นมีจุดเด่นและลักษณะการใช้งานที่แตกต่างกันดังนี้นะคะ)\n"
            "- จัดรูปแบบอุปกรณ์แต่ละชิ้นที่เปรียบเทียบแยกเป็นบล็อกรายการอย่างชัดเจน สบายตาบนมือถือ (ห้ามเขียนเปรียบเทียบอุปกรณ์รวมกันในประโยคเดียวติดกันด้วยคำว่า 'ส่วน' เช่น ห้ามตอบแนว '**รุ่น A** ทำงานนี้ ส่วน **รุ่น B** ทำงานนั้นค่ะ' และห้ามเขียนรวมเป็นย่อหน้าเดียวติดกันเป็นก้อนยาวเด็ดขาด):\n"
            "  **ชื่ออุปกรณ์ตรงรุ่นเป๊ะๆ ตามรายการ**\n"
            "  - **จุดเด่น/การใช้งาน:** จุดเด่น สเปกหลัก (เช่น ชิปประมวลผล หน้าจอ กล้อง) และลักษณะงานที่เหมาะสมสั้นๆ 1-2 ประโยค (หากเป็นการเปรียบเทียบกับรุ่นล่าสุด ให้ระบุชื่อรุ่นล่าสุดจริงตามข้อมูลเว็บภายนอก เช่น iPhone 17 ซีรีส์ และนำสเปกจริงมาเปรียบเทียบอย่างตรงไปตรงมา)\n"
            "  - **ราคาเช่า:** ราคาจำนวนเต็มไม่มีทศนิยม เช่น 380 บาท ต่อ วัน หรือ ชั่วโมง (หากเป็นอุปกรณ์รุ่นนอกแคตตาล็อกหรือรุ่นล่าสุดที่ยังไม่มีในร้าน ให้ระบุว่า 'ยังไม่มีให้บริการในระบบค่ะ')\n"
            "- สรุปชี้แนะอย่างเป็นกลาง 1 บรรทัดตามการใช้งานจริง (ห้ามแสดงความลำเอียงหรือเชียร์แบรนด์ใดแบรนด์หนึ่งเด็ดขาด)\n"
            "- ห้ามใช้ตาราง Markdown Table (|---|---|), ห้ามใส่รหัส ID ภายในฐานข้อมูล และห้ามใส่เครื่องหมายวงเล็บก้ามปู [ ] ครอบชื่ออุปกรณ์โดยเด็ดขาด\n"
            "- ปิดท้ายด้วยการแนะนำให้ผู้ใช้แตะดูรายละเอียดที่การ์ดอุปกรณ์ด้านล่างอย่างสุภาพ เช่น 'หากสนใจสินค้าที่มีให้เช่าในระบบตอนนี้ สามารถแตะดูรายละเอียดเพิ่มเติมที่การ์ดด้านล่างนี้ได้เลยนะคะ'"
        )

        response_text = await self._llm.generate_text(
            prompt=prompt,
            system_instruction=SYSTEM_PROMPT_CHATBOT,
            max_tokens=600,
            temperature=0.3,
        )
        return response_text, search_sources
