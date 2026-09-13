from typing import List, Optional, Tuple, Callable, Awaitable
from app.domain.entities.item import Item
from app.domain.entities.comparison import ComparisonMatrix, ComparisonSpec, VerifiedSource
from app.domain.entities.intent import IntentDecision
from app.domain.interfaces.item_repository import ItemRepositoryInterface
from app.domain.interfaces.search_service import SearchServiceInterface
from app.domain.interfaces.llm_service import LLMServiceInterface
from app.application.services.fact_verification import FactVerificationService
from app.application.services.web_grounding_service import WebGroundingService
from app.application.use_cases.query_items import QueryItemsUseCase
from app.infrastructure.llm.prompt_templates import SYSTEM_SYNTHESIZER
from app.infrastructure.utils.text_sanitizer import (
    sanitize_instruction_leakage,
    sanitize_thai_output
)
from app.core.logging import logger

class CompareItemsUseCase:
    """Orchestrates rental item comparison: DB Retrieval -> Web Grounding -> Fact Verification -> LLM Synthesis."""

    def __init__(
        self,
        item_repo: ItemRepositoryInterface,
        query_items_use_case: QueryItemsUseCase,
        search_service: SearchServiceInterface,
        fact_verification_service: FactVerificationService,
        llm_service: LLMServiceInterface,
        web_grounding_service: Optional[WebGroundingService] = None
    ):
        self.item_repo = item_repo
        self.query_items_use_case = query_items_use_case
        self.search_service = search_service
        self.fact_verification_service = fact_verification_service
        self.llm_service = llm_service
        self.web_grounding_service = web_grounding_service or WebGroundingService(
            search_service=search_service,
            llm_service=llm_service,
            fact_verification_service=fact_verification_service
        )

    async def prepare_comparison(
        self,
        user_query: str,
        intent_decision: IntentDecision,
        on_status: Optional[Callable[[str, str], Awaitable[None]]] = None
    ) -> Tuple[str, ComparisonMatrix, List[Item]]:
        """Prepares comparison matrix, web search, and verified specs, emitting progressive status events."""
        if on_status:
            await on_status("searching_db", "กำลังค้นหาอุปกรณ์ในระบบ...")

        # 1. Identify items to compare from the user's query
        targets = intent_decision.slots.target_items or []
        target_a_raw = targets[0] if len(targets) > 0 else "สินค้าชิ้นแรก"
        target_b_raw = targets[1] if len(targets) > 1 else "สินค้าเปรียบเทียบ"

        item_a: Optional[Item] = None
        item_b: Optional[Item] = None

        if len(targets) > 0:
            match_a = await self.query_items_use_case.execute(
                user_query=user_query,
                target_item_names=[targets[0]],
                limit=1
            )
            item_a = match_a[0] if match_a else None

        if len(targets) > 1:
            match_b = await self.query_items_use_case.execute(
                user_query=user_query,
                target_item_names=[targets[1]],
                limit=1
            )
            item_b = match_b[0] if match_b else None

        # Ground comparison targets to in-store catalog item display names if matched,
        # otherwise preserve the user's raw target name (e.g. for out-of-catalog items).
        item_a_name = item_a.display_name if item_a else target_a_raw
        item_b_name = item_b.display_name if item_b else target_b_raw

        matched_items: List[Item] = []
        if item_a and item_a.is_available and item_a not in matched_items:
            matched_items.append(item_a)
        if item_b and item_b.is_available and item_b not in matched_items:
            matched_items.append(item_b)

        logger.info(f"Comparing items: '{item_a_name}' vs '{item_b_name}' (Catalog matches: {len(matched_items)})")

        if on_status:
            await on_status("searching_web", "กำลังค้นหาข้อมูลและสเปกทางเทคนิคจากอินเทอร์เน็ต...")

        # 2. Web search via Search Service with targeted query derived from actual user target entities
        attribute_focus = intent_decision.slots.target_attribute or intent_decision.slots.intended_use
        search_query = self.web_grounding_service.formulate_comparison_query(
            item_a_name=item_a_name,
            item_b_name=item_b_name,
            attribute=attribute_focus
        )
        logger.info(f"Web Search Query: '{search_query}'")
        raw_search = await self.search_service.search(query=search_query, num_results=6)

        if on_status:
            await on_status("verifying_facts", "กำลังตรวจสอบและวิเคราะห์ความถูกต้องของสเปก...")

        # 3. Fact Verification & Filtering
        fact_result = await self.fact_verification_service.verify_and_filter(
            item_a_name=item_a_name,
            item_b_name=item_b_name,
            raw_search_results=raw_search
        )

        # 4. Construct ComparisonMatrix domain entity
        specs = [
            ComparisonSpec(
                feature_name=s.feature_name,
                item_a_value=s.item_a_value,
                item_b_value=s.item_b_value,
                notes=s.notes
            )
            for s in fact_result.verified_specs
        ]

        sources = [
            VerifiedSource(
                title=src.title,
                link=src.link,
                snippet=src.snippet,
                relevance_score=src.relevance_score,
                is_credible=src.is_credible
            )
            for src in fact_result.filtered_sources
        ]

        matrix = ComparisonMatrix(
            item_a_name=item_a_name,
            item_b_name=item_b_name,
            item_a_price=item_a.price if item_a else None,
            item_b_price=item_b.price if item_b else None,
            item_a_status=item_a.status if item_a else None,
            item_b_status=item_b.status if item_b else None,
            specs=specs,
            key_differences=fact_result.key_differences,
            recommendation="",
            sources=sources,
            search_query=search_query
        )

        # 5. Build prompt for comparison synthesis (Grounding + In-Store Inventory Policy)
        def _fmt_catalog_info(it: Optional[Item], model_name: str) -> str:
            if not it:
                return f"ไม่มีในระบบของร้านยืมหน่อย (Out-of-Catalog)"
            price_str = str(int(it.price)) if it.price.is_integer() else f"{it.price:.2f}"
            if it.is_available:
                return f"มีในระบบและพร้อมให้บริการเช่า ราคา {price_str} บาท/{it.type} (สถานะ: พร้อมเช่า available)"
            return f"มีในระบบของร้านยืมหน่อย แต่ขณะนี้ยังไม่พร้อมให้บริการเช่า (สถานะ: {it.status} เช่น อยู่ระหว่างการเช่าหรือรอคิวส่งมอบ)"

        is_a_avail = item_a is not None and item_a.is_available
        is_b_avail = item_b is not None and item_b.is_available
        is_a_in_store = item_a is not None
        is_b_in_store = item_b is not None

        if is_a_avail and is_b_avail:
            catalog_rule = (
                "ทั้งสองรุ่นมีให้บริการพร้อมเช่าในร้านยืมหน่อย: สรุปเปรียบเทียบสเปกและจุดเด่นของทั้งสองรุ่น และเชิญชวนแตะดูราคาและรายละเอียดที่การ์ดสินค้าทั้งสองรุ่นด้านล่างได้เลย (ห้ามแจ้งว่าไม่มีสินค้าเด็ดขาด เพราะทางร้านมีทั้งสองรุ่นพร้อมเช่า 100%)\n"
            )
            card_cta = "ปิดท้ายด้วยประโยคเชิญชวนแตะดูรายละเอียดเพิ่มเติมและราคาเช่าที่การ์ดด้านล่าง เช่น \"คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติมและราคาเช่าของอุปกรณ์ได้ที่การ์ดด้านล่างได้เลยนะคะ\"\n"
        elif is_a_avail or is_b_avail:
            avail_name = item_a_name if is_a_avail else item_b_name
            other_item = item_b if is_a_avail else item_a
            other_name = item_b_name if is_a_avail else item_a_name
            if other_item is not None:
                other_clause = f"ส่วน **{other_name}** มีในระบบของร้านแต่ขณะนี้ยังไม่พร้อมให้บริการเช่า (อาจอยู่ระหว่างการเช่าหรือรอคิวส่งมอบ) ค่ะ"
                forbidden_clause = f"'ห้ามบอกว่าทางร้านไม่มี {other_name} เด็ดขาด' เพราะร้านมีในระบบแต่สถานะยังไม่ว่าง"
            else:
                other_clause = f"ส่วน **{other_name}** ทางร้านยังไม่มีในระบบให้บริการเช่าในขณะนี้ค่ะ"
                forbidden_clause = "แจ้งตามความเป็นจริงเท่านั้น"

            catalog_rule = (
                f"มีสินค้าพร้อมเช่าในร้าน 1 รุ่น:\n"
                f"- ในย่อหน้าสรุป ให้ระบุอย่างสุภาพและตรงไปตรงมาว่า ปัจจุบันทางร้านยืมหน่อยมี **{avail_name}** พร้อมให้บริการเช่า (สามารถแตะดูรายละเอียดและราคาที่การ์ดด้านล่างได้เลยค่ะ) {other_clause}\n"
                f"- ข้อกำหนดสำคัญ: {forbidden_clause} และห้ามแนะนำสินค้าอื่นในหมวดเดียวกันมาทดแทนเด็ดขาด\n"
            )
            card_cta = f"ปิดท้ายด้วยประโยคเชิญชวนแตะดูรายละเอียดเพิ่มเติมและราคาเช่าของ **{avail_name}** ได้ที่การ์ดด้านล่างได้เลยนะคะ\n"
        elif is_a_in_store or is_b_in_store:
            if is_a_in_store and is_b_in_store:
                catalog_rule = (
                    f"ทั้งสองรุ่นมีในระบบของร้าน แต่ขณะนี้ยังไม่พร้อมให้บริการเช่าทั้งคู่ (unavailable):\n"
                    f"- ในย่อหน้าสรุป ให้ระบุอย่างสุภาพว่า ปัจจุบันทางร้านยืมหน่อยมีทั้ง **{item_a_name}** และ **{item_b_name}** ในระบบ แต่ขณะนี้ยังไม่พร้อมให้บริการเช่าทั้งสองรุ่น (อาจอยู่ระหว่างการเช่าหรือรอคิวส่งมอบ) ค่ะ\n"
                    f"- ข้อกำหนดสำคัญ: ห้ามบอกว่าร้านไม่มีสินค้าเด็ดขาด และห้ามแนะนำสินค้าอื่นในหมวดเดียวกันมาทดแทนเด็ดขาด\n"
                )
            else:
                unavail_name = item_a_name if is_a_in_store else item_b_name
                out_name = item_b_name if is_a_in_store else item_a_name
                catalog_rule = (
                    f"สถานะสินค้าในร้าน (1 รุ่นมีในระบบแต่ไม่พร้อมเช่า, 1 รุ่นไม่มีในระบบ):\n"
                    f"- ในย่อหน้าสรุป ให้ระบุอย่างสุภาพว่า **{unavail_name}** มีในระบบของร้านยืมหน่อยแต่ขณะนี้ยังไม่พร้อมให้บริการเช่า ส่วน **{out_name}** ทางร้านยังไม่มีในระบบให้บริการเช่าค่ะ\n"
                    f"- ข้อกำหนดสำคัญ: ห้ามแนะนำสินค้าอื่นในหมวดเดียวกันมาทดแทนเด็ดขาด\n"
                )
            card_cta = "ปิดท้ายอย่างสุภาพ โดยไม่ต้องเชิญชวนแตะดูการ์ดด้านล่างเนื่องจากสินค้ายังไม่พร้อมเช่าในขณะนี้\n"
        else:
            catalog_rule = (
                "ทั้งสองรุ่นไม่มีให้บริการในร้านยืมหน่อย (Out-of-Catalog Policy):\n"
                "- สรุปเปรียบเทียบสเปกของทั้งสองรุ่นตามจริงอย่างเป็นกลางและน่าเชื่อถือ\n"
                "- ในย่อหน้าสรุป ให้แจ้งอย่างสุภาพว่าปัจจุบันทางร้านยืมหน่อยยังไม่มีทั้งสองรุ่นนี้ในระบบให้บริการเช่าค่ะ\n"
                "- ข้อกำหนดสำคัญ: ห้ามแนะนำสินค้าอื่นในหมวดเดียวกันมาทดแทนเด็ดขาด (ห้ามดึงสินค้าอื่นมาเสนอทดแทน) ให้แจ้งตามความเป็นจริงเท่านั้น\n"
            )
            card_cta = "ปิดท้ายอย่างสุภาพ โดยไม่ต้องเชิญชวนแตะดูการ์ดด้านล่างเนื่องจากไม่มีสินค้าพร้อมเช่าในร้าน\n"

        prompt = (
            f"คำถามของผู้ใช้: \"{user_query}\"\n\n"
            f"ข้อมูลสินค้าในร้านเช่าของเรา:\n"
            f"- {item_a_name}: {_fmt_catalog_info(item_a, item_a_name)}\n"
            f"- {item_b_name}: {_fmt_catalog_info(item_b, item_b_name)}\n\n"
            f"สเปกทางเทคนิคที่ผ่านการตรวจสอบความถูกต้องแล้ว (Verified Specs):\n"
        )
        for s in specs:
            prompt += f"- {s.feature_name}: {item_a_name} ({s.item_a_value}) vs {item_b_name} ({s.item_b_value}) {f'[{s.notes}]' if s.notes else ''}\n"

        prompt += (
            f"\nจุดแตกต่างสำคัญที่ยืนยันแล้ว:\n"
            + "\n".join(f"- {d}" for d in fact_result.key_differences)
            + "\n\nคำสั่งจัดโครงสร้าง Markdown ให้กระชับ สละสลวย เป็นธรรมชาติ และตรงประเด็น:\n"
            + "- เริ่มต้นด้วยการเข้าเรื่องเปรียบเทียบทันที 1 ประโยค (ไม่กล่าวทักทายซ้ำ และลงท้ายด้วย ค่ะ เช่น \"หากกำลังตัดสินใจเลือกระหว่างสองรุ่นนี้ ขอสรุปข้อแตกต่างที่สำคัญดังนี้ค่ะ:\")\n"
            + "- สกัดและใช้เฉพาะชื่อแบรนด์และชื่อรุ่นทางการในเครื่องหมายตัวหนา เช่น **PlayStation 5**, **Nintendo Switch OLED** (ไม่นำคำระบุแพ็กเกจหรือของแถมมาใส่ในเนื้อหา)\n"
            + "- เปรียบเทียบความแตกต่างสำคัญแบบหมวดหมู่ชนหมวดหมู่ 3 ข้อย่อยเท่านั้น โดยใช้หัวข้อระดับ 3 (###) พร้อมอิโมจิที่เข้ากับหัวข้อมิติ และแตกเป็น 2 ข้อย่อยคู่ขนานสำหรับแต่ละรุ่น โดยขึ้นต้นด้วย - **[ชื่อรุ่น]**: [สเปก/จุดเด่น 1 บรรทัด] เสมอ (ห้ามนำทั้งสองรุ่นมารวมในบรรทัดเดียวกันด้วยคำว่า 'ส่วน...' เพื่อให้อ่านง่ายบนมือถือ)\n"
            + "- วิเคราะห์เปรียบเทียบสเปกตามจริงอย่างเป็นกลาง 100% หากรุ่นใดตอบโจทย์การใช้งานของผู้ใช้ได้ดีกว่า ให้อธิบายตามความเป็นจริง ไม่อวยหรือบิดเบือนข้อเท็จจริงเพื่อผลักดันสินค้าที่มีในร้าน\n"
            + f"- สถานะสินค้าในร้าน:\n  {catalog_rule.strip()}\n"
            + f"- ประโยคปิดท้าย:\n  {card_cta.strip()}\n"
            + "- แชตบอตเป็นผู้หญิง 100% ต้องลงท้ายด้วย 'ค่ะ' หรือ 'นะคะ' เสมอ (ห้ามใช้ 'ครับ' หรือ 'ผม')\n"
            + "- ห้ามใส่เครื่องหมายหรือป้ายตัวเลขอ้างอิง หรือลิงก์ในเนื้อหาเด็ดขาด (ข้อมูลแหล่งที่มาและคำค้นหาจะแสดงในการ์ดโดยอัตโนมัติ)\n"
            + "- ตอบกระชับ ตรงประเด็น สละสลวย เว้น 1 บรรทัดว่างระหว่างแต่ละส่วน และห้ามมีตัวอักษรภาษาจีนเด็ดขาด\n"
            + "- ข้อห้ามเด็ดขาด: ห้ามใส่หัวข้อคำสั่ง กฎเกณฑ์ หรือชื่อข้อกำหนดลงในคำตอบเด็ดขาด ให้เขียนเฉพาะเนื้อหาตอบลูกค้าโดยตรงเท่านั้น"
        )

        return prompt, matrix, matched_items

    async def execute(
        self,
        user_query: str,
        intent_decision: IntentDecision
    ) -> Tuple[str, Optional[ComparisonMatrix], List[Item]]:
        prompt, matrix, matched_items = await self.prepare_comparison(user_query, intent_decision)

        answer = await self.llm_service.generate_text(
            prompt=prompt,
            system_instruction=SYSTEM_SYNTHESIZER,
            temperature=0.4
        )

        clean_answer = sanitize_instruction_leakage(sanitize_thai_output(answer))
        matrix.recommendation = clean_answer
        return clean_answer, matrix, matched_items
