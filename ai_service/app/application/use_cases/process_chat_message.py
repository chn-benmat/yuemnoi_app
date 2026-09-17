from typing import Optional, List
from app.application.dtos.chat_dto import ChatRequestDTO, ChatResponseDTO
from app.application.dtos.item_dto import ItemDTO
from app.application.dtos.comparison_dto import ComparisonDTO, ComparisonSpecDTO, VerifiedSourceDTO
from app.application.dtos.clarification_dto import ClarificationDTO, ChoiceOptionDTO, QuestionStepDTO
from app.domain.entities.intent import IntentType
from app.application.use_cases.route_intent import RouteIntentUseCase
from app.application.use_cases.query_items import QueryItemsUseCase
from app.application.use_cases.compare_items import CompareItemsUseCase
from app.application.use_cases.generate_clarification import GenerateClarificationUseCase
from app.application.use_cases.inquire_item_spec import InquireItemSpecUseCase
from app.domain.interfaces.llm_service import LLMServiceInterface
from app.domain.entities.chat import ChatMessage, ChatRole
from app.infrastructure.llm.prompt_templates import SYSTEM_SYNTHESIZER
from app.infrastructure.utils.text_sanitizer import (
    sanitize_thai_output,
    normalize_rental_unit,
    strip_selection_guide,
    strip_card_cta_if_no_items,
    sanitize_instruction_leakage,
    separate_trailing_card_cta,
    trim_verbose_recommendation_intro
)
from app.core.logging import logger

def _build_multi_turn_messages(history: list, latest_user_prompt: str, max_turns: int = 4) -> list[ChatMessage]:
    """Build multi-turn ChatMessage objects preserving user and assistant turns without dumping string prefixes."""
    messages: list[ChatMessage] = []
    if history:
        for m in history[-max_turns:]:
            role = ChatRole.ASSISTANT if m.role == "assistant" else ChatRole.USER
            content = m.content.strip()
            if content:
                messages.append(ChatMessage(role=role, content=content))
    messages.append(ChatMessage(role=ChatRole.USER, content=latest_user_prompt))
    return messages

class ProcessChatMessageUseCase:
    """Master Application Use Case: Orchestrates Intent Routing, Database Retrieval, External Search, and Clarification."""

    def __init__(
        self,
        route_intent_use_case: RouteIntentUseCase,
        query_items_use_case: QueryItemsUseCase,
        compare_items_use_case: CompareItemsUseCase,
        generate_clarification_use_case: GenerateClarificationUseCase,
        inquire_item_spec_use_case: InquireItemSpecUseCase,
        llm_service: LLMServiceInterface
    ):
        self.route_intent = route_intent_use_case
        self.query_items = query_items_use_case
        self.compare_items = compare_items_use_case
        self.generate_clarification = generate_clarification_use_case
        self.inquire_item_spec = inquire_item_spec_use_case
        self.llm_service = llm_service

    async def execute(self, request: ChatRequestDTO) -> ChatResponseDTO:
        # Build history context if provided
        history_context = ""
        if request.history:
            history_context = "\n".join([f"{msg.role}: {msg.content}" for msg in request.history[-4:]])

        # Step 1: AI Intent & Ambiguity Classification (Zero-Regex, Zero-Keyword)
        decision = await self.route_intent.execute(request.message, history_context=history_context)
        logger.info(f"Intent classified as: {decision.intent.value} (Confidence: {decision.confidence}, Ambiguity: {decision.ambiguity_level})")

        # Step 2: Branch based on classified intent
        if decision.intent == IntentType.CLARIFICATION_NEEDED:
            clarification_entity = await self.generate_clarification.execute(
                request.message, decision, history_context=history_context
            )
            question_dtos = [
                QuestionStepDTO(
                    id=st.id,
                    title=st.title,
                    options=st.options,
                    step=st.step,
                    total_steps=st.total_steps,
                    branch_titles=st.branch_titles,
                    branch_options=st.branch_options
                )
                for st in clarification_entity.steps
            ]
            clarification_dto = ClarificationDTO(
                question=clarification_entity.question,
                missing_dimension=clarification_entity.missing_dimension,
                options=[
                    ChoiceOptionDTO(
                        id=opt.id,
                        label=opt.label,
                        description=opt.description,
                        action_value=opt.action_value
                    )
                    for opt in clarification_entity.options
                ],
                questions=question_dtos
            )
            return ChatResponseDTO(
                response=clarification_entity.question,
                intent=decision.intent.value,
                confidence=decision.confidence,
                ambiguity_level=decision.ambiguity_level,
                clarification=clarification_dto,
                items=[],
                comparison=None
            )

        elif decision.intent == IntentType.RENTAL_COMPARISON:
            comparison_text, matrix, matched_items = await self.compare_items.execute(request.message, decision)
            comparison_dto = None
            if matrix:
                comparison_dto = ComparisonDTO(
                    item_a_name=matrix.item_a_name,
                    item_b_name=matrix.item_b_name,
                    item_a_price=matrix.item_a_price,
                    item_b_price=matrix.item_b_price,
                    item_a_status=matrix.item_a_status,
                    item_b_status=matrix.item_b_status,
                    specs=[
                        ComparisonSpecDTO(
                            feature_name=sp.feature_name,
                            item_a_value=sp.item_a_value,
                            item_b_value=sp.item_b_value,
                            notes=sp.notes
                        )
                        for sp in matrix.specs
                    ],
                    key_differences=matrix.key_differences,
                    recommendation=matrix.recommendation,
                    sources=[
                        VerifiedSourceDTO(
                            title=sc.title,
                            link=sc.link,
                            snippet=sc.snippet,
                            relevance_score=sc.relevance_score,
                            is_credible=sc.is_credible
                        )
                        for sc in matrix.sources
                    ],
                    search_query=matrix.search_query
                )

            item_dtos = [
                ItemDTO(
                    id=it.id,
                    name=it.display_name,
                    category=it.category,
                    price=it.price,
                    type=normalize_rental_unit(it.type),
                    status=it.status,
                    image_urls=it.item_image_url,
                    description=it.description
                )
                for it in matched_items
            ]

            final_comp_text = sanitize_instruction_leakage(strip_selection_guide(sanitize_thai_output(comparison_text)))
            if not item_dtos:
                final_comp_text = strip_card_cta_if_no_items(final_comp_text)

            return ChatResponseDTO(
                response=final_comp_text,
                intent=decision.intent.value,
                confidence=decision.confidence,
                ambiguity_level=decision.ambiguity_level,
                clarification=None,
                items=item_dtos,
                comparison=comparison_dto,
                search_query=comparison_dto.search_query if comparison_dto else None,
                search_sources=comparison_dto.sources if comparison_dto else []
            )

        elif decision.intent == IntentType.ITEM_INQUIRY:
            matched_items = await self.query_items.execute(
                user_query=request.message,
                target_item_names=decision.slots.target_items,
                category_hints=decision.slots.categories,
                intended_use=decision.slots.intended_use,
                budget_max=decision.slots.budget_max,
                limit=3
            )

            def _fmt_price(val: float) -> str:
                return str(int(val)) if val.is_integer() else f"{val:.2f}"

            # Check if any item actually matched
            if not matched_items:
                available_categories = await self.query_items.get_available_categories()
                cats_str = ", ".join(available_categories)

                # Differentiate between no cheaper item in category vs item not offered in store
                if decision.slots.categories and decision.slots.budget_max:
                    cat_name = decision.slots.categories[0]
                    prompt = (
                        f"คำขอของผู้ใช้: \"{request.message}\"\n\n"
                        f"สถานะคลังสินค้า: ไม่พบอุปกรณ์ในหมวด '{cat_name}' ที่มีราคาเช่าต่ำกว่า {_fmt_price(decision.slots.budget_max)} บาท/วัน เนื่องจากสินค้ารุ่นดังกล่าวเป็นราคาเช่าเริ่มต้นที่ประหยัดที่สุดในหมวดนี้ของทางร้านแล้ว\n\n"
                        f"แนวทางการตอบ (เขียนเป็นบทสนทนาธรรมชาติสั้นกระชับ ให้อ่านง่ายและสบายตา):\n"
                        f"- ชี้แจงอย่างสุภาพว่าสินค้ารุ่นดังกล่าวมีราคาเช่าเริ่มต้นที่ประหยัดที่สุดในหมวด {cat_name} ของทางร้านแล้วค่ะ\n"
                        f"- ให้ข้อมูลความคุ้มค่าของอุปกรณ์อย่างเป็นมิตร\n"
                        f"- เชิญชวนสอบถามรายละเอียดเพิ่มเติมหรือให้ช่วยแนะนำอุปกรณ์ด้านอื่นได้เสมอค่ะ\n\n"
                        f"ข้อห้ามเด็ดขาด (Strict Output Constraints):\n"
                        f"- ห้ามพิมพ์หัวข้อคำสั่ง, ตัวเลขกำกับหัวข้อ, หรือคำว่า 'กฎเหล็ก' เด็ดขาด ให้ตอบเฉพาะเนื้อหาบทสนทนาจริงเท่านั้น\n"
                        f"- แชตบอตเป็นผู้หญิง 100% ต้องลงท้ายด้วย 'ค่ะ' หรือ 'นะคะ' เสมอ และเรียกผู้ใช้ว่า 'คุณลูกค้า' เสมอ\n"
                        f"- เว้นวรรคระหว่างภาษาไทยและภาษาอังกฤษเสมอ และห้ามมีตัวอักษรภาษาจีนเด็ดขาด"
                    )
                else:
                    prompt = (
                        f"คำขอของผู้ใช้: \"{request.message}\"\n\n"
                        f"สถานะคลังสินค้า: ไม่พบอุปกรณ์หรือบริการที่ตรงกับคำขอนี้ในระบบร้านยืมหน่อย\n"
                        f"หมวดหมู่สินค้าที่ทางร้านยืมหน่อยมีให้บริการพร้อมเช่าในปัจจุบัน:\n{cats_str}\n\n"
                        f"แนวทางการตอบ (เขียนเป็นบทสนทนาธรรมชาติสั้นกระชับ ให้อ่านง่ายและสบายตา):\n"
                        f"- แจ้งขออภัยอย่างสุภาพและจริงใจว่าทางร้านยืมหน่อยยังไม่มีบริการให้อุปกรณ์หรือหมวดหมู่นี้ในขณะนี้ค่ะ\n"
                        f"- สรุปหมวดหมู่หลักที่ทางร้านมีให้บริการพร้อมเช่าให้คุณลูกค้าทราบขอบเขตบริการ\n"
                        f"- เชิญชวนอย่างอบอุ่นให้สอบถามอุปกรณ์ในหมวดหมู่ที่มีให้บริการได้เสมอค่ะ\n\n"
                        f"ข้อห้ามเด็ดขาด (Strict Output Constraints):\n"
                        f"- ห้ามพิมพ์หัวข้อคำสั่ง, ตัวเลขกำกับหัวข้อ (เช่น 1., 2., 3.), หรือคำว่า 'กฎเหล็ก' เด็ดขาด ให้ตอบเฉพาะเนื้อหาบทสนทนาจริงเท่านั้น\n"
                        f"- แชตบอตเป็นผู้หญิง 100% ต้องลงท้ายด้วย 'ค่ะ' หรือ 'นะคะ' เสมอ และเรียกผู้ใช้ว่า 'คุณลูกค้า' เสมอ\n"
                        f"- เว้นวรรคระหว่างภาษาไทยและภาษาอังกฤษเสมอ และห้ามมีตัวอักษรภาษาจีนเด็ดขาด"
                    )
                messages = _build_multi_turn_messages(request.history, prompt)
                answer = await self.llm_service.generate_chat(
                    messages=messages,
                    system_instruction=SYSTEM_SYNTHESIZER,
                    temperature=0.3
                )
                clean_ans = sanitize_instruction_leakage(sanitize_thai_output(answer))
                return ChatResponseDTO(
                    response=clean_ans,
                    intent=decision.intent.value,
                    confidence=decision.confidence,
                    ambiguity_level=decision.ambiguity_level,
                    clarification=None,
                    items=[],
                    comparison=None
                )

            items_desc = "\n".join([
                f"- {it.display_name} (หมวดหมู่: {it.category}) : ราคา {_fmt_price(it.price)} บาท/{normalize_rental_unit(it.type)}\n  รายละเอียดสเปกจากระบบ: {it.description}"
                for it in matched_items
            ])
            matched_names = ", ".join([it.display_name for it in matched_items])
            item_count = len(matched_items)

            user_intent_note = ""
            if decision.slots.intended_use:
                user_intent_note = (
                    f"เป้าหมายหรือลักษณะการใช้งานที่ผู้ใช้ต้องการ: \"{decision.slots.intended_use}\"\n"
                    f"(คำสั่งสำคัญ: รายละเอียดสินค้าจากระบบอาจมีกิจกรรมส่วนตัวของผู้ให้เช่าปะปน เช่น ส่องนก หรือท่องเที่ยว ให้สกัดเฉพาะข้อเท็จจริงทางเทคนิค และสังเคราะห์ '• จุดเด่น:' กับ '• เหมาะสำหรับ:' ให้ตอบโจทย์เป้าหมายการใช้งานที่ระบุไว้นี้เป็นหลัก ห้ามลอกกิจกรรมที่ไม่เกี่ยวข้องของผู้ให้เช่ามาตอบเด็ดขาด)\n\n"
                )

            min_item_price = min(it.price for it in matched_items)
            budget_instruction = ""
            if decision.slots.budget_max and min_item_price > decision.slots.budget_max:
                budget_instruction = (
                    f"หมายเหตุเรื่องงบประมาณ: สินค้าของร้านมีราคาเริ่มต้นที่ {_fmt_price(min_item_price)} บาท ซึ่งสูงกว่างบ {_fmt_price(decision.slots.budget_max)} บาท เล็กน้อย ให้ชี้แจงสั้นๆ ภายในประโยคเปิด 1 บรรทัดค่ะ\n\n"
                )

            if item_count == 1:
                prompt = (
                    f"คำถามหรือความต้องการล่าสุดของผู้ใช้: \"{request.message}\"\n\n"
                    f"{user_intent_note}"
                    f"{budget_instruction}"
                    f"รายการสินค้าพร้อมเช่าที่คัดเลือกมาให้ผู้ใช้ ({matched_names}):\n{items_desc}\n\n"
                    f"คำสั่ง: จงสังเคราะห์คำตอบแนะนำสินค้าด้วยข้อความที่เป็นธรรมชาติ สุภาพ อบอุ่น ตามลำดับ 3 ส่วนดังนี้:\n"
                    f"1. ประโยคเปิด (1 บรรทัด): เขียนประโยคเปิดสั้นกระชับ 1 บรรทัด เพื่อแนะนำ {matched_items[0].display_name} ทันที (เช่น 'ขอแนะนำ {matched_items[0].display_name} ที่ตอบโจทย์การใช้งานของคุณลูกค้าค่ะ' ห้ามเกริ่นทักทายเวิ่นเว้อ และห้ามใส่สเปกลงในประโยคเปิดนี้)\n"
                    f"2. รายละเอียดสินค้า: แสดงหัวข้อและคุณสมบัติในรูปแบบ Markdown:\n"
                    f"### [ไอคอนอุปกรณ์ เช่น 💻, 📱, 📸, 🎸] {matched_items[0].display_name}\n"
                    f"• **ค่าเช่า**: {_fmt_price(matched_items[0].price)} บาท/{normalize_rental_unit(matched_items[0].type)}\n"
                    f"• **จุดเด่น**: สรุปสเปกเด่นและข้อดีในการใช้งานจริง 1 บรรทัด\n"
                    f"• **เหมาะสำหรับ**: สรุปกลุ่มผู้ใช้หรือโจทย์การใช้งานจริง 1 บรรทัด\n"
                    f"3. ประโยคปิดท้าย (1 บรรทัด): เว้น 1 บรรทัดว่าง แล้วปิดท้ายด้วยประโยคเชิญชวนแตะดูรายละเอียดเพิ่มเติมและกดเช่าจากรายการสินค้าด้านล่าง\n\n"
                    f"ข้อกำหนดรูปแบบการตอบ (Strict Formatting Constraints):\n"
                    f"- เขียนเนื้อหาคำตอบตามลำดับอย่างต่อเนื่องเป็นธรรมชาติ ห้ามพิมพ์ชื่อหัวข้อคำสั่ง (เช่น ห้ามพิมพ์ '1. ประโยคเปิด:', '2. รายละเอียดสินค้า:', '3. ประโยคปิดท้าย:') หรือตัวเลขกำกับขั้นตอนเด็ดขาด\n"
                    f"- ต้องมีประโยคเปิดความยาว 1 บรรทัดเสมอ เพื่อเกริ่นแนะนำสินค้าอย่างสุภาพ\n"
                    f"- ห้ามใส่วงเล็บก้ามปูหรือคัดลอกข้อความคำสั่งใน prompt ลงในคำตอบเด็ดขาด\n"
                    f"- ห้ามใส่เครื่องหมายคำพูด (เช่น \" หรือ “) ครอบประโยคบทสนทนาเด็ดขาด\n"
                    f"- บรรทัดชื่อสินค้าต้องขึ้นต้นด้วย '### [ไอคอนอุปกรณ์]' เสมอ โดยใช้ชื่อรุ่นทางการ '{matched_items[0].display_name}' ครบทุกตัวอักษรและตัวเลข ห้ามใส่เครื่องหมาย bullet หรือตัวเลขนำหน้าชื่อสินค้าเด็ดขาด\n"
                    f"- คำว่า **ค่าเช่า**, **จุดเด่น**, **เหมาะสำหรับ** ต้องมีเครื่องหมายดอกจันคู่ ** ปิดก่อนเครื่องหมายโคลอน (:) เสมอ\n"
                    f"- ประโยคสรุปปิดท้ายต้องเว้น 1 บรรทัดว่างเสมอ และแยกออกเป็นย่อหน้าใหม่อย่างชัดเจน (ห้ามนำไปต่อท้ายบรรทัดเหมาะสำหรับเด็ดขาด)\n"
                    f"- ห้ามใส่หัวข้อ 'คำแนะนำในการเลือก' หรือสรุปเปรียบเทียบใดๆ ทั้งสิ้น"
                )
            else:
                prompt = (
                    f"คำถามหรือความต้องการล่าสุดของผู้ใช้: \"{request.message}\"\n\n"
                    f"{user_intent_note}"
                    f"{budget_instruction}"
                    f"รายการสินค้าพร้อมเช่าที่คัดเลือกมาให้ผู้ใช้ ({matched_names}):\n{items_desc}\n\n"
                    f"คำสั่ง: จงสังเคราะห์คำตอบแนะนำสินค้าด้วยข้อความที่เป็นธรรมชาติ สุภาพ อบอุ่น ตามลำดับ 3 ส่วนดังนี้:\n"
                    f"1. ประโยคเปิด (1 บรรทัด): เขียนประโยคเปิดสั้นกระชับ 1 บรรทัด เพื่อแนะนำรุ่นที่ตอบโจทย์ความต้องการของผู้ใช้ทันที (เช่น 'ขอแนะนำอุปกรณ์ที่ตอบโจทย์การใช้งานของคุณลูกค้าดังนี้ค่ะ' ห้ามเกริ่นทักทายเวิ่นเว้อ และห้ามบรรยายความต้องการซ้ำซ้อน)\n"
                    f"2. รายละเอียดของแต่ละรุ่น: สำหรับแต่ละรุ่น ให้แสดงหัวข้อและคุณสมบัติในรูปแบบ Markdown:\n"
                    f"### [ไอคอนอุปกรณ์ เช่น 💻, 📱, 📸, 🎸] [ชื่อรุ่นทางการ]\n"
                    f"• **ค่าเช่า**: [ราคา] บาท/[หน่วยเช่า เช่น วัน หรือ ชั่วโมง]\n"
                    f"• **จุดเด่น**: สรุปสเปกเด่นและข้อดีในการใช้งานจริง 1 บรรทัด\n"
                    f"• **เหมาะสำหรับ**: สรุปกลุ่มผู้ใช้หรือโจทย์การใช้งานจริง 1 บรรทัด\n"
                    f"3. ประโยคปิดท้าย (1 บรรทัด): เว้น 1 บรรทัดว่าง แล้วปิดท้ายด้วยประโยคเชิญชวนแตะดูรายละเอียดเพิ่มเติมและกดเช่าจากรายการสินค้าด้านล่าง\n\n"
                    f"ข้อกำหนดรูปแบบการตอบ (Strict Formatting Constraints):\n"
                    f"- เขียนเนื้อหาคำตอบตามลำดับอย่างต่อเนื่องเป็นธรรมชาติ ห้ามพิมพ์ชื่อหัวข้อคำสั่ง (เช่น ห้ามพิมพ์ '1. ประโยคเปิด:', '2. รายละเอียดของแต่ละรุ่น:', '3. ประโยคปิดท้าย:') หรือตัวเลขกำกับขั้นตอนเด็ดขาด\n"
                    f"- ต้องมีประโยคเปิดความยาว 1 บรรทัดเสมอ เพื่อเกริ่นแนะนำสินค้าอย่างสุภาพ\n"
                    f"- ห้ามใส่วงเล็บก้ามปูหรือคัดลอกข้อความคำสั่งใน prompt ลงในคำตอบเด็ดขาด\n"
                    f"- ห้ามใส่เครื่องหมายคำพูด (เช่น \" หรือ “) ครอบประโยคบทสนทนาเด็ดขาด\n"
                    f"- บรรทัดชื่อสินค้าต้องขึ้นต้นด้วย '### [ไอคอนอุปกรณ์]' เสมอ โดยตัดคำนำหน้าประเภทสินค้าภาษาไทยออก และห้ามใส่เครื่องหมาย bullet หรือตัวเลขนำหน้าชื่อสินค้าเด็ดขาด\n"
                    f"- คำว่า **ค่าเช่า**, **จุดเด่น**, **เหมาะสำหรับ** ต้องมีเครื่องหมายดอกจันคู่ ** ปิดก่อนเครื่องหมายโคลอน (:) เสมอ\n"
                    f"- ประโยคสรุปปิดท้ายต้องเว้น 1 บรรทัดว่างเสมอ และแยกออกเป็นย่อหน้าใหม่อย่างชัดเจน (ห้ามนำไปต่อท้ายบรรทัดเหมาะสำหรับเด็ดขาด)\n"
                    f"- ห้ามใส่หัวข้อ 'คำแนะนำในการเลือก' หรือสรุปเปรียบเทียบใดๆ ทั้งสิ้น"
                )

            messages = _build_multi_turn_messages(request.history, prompt)
            answer = await self.llm_service.generate_chat(
                messages=messages,
                system_instruction=SYSTEM_SYNTHESIZER,
                temperature=0.3
            )

            final_text = sanitize_thai_output(answer)
            final_text = sanitize_instruction_leakage(final_text)
            final_text = strip_selection_guide(final_text)
            final_text = separate_trailing_card_cta(final_text)
            final_text = trim_verbose_recommendation_intro(final_text)

            item_dtos = [
                ItemDTO(
                    id=it.id,
                    name=it.display_name,
                    category=it.category,
                    price=it.price,
                    type=normalize_rental_unit(it.type),
                    status=it.status,
                    image_urls=it.item_image_url,
                    description=it.description
                )
                for it in matched_items
            ]

            return ChatResponseDTO(
                response=final_text,
                intent=decision.intent.value,
                confidence=decision.confidence,
                ambiguity_level=decision.ambiguity_level,
                clarification=None,
                items=item_dtos,
                comparison=None
            )

        elif decision.intent == IntentType.ITEM_SPEC_INQUIRY:
            prompt, matched_items, search_query, sources = await self.inquire_item_spec.execute(request.message, decision)
            messages = _build_multi_turn_messages(request.history, prompt)
            answer = await self.llm_service.generate_chat(
                messages=messages,
                system_instruction=SYSTEM_SYNTHESIZER,
                temperature=0.3
            )

            item_dtos = [
                ItemDTO(
                    id=it.id,
                    name=it.display_name if hasattr(it, 'display_name') else it.item_name,
                    category=it.category,
                    price=it.price,
                    type=normalize_rental_unit(it.type),
                    status=it.status,
                    image_urls=it.item_image_url,
                    description=it.description
                )
                for it in matched_items
            ]

            source_dtos = [
                VerifiedSourceDTO(
                    title=s.title,
                    link=s.link,
                    snippet=s.snippet,
                    relevance_score=s.relevance_score,
                    is_credible=s.is_credible
                )
                for s in sources
            ]

            final_spec_text = sanitize_instruction_leakage(sanitize_thai_output(answer))
            if not item_dtos:
                final_spec_text = strip_card_cta_if_no_items(final_spec_text)

            return ChatResponseDTO(
                response=final_spec_text,
                intent=decision.intent.value,
                confidence=decision.confidence,
                ambiguity_level=decision.ambiguity_level,
                clarification=None,
                items=item_dtos,
                comparison=None,
                search_query=search_query if search_query else None,
                search_sources=source_dtos
            )

        else:  # GENERAL_CHAT
            prompt = (
                f"ข้อความล่าสุดของผู้ใช้: \"{request.message}\"\n\n"
                f"แนวทางการตอบกลับ:\n"
                f"- หากผู้ใช้ทักทาย (สวัสดี, ดีครับ, ฮัลโหล): ให้ตอบทักทายอย่างอบอุ่น น่ารัก และเป็นมิตร ความยาว 1-2 ประโยคในย่อหน้าเดียวเท่านั้น ห้ามตัดคำว่า \"คุณลูกค้า\" เป็น \"คุณลูก\" หรือ \"คุณลูกน้อย\" และห้ามขึ้นบรรทัดใหม่เป็นท่อนๆ\n"
                f"  (ตัวอย่าง: \"สวัสดีค่ะคุณลูกค้า ยินดีต้อนรับสู่ร้านยืมหน่อยนะคะ วันนี้กำลังมองหาอุปกรณ์อะไร หรืออยากให้ช่วยแนะนำชิ้นไหน สอบถามน้องยืมหน่อยได้เลยนะคะ 😊\")\n"
                f"- หากผู้ใช้ถามความสามารถ (\"ทำไรได้\", \"ช่วยอะไรได้บ้าง\", \"คุณคือใคร\"): เริ่มต้นด้วยการแนะนำตัวว่า \"ฉันคือน้องยืมหน่อย AI ผู้ช่วยที่ปรึกษาการเช่าอุปกรณ์ประจำร้านยืมหน่อยค่ะ\" แล้วสรุปความสามารถหลัก 4 ข้อด้วย bullet points (-) ให้อ่านง่าย และเว้น 1 บรรทัดปิดท้ายด้วยประโยคเชิญชวนว่า \"คุณลูกค้าสามารถพิมพ์บอกสิ่งที่กำลังมองหา หรือสอบถามข้อมูลเพิ่มเติมได้เลยนะคะ\" (ห้ามพูดถึงการ์ดสินค้าด้านล่างเนื่องจากไม่มีการ์ดสินค้าแสดง)\n"
                f"- หากผู้ใช้ขอบคุณหรืออำลา: ตอบรับอย่างสุภาพ น่ารัก และยินดีให้บริการเสมอใน 1 ย่อหน้าสั้นๆ\n"
                f"- หากเป็นคำถามทั่วไป: ตอบกลับอย่างสุภาพ เป็นมิตร กระชับ ตรงประเด็น และแนะนำว่าสามารถสอบถามหรือค้นหาอุปกรณ์เช่าได้เสมอ\n\n"
                f"ข้อห้ามเด็ดขาด (Strict Output Constraints):\n"
                f"- ห้ามพิมพ์หัวข้อคำสั่ง, ตัวเลขกำกับหัวข้อ, หรือคำว่า 'กฎเหล็ก' เด็ดขาด ให้ตอบเฉพาะเนื้อหาบทสนทนาจริงเท่านั้น\n"
                f"- แชตบอตเป็นผู้หญิง 100% ต้องลงท้ายด้วย 'ค่ะ' หรือ 'นะคะ' เสมอ และเรียกผู้ใช้ว่า 'คุณลูกค้า' เสมอ\n"
                f"- ห้ามแนะนำสินค้าที่ไม่มีอยู่จริง และไม่ต้องใส่การ์ดสินค้า\n"
                f"- เว้นวรรคระหว่างภาษาไทยและภาษาอังกฤษเสมอ และห้ามมีตัวอักษรภาษาจีนเด็ดขาด"
            )
            messages = _build_multi_turn_messages(request.history, prompt)
            answer = await self.llm_service.generate_chat(
                messages=messages,
                system_instruction=SYSTEM_SYNTHESIZER,
                temperature=0.2
            )
            clean_gen = sanitize_instruction_leakage(sanitize_thai_output(answer))
            return ChatResponseDTO(
                response=clean_gen,
                intent=decision.intent.value,
                confidence=decision.confidence,
                ambiguity_level=decision.ambiguity_level,
                clarification=None,
                items=[],
                comparison=None
            )
