from typing import List, Optional, Tuple
from app.domain.entities.item import Item
from app.domain.entities.intent import IntentDecision
from app.domain.entities.comparison import VerifiedSource
from app.domain.interfaces.search_service import SearchServiceInterface
from app.domain.interfaces.llm_service import LLMServiceInterface
from app.application.use_cases.query_items import QueryItemsUseCase
from app.application.services.web_grounding_service import WebGroundingService
from app.infrastructure.utils.text_sanitizer import normalize_rental_unit
from app.core.logging import logger

class InquireItemSpecUseCase:
    """Orchestrates technical specification and dimension inquiry:
    1. Resolves target item from query/slots or history.
    2. Matches with catalog item in item_tb (if available).
    3. Factual web grounding via WebGroundingService (dimensions, weight, battery, sensor, ports).
    4. Builds grounded prompt answering the user's specific technical question directly.
    """

    def __init__(
        self,
        query_items_use_case: QueryItemsUseCase,
        search_service: SearchServiceInterface,
        llm_service: LLMServiceInterface,
        web_grounding_service: Optional[WebGroundingService] = None
    ):
        self.query_items_use_case = query_items_use_case
        self.search_service = search_service
        self.llm_service = llm_service
        self.web_grounding_service = web_grounding_service or WebGroundingService(
            search_service=search_service,
            llm_service=llm_service
        )

    async def execute(
        self,
        user_query: str,
        intent_decision: IntentDecision
    ) -> Tuple[str, List[Item], str, List[VerifiedSource]]:
        """
        Returns:
            prompt: Grounded prompt ready for LLM synthesis (streaming or non-streaming)
            matched_items: Single matching catalog item (if in store) or empty list
            search_query: Google search query formulated for grounding
            sources: List of verified reference sources
        """
        target_item_name = ""
        if intent_decision.slots.target_items:
            target_item_name = intent_decision.slots.target_items[0].strip()

        # Step 1: Match with catalog item (if in store)
        matched_items: List[Item] = []
        if target_item_name:
            matched_items = await self.query_items_use_case.execute(
                user_query=target_item_name,
                target_item_names=[target_item_name],
                limit=1
            )

        catalog_item: Optional[Item] = matched_items[0] if matched_items else None
        effective_item_name = catalog_item.display_name if catalog_item else (target_item_name or user_query)

        # Step 2: Search web for real specifications via WebGroundingService
        attribute = (intent_decision.slots.target_attribute or user_query).strip()
        search_target = catalog_item.display_name if catalog_item else (target_item_name or effective_item_name)

        grounding_result = await self.web_grounding_service.search_and_ground_spec(
            item_name=search_target,
            attribute=attribute,
            num_results=3
        )
        snippets_text = grounding_result.snippets_text
        search_query = grounding_result.search_query
        sources = grounding_result.sources

        # Step 3: Shop context if available
        shop_context = ""
        if catalog_item:
            unit_th = normalize_rental_unit(catalog_item.type)
            if catalog_item.is_available:
                shop_context = (
                    f"ข้อมูลสินค้าในร้านยืมหน่อย:\n"
                    f"- รุ่น: {catalog_item.display_name}\n"
                    f"- ราคาเช่า: {catalog_item.price} บาท/{unit_th}\n"
                    f"- สถานะในคลัง: พร้อมให้บริการเช่า (available)\n"
                    f"- รายละเอียดเดิมในร้าน: {catalog_item.description}"
                )
                closing_instruction = (
                    "3. สรุปสถานะและเชิญชวน (ย่อหน้าสุดท้าย):\n"
                    "   - เว้น 1 บรรทัดว่าง แล้วปิดท้ายด้วย \"คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติมได้ที่การ์ดด้านล่างได้เลยนะคะ\""
                )
            else:
                shop_context = (
                    f"ข้อมูลสินค้าในร้านยืมหน่อย:\n"
                    f"- รุ่น: {catalog_item.display_name}\n"
                    f"- สถานะในคลัง: มีในระบบของร้านยืมหน่อย แต่ขณะนี้ยังไม่พร้อมให้บริการเช่า (สถานะ: {catalog_item.status} - เช่น มีผู้เช่าอยู่หรือรอคิวส่งมอบ)\n"
                    f"- รายละเอียดเดิมในร้าน: {catalog_item.description}"
                )
                closing_instruction = (
                    f"3. สรุปสถานะสินค้าในร้านยืมหน่อย (บังคับต้องระบุในย่อหน้าสุดท้ายเสมอ):\n"
                    f"   - แจ้งอย่างสุภาพและตรงไปตรงมาว่า ปัจจุบันทางร้านยืมหน่อยมี **{catalog_item.display_name}** ในระบบ แต่ขณะนี้สินค้ายังไม่พร้อมให้บริการเช่า (อาจอยู่ระหว่างการเช่าหรือรอคิวส่งมอบ) ค่ะ\n"
                    f"   - กฎเหล็กเด็ดขาด: 'ห้ามบอกว่าทางร้านไม่มีสินค้านี้เด็ดขาด' เพราะทางร้านมีสินค้านี้ในระบบแต่ขณะนี้ยังไม่ว่าง และไม่ต้องเชิญชวนแตะดูการ์ดสินค้า\n"
                    f"   - ห้ามแนะนำสินค้าอื่นในหมวดเดียวกันมาทดแทนเด็ดขาด ให้แจ้งสถานะตามความเป็นจริงเท่านั้น"
                )
        else:
            shop_context = "สถานะสินค้าในร้านยืมหน่อย: อุปกรณ์นี้ไม่มีในรายการหรือระบบของร้านยืมหน่อย (Out-of-Catalog)"
            closing_instruction = (
                f"3. สรุปสถานะสินค้าในร้านยืมหน่อย (บังคับต้องระบุในย่อหน้าสุดท้ายเสมอ):\n"
                f"   - แจ้งอย่างสุภาพว่า ปัจจุบันทางร้านยืมหน่อยยังไม่มี **{target_item_name or effective_item_name}** ในระบบให้บริการเช่าค่ะ\n"
                f"   - กฎเหล็กเด็ดขาด: ห้ามแนะนำสินค้าอื่นในหมวดเดียวกันมาทดแทนเด็ดขาด ให้แจ้งตามความเป็นจริงเท่านั้น\n"
                f"   - ไม่ต้องเชิญชวนแตะดูการ์ดสินค้า"
            )

        # Step 4: Build direct, grounded prompt
        prompt = (
            f"คำถามของผู้ใช้: \"{user_query}\"\n\n"
            f"อุปกรณ์ที่เกี่ยวข้อง: {effective_item_name}\n\n"
            f"ประเด็นที่คุณลักษณะที่ผู้ใช้ถามหา: {attribute}\n\n"
            f"ข้อมูลสเปกและข้อเท็จจริงที่ค้นพบ (Grounding Specs):\n{snippets_text}\n\n"
            f"{shop_context}\n\n"
            f"คำสั่งในการตอบ (ตามแนวทางใน SYSTEM_SYNTHESIZER ข้อ C อย่างเคร่งครัด):\n"
            f"1. ตอบตรงประเด็นคุณลักษณะที่ผู้ใช้ถามหาทันที 1 บรรทัด (Direct Answer to Attribute First): ตอบประเด็นคุณลักษณะที่ผู้ใช้ถาม ({attribute}) ทันทีอย่างสุภาพ ลงท้ายด้วย ค่ะ และต้องใส่ชื่อรุ่นในเครื่องหมายตัวหนาเสมอ เช่น หากผู้ใช้ถามขนาดหรือน้ำหนัก ให้ตอบขนาดหรือความกะทัดรัด/น้ำหนักทันที ไม่ตอบเรื่องอื่นนอกเรื่อง\n"
            f"2. แยกหัวข้อย่อยให้อ่านง่าย ชัดเจน สบายตา (2-3 ข้อย่อย): ใช้เครื่องหมายขีด (-) ตามด้วย **หัวข้อตัวหนา** เสมอ โดยข้อแรกต้องเน้นคุณลักษณะที่ผู้ใช้ถาม ({attribute}) เช่น:\n"
            f"   - หากถามขนาด/มิติ: **ขนาดและมิติ** หรือ **น้ำหนัก** (ระบุ มม. / กรัม / กก. ตามข้อมูลที่ค้นพบ)\n"
            f"   - หากถามพอร์ต: **พอร์ตการเชื่อมต่อ** (HDMI, USB-C ฯลฯ)\n"
            f"   - หากถามการใช้งาน: **ความเหมาะสมในการใช้งาน** หรือ **ประสิทธิภาพ** (วิเคราะห์ตามจริงอย่างจริงใจ ทั้งข้อดีและข้อจำกัด ไม่อวยสินค้าเกินจริง)\n"
            f"{closing_instruction}\n"
            f"4. กฎเหล็กข้อห้ามและการจัดรูปแบบ:\n"
            f"   - 'ห้ามนำคำตอบไปใส่ในกล่องเน้นข้อความ Blockquote (>) โดยเด็ดขาด' (ให้ตอบเป็น bullet ธรรมดาเพื่อความโปร่งตา สะอาด สบายตา คล้าย ChatGPT/Claude/Gemini)\n"
            f"   - 'ห้ามใส่เครื่องหมายหรือป้ายตัวเลขอ้างอิง เช่น [1], [2], (1) หรือลิงก์ในเนื้อหาข้อความเด็ดขาด 100%' เพื่อให้ข้อความอ่านสบายตาและเรียบร้อย ข้อมูลแหล่งที่มาและคำค้นหาจะแสดงใน AI Summary ด้านบนโดยอัตโนมัติ\n"
            f"   - หากผู้ใช้ถามเรื่องขนาด/มิติ/น้ำหนัก: ต้องระบุขนาดและน้ำหนัก (เช่น มม. กรัม หรือขนาด) ให้ชัดเจน\n"
            f"   - หากผู้ใช้ถามเรื่องอื่น (เช่น ความเหมาะสมในการเล่นเกม, ตัดต่อวิดีโอ, ประสิทธิภาพ, แบตเตอรี่, พอร์ต, จอภาพ): 'ห้ามระบุขนาด มิติ กว้างยาว หรือน้ำหนักโดยเด็ดขาด' เพราะผู้ใช้ไม่ได้ถามเรื่องขนาด\n"
            f"   - แชตบอตเป็นผู้หญิง 100% ต้องลงท้ายด้วย 'ค่ะ' หรือ 'นะคะ' เสมอ (ห้ามใช้ 'ครับ' หรือ 'ผม' เด็ดขาด)\n"
            f"   - เว้นวรรคระหว่างภาษาไทยและชื่อภาษาอังกฤษเสมอ และห้ามมีตัวอักษรภาษาจีนเด็ดขาด"
        )

        active_items = [catalog_item] if (catalog_item and catalog_item.is_available) else []
        return prompt, active_items, search_query, sources

