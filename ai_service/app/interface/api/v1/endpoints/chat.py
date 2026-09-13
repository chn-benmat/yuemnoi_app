from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
import json
import asyncio
from urllib.parse import urlparse
from app.interface.schemas.chat_request import ChatRequest
from app.interface.schemas.chat_response import ChatResponse
from app.application.dtos.chat_dto import ChatRequestDTO, ChatMessageDTO
from app.core.container import Container, get_container
from app.domain.entities.chat import ChatMessage, ChatRole
from app.infrastructure.utils.text_sanitizer import (
    sanitize_thai_output,
    sanitize_streaming_token,
    normalize_rental_unit,
    strip_selection_guide,
    strip_card_cta_if_no_items,
    sanitize_instruction_leakage,
    separate_trailing_card_cta,
    trim_verbose_recommendation_intro,
    StreamingLineSanitizer
)
from app.core.logging import logger

def build_multi_turn_messages(
    history: list,
    latest_user_prompt: str,
    max_history_turns: int = 4
) -> list[ChatMessage]:
    """Build multi-turn ChatMessage objects preserving user and assistant turns without dumping string prefixes."""
    messages: list[ChatMessage] = []
    if history:
        for m in history[-max_history_turns:]:
            role = ChatRole.ASSISTANT if m.role == "assistant" else ChatRole.USER
            content = m.content.strip()
            if content:
                messages.append(ChatMessage(role=role, content=content))
    messages.append(ChatMessage(role=ChatRole.USER, content=latest_user_prompt))
    return messages

router = APIRouter(prefix="/chat", tags=["Chat"])

@router.post("", response_model=ChatResponse)
async def chat_message(
    request: ChatRequest,
    container: Container = Depends(get_container)
) -> ChatResponse:
    """Standard Chat endpoint returning complete response with intent, items, choices, and comparison."""
    try:
        dto = ChatRequestDTO(
            message=request.message,
            session_id=request.session_id,
            history=[ChatMessageDTO(role=m.role, content=m.content) for m in request.history]
        )
        result = await container.process_chat_message_use_case.execute(dto)
        questions = result.clarification.questions if result.clarification else []
        return ChatResponse(
            response=result.response,
            intent=result.intent,
            confidence=result.confidence,
            ambiguity_level=result.ambiguity_level,
            clarification=result.clarification,
            questions=questions,
            items=result.items,
            comparison=result.comparison,
            search_query=result.search_query,
            search_sources=result.search_sources
        )
    except Exception as e:
        logger.error(f"Error processing chat request: {e}")
        raise HTTPException(status_code=500, detail=str(e))

from app.domain.entities.intent import IntentType
from app.infrastructure.llm.prompt_templates import SYSTEM_SYNTHESIZER

@router.post("/stream")
async def chat_stream(
    request: ChatRequest,
    container: Container = Depends(get_container)
):
    """Streaming Chat endpoint using Server-Sent Events (SSE) orchestrating intent routing, clarification, and catalog retrieval."""
    async def event_generator():
        try:
            # Build history context
            history_context = ""
            if request.history:
                history_context = "\n".join([f"{m.role}: {m.content}" for m in request.history[-4:]])

            user_msg = request.message.strip()

            # Step 1: AI Intent & Ambiguity Classification
            yield f"event: status\ndata: {json.dumps({'step': 'intent_analysis', 'message': 'กำลังวิเคราะห์คำถาม...'}, ensure_ascii=False)}\n\n"
            decision = await container.route_intent_use_case.execute(user_msg, history_context=history_context)
            logger.info(f"Stream Intent: {decision.intent.value} (Confidence: {decision.confidence}, Ambiguity: {decision.ambiguity_level})")

            # Branch A: คำถามกว้างหรือกำกวม ต้องการความชัดเจน (สร้างชุดคำถามแบบสอบถาม 2-3 ข้อต่อเนื่องในรอบเดียว)
            if decision.intent == IntentType.CLARIFICATION_NEEDED:
                yield f"event: status\ndata: {json.dumps({'step': 'clarification', 'message': 'กำลังสร้างตัวเลือกแนะนำ...'}, ensure_ascii=False)}\n\n"
                clarification = await container.generate_clarification_use_case.execute(
                    user_msg, decision, history_context=history_context
                )

                if clarification.steps:
                    questions_data = [
                        {
                            "id": st.id,
                            "title": st.title,
                            "options": st.options,
                            "step": st.step,
                            "total_steps": st.total_steps,
                            "branch_titles": st.branch_titles,
                            "branch_options": st.branch_options
                        }
                        for st in clarification.steps
                    ]
                    options_labels = clarification.steps[0].options
                elif clarification.options:
                    questions_data = [
                        {
                            "id": "clarification_q1",
                            "title": clarification.question,
                            "options": [opt.label for opt in clarification.options],
                            "step": 1,
                            "total_steps": 1,
                            "branch_titles": None,
                            "branch_options": None
                        }
                    ]
                    options_labels = [opt.label for opt in clarification.options]
                else:
                    questions_data = []
                    options_labels = []

                # ส่ง metadata เพื่อให้ Flutter เตรียม UI คำถามและช้อยส์ตัวเลือก
                metadata_payload = {
                    "mode": "clarification",
                    "questions": questions_data,
                    "recommended_items": []
                }
                yield f"event: metadata\ndata: {json.dumps(metadata_payload, ensure_ascii=False)}\n\n"

                # สตรีมข้อความเกริ่นนำเป็นภาษาไทยทีละชิ้น (Typewriter Effect)
                words = clarification.question.split(" ")
                for i, w in enumerate(words):
                    chunk = w if i == len(words) - 1 else w + " "
                    yield f"event: delta\ndata: {json.dumps({'text': chunk, 'token': chunk}, ensure_ascii=False)}\n\n"
                    await asyncio.sleep(0.03)

                activities = [
                    "วิเคราะห์คำถามและเจตนาของผู้ใช้",
                    "สร้างตัวเลือกและคำถามเพื่อขอข้อมูลเพิ่มเติม"
                ]
                done_payload = {
                    "status": "done",
                    "answer": clarification.question,
                    "questions": questions_data,
                    "suggested_replies": options_labels,
                    "recommended_items": [],
                    "activities": activities
                }
                yield f"event: done\ndata: {json.dumps(done_payload, ensure_ascii=False)}\n\n"
                return

            # Branch B: สอบถามสินค้าในร้าน (ค้นหาจาก Supabase item_tb)
            elif decision.intent == IntentType.ITEM_INQUIRY:
                yield f"event: status\ndata: {json.dumps({'step': 'searching', 'message': 'กำลังค้นหาอุปกรณ์ในระบบ...'}, ensure_ascii=False)}\n\n"
                matched_items = await container.query_items_use_case.execute(
                    user_query=user_msg,
                    target_item_names=decision.slots.target_items,
                    category_hints=decision.slots.categories,
                    intended_use=decision.slots.intended_use,
                    budget_max=decision.slots.budget_max,
                    limit=3
                )

                if not matched_items:
                    available_categories = await container.query_items_use_case.get_available_categories()
                    cats_str = ", ".join(available_categories)

                    prompt = (
                        f"คำขอของผู้ใช้: \"{user_msg}\"\n\n"
                        f"สถานะคลังสินค้า: ไม่พบอุปกรณ์หรือบริการที่ตรงกับคำขอนี้ในระบบร้านยืมหน่อย\n"
                        f"หมวดหมู่สินค้าที่ทางร้านยืมหน่อยมีให้บริการพร้อมเช่าในปัจจุบัน:\n{cats_str}\n\n"
                        f"แนวทางการตอบ (เขียนเป็นบทสนทนาธรรมชาติสั้นกระชับ ให้อ่านง่ายและสบายตา):\n"
                        f"- แจ้งขออภัยอย่างสุภาพและจริงใจว่าทางร้านยืมหน่อยยังไม่มีบริการให้อุปกรณ์หรือหมวดหมู่นี้ในขณะนี้ค่ะ\n"
                        f"- สรุปหมวดหมู่หลักที่ทางร้านมีให้บริการพร้อมเช่าให้คุณลูกค้าทราบขอบเขตบริการ\n"
                        f"- เชิญชวนอย่างอบอุ่นให้สอบถามอุปกรณ์ในหมวดหมู่ที่มีให้บริการได้เสมอค่ะ\n\n"
                        f"ข้อห้ามเด็ดขาด (Strict Output Constraints):\n"
                        f"- ห้ามพิมพ์หัวข้อคำสั่ง, ตัวเลขกำกับหัวข้อ (เช่น 1., 2., 3.), หรือคำว่า 'กฎเหล็ก' เด็ดขาด ให้ตอบเฉพาะเนื้อหาบทสนทนาจริงเท่านั้น"
                    )

                    yield f"event: metadata\ndata: {json.dumps({'mode': 'recommendation', 'recommended_items': [], 'questions': []}, ensure_ascii=False)}\n\n"

                    messages = build_multi_turn_messages(request.history, prompt)
                    full_answer = []
                    sanitizer = StreamingLineSanitizer()
                    async for token in container.llm_service.generate_chat_stream(messages, system_instruction=SYSTEM_SYNTHESIZER):
                        for clean_chunk in sanitizer.process_token(token):
                            full_answer.append(clean_chunk)
                            yield f"event: delta\ndata: {json.dumps({'token': clean_chunk, 'text': clean_chunk}, ensure_ascii=False)}\n\n"
                    for flush_chunk in sanitizer.flush():
                        full_answer.append(flush_chunk)
                        yield f"event: delta\ndata: {json.dumps({'token': flush_chunk, 'text': flush_chunk}, ensure_ascii=False)}\n\n"

                    final_text = sanitize_thai_output("".join(full_answer))
                    final_text = sanitize_instruction_leakage(final_text)
                    done_payload = {
                        "status": "done",
                        "answer": final_text,
                        "recommended_items": [],
                        "questions": []
                    }
                    yield f"event: done\ndata: {json.dumps(done_payload, ensure_ascii=False)}\n\n"
                    return

                items_data = [
                    {
                        "id": it.id,
                        "name": it.display_name,
                        "item_name": it.display_name,
                        "category": it.category,
                        "price": it.price,
                        "price_unit": normalize_rental_unit(it.type),
                        "unit": normalize_rental_unit(it.type),
                        "status": it.status,
                        "image_url": it.item_image_url[0] if it.item_image_url else "",
                        "description": it.description
                    }
                    for it in matched_items
                ]

                # ส่ง metadata รายการสินค้าให้ Flutter แสดงการ์ดสินค้า
                yield f"event: metadata\ndata: {json.dumps({'mode': 'recommendation', 'recommended_items': items_data, 'questions': []}, ensure_ascii=False)}\n\n"
                yield f"event: status\ndata: {json.dumps({'step': 'synthesizing', 'message': 'กำลังสรุปคำแนะนำ...'}, ensure_ascii=False)}\n\n"

                def _fmt_price(val: float) -> str:
                    return str(int(val)) if val.is_integer() else f"{val:.2f}"

                items_desc = "\n".join([
                    f"- {it.display_name} (หมวดหมู่: {it.category}) : ราคา {_fmt_price(it.price)} บาท/{normalize_rental_unit(it.type)}\n  รายละเอียด: {it.description}"
                    for it in matched_items
                ])
                matched_names = ", ".join([it.display_name for it in matched_items])
                item_count = len(matched_items)

                min_item_price = min(it.price for it in matched_items)
                user_intent_note = ""
                if decision.slots.intended_use:
                    user_intent_note = (
                        f"เป้าหมายหรือลักษณะการใช้งานที่ผู้ใช้ต้องการ: \"{decision.slots.intended_use}\"\n"
                        f"(คำสั่งสำคัญ: สกัดเฉพาะข้อเท็จจริงทางเทคนิค และสังเคราะห์ '• จุดเด่น:' กับ '• เหมาะสำหรับ:' ให้ตอบโจทย์เป้าหมายการใช้งานที่ระบุไว้นี้เป็นหลัก ห้ามลอกกิจกรรมที่ไม่เกี่ยวข้องของผู้ให้เช่ามาตอบเด็ดขาด)\n\n"
                    )

                budget_instruction = ""
                if decision.slots.budget_max and min_item_price > decision.slots.budget_max:
                    budget_instruction = (
                        f"หมายเหตุเรื่องงบประมาณ: สินค้าของร้านมีราคาเริ่มต้นที่ {_fmt_price(min_item_price)} บาท ซึ่งสูงกว่างบ {_fmt_price(decision.slots.budget_max)} บาท เล็กน้อย ให้ชี้แจงสั้นๆ ภายในประโยคเปิด 1 บรรทัดค่ะ\n\n"
                    )

                if item_count == 1:
                    prompt = (
                        f"คำถามหรือความต้องการล่าสุดของผู้ใช้: \"{user_msg}\"\n\n"
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
                        f"คำถามหรือความต้องการล่าสุดของผู้ใช้: \"{user_msg}\"\n\n"
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

                messages = build_multi_turn_messages(request.history, prompt)
                full_answer = []
                sanitizer = StreamingLineSanitizer()
                async for token in container.llm_service.generate_chat_stream(messages, system_instruction=SYSTEM_SYNTHESIZER):
                    for clean_chunk in sanitizer.process_token(token):
                        full_answer.append(clean_chunk)
                        yield f"event: delta\ndata: {json.dumps({'token': clean_chunk, 'text': clean_chunk}, ensure_ascii=False)}\n\n"
                for flush_chunk in sanitizer.flush():
                    full_answer.append(flush_chunk)
                    yield f"event: delta\ndata: {json.dumps({'token': flush_chunk, 'text': flush_chunk}, ensure_ascii=False)}\n\n"

                final_text = sanitize_thai_output("".join(full_answer))
                final_text = sanitize_instruction_leakage(final_text)
                final_text = strip_selection_guide(final_text)
                final_text = separate_trailing_card_cta(final_text)
                final_text = trim_verbose_recommendation_intro(final_text)

                activities = [
                    "วิเคราะห์คำถามและเจตนาของผู้ใช้",
                    "ค้นหาอุปกรณ์ที่ตรงกับความต้องการในคลังระบบ Yuemnoi",
                    "สรุปรายการแนะนำและรายละเอียดการเช่า"
                ]
                done_payload = {
                    "status": "done",
                    "answer": final_text,
                    "recommended_items": items_data,
                    "questions": [],
                    "activities": activities
                }
                yield f"event: done\ndata: {json.dumps(done_payload, ensure_ascii=False)}\n\n"
                return

            # Branch C: สอบถามสเปก มิติ ขนาด น้ำหนัก ของอุปกรณ์ (ITEM_SPEC_INQUIRY)
            elif decision.intent == IntentType.ITEM_SPEC_INQUIRY:
                yield f"event: status\ndata: {json.dumps({'step': 'spec_inquiry', 'message': 'กำลังตรวจสอบสเปกและมิติอุปกรณ์...'}, ensure_ascii=False)}\n\n"
                prompt, matched_items, search_query, sources = await container.inquire_item_spec_use_case.execute(user_msg, decision)
                items_data = [
                    {
                        "id": it.id,
                        "name": it.display_name,
                        "item_name": it.display_name,
                        "category": it.category,
                        "price": it.price,
                        "price_unit": normalize_rental_unit(it.type),
                        "unit": normalize_rental_unit(it.type),
                        "status": it.status,
                        "image_url": it.item_image_url[0] if it.item_image_url else "",
                        "description": it.description
                    }
                    for it in matched_items
                ]
                yield f"event: metadata\ndata: {json.dumps({'mode': 'spec', 'recommended_items': items_data, 'questions': []}, ensure_ascii=False)}\n\n"
                yield f"event: status\ndata: {json.dumps({'step': 'synthesizing', 'message': 'กำลังเรียบเรียงข้อมูลสเปก...'}, ensure_ascii=False)}\n\n"
                messages = build_multi_turn_messages(request.history, prompt)
                full_answer = []
                sanitizer = StreamingLineSanitizer()
                async for token in container.llm_service.generate_chat_stream(messages, system_instruction=SYSTEM_SYNTHESIZER):
                    for clean_chunk in sanitizer.process_token(token):
                        full_answer.append(clean_chunk)
                        yield f"event: delta\ndata: {json.dumps({'token': clean_chunk, 'text': clean_chunk}, ensure_ascii=False)}\n\n"
                for flush_chunk in sanitizer.flush():
                    full_answer.append(flush_chunk)
                    yield f"event: delta\ndata: {json.dumps({'token': flush_chunk, 'text': flush_chunk}, ensure_ascii=False)}\n\n"

                final_text = sanitize_thai_output("".join(full_answer))
                if not items_data:
                    final_text = strip_card_cta_if_no_items(final_text)
                search_sources_data = [
                    {
                        "title": s.title,
                        "url": s.link,
                        "domain": urlparse(s.link).netloc if s.link else "",
                        "snippet": s.snippet
                    }
                    for s in sources
                ]
                activities = [
                    "วิเคราะห์คำถามและเจตนาของผู้ใช้",
                    "ตรวจสอบสเปกและมิติอุปกรณ์ในระบบ Yuemnoi",
                ]
                if search_query:
                    activities.append(f"ค้นหาข้อมูลและสเปกจาก Google (\"{search_query}\")")
                    activities.append("ตรวจสอบความถูกต้องของสเปกและตัดข้อมูลโฆษณา")
                activities.append("เรียบเรียงข้อมูลสเปกและสรุปคำแนะนำ")

                done_payload = {
                    "status": "done",
                    "answer": final_text,
                    "recommended_items": items_data,
                    "questions": [],
                    "search_query": search_query if search_query else None,
                    "search_sources": search_sources_data,
                    "activities": activities
                }
                yield f"event: done\ndata: {json.dumps(done_payload, ensure_ascii=False)}\n\n"
                return

            # Branch D: เปรียบเทียบอุปกรณ์ (RENTAL_COMPARISON)
            elif decision.intent == IntentType.RENTAL_COMPARISON:
                status_queue: asyncio.Queue = asyncio.Queue()

                async def on_status(step: str, message: str) -> None:
                    await status_queue.put((step, message))

                prep_task = asyncio.create_task(
                    container.compare_items_use_case.prepare_comparison(
                        user_msg, decision, on_status=on_status
                    )
                )

                while not prep_task.done():
                    try:
                        step, msg = await asyncio.wait_for(status_queue.get(), timeout=2.0)
                        yield f"event: status\ndata: {json.dumps({'step': step, 'message': msg}, ensure_ascii=False)}\n\n"
                    except asyncio.TimeoutError:
                        # Send standard SSE keepalive comment line to keep connection fresh and reset stream timeout
                        yield ": ping\n\n"

                # Drain remaining status updates
                while not status_queue.empty():
                    step, msg = status_queue.get_nowait()
                    yield f"event: status\ndata: {json.dumps({'step': step, 'message': msg}, ensure_ascii=False)}\n\n"

                prompt, matrix, matched_items = await prep_task

                items_data = [
                    {
                        "id": it.id,
                        "name": it.display_name,
                        "item_name": it.display_name,
                        "category": it.category,
                        "price": it.price,
                        "price_unit": normalize_rental_unit(it.type),
                        "unit": normalize_rental_unit(it.type),
                        "status": it.status,
                        "image_url": it.item_image_url[0] if it.item_image_url else "",
                        "description": it.description
                    }
                    for it in matched_items
                ]

                # ส่ง metadata รายการสินค้าที่นำมาเปรียบเทียบให้ Flutter แสดงการ์ดสินค้า
                yield f"event: metadata\ndata: {json.dumps({'mode': 'comparison', 'recommended_items': items_data, 'questions': []}, ensure_ascii=False)}\n\n"

                yield f"event: status\ndata: {json.dumps({'step': 'synthesizing', 'message': 'กำลังเรียบเรียงผลการเปรียบเทียบ...'}, ensure_ascii=False)}\n\n"

                messages = build_multi_turn_messages(request.history, prompt)
                full_answer = []
                sanitizer = StreamingLineSanitizer()
                async for token in container.llm_service.generate_chat_stream(messages, system_instruction=SYSTEM_SYNTHESIZER):
                    for clean_chunk in sanitizer.process_token(token):
                        full_answer.append(clean_chunk)
                        yield f"event: delta\ndata: {json.dumps({'token': clean_chunk, 'text': clean_chunk}, ensure_ascii=False)}\n\n"
                for flush_chunk in sanitizer.flush():
                    full_answer.append(flush_chunk)
                    yield f"event: delta\ndata: {json.dumps({'token': flush_chunk, 'text': flush_chunk}, ensure_ascii=False)}\n\n"

                final_text = sanitize_thai_output("".join(full_answer))
                final_text = sanitize_instruction_leakage(final_text)
                final_text = strip_selection_guide(final_text)
                if not items_data:
                    final_text = strip_card_cta_if_no_items(final_text)

                search_sources_data = [
                    {
                        "title": s.title,
                        "url": s.link,
                        "domain": urlparse(s.link).netloc if s.link else "",
                        "snippet": s.snippet
                    }
                    for s in matrix.sources
                ]
                activities = [
                    "วิเคราะห์คำถามและเจตนาของผู้ใช้",
                    "ค้นหาอุปกรณ์ในคลังระบบ Yuemnoi",
                    f"ค้นหาข้อมูลและสเปกจาก Google (\"{matrix.search_query}\")" if matrix.search_query else "ค้นหาข้อมูลสเปกจากอินเทอร์เน็ต",
                    "ตรวจสอบความถูกต้องของสเปกและตัดข้อมูลโฆษณา",
                    "เรียบเรียงผลการเปรียบเทียบและสรุปคำแนะนำ"
                ]
                done_payload = {
                    "status": "done",
                    "answer": final_text,
                    "recommended_items": items_data,
                    "questions": [],
                    "search_query": matrix.search_query,
                    "search_sources": search_sources_data,
                    "activities": activities
                }
                yield f"event: done\ndata: {json.dumps(done_payload, ensure_ascii=False)}\n\n"
                return

            # Branch D: แชททั่วไป (GENERAL_CHAT)
            else:
                yield f"event: status\ndata: {json.dumps({'step': 'synthesizing', 'message': 'กำลังเรียบเรียงคำตอบ...'}, ensure_ascii=False)}\n\n"
                prompt = (
                    f"ข้อความล่าสุดของผู้ใช้: \"{user_msg}\"\n\n"
                    f"แนวทางการตอบกลับตาม SYSTEM_SYNTHESIZER (ตอบอย่างเป็นธรรมชาติ สุภาพ อบอุ่น และเป็นมิตร):\n"
                    f"- หากผู้ใช้ทักทาย (สวัสดี, ดีครับ, ฮัลโหล): ให้ตอบทักทายอย่างอบอุ่น น่ารัก และเป็นมิตร ความยาว 1-2 ประโยคในย่อหน้าเดียวเท่านั้น เช่น \"สวัสดีค่ะคุณลูกค้า ยินดีต้อนรับสู่ร้านยืมหน่อยนะคะ วันนี้กำลังมองหาอุปกรณ์อะไร หรืออยากให้ช่วยแนะนำชิ้นไหน สอบถามน้องยืมหน่อยได้เลยนะคะ 😊\"\n"
                    f"- หากผู้ใช้ถามความสามารถ (\"ทำไรได้\", \"ช่วยอะไรได้บ้าง\", \"คุณคือใคร\"): แนะนำตัวสั้นๆ ว่า \"ฉันคือน้องยืมหน่อย AI ผู้ช่วยที่ปรึกษาการเช่าอุปกรณ์ประจำร้านยืมหน่อยค่ะ\" แล้วสรุปความสามารถหลัก 4 ข้อด้วย bullet points (-) ให้อ่านง่าย และเว้น 1 บรรทัดปิดท้ายด้วยประโยคเชิญชวนว่า \"คุณลูกค้าสามารถพิมพ์บอกสิ่งที่กำลังมองหา หรือสอบถามข้อมูลเพิ่มเติมได้เลยนะคะ\" (ห้ามพูดถึงการ์ดสินค้าด้านล่างเนื่องจากไม่มีการ์ดสินค้าแสดง)\n"
                    f"- หากผู้ใช้ขอบคุณหรืออำลา: ตอบรับอย่างสุภาพ น่ารัก และยินดีให้บริการเสมอใน 1 ย่อหน้าสั้นๆ\n"
                    f"- หากเป็นคำถามทั่วไป: ตอบกลับอย่างสุภาพ เป็นมิตร กระชับ ตรงประเด็น และแนะนำว่าสามารถสอบถามหรือค้นหาอุปกรณ์เช่าได้เสมอ\n\n"
                    f"ข้อห้ามเด็ดขาด:\n"
                    f"- ห้ามพิมพ์หัวข้อคำสั่ง หรือนำข้อความกฎเกณฑ์มาแสดงในคำตอบเด็ดขาด ให้ตอบเฉพาะบทสนทนาจริงเท่านั้น"
                )
                messages = build_multi_turn_messages(request.history, prompt)
                full_answer = []
                sanitizer = StreamingLineSanitizer()
                async for token in container.llm_service.generate_chat_stream(messages, system_instruction=SYSTEM_SYNTHESIZER, temperature=0.2):
                    for clean_chunk in sanitizer.process_token(token):
                        full_answer.append(clean_chunk)
                        yield f"event: delta\ndata: {json.dumps({'token': clean_chunk, 'text': clean_chunk}, ensure_ascii=False)}\n\n"
                for flush_chunk in sanitizer.flush():
                    full_answer.append(flush_chunk)
                    yield f"event: delta\ndata: {json.dumps({'token': flush_chunk, 'text': flush_chunk}, ensure_ascii=False)}\n\n"

                final_text = sanitize_thai_output("".join(full_answer))
                final_text = sanitize_instruction_leakage(final_text)
                activities = [
                    "วิเคราะห์ข้อความของผู้ใช้",
                    "เรียบเรียงคำตอบและข้อความต้อนรับ"
                ]
                yield f"event: done\ndata: {json.dumps({'status': 'done', 'answer': final_text, 'questions': [], 'recommended_items': [], 'activities': activities}, ensure_ascii=False)}\n\n"
                return

        except Exception as e:
            logger.error(f"Stream error: {e}")
            yield f"event: error\ndata: {json.dumps({'error': str(e), 'error_code': 'stream_error'}, ensure_ascii=False)}\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")
