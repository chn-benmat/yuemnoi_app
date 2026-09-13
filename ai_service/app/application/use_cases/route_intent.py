import json
from typing import List, Optional
from pydantic import BaseModel, Field
from app.domain.entities.intent import IntentType, IntentDecision, ExtractedSlots
from app.domain.interfaces.llm_service import LLMServiceInterface
from app.infrastructure.llm.prompt_templates import SYSTEM_INTENT_ROUTER
from app.core.logging import logger

class ExtractedEntitiesModel(BaseModel):
    target_items: List[str] = Field(
        default_factory=list,
        description=(
            "ชื่อรุ่นสินค้า ชื่อซีรีส์ หรือแบรนด์เฉพาะเจาะจงระดับโมเดล เช่น 'iPhone 15 Pro', 'Canon EOS R50', 'Sony Alpha', 'PlayStation 5' "
            "(กรณีเปรียบเทียบ ให้ดึงชื่ออุปกรณ์หรือแบรนด์ทั้ง 2 ชิ้นมาใส่ในลิสต์นี้เสมอ แม้จะเป็นคำกว้างๆ; "
            "หากผู้ใช้ถามหารุ่นที่ถูกกว่าหรือประหยัดกว่าของอุปกรณ์ล่าสุด เช่น 'มีที่ถูกกว่านี้ไหม' ให้เว้นว่างเป็น [] เสมอ เพื่อให้ค้นหารุ่นอื่นในหมวดเดียวกัน; "
            "กฎเหล็ก: ห้ามใส่คำเรียกประเภททั่วไป เช่น 'มือถือ', 'กล้อง', 'คอม' และห้ามใส่ข้อความบรรยายคุณลักษณะหรือตัวเลือกจากแบบสอบถาม "
            "เช่น 'สมาร์ตโฟนจอใหญ่สำหรับทำงาน', 'กล้องท่องเที่ยว/Vlog', 'โน้ตบุ๊กทำงานกราฟิก', 'ประชุมออนไลน์' โดยเด็ดขาด "
            "ให้นำไปใส่ใน intended_use แทน หากไม่มีชื่อรุ่นหรือแบรนด์เฉพาะ ให้เว้นว่างเป็น [])"
        )
    )
    target_items_are_specific: bool = Field(
        default=True,
        description="จริง หากสินค้าที่ต้องการเปรียบเทียบหรือค้นหาทุกชิ้นเป็น 'ชื่อรุ่นเฉพาะเจาะจงระดับโมเดล' ชัดเจน (เช่น 'Sony A7 IV', 'iPhone 15 Pro', 'Canon EOS R50') แต่เป็นเท็จ หากมีสินค้าชิ้นใดชิ้นหนึ่งหรือทั้งหมดเป็นชื่อกว้างๆ, ชื่อซีรีส์, ชื่อแบรนด์ลอยๆ, คำบรรยายคุณลักษณะ หรือคำเปรียบเทียบสัมพัทธ์ (เช่น 'Sony Alpha', 'iphon ล่าสุด', 'iPhone รุ่นล่าสุด', 'iPhone', 'กล้อง Canon', 'มือถือ', 'สมาร์ตโฟนจอใหญ่')"
    )
    categories: List[str] = Field(
        default_factory=list,
        description=(
            "หมวดหมู่ทางการ 11 หมวดของร้านที่ตรงกับอุปกรณ์ที่ผู้ใช้เอ่ยถึง: "
            "1. 'โทรศัพท์และอุปกรณ์สื่อสาร' (สำหรับ มือถือ, โทรศัพท์, สมาร์ตโฟน, วอ), "
            "2. 'คอมพิวเตอร์และอุปกรณ์ไอที' (สำหรับ คอม, โน้ตบุ๊ก, แท็บเล็ต, แล็ปท็อป, คอมพิวเตอร์), "
            "3. 'กล้องและอุปกรณ์ถ่ายภาพ' (สำหรับ กล้อง, เลนส์, ไฟถ่ายภาพ, โดรน), "
            "4. 'ดนตรีและเครื่องดนตรี' (สำหรับ กีตาร์, กีต้า, เบส, คีย์บอร์ด, กลอง), "
            "5. 'เกมและความบันเทิง' (สำหรับ เกม, เครื่องเล่นเกม, PS5, Switch), "
            "6. 'เครื่องเสียงและอุปกรณ์จัดงาน' (สำหรับ ลำโพง, ไมค์, ไมโครโฟน), "
            "7. 'กีฬาและออกกำลังกาย', 8. 'แคมป์ปิงและกิจกรรมกลางแจ้ง', 9. 'เครื่องมือช่างและงานก่อสร้าง', 10. 'เครื่องใช้ไฟฟ้าและอุปกรณ์ภายในบ้าน', 11. 'อื่น ๆ' "
            "(หากผู้ใช้ถามกว้างระดับร้านโดยไม่ระบุชนิดอุปกรณ์ใดๆ เลย เช่น 'แนะนำอุปกรณ์เช่าหน่อย', 'มีอะไรให้เช่าบ้าง' ให้เว้นว่างเป็น [])"
        )
    )
    target_attribute: Optional[str] = Field(
        None, 
        description="มิติ คุณลักษณะ หรือหัวข้อการนำไปใช้งานที่ถาม เช่น ขนาด, มิติ, น้ำหนัก, แบตเตอรี่, เซนเซอร์, พอร์ต, ความเหมาะสม (เช่น 'เหมาะเอามาเล่นเกมจริงดิ', 'เล่นเกมไหวไหม'), หรือการนำไปใช้งาน (เช่น 'เอาไปใช้อะไรได้บ้าง', 'ทำอะไรได้บ้าง', 'เหมาะกับงานอะไร')"
    )
    budget_max: Optional[float] = Field(
        None, 
        description="งบประมาณสูงสุดที่เป็นตัวเลข เช่น หากผู้ใช้ระบุ 'ประหยัด (ไม่เกิน 350 บ./วัน)' ให้สกัด 350.0, หากระบุ 'ไม่เกิน 500' ให้สกัด 500.0, หากผู้ใช้ถามหาราคาที่ถูกกว่าหรือประหยัดกว่าของอุปกรณ์ล่าสุดในประวัติ (เช่น 'มีที่ถูกกว่านี้ไหม') ให้สกัดตัวเลขราคาเช่าของอุปกรณ์เดิมในประวัติมาใส่ เช่น 900.0, หากระบุ 'ตามความเหมาะสม / ไม่จำกัด' หรือไม่มี ให้เป็น null"
    )
    rental_duration: Optional[str] = Field(None, description="ระยะเวลาที่ต้องการเช่า")
    intended_use: Optional[str] = Field(None, description="ลักษณะหรือวัตถุประสงค์การใช้งาน")

class IntentClassificationResult(BaseModel):
    intent: IntentType = Field(
        ..., 
        description=(
            "ประเภท Intent ของคำถาม: "
            "'ITEM_SPEC_INQUIRY' (หากถามเจาะจงเกี่ยวกับสเปก, ขนาด, น้ำหนัก, แบตเตอรี่, ประสิทธิภาพ, ความเหมาะสม, หรือการนำไปใช้งาน/ความสามารถของสินค้า เช่น 'เอาไปใช้อะไรได้บ้าง', 'ทำอะไรได้บ้าง', 'เหมาะกับงานอะไร', 'เล่นเกมไหวไหม', 'เหมาะเอามา...จริงดิ', 'พอร์ตอะไร'); "
            "'RENTAL_COMPARISON' (หากถามเปรียบเทียบสเปก ความคุ้มค่า หรือความเหมาะสมระหว่างอุปกรณ์ 2 รายการขึ้นไป เช่น 'A กับ B อันไหนดีกว่า/เหมาะกว่า', 'ต่างกันยังไง'); "
            "'CLARIFICATION_NEEDED' (หากถามกว้างๆ ลอยๆ ปลายเปิด ขาดชื่อรุ่นเฉพาะเจาะจง หรือถามเปรียบเทียบแต่มีรุ่นใดรุ่นหนึ่งเป็นคำกว้างๆ/รุ่นล่าสุด เช่น 'sony alpha กับ iphon ล่าสุด', 'vivo v30 กับ iphon รุ่นล่าสุด'); "
            "'ITEM_INQUIRY' (หากต้องการค้นหาอุปกรณ์เพื่อเช่า, ตอบช้อยส์แบบสอบถามต่อเนื่อง, หรือถามหาสินค้าทางเลือกราคาประหยัดกว่า เช่น 'มีที่ถูกกว่านี้ไหม'); "
            "'GENERAL_CHAT' (หากทักทาย ขอบคุณ หรือถามความสามารถของ AI เช่น 'ทำไรได้', 'ช่วยอะไรได้บ้าง')"
        )
    )
    is_comparison: bool = Field(
        False, 
        description="จริง หากผู้ใช้มีเจตนาต้องการเปรียบเทียบหรือถามหาความเหมาะสมระหว่างอุปกรณ์ตั้งแต่ 2 รุ่น/ชนิดขึ้นไป (เช่น 'A กับ B อันไหนดีกว่า', 'A กับ B อันไหนเหมาะสำหรับ...') แต่เป็นเท็จ หากเป็นการขอราคาประหยัดกว่าหรือปรับงบประมาณ เช่น 'มีที่ถูกกว่านี้ไหม'"
    )
    confidence: float = Field(..., ge=0.0, le=1.0, description="ระดับความมั่นใจ")
    ambiguity_level: float = Field(..., ge=0.0, le=1.0, description="ระดับความกำกวม (0.0 = ระบุรุ่น/แบรนด์ชัดเจน, 1.0 = คำถามปลายเปิด กว้าง หรือขอคำแนะนำลอยๆ เช่น 'แนะนำอุปกรณ์เช่าหน่อย', 'แนะนำมือถือ')")
    is_followup_answer: bool = Field(
        False, 
        description="จริง เมื่อข้อความนี้เป็นการตอบคำถามช้อยส์จากแบบสอบถามในรอบก่อนหน้า หรือเป็นคำถามต่อยอดงบประมาณ/ขอราคาประหยัดกว่าของอุปกรณ์เดิม (เช่น 'มีที่ถูกกว่านี้ไหม') หากเป็นคำถามใหม่ ถามสเปก หรือถามความเหมาะสม ให้เป็นเท็จเสมอ"
    )
    needs_further_clarification: bool = Field(False, description="จริง หากเป็นคำถามปลายเปิด กว้าง หรือขาดข้อมูลสำคัญจนต้องถามช้อยส์ผู้ใช้ต่อ")
    needs_web_search: bool = Field(False, description="จริง หากคำถามจำเป็นต้องค้นหาข้อมูลล่าสุดหรือสเปกจากอินเทอร์เน็ตภายนอก")
    extracted_entities: ExtractedEntitiesModel = Field(default_factory=ExtractedEntitiesModel)
    missing_slots: List[str] = Field(default_factory=list, description="ข้อมูลจำเป็นที่ยังขาด")
    reasoning: str = Field("", description="เหตุผลในการจำแนก")

def clean_history_context(raw_history: Optional[str]) -> str:
    """แปลงประวัติการสนทนาที่มีโครงสร้าง JSON ให้เป็นข้อความภาษาไทยที่อ่านง่ายและชัดเจนสำหรับ LLM"""
    if not raw_history:
        return ""
    lines = raw_history.split("\n")
    cleaned_lines = []
    for line in lines:
        if ": {" in line:
            role, _, json_part = line.partition(": ")
            try:
                data = json.loads(json_part)
                text = data.get("answer", "")
                questions = data.get("questions", [])
                selected = [
                    f"{q.get('title', '')}: {q.get('selected', '')}"
                    for q in questions if q.get("selected")
                ]
                summary = text
                if selected:
                    summary += f" (คำตอบช้อยส์ที่เลือก: {', '.join(selected)})"
                cleaned_lines.append(f"{role}: {summary}")
                continue
            except Exception:
                pass
        cleaned_lines.append(line)
    return "\n".join(cleaned_lines)

class RouteIntentUseCase:
    """Zero-regex, zero-keyword Intent & Ambiguity Classifier using LLM Structured Outputs."""

    def __init__(self, llm_service: LLMServiceInterface):
        self.llm_service = llm_service

    async def execute(self, user_message: str, history_context: Optional[str] = None) -> IntentDecision:
        formatted_history = clean_history_context(history_context)
        if formatted_history:
            prompt = (
                f"บริบทประวัติการสนทนาก่อนหน้า (History Context):\n{formatted_history}\n\n"
                f"คำสั่ง: จงวิเคราะห์ข้อความล่าสุดของผู้ใช้ "
                f"(หากข้อความเป็นคำตอบช้อยส์หรือตอบคำถามตามแบบสอบถามความต้องการในประวัติ เช่น มีการระบุลักษณะการใช้งาน รูปแบบงาน หรืองบประมาณ ให้จัดเป็น ITEM_INQUIRY เสมอ โดยกำหนด is_followup_answer = true, ambiguity_level = 0.0, target_items = []; "
                f"หากผู้ใช้ถามความสามารถของระบบหรือบริการ เช่น 'ทำไรได้', 'ทำอะไรได้บ้าง', 'ช่วยอะไรได้บ้าง', 'คุณคือใคร' ให้จัดเป็น GENERAL_CHAT เสมอ 100% แม้จะมีประวัติคุยเรื่องสินค้า; "
                f"หากข้อความเป็นคำถามขอคำแนะนำกว้างๆ ปลายเปิด หรือระบุเพียงชนิดอุปกรณ์ทั่วไปในหมวดโดยไม่มีชื่อรุ่นเฉพาะ เช่น 'อยากเช่าคอม', 'อยากเช่ากล้อง', 'อยากเช่ามือถือ', 'แนะนำคอม' แม้จะมีประวัติทักทาย ให้จัดเป็น CLARIFICATION_NEEDED เสมอ กำหนด target_items เป็น [] และระบุ categories ให้ตรงกับหมวดหมู่; "
                f"หากผู้ใช้ถามเปรียบเทียบอุปกรณ์หรือแบรนด์ที่เคยแนะนำในประวัติ ให้สืบทอดชื่อรุ่นเฉพาะเจาะจงจากประวัติมาใช้; "
                f"หากผู้ใช้ถามหาราคาที่ถูกกว่าหรือประหยัดกว่าของอุปกรณ์เดิม เช่น 'มีที่ถูกกว่านี้ไหม' ให้จัดเป็น ITEM_INQUIRY กำหนด target_items เป็น [] เสมอเพื่อค้นหารุ่นอื่นในหมวดเดียวกัน และสกัด budget_max จากราคาของอุปกรณ์เดิม):\n"
                f"ข้อความล่าสุดของผู้ใช้: \"\"\"{user_message}\"\"\""
            )
        else:
            prompt = f"วิเคราะห์ข้อความของผู้ใช้งานต่อไปนี้:\n\"\"\"{user_message}\"\"\""

        try:
            result = await self.llm_service.generate_structured(
                prompt=prompt,
                response_model=IntentClassificationResult,
                system_instruction=SYSTEM_INTENT_ROUTER,
                temperature=0.0
            )
            
            slots = ExtractedSlots(
                target_items=result.extracted_entities.target_items,
                categories=result.extracted_entities.categories,
                target_attribute=result.extracted_entities.target_attribute,
                budget_max=result.extracted_entities.budget_max,
                rental_duration=result.extracted_entities.rental_duration,
                intended_use=result.extracted_entities.intended_use,
                missing_slots=result.missing_slots
            )

            # หากเป็นการตอบคำถามช้อยส์จากแบบสอบถาม (is_followup_answer ที่ไม่ใช่การถามเปรียบเทียบ)
            # ตัวเลือกที่ผู้ใช้เลือก (เช่น 'สมาร์ตโฟนจอใหญ่สำหรับทำงาน', 'กล้องท่องเที่ยว/Vlog') ไม่ใช่ชื่อรุ่นสินค้าเฉพาะเจาะจง
            # หากโมเดลสกัดเข้ามาใน target_items และ target_items_are_specific เป็น False ให้ย้ายไปเป็น intended_use แทน
            is_comp_intent = bool(getattr(result, "is_comparison", False) or result.intent == IntentType.RENTAL_COMPARISON)
            if result.is_followup_answer and not is_comp_intent and slots.target_items and not result.extracted_entities.target_items_are_specific:
                extra_use = ", ".join(slots.target_items)
                slots.intended_use = f"{extra_use}, {slots.intended_use}" if slots.intended_use else extra_use
                slots.target_items = []

            logger.info(
                f"Raw router result: intent={result.intent}, reasoning='{result.reasoning}', "
                f"targets={slots.target_items}, attr={slots.target_attribute}, use={slots.intended_use}"
            )

            intent = result.intent
            ambiguity_level = result.ambiguity_level

            # กรณีที่คำถามเป็นคำถามใหม่ (ไม่ได้ตอบช้อยส์ต่อเนื่อง) และไม่ได้ระบุรุ่นหรือแบรนด์เฉพาะเจาะจง (target_items ว่าง)
            # ไม่ว่าจะเป็นการถามกว้างระดับร้าน (categories ว่าง) หรือระดับหมวดหมู่ (categories มีค่า)
            # หากโมเดลจัดเป็น CLARIFICATION_NEEDED, หรือความกำกวมสูง, หรือขาดข้อมูลสำคัญ ให้จัดเป็น CLARIFICATION_NEEDED เพื่อเปิดแบบสอบถาม
            # ยกเว้นกรณีที่มี rich slots (เช่น ระบุ intended_use หรือ budget_max ชัดเจน)
            has_rich_slots = bool(slots.intended_use or slots.budget_max)
            if not result.is_followup_answer and intent not in (IntentType.GENERAL_CHAT, IntentType.RENTAL_COMPARISON):
                is_underspecified = (
                    intent == IntentType.CLARIFICATION_NEEDED
                    or ambiguity_level >= 0.5
                    or result.needs_further_clarification
                    or len(result.missing_slots) >= 2
                )
                if len(slots.target_items) == 0 and is_underspecified and not has_rich_slots:
                    intent = IntentType.CLARIFICATION_NEEDED
                    ambiguity_level = max(ambiguity_level, 0.8)

            # ตรวจสอบเจตนาเปรียบเทียบเบื้องต้น (Zero-Keyword Policy)
            is_comparison = (
                getattr(result, "is_comparison", False)
                or (result.intent == IntentType.RENTAL_COMPARISON)
                or (len(slots.target_items) >= 2 and not result.is_followup_answer)
            )

            if intent == IntentType.CLARIFICATION_NEEDED:
                # หากเป็นการตอบคำถามช้อยส์จากรอบก่อนหน้า และโมเดลไม่ได้ระบุว่าต้องการข้อมูลเพิ่ม ให้จัดเป็น ITEM_INQUIRY เพื่อค้นหาสินค้าทันที ไม่ถามซ้ำ
                if result.is_followup_answer and not result.needs_further_clarification:
                    intent = IntentType.ITEM_INQUIRY
                elif (
                    not is_comparison
                    and len(slots.target_items) == 1
                    and result.extracted_entities.target_items_are_specific
                ):
                    # หากผู้ใช้ระบุชื่อสิ่งของหรือรุ่นเฉพาะเจาะจงชิ้นเดียวมาแล้ว (เช่น 'เสื้อ', 'ตู้เย็น', 'PS5') ไม่ใช่คำถามกว้างระดับร้าน/หมวด
                    if slots.target_attribute:
                        intent = IntentType.ITEM_SPEC_INQUIRY
                    else:
                        intent = IntentType.ITEM_INQUIRY
                        ambiguity_level = 0.0
                else:
                    ambiguity_level = max(ambiguity_level, 0.8)
            elif intent == IntentType.ITEM_INQUIRY:
                # หากคำถามกำกวม หรือโมเดลต้องการข้อมูลเพิ่ม และไม่ได้ระบุรุ่นเฉพาะเจาะจง และไม่ได้ตอบช้อยส์ต่อเนื่อง ให้เปิดโหมดสอบถามเพิ่มเติม
                if not result.is_followup_answer and len(slots.target_items) == 0 and (
                    ambiguity_level >= 0.5 
                    or result.needs_further_clarification 
                    or len(result.missing_slots) >= 2 
                    or not has_rich_slots
                ):
                    intent = IntentType.CLARIFICATION_NEEDED
                    ambiguity_level = max(ambiguity_level, 0.8)
                # หากมีเจตนาเปรียบเทียบ หรือมีสินค้าตั้งแต่ 2 ชิ้นขึ้นไป และไม่ใช่การตอบช้อยส์ต่อเนื่อง
                elif not result.is_followup_answer and (getattr(result, "is_comparison", False) or len(slots.target_items) >= 2):
                    if not result.extracted_entities.target_items_are_specific or ambiguity_level >= 0.5 or result.needs_further_clarification:
                        intent = IntentType.CLARIFICATION_NEEDED
                        ambiguity_level = max(ambiguity_level, 0.8)
                    else:
                        intent = IntentType.RENTAL_COMPARISON
                # หากโมเดลสกัด target_attribute (สเปก/ขนาด/น้ำหนัก/คุณลักษณะ) ออกมาได้ชัดเจน และมีสินค้าไม่เกิน 1 รายการ
                elif not result.is_followup_answer and slots.target_attribute and len(slots.target_items) <= 1:
                    intent = IntentType.ITEM_SPEC_INQUIRY
            elif intent == IntentType.ITEM_SPEC_INQUIRY:
                # การสอบถามคุณลักษณะ/ความเหมาะสมที่มีสินค้าตั้งแต่ 2 รายการขึ้นไป จัดเป็นการเปรียบเทียบ (RENTAL_COMPARISON)
                if len(slots.target_items) >= 2:
                    intent = IntentType.RENTAL_COMPARISON
            elif intent == IntentType.RENTAL_COMPARISON:
                # การเปรียบเทียบต้องมีสินค้าอย่างน้อย 2 รายการ และทั้งสองรายการต้องเป็นรุ่นเฉพาะเจาะจง ไม่ใช่ชื่อซีรีส์/คำกว้างๆ/รุ่นล่าสุด
                # หากมีสินค้าน้อยกว่า 2 รายการ หรือสินค้าไม่ใช่รุ่นเฉพาะ (เป็นคำกว้างๆ เช่น 'Sony Alpha', 'iphon ล่าสุด')
                # หรือมีความกำกวมสูง (ambiguity_level >= 0.5 หรือ needs_further_clarification หรือ target_items_are_specific เป็น False)
                # ให้เปิดโหมด Clarification ถามรุ่นเฉพาะเจาะจงก่อน
                if len(slots.target_items) < 2:
                    if len(slots.target_items) == 1 and (slots.target_attribute or slots.intended_use):
                        intent = IntentType.ITEM_SPEC_INQUIRY
                    else:
                        intent = IntentType.CLARIFICATION_NEEDED
                        ambiguity_level = max(ambiguity_level, 0.8)
                elif not result.extracted_entities.target_items_are_specific or ambiguity_level >= 0.5 or result.needs_further_clarification:
                    intent = IntentType.CLARIFICATION_NEEDED
                    ambiguity_level = max(ambiguity_level, 0.8)

            # ประเมินความจำเป็นในการค้นหาเว็บ (Autonomous Web Grounding)
            needs_web_search = result.needs_web_search
            if intent in (IntentType.RENTAL_COMPARISON, IntentType.ITEM_SPEC_INQUIRY):
                needs_web_search = True
            elif intent in (IntentType.GENERAL_CHAT, IntentType.CLARIFICATION_NEEDED):
                needs_web_search = False
            # ตรวจสอบเจตนาเปรียบเทียบอย่างแท้จริงผ่าน AI-Native Structured Reasoning (Zero-Keyword Policy)
            # ตัดการตรวจจับคำว่า "เปรียบเทียบ" ใน reasoning และการเช็คจำนวน categories ออก เพื่อป้องกัน False Positive
            is_comparison = (
                getattr(result, "is_comparison", False)
                or (result.intent == IntentType.RENTAL_COMPARISON)
                or (intent == IntentType.RENTAL_COMPARISON)
                or (len(slots.target_items) >= 2 and not result.is_followup_answer)
            )

            return IntentDecision(
                intent=intent,
                confidence=result.confidence,
                ambiguity_level=ambiguity_level,
                slots=slots,
                reasoning=result.reasoning,
                needs_web_search=needs_web_search,
                is_comparison=is_comparison
            )
        except Exception as e:
            logger.error(f"Error executing RouteIntentUseCase: {e}")
            # Safe domain fallback without keywords
            return IntentDecision(
                intent=IntentType.ITEM_INQUIRY,
                confidence=0.5,
                ambiguity_level=0.5,
                slots=ExtractedSlots(),
                reasoning="Fallback due to classifier error",
                needs_web_search=False
            )

