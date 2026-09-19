from typing import List
from app.domain.entities.clarification import ClarificationQuestion, ChoiceOption, QuestionStep
from app.domain.entities.intent_decision import IntentDecision
from app.domain.interfaces.item_repository import ItemRepositoryInterface
from app.domain.interfaces.llm_service import LLMServiceInterface
from app.infrastructure.prompts.prompt_templates import CLARIFICATION_PROMPT


class GenerateClarificationUseCase:
    """Generates polite, concise clarifying questions and interactive choices for underspecified requests."""

    def __init__(self, llm_service: LLMServiceInterface, item_repository: ItemRepositoryInterface):
        self._llm = llm_service
        self._item_repo = item_repository

    async def execute(
        self,
        user_message: str,
        decision: IntentDecision,
    ) -> ClarificationQuestion:
        # Fetch items from repository
        all_items = await self._item_repo.get_all_items()

        # Check if a category was identified by intent routing
        matching_items = []
        if decision.categories:
            matching_items = [
                i for i in all_items
                if any(c.lower() in i.category.lower() or i.category.lower() in c.lower() for c in decision.categories)
            ]

        # Target Scope Alignment: If target_items specifies an equipment type, filter matching_items to relevant items
        target_tokens = [t.lower().strip() for t in decision.target_items if t.strip()]
        if not target_tokens and user_message:
            msg_clean = user_message.lower()
            for i in matching_items:
                for word in i.name.lower().split():
                    if len(word) >= 3 and word in msg_clean:
                        target_tokens.append(word)

        if target_tokens and matching_items:
            scoped_items = []
            for item in matching_items:
                name_l = item.name.lower()
                desc_l = (item.description or "").lower()
                if any(t in name_l or t in desc_l for t in target_tokens):
                    scoped_items.append(item)
            if scoped_items:
                matching_items = scoped_items

        if matching_items:
            primary_cat = decision.categories[0] if decision.categories else matching_items[0].category
            item_summaries = []
            for i in matching_items[:6]:
                desc = f" - จุดเด่น: {i.description[:80]}" if i.description else ""
                item_summaries.append(f"  * {i.name}{desc}")
            context_block = (
                f"หมวดหมู่อุปกรณ์ที่เกี่ยวข้อง: {primary_cat}\n"
                f"อุปกรณ์ที่มีให้เช่าจริงในหมวดนี้:\n" + "\n".join(item_summaries)
            )
        else:
            available_categories = list(set(i.category for i in all_items if i.category))
            context_block = f"หมวดหมู่อุปกรณ์ที่มีในระบบยืมหน่อย: {', '.join(available_categories[:8])}"

        missing_desc = ", ".join(decision.missing_slots) if decision.missing_slots else "ยังไม่ระบุรุ่น สเปก หรือวัตถุประสงค์เฉพาะ"

        prompt = (
            f"ข้อความของผู้ใช้: '{user_message}'\n"
            f"ประเด็นที่ยังขาด: {missing_desc}\n\n"
            f"{context_block}\n\n"
            "คำแนะนำในการสร้างแบบสอบถาม 2 คำถามต่อเนื่อง (2 Continuous Steps) ในฟิลด์ questions:\n"
            "1. กฎความกระชับสูงสุด: หัวข้อคำถาม (title) ทุกข้อต้องสั้น กระชับ ตรงประเด็น เหมาะสำหรับ Mobile UI (ความยาวไม่เกิน 5-8 คำ หรือ 35-40 ตัวอักษร) ห้ามใส่คำเกริ่นเยิ่นเย้อ เช่น ห้ามใช้ 'รบกวนระบุลักษณะการใช้งานหลักในการเช่า... เพื่อให้ทางเราแนะนำรุ่นที่เหมาะสมที่สุดให้ได้นะคะ' เด็ดขาด ให้ถามตรงๆ เช่น 'ต้องการเน้นใช้งานด้านใดเป็นหลักคะ?', 'มีระบบหรือแบรนด์ที่สะดวกใช้งานไหมคะ?'\n"
            "2. กฎความตรงประเด็นกับชนิดอุปกรณ์ที่ผู้ใช้ระบุ (Target Scope Alignment - ห้ามหลุดชนิดอุปกรณ์เด็ดขาด):\n"
            "   - หากผู้ใช้ระบุชนิดอุปกรณ์มาแล้ว (เช่น 'อยากเช่ากีต้า', 'อยากเช่าโดรน', 'อยากเช่ามือถือ') หัวข้อคำถาม (title) และตัวเลือก (options / choices) ทุกข้อในทุกขั้นตอน (รวมถึง branch_options ทั้งหมด) ต้องจำกัดขอบเขตอยู่เฉพาะอุปกรณ์ชนิดนั้นเท่านั้น\n"
            "   - ห้ามนำอุปกรณ์ชนิดอื่นในหมวดหมู่เดียวกันที่ไม่เกี่ยวข้อง (เช่น ผู้ใช้ระบุว่าต้องการเช่ากีตาร์ ห้ามนำ คีย์บอร์ดไฟฟ้า เปียโน หรือกลอง มาเป็นตัวเลือกโดยเด็ดขาด เพราะไม่ตรงกับชนิดอุปกรณ์ที่ผู้ใช้ต้องการ)\n"
            "   - ตัวเลือกสำหรับอุปกรณ์ที่ระบุ ต้องกระจายสายพันธุ์หรือประเภทย่อยของอุปกรณ์นั้นอย่างสมดุล (เช่น สำหรับกีตาร์ -> กีตาร์โปร่ง, กีตาร์เบส / กีตาร์ไฟฟ้า, ได้ทุกประเภท / ไม่จำกัด)\n"
            "3. กฎความเป็นกลางเด็ดขาด 100% (Strict Neutrality & Zero-Bias):\n"
            "   - ห้ามถามคำถามชี้นำหรือเอนเอียงไปยังแบรนด์/ระบบใดระบบหนึ่งเด็ดขาด (ห้ามถาม เช่น 'สนใจรับเป็น iOS รุ่นท็อปไหมคะ?', 'สนใจเป็นกีตาร์โปร่ง Yamaha ไหมคะ?')\n"
            "   - ตัวเลือก (Choices) ต้องเป็นกลางและครอบคลุมทุกค่ายหลัก/ประเภทย่อยที่มีในคลังสินค้าอย่างสมดุล (เช่น หากเป็นหมวดโทรศัพท์มือถือ ตัวเลือกต้องมีทั้ง 'ระบบ iOS (iPhone)', 'ระบบ Android (Samsung)' และ 'ได้ทุกระบบ / ไม่จำกัด' หรือหมวดกีตาร์ มีทั้ง 'กีตาร์โปร่ง', 'กีตาร์เบส / กีตาร์ไฟฟ้า' และ 'ได้ทุกประเภท / ไม่จำกัด')\n"
            "   - ห้ามสร้างตัวเลือกที่ผูกขาดรุ่นเดียว (No Single Product Locking)\n"
            "4. Step 1 (step=1, total_steps=2): หากผู้ใช้ยังไม่ระบุวัตถุประสงค์ ให้ถามลักษณะการใช้งานหลักหรือวัตถุประสงค์เด่นสั้นๆ พร้อมตัวเลือก 3-4 ข้อที่เป็นกลางและตรงกับของในคลัง\n"
            "5. Step 2 (step=2, total_steps=2): ถามระบบ/ประเภทย่อย/แบรนด์ที่สะดวกใช้งาน หรือระดับสเปก/ขนาดเครื่อง เพื่อช่วยจำกัดรุ่นให้แคบลง พร้อมตัวเลือก 3-4 ข้อที่สมดุล\n"
            "- ใส่ branch_titles และ branch_options ใน Step 2 สำหรับแต่ละตัวเลือกของ Step 1 โดยทุก title ต้องสั้น (<= 40 ตัวอักษร) ทุก option ต้องตรงกับชนิดอุปกรณ์และเป็นกลาง 100% เสมอ\n"
            "- แต่ละ Choice ให้ระบุ label สั้นกระชับ (2-4 คำ เข้าใจง่ายสำหรับ Mobile UI)\n"
            "- กำหนด question หลักเป็นคำถามเกริ่นภาพรวมสั้นๆ 1 ประโยค (ไม่เกิน 1 บรรทัด เช่น 'เพื่อแนะนำรุ่นที่ตอบโจทย์ รบกวนเลือกข้อมูลเบื้องต้นสักนิดนะคะ') และกำหนด options หลักให้ตรงกับ options ของ Step 1"
        )

        clarification = await self._llm.generate_structured(
            prompt=prompt,
            schema=ClarificationQuestion,
            system_instruction=CLARIFICATION_PROMPT,
            temperature=0.2,
        )

        # Ensure questions list is properly populated and has 2 continuous steps
        if not clarification.questions:
            opts_labels = [opt.label for opt in clarification.options] if clarification.options else ["ใช้งานทั่วไป", "งานประสิทธิภาพสูง", "พกพาสะดวก"]
            clarification.questions = [
                QuestionStep(
                    id="step-1",
                    title="ต้องการเน้นใช้งานด้านใดเป็นหลักคะ?",
                    options=opts_labels,
                    step=1,
                    total_steps=2,
                ),
                QuestionStep(
                    id="step-2",
                    title="มีระบบหรือแบรนด์ที่สะดวกใช้งานไหมคะ?",
                    options=["ระบบ iOS (iPhone)", "ระบบ Android (Samsung)", "ได้ทุกระบบ / ไม่จำกัด"],
                    step=2,
                    total_steps=2,
                ),
            ]
        elif len(clarification.questions) == 1:
            clarification.questions[0].step = 1
            clarification.questions[0].total_steps = 2
            clarification.questions.append(
                QuestionStep(
                    id="step-2",
                    title="มีระบบหรือสเปกที่สะดวกใช้งานไหมคะ?",
                    options=["รุ่นมาตรฐานคุ้มค่า", "รุ่นท็อปประสิทธิภาพสูง", "ได้ทุกรุ่น / ไม่จำกัด"],
                    step=2,
                    total_steps=2,
                )
            )

        # Ensure total_steps is updated and step numbers are sequential
        total_steps = len(clarification.questions)
        for idx, q in enumerate(clarification.questions):
            q.step = idx + 1
            q.total_steps = total_steps
            if not q.options and clarification.options:
                q.options = [opt.label for opt in clarification.options]

        # Sync options for step 1
        step1_opts = clarification.questions[0].options
        clarification.options = [
            ChoiceOption(
                id=f"opt_{idx + 1}",
                label=opt_title,
                description=opt_title,
                action_value=opt_title,
            )
            for idx, opt_title in enumerate(step1_opts)
        ]

        if not clarification.question:
            clarification.question = "เพื่อแนะนำรุ่นที่ตอบโจทย์ รบกวนเลือกข้อมูลเบื้องต้นสักนิดนะคะ"

        return clarification
