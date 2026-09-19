import json
import re
from typing import AsyncGenerator, List, Optional
from app.application.dtos.chat_dto import (
    ChatRequestDTO,
    ChatResponseDTO,
    ClarificationDTO,
    ItemDTO,
    SearchSourceDTO,
)
from app.application.use_cases.compare_items_use_case import CompareItemsUseCase
from app.application.use_cases.generate_clarification_use_case import GenerateClarificationUseCase
from app.application.use_cases.query_items_use_case import QueryItemsUseCase
from app.application.use_cases.route_intent_use_case import RouteIntentUseCase
from app.domain.entities.clarification import QuestionStep
from app.domain.entities.item import Item
from app.domain.entities.search_source import SearchSource
from app.domain.interfaces.llm_service import LLMServiceInterface
from app.domain.interfaces.search_service import SearchServiceInterface
from app.infrastructure.prompts.prompt_templates import SYSTEM_PROMPT_CHATBOT


class ProcessChatMessageUseCase:
    """Master orchestrator for processing chat messages, routing intents, and generating responses."""

    def __init__(
        self,
        route_intent: RouteIntentUseCase,
        query_items: QueryItemsUseCase,
        compare_items: CompareItemsUseCase,
        generate_clarification: GenerateClarificationUseCase,
        llm_service: LLMServiceInterface,
        search_service: SearchServiceInterface,
    ):
        self._route_intent = route_intent
        self._query_items = query_items
        self._compare_items = compare_items
        self._generate_clarification = generate_clarification
        self._llm = llm_service
        self._search = search_service

    def _build_history_summary(self, history) -> str:
        if not history:
            return ""
        turns = []
        for msg in history[-4:]:
            content = msg.content
            if content.strip().startswith("{") and "}" in content:
                try:
                    parsed = json.loads(content)
                    ans = parsed.get("answer", "")
                    items = parsed.get("items", [])
                    item_names = [it.get("name") for it in items if isinstance(it, dict) and it.get("name")]
                    prefix = f"[อุปกรณ์ที่เพิ่งแนะนำในบริบท: {', '.join(item_names)}]\n" if item_names else ""
                    turns.append(f"{msg.role}: {prefix}{ans[:300]}")
                    continue
                except Exception:
                    pass
            turns.append(f"{msg.role}: {content[:300]}")
        return "\n".join(turns)

    @staticmethod
    def _format_thai_unit(unit: Optional[str]) -> str:
        clean = (unit or "").strip().lower()
        if clean in ("daily", "day"):
            return "วัน"
        if clean in ("hourly", "hour"):
            return "ชั่วโมง"
        if clean in ("weekly", "week"):
            return "สัปดาห์"
        if clean in ("monthly", "month"):
            return "เดือน"
        return clean or "วัน"

    @staticmethod
    def _format_price(price: Optional[float]) -> str:
        if price is None:
            return "0"
        if price == int(price):
            return str(int(price))
        return f"{price:.2f}"

    @classmethod
    def _build_item_context(cls, items: List[Item]) -> str:
        if not items:
            return ""
        lines = []
        for i in items:
            p_str = cls._format_price(i.price)
            u_str = cls._format_thai_unit(i.type or i.unit)
            desc_part = f", รายละเอียด: {i.description}" if i.description else ""
            lines.append(f"- {i.name} (หมวดหมู่: {i.category}, ค่าเช่า: {p_str} บาท ต่อ {u_str}, สถานะ: {i.status}{desc_part})")
        return "รายการอุปกรณ์ในระบบยืมหน่อยที่เกี่ยวข้อง:\n" + "\n".join(lines)

    @staticmethod
    def _clean_square_brackets(text: str) -> str:
        """Removes literal square brackets [ ] around device names and converts them to clean bold markdown."""
        if not text or "[" not in text:
            return text

        # 1. **[Device]** -> **Device**
        cleaned = re.sub(r"\*\*\[\s*([^\]\n]+?)\s*\]\*\*", r"**\1**", text)
        # 2. [**Device**] -> **Device**
        cleaned = re.sub(r"\[\s*\*\*\s*([^\]\n]+?)\s*\*\*\s*\]", r"**\1**", cleaned)
        # 3. [Device] at start of line or bullet -> **Device**
        cleaned = re.sub(r"(^|\n)(\s*(?:[-•*]\s*)?)\[\s*([^\]\n]+?)\s*\]", r"\1\2**\3**", cleaned)
        # 4. Any remaining [text] (not followed by '(' which would be markdown link) -> text
        cleaned = re.sub(r"\[\s*([^\]\n]+?)\s*\](?!\()", r"\1", cleaned)
        return cleaned

    @classmethod
    def _is_item_explicitly_negated(cls, item: Item, text: str) -> bool:
        """Checks whether this specific item is explicitly negated in the text (e.g., 'ยังไม่มี Sony A7 IV')."""
        text_lower = text.lower()
        name_lower = item.name.lower().strip()
        names_to_check = [name_lower]
        clean_name = re.sub(r"\s*\(.*?\)", "", name_lower).strip()
        if len(clean_name) >= 5 and clean_name != name_lower:
            names_to_check.append(clean_name)

        neg_phrases = ["ยังไม่มี", "ไม่มีอุปกรณ์", "ไม่มีสินค้า", "ไม่มีบริการ", "ไม่มีรายการ", "ไม่มี", "ไม่พบ"]
        positive_transitions = ["แต่", "ขอแนะนำ", "แนะนำ", "ทางเลือก", "เป็นทางเลือก", "แทน"]

        found_any = False
        all_negated = True

        for target in names_to_check:
            start = 0
            while True:
                idx = text_lower.find(target, start)
                if idx == -1:
                    break
                found_any = True
                prefix_start = max(0, idx - 60)
                prefix = text_lower[prefix_start:idx]

                # Find all negative phrases and their end positions
                neg_matches = []
                for np in neg_phrases:
                    pos = prefix.rfind(np)
                    if pos != -1:
                        neg_matches.append((pos, pos + len(np)))

                if neg_matches:
                    neg_matches.sort(key=lambda x: x[0])
                    _, latest_neg_end = neg_matches[-1]
                    between = prefix[latest_neg_end:]
                    has_positive_transition = any(pt in between for pt in positive_transitions)
                    if has_positive_transition:
                        all_negated = False
                else:
                    all_negated = False

                start = idx + len(target)

        return found_any and all_negated

    @classmethod
    def _is_item_mentioned(cls, item: Item, text: str) -> bool:
        """Determines whether an inventory item was actually mentioned/recommended in response text."""
        clean_text = cls._clean_square_brackets(text)
        text_lower = clean_text.lower()
        name_lower = item.name.lower()

        # 1. Full item name directly in text
        if name_lower in text_lower:
            return True

        # 2. Check explicitly formatted device lines: e.g. **ชื่ออุปกรณ์:** ... or **ชื่ออุปกรณ์: ...**
        device_line_matches = re.findall(
            r"(?:^|\n)\s*(?:\*\*)?\s*ชื่ออุปกรณ์\s*[:：]\s*(?:\*\*)?\s*([^\n]+)",
            clean_text,
            flags=re.IGNORECASE,
        )
        for dline in device_line_matches:
            clean_dline = re.sub(r"\*+", "", dline).strip().lower().strip("[] \t")
            if clean_dline and (clean_dline in name_lower or name_lower in clean_dline):
                return True
            dline_tokens = set(clean_dline.split())
            item_tokens = set(name_lower.split())
            if len(dline_tokens.intersection(item_tokens)) >= 2:
                return True

        # 3. Check markdown bold spans: **...**
        bold_spans = re.findall(r"\*\*\s*([^*\n]+?)\s*\*\*", clean_text)
        for span in bold_spans:
            # Strip "ชื่ออุปกรณ์:" prefix if model wrapped the whole line in bold
            span_clean = re.sub(r"^(?:ชื่ออุปกรณ์|อุปกรณ์)\s*[:：]\s*", "", span.strip())
            span_clean = span_clean.strip("[] \t")
            span_lower = span_clean.lower().strip()
            ignored_prefixes = (
                "รายละเอียด", "ราคาเช่า", "ชื่ออุปกรณ์", "จุดเด่น", "การใช้งาน",
                "จุดเด่น/การใช้งาน", "จุดเด่น/ความสามารถ", "ความสามารถ", "สเปก", "คุณสมบัติ", "ข้อดี", "ข้อจำกัด"
            )
            clean_span_label = span_lower.rstrip(":： \t")
            if not clean_span_label or clean_span_label in ignored_prefixes or any(clean_span_label.startswith(p) for p in ignored_prefixes):
                continue
            if span_lower in name_lower or name_lower in span_lower:
                return True
            span_tokens = set(span_lower.split())
            item_tokens = set(name_lower.split())
            overlap = span_tokens.intersection(item_tokens)
            if len(overlap) >= 2:
                return True

        # 4. Check lines starting with bullet (•, -, *)
        for line in clean_text.splitlines():
            line_clean = line.strip().lower().strip("[] \t")
            if line_clean.startswith(("•", "-", "*")):
                item_tokens = [t for t in name_lower.split() if len(t) >= 2 and not t.isdigit()]
                matched_tokens = [t for t in item_tokens if t in line_clean]
                if len(matched_tokens) >= 2 or (len(item_tokens) == 1 and len(matched_tokens) == 1):
                    return True

        # 5. Check standalone lines matching device name
        for line in clean_text.splitlines():
            lclean = line.strip().strip("[]* \t").lower()
            if lclean and (lclean == name_lower or lclean in name_lower or name_lower in lclean):
                return True

        # 6. Check distinctive brand/model tokens
        distinctive_tokens = [
            t for t in name_lower.split()
            if len(t) >= 4 and t not in ("ชุด", "ขนาด", "เครื่อง", "สำหรับ", "พร้อม")
        ]
        matched_distinctive = [t for t in distinctive_tokens if t in text_lower]
        if len(matched_distinctive) >= 2:
            return True

        return False

    def _sync_recommended_items(self, candidate_items: List[Item], response_text: str) -> List[Item]:
        """Filters candidate items to return ONLY items that were actually mentioned in the AI response."""
        if not candidate_items or not response_text:
            return []

        clean_text = self._clean_square_brackets(response_text)
        text_lower = clean_text.lower()

        # Check if the entire response is a pure negative rejection with no recommendations
        negative_phrases = ["ยังไม่มี", "ไม่มีอุปกรณ์", "ไม่มีสินค้า", "ไม่พบ", "ไม่มีบริการ", "ไม่มีรายการ"]
        has_negative = any(p in text_lower for p in negative_phrases)

        # Positive recommendation markers indicating alternative suggestions or active item recommendations
        positive_markers = [
            "ขอแนะนำ", "แนะนำ", "ทางเลือก", "เสริม", "ตัวเลือก",
            "การ์ดด้านล่าง", "การ์ดอุปกรณ์", "ราคาเช่า", "บาท ต่อ", "บาทต่อ",
            "สามารถเลือกเช่า", "สามารถกดดู", "แตะดู"
        ]
        has_positive = any(p in text_lower for p in positive_markers)

        # If response states no items are available and contains zero positive recommendation intent, return []
        if has_negative and not has_positive:
            return []

        matched = []
        for item in candidate_items:
            if not self._is_item_mentioned(item, clean_text):
                continue
            if self._is_item_explicitly_negated(item, clean_text):
                continue
            matched.append(item)

        return matched

    async def execute(self, request: ChatRequestDTO) -> ChatResponseDTO:
        user_message = request.effective_message
        if not user_message:
            return ChatResponseDTO(
                response="สวัสดีค่ะ กำลังมองหาหรือต้องการหาสินค้าเช่าประเภทไหน แจ้งน้องยืมหน่อยได้เลยนะคะ",
                intent="general_greeting",
            )

        # 1. Semantic Intent Routing
        decision = await self._route_intent.execute(user_message, request.history)

        # 2. Clarification Flow (Underspecified or ambiguous queries)
        is_clarification = decision.intent == "clarification_needed" or (
            decision.ambiguity_level >= 0.5
            and decision.intent not in ("bot_capabilities", "platform_faq", "general_greeting", "item_inquiry")
        )
        if is_clarification:
            clarification = await self._generate_clarification.execute(user_message, decision)
            clarification_dto = ClarificationDTO(
                question=clarification.question,
                missing_dimension=clarification.missing_dimension,
                options=clarification.options,
                questions=clarification.questions,
            )
            return ChatResponseDTO(
                response=clarification.question,
                intent="clarification_needed",
                confidence=decision.confidence,
                ambiguity_level=decision.ambiguity_level,
                clarification=clarification_dto,
                questions=clarification.questions,
                items=[],
            )

        # 3. Item Querying
        if decision.intent in ("item_inquiry", "comparison") and not decision.target_items and request.history:
            for msg in reversed(request.history):
                if msg.role == "assistant" and msg.content:
                    if msg.content.strip().startswith("{") and "}" in msg.content:
                        try:
                            parsed = json.loads(msg.content)
                            hist_items = parsed.get("items", [])
                            extracted_names = [it.get("name") for it in hist_items if isinstance(it, dict) and it.get("name")]
                            if extracted_names:
                                decision.target_items = extracted_names
                                break
                        except Exception:
                            pass

        candidate_items: List[Item] = []
        if decision.intent in ("inventory_search", "comparison", "item_inquiry"):
            candidate_items = await self._query_items.execute(decision, limit=3)

        # 4. Comparison Flow
        if decision.intent == "comparison":
            answer, search_sources = await self._compare_items.execute(decision, candidate_items)
            answer = self._clean_square_brackets(answer)
            matched_items = self._sync_recommended_items(candidate_items, answer)
            return ChatResponseDTO(
                response=answer,
                intent="comparison",
                confidence=decision.confidence,
                ambiguity_level=decision.ambiguity_level,
                items=[ItemDTO.from_entity(i) for i in matched_items],
                search_query=decision.search_query or "",
                search_sources=[SearchSourceDTO.from_entity(s) for s in search_sources],
            )

        # 5. External Web Search if explicitly requested or needed
        search_sources: List[SearchSource] = []
        effective_search_query = decision.search_query
        from datetime import datetime
        current_year = datetime.now().year

        if not effective_search_query and (decision.needs_external_search or decision.intent == "comparison"):
            if len(decision.target_items) >= 2:
                effective_search_query = f"compare {' vs '.join(decision.target_items)} specs"
            elif decision.target_items:
                effective_search_query = f"{' '.join(decision.target_items)} specs review"
            elif candidate_items and len(candidate_items) >= 2:
                effective_search_query = f"compare {' vs '.join(i.name for i in candidate_items)} specs"
            elif candidate_items:
                effective_search_query = f"{candidate_items[0].name} specs review"
            elif user_message:
                effective_search_query = f"{user_message} specs"

        if effective_search_query and any(w in effective_search_query.lower() for w in ["ล่าสุด", "latest"]) and str(current_year) not in effective_search_query:
            effective_search_query = f"{effective_search_query} {current_year}"

        if (decision.needs_external_search or decision.intent == "comparison") and effective_search_query:
            search_sources = await self._search.search(effective_search_query, max_results=3)

        # 6. Inventory Search / Platform FAQ / General Synthesis
        item_context = self._build_item_context(candidate_items)

        search_context = ""
        if search_sources:
            search_context = "ข้อมูลเพิ่มเติมจากอินเทอร์เน็ต:\n" + "\n".join(
                f"- {s.title}: {s.snippet[:500]}" for s in search_sources
            )

        history_context = self._build_history_summary(request.history)

        prompt_parts = []
        prompt_parts.append(f"บริบทเวลาปัจจุบัน: ปี ค.ศ. {current_year} (พ.ศ. {current_year + 543})")
        if history_context:
            prompt_parts.append(f"ประวัติการสนทนา:\n{history_context}")
        if item_context:
            prompt_parts.append(item_context)
        if search_context:
            prompt_parts.append(search_context)
        prompt_parts.append(f"ผู้ใช้สอบถาม: '{user_message}'")
        prompt_parts.append(
            "คำแนะนำในการตอบ (Concise Mobile Markdown):\n"
            "- ตอบสั้น กระชับ ตรงประเด็น ไม่เกริ่นยาว ไม่กล่าวต้อนรับซ้ำซาก ไม่ใส่คำคมหรือคำขวัญ สุภาพ อ่อนน้อม (ลงท้าย 'ค่ะ/นะคะ')\n"
            "- ห้ามใช้ตาราง Markdown Table (|---|---|) และห้ามใส่รหัส ID ภายในฐานข้อมูลเด็ดขาด\n"
            "- ห้ามใส่เครื่องหมายวงเล็บก้ามปู [ ] ครอบชื่ออุปกรณ์หรือข้อความใดๆ โดยเด็ดขาด ให้ใช้ตัวหนา **ชื่ออุปกรณ์** โดยตรง\n"
            "- หากเป็นการทักทาย: ทักทายสั้นๆ 1-2 ประโยคอย่างสุภาพและเป็นมิตร พร้อมสอบถามว่าต้องการหาสินค้าเช่าหรืออุปกรณ์ประเภทใด (ห้ามใช้คำว่า 'ให้อุปกรณ์ชิ้นไหนช่วยดูแล' หรือคำพูดแปลกๆ แต่ให้ถามความต้องการในการค้นหาหรือเช่าสินค้าอุปกรณ์โดยตรง เช่น ต้องการหาสินค้าเช่าหรืออุปกรณ์ประเภทไหน สอบถามน้องยืมหน่อยได้เลยนะคะ)\n"
            "- หากเป็นการสอบถามบทบาทหน้าที่หรือความสามารถระบบ (เมื่อไม่มีอุปกรณ์ในบริบท): สรุปหน้าที่สั้นๆ 3 ข้อเป็น Bullet สั้นๆ ไม่เกิน 3 บรรทัด\n"
            "- หากเป็นการสอบถามข้อมูล สเปก หรือสิ่งที่อุปกรณ์ทำได้ (item_inquiry):\n"
            "  * หากในบริบทมีอุปกรณ์รุ่นเดียว: อธิบายจุดเด่น สเปกการทำงาน และสิ่งที่อุปกรณ์รุ่นดังกล่าวทำได้จริงตามข้อมูลที่มีอย่างชัดเจน ตรงไปตรงมา กระชับ (3-4 บรรทัด) โดยระบุชื่ออุปกรณ์ตัวหนา **ชื่ออุปกรณ์ตรงรุ่น** ชัดเจน (ห้ามใส่ [ ] เด็ดขาด) เพื่อให้การ์ดอุปกรณ์ด้านล่างเชื่อมโยงตรงกัน พร้อมชวนแตะดูการ์ดด้านล่าง 1 บรรทัด เช่น 'คุณผู้ใช้งานสามารถแตะดูรายละเอียดเพิ่มเติมที่การ์ดด้านล่างนี้ได้เลยนะคะ'\n"
            "  * หากในบริบทมีอุปกรณ์ตั้งแต่ 2 รุ่นขึ้นไป (เช่น ผู้ใช้ถาม 'ทำไรได้บ้าง', 'ความสามารถมีอะไรบ้าง', 'ใช้งานอะไรได้'): ให้แจกแจงสิ่งที่แต่ละรุ่นทำได้จริงแยกเป็นบล็อกรายการของแต่ละรุ่นให้ครบถ้วนทุกชิ้นอย่างสมดุล สบายตาบนมือถือ (ห้ามเลือกตอบเพียงรุ่นใดรุ่นหนึ่งเด็ดขาด โดยต้องแจกแจงให้ครบทุกรุ่นตามรายการอุปกรณ์ที่เกี่ยวข้อง):\n"
            "    **ชื่ออุปกรณ์ตรงรุ่นเป๊ะๆ ตามรายการ**\n"
            "    - **จุดเด่น/ความสามารถ:** สรุปสิ่งที่รุ่นนี้ทำได้ จุดเด่นหรือฟังก์ชันหลักสั้นๆ 1-2 ประโยค\n"
            "    - **ราคาเช่า:** ราคาจำนวนเต็มไม่มีทศนิยม เช่น 800 บาท ต่อ วัน หรือ ชั่วโมง\n"
            "    -> ปิดท้ายด้วยการชวนแตะดูการ์ดด้านล่าง 1 บรรทัด เช่น 'คุณผู้ใช้งานสามารถแตะดูรายละเอียดเพิ่มเติมที่การ์ดด้านล่างนี้ได้เลยนะคะ' (เพื่อให้การ์ดอุปกรณ์ด้านล่างยังคงแสดงอยู่ครบถ้วนทุกรุ่น)\n"
            "- หากเป็นการเปรียบเทียบหรือขอคำแนะนำในการเลือกอุปกรณ์ (comparison / ขอให้ช่วยเลือก / ถามความต่าง): เกริ่นนำสั้นๆ 1 บรรทัด -> จัดรูปแบบอุปกรณ์แต่ละชิ้นที่เปรียบเทียบแยกเป็นบล็อกรายการอย่างชัดเจน สบายตาบนมือถือ (ห้ามเขียนเปรียบเทียบอุปกรณ์รวมกันในประโยคเดียวติดกันด้วยคำว่า 'ส่วน' เช่น ห้ามตอบแนว '**รุ่น A** ทำงานนี้ ส่วน **รุ่น B** ทำงานนั้นค่ะ' และห้ามเขียนรวมเป็นย่อหน้าเดียวติดกันเป็นก้อนยาวเด็ดขาด):\n"
            "  **ชื่ออุปกรณ์ตรงรุ่นเป๊ะๆ ตามรายการ**\n"
            "  - **จุดเด่น/การใช้งาน:** จุดเด่น สเปกหลัก (เช่น ชิปประมวลผล หน้าจอ กล้อง) และลักษณะงานที่เหมาะสมสั้นๆ 1-2 ประโยค (หากมีข้อมูลจากเว็บภายนอก ให้นำสเปกจริงมาเปรียบเทียบอย่างตรงไปตรงมา)\n"
            "  - **ราคาเช่า:** ราคาจำนวนเต็มไม่มีทศนิยม เช่น 380 บาท ต่อ วัน หรือ ชั่วโมง (หากเป็นอุปกรณ์รุ่นนอกแคตตาล็อกหรือรุ่นล่าสุดที่ยังไม่มีในร้าน ให้ระบุว่า 'ยังไม่มีให้บริการในระบบค่ะ')\n"
            "  -> สรุปชี้แนะอย่างเป็นกลาง 1 บรรทัดตามการใช้งานจริง พร้อมชวนแตะดูการ์ดอุปกรณ์ที่มีให้เช่าในระบบ 1 บรรทัด เช่น 'หากสนใจสินค้าที่มีให้เช่าในระบบตอนนี้ สามารถแตะดูรายละเอียดเพิ่มเติมที่การ์ดด้านล่างนี้ได้เลยนะคะ' (ห้ามใส่ [ ] เด็ดขาด เพื่อให้การ์ดอุปกรณ์ด้านล่างยังคงแสดงอยู่ครบถ้วน)\n"
            "- หากเป็นการแนะนำอุปกรณ์ (ทั้งกรณีค้นหาตรงหมวด และกรณีแนะนำอุปกรณ์ทางเลือกเสริมข้ามหมวด เช่น ถามหาคอมเล่นเกมแต่แนะนำคอนโซล):\n"
            "  1. เกริ่นนำสั้นๆ 1-2 ประโยคอย่างสุภาพและตรงประเด็น (หากหมวดหลักไม่มีอุปกรณ์ตรงรุ่น ให้แจ้งข้อเท็จจริงตามตรงก่อน แล้วเสนอทางเลือกเสริมอย่างสุภาพ)\n"
            "  2. จัดรูปแบบอุปกรณ์ที่แนะนำแต่ละชิ้นแยกเป็นบล็อกรายการอย่างสวยงาม สบายตาบนมือถือ (ห้ามเขียนรวมเป็นพารากราฟเดียวติดกันเป็นก้อนยาวเด็ดขาด, ห้ามใส่คำว่า 'ชื่ออุปกรณ์:' ให้ขึ้นต้นด้วยชื่ออุปกรณ์ตัวหนาโดยตรง และห้ามใส่ [ ] เด็ดขาด):\n"
            "     **ชื่ออุปกรณ์ตรงรุ่นเป๊ะๆ ตามรายการ**\n"
            "     - **รายละเอียด:** จุดเด่นหรือสเปกสั้นๆ 1 ประโยค\n"
            "     - **ราคาเช่า:** ราคาจำนวนเต็มไม่มีทศนิยม เช่น 700 บาท ต่อ วัน หรือ ชั่วโมง\n"
            "  3. ปิดท้ายด้วยการชวนแตะดูการ์ดด้านล่าง 1 บรรทัด เช่น 'คุณผู้ใช้งานสามารถแตะดูรายละเอียดเพิ่มเติมที่การ์ดด้านล่างนี้ได้เลยนะคะ'\n"
            "- หากไม่มีอุปกรณ์ที่ตรงกับที่ถามและไม่มีทางเลือกที่เหมาะสม: ตอบสั้นๆ 1-2 ประโยคอย่างสุภาพว่าขณะนี้ยังไม่มีอุปกรณ์ประเภทดังกล่าวให้เช่าในระบบ โดยไม่ต้องแนะนำหรือยัดเยียดอุปกรณ์หมวดหมู่อื่น และไม่ต้องแนะนำการ์ดอุปกรณ์ใดๆ เด็ดขาด"
        )

        final_prompt = "\n\n".join(prompt_parts)
        answer = await self._llm.generate_text(
            prompt=final_prompt,
            system_instruction=SYSTEM_PROMPT_CHATBOT,
            max_tokens=500,
            temperature=0.3,
        )
        answer = self._clean_square_brackets(answer)

        matched_items = self._sync_recommended_items(candidate_items, answer)
        return ChatResponseDTO(
            response=answer,
            intent=decision.intent,
            confidence=decision.confidence,
            ambiguity_level=decision.ambiguity_level,
            items=[ItemDTO.from_entity(i) for i in matched_items],
            search_query=decision.search_query or "",
            search_sources=[SearchSourceDTO.from_entity(s) for s in search_sources],
        )

    async def execute_stream(self, request: ChatRequestDTO) -> AsyncGenerator[str, None]:
        """Executes the conversation and yields SSE lines conforming to frontend event specs."""
        user_message = request.effective_message
        if not user_message:
            default_greeting = "สวัสดีค่ะ กำลังมองหาหรือต้องการหาสินค้าเช่าประเภทไหน แจ้งน้องยืมหน่อยได้เลยนะคะ"
            yield f"event: delta\ndata: {json.dumps({'text': default_greeting}, ensure_ascii=False)}\n\n"
            yield f"event: done\ndata: {json.dumps({'answer': default_greeting, 'suggested_replies': []}, ensure_ascii=False)}\n\n"
            yield "data: [DONE]\n\n"
            return

        yield f"event: status\ndata: {json.dumps({'step': 'intent_analysis', 'message': 'กำลังวิเคราะห์คำถาม...'}, ensure_ascii=False)}\n\n"

        decision = await self._route_intent.execute(user_message, request.history)

        # Clarification handling in stream
        is_clarification = decision.intent == "clarification_needed" or (
            decision.ambiguity_level >= 0.5
            and decision.intent not in ("bot_capabilities", "platform_faq", "general_greeting", "item_inquiry")
        )
        if is_clarification:
            clarification = await self._generate_clarification.execute(user_message, decision)
            question_dicts = [q.model_dump() for q in clarification.questions]
            options_labels = [opt.label for opt in clarification.options]

            meta_payload = {
                "mode": "clarification",
                "recommended_items": [],
                "questions": question_dicts,
            }
            yield f"event: metadata\ndata: {json.dumps(meta_payload, ensure_ascii=False)}\n\n"
            yield f"event: delta\ndata: {json.dumps({'text': clarification.question}, ensure_ascii=False)}\n\n"

            done_payload = {
                "answer": clarification.question,
                "suggested_replies": options_labels,
                "recommended_items": [],
                "questions": question_dicts,
            }
            yield f"event: done\ndata: {json.dumps(done_payload, ensure_ascii=False)}\n\n"
            yield "data: [DONE]\n\n"
            return

        # Query items
        if decision.intent in ("item_inquiry", "comparison") and not decision.target_items and request.history:
            for msg in reversed(request.history):
                if msg.role == "assistant" and msg.content:
                    if msg.content.strip().startswith("{") and "}" in msg.content:
                        try:
                            parsed = json.loads(msg.content)
                            hist_items = parsed.get("items", [])
                            extracted_names = [it.get("name") for it in hist_items if isinstance(it, dict) and it.get("name")]
                            if extracted_names:
                                decision.target_items = extracted_names
                                break
                        except Exception:
                            pass

        candidate_items: List[Item] = []
        if decision.intent in ("inventory_search", "comparison", "item_inquiry"):
            yield f"event: status\ndata: {json.dumps({'step': 'retrieval', 'message': 'กำลังตรวจสอบรายการอุปกรณ์...'}, ensure_ascii=False)}\n\n"
            candidate_items = await self._query_items.execute(decision, limit=3)

        # Web search if needed
        search_sources: List[SearchSource] = []
        effective_search_query = decision.search_query
        from datetime import datetime
        current_year = datetime.now().year

        if not effective_search_query and (decision.needs_external_search or decision.intent == "comparison"):
            if len(decision.target_items) >= 2:
                effective_search_query = f"compare {' vs '.join(decision.target_items)} specs"
            elif decision.target_items:
                effective_search_query = f"{' '.join(decision.target_items)} specs review"
            elif candidate_items and len(candidate_items) >= 2:
                effective_search_query = f"compare {' vs '.join(i.name for i in candidate_items)} specs"
            elif candidate_items:
                effective_search_query = f"{candidate_items[0].name} specs review"
            elif user_message:
                effective_search_query = f"{user_message} specs"

        if effective_search_query and any(w in effective_search_query.lower() for w in ["ล่าสุด", "latest"]) and str(current_year) not in effective_search_query:
            effective_search_query = f"{effective_search_query} {current_year}"

        if (decision.needs_external_search or decision.intent == "comparison") and effective_search_query:
            yield f"event: status\ndata: {json.dumps({'step': 'web_search', 'message': 'กำลังค้นหาข้อมูลสเปกเพิ่มเติม...'}, ensure_ascii=False)}\n\n"
            search_sources = await self._search.search(effective_search_query, max_results=3)

        items_dto = [ItemDTO.from_entity(i).model_dump() for i in candidate_items]
        meta_payload = {
            "mode": "recommendation" if candidate_items else "chat",
            "recommended_items": items_dto,
            "questions": [],
        }
        yield f"event: metadata\ndata: {json.dumps(meta_payload, ensure_ascii=False)}\n\n"

        # Build prompt for streaming synthesis
        item_context = self._build_item_context(candidate_items)

        search_context = ""
        if search_sources:
            search_context = "ข้อมูลเพิ่มเติมจากอินเทอร์เน็ต:\n" + "\n".join(
                f"- {s.title}: {s.snippet[:500]}" for s in search_sources
            )

        history_context = self._build_history_summary(request.history)

        prompt_parts = []
        prompt_parts.append(f"บริบทเวลาปัจจุบัน: ปี ค.ศ. {current_year} (พ.ศ. {current_year + 543})")
        if history_context:
            prompt_parts.append(f"ประวัติการสนทนา:\n{history_context}")
        if item_context:
            prompt_parts.append(item_context)
        if search_context:
            prompt_parts.append(search_context)
        prompt_parts.append(f"ผู้ใช้สอบถาม: '{user_message}'")
        prompt_parts.append(
            "คำแนะนำในการตอบ (Concise Mobile Markdown):\n"
            "- ตอบสั้น กระชับ ตรงประเด็น ไม่เกริ่นยาว ไม่กล่าวต้อนรับซ้ำซาก ไม่ใส่คำคมหรือคำขวัญ สุภาพ อ่อนน้อม (ลงท้าย 'ค่ะ/นะคะ')\n"
            "- ห้ามใช้ตาราง Markdown Table (|---|---|) และห้ามใส่รหัส ID ภายในฐานข้อมูลเด็ดขาด\n"
            "- ห้ามใส่เครื่องหมายวงเล็บก้ามปู [ ] ครอบชื่ออุปกรณ์หรือข้อความใดๆ โดยเด็ดขาด ให้ใช้ตัวหนา **ชื่ออุปกรณ์** โดยตรง\n"
            "- หากเป็นการทักทาย: ทักทายสั้นๆ 1-2 ประโยคอย่างสุภาพและเป็นมิตร พร้อมสอบถามว่าต้องการหาสินค้าเช่าหรืออุปกรณ์ประเภทใด (ห้ามใช้คำว่า 'ให้อุปกรณ์ชิ้นไหนช่วยดูแล' หรือคำพูดแปลกๆ แต่ให้ถามความต้องการในการค้นหาหรือเช่าสินค้าอุปกรณ์โดยตรง เช่น ต้องการหาสินค้าเช่าหรืออุปกรณ์ประเภทไหน สอบถามน้องยืมหน่อยได้เลยนะคะ)\n"
            "- หากเป็นการสอบถามบทบาทหน้าที่หรือความสามารถระบบ (เมื่อไม่มีอุปกรณ์ในบริบท): สรุปหน้าที่สั้นๆ 3 ข้อเป็น Bullet สั้นๆ ไม่เกิน 3 บรรทัด\n"
            "- หากเป็นการสอบถามข้อมูล สเปก หรือสิ่งที่อุปกรณ์ทำได้ (item_inquiry):\n"
            "  * หากในบริบทมีอุปกรณ์รุ่นเดียว: อธิบายจุดเด่น สเปกการทำงาน และสิ่งที่อุปกรณ์รุ่นดังกล่าวทำได้จริงตามข้อมูลที่มีอย่างชัดเจน ตรงไปตรงมา กระชับ (3-4 บรรทัด) โดยระบุชื่ออุปกรณ์ตัวหนา **ชื่ออุปกรณ์ตรงรุ่น** ชัดเจน (ห้ามใส่ [ ] เด็ดขาด) เพื่อให้การ์ดอุปกรณ์ด้านล่างเชื่อมโยงตรงกัน พร้อมชวนแตะดูการ์ดด้านล่าง 1 บรรทัด เช่น 'คุณผู้ใช้งานสามารถแตะดูรายละเอียดเพิ่มเติมที่การ์ดด้านล่างนี้ได้เลยนะคะ'\n"
            "  * หากในบริบทมีอุปกรณ์ตั้งแต่ 2 รุ่นขึ้นไป (เช่น ผู้ใช้ถาม 'ทำไรได้บ้าง', 'ความสามารถมีอะไรบ้าง', 'ใช้งานอะไรได้'): ให้แจกแจงสิ่งที่แต่ละรุ่นทำได้จริงแยกเป็นบล็อกรายการของแต่ละรุ่นให้ครบถ้วนทุกชิ้นอย่างสมดุล สบายตาบนมือถือ (ห้ามเลือกตอบเพียงรุ่นใดรุ่นหนึ่งเด็ดขาด โดยต้องแจกแจงให้ครบทุกรุ่นตามรายการอุปกรณ์ที่เกี่ยวข้อง):\n"
            "    **ชื่ออุปกรณ์ตรงรุ่นเป๊ะๆ ตามรายการ**\n"
            "    - **จุดเด่น/ความสามารถ:** สรุปสิ่งที่รุ่นนี้ทำได้ จุดเด่นหรือฟังก์ชันหลักสั้นๆ 1-2 ประโยค\n"
            "    - **ราคาเช่า:** ราคาจำนวนเต็มไม่มีทศนิยม เช่น 800 บาท ต่อ วัน หรือ ชั่วโมง\n"
            "    -> ปิดท้ายด้วยการชวนแตะดูการ์ดด้านล่าง 1 บรรทัด เช่น 'คุณผู้ใช้งานสามารถแตะดูรายละเอียดเพิ่มเติมที่การ์ดด้านล่างนี้ได้เลยนะคะ' (เพื่อให้การ์ดอุปกรณ์ด้านล่างยังคงแสดงอยู่ครบถ้วนทุกรุ่น)\n"
            "- หากเป็นการเปรียบเทียบหรือขอคำแนะนำในการเลือกอุปกรณ์ (comparison / ขอให้ช่วยเลือก / ถามความต่าง): เกริ่นนำสั้นๆ 1 บรรทัด -> จัดรูปแบบอุปกรณ์แต่ละชิ้นที่เปรียบเทียบแยกเป็นบล็อกรายการอย่างชัดเจน สบายตาบนมือถือ (ห้ามเขียนเปรียบเทียบอุปกรณ์รวมกันในประโยคเดียวติดกันด้วยคำว่า 'ส่วน' เช่น ห้ามตอบแนว '**รุ่น A** ทำงานนี้ ส่วน **รุ่น B** ทำงานนั้นค่ะ' และห้ามเขียนรวมเป็นย่อหน้าเดียวติดกันเป็นก้อนยาวเด็ดขาด):\n"
            "  **ชื่ออุปกรณ์ตรงรุ่นเป๊ะๆ ตามรายการ**\n"
            "  - **จุดเด่น/การใช้งาน:** จุดเด่น สเปกหลัก (เช่น ชิปประมวลผล หน้าจอ กล้อง) และลักษณะงานที่เหมาะสมสั้นๆ 1-2 ประโยค (หากมีข้อมูลจากเว็บภายนอก ให้นำสเปกจริงมาเปรียบเทียบอย่างตรงไปตรงมา)\n"
            "  - **ราคาเช่า:** ราคาจำนวนเต็มไม่มีทศนิยม เช่น 380 บาท ต่อ วัน หรือ ชั่วโมง (หากเป็นอุปกรณ์รุ่นนอกแคตตาล็อกหรือรุ่นล่าสุดที่ยังไม่มีในร้าน ให้ระบุว่า 'ยังไม่มีให้บริการในระบบค่ะ')\n"
            "  -> สรุปชี้แนะอย่างเป็นกลาง 1 บรรทัดตามการใช้งานจริง พร้อมชวนแตะดูการ์ดอุปกรณ์ที่มีให้เช่าในระบบ 1 บรรทัด เช่น 'หากสนใจสินค้าที่มีให้เช่าในระบบตอนนี้ สามารถแตะดูรายละเอียดเพิ่มเติมที่การ์ดด้านล่างนี้ได้เลยนะคะ' (ห้ามใส่ [ ] เด็ดขาด เพื่อให้การ์ดอุปกรณ์ด้านล่างยังคงแสดงอยู่ครบถ้วน)\n"
            "- หากเป็นการแนะนำอุปกรณ์ (ทั้งกรณีค้นหาตรงหมวด และกรณีแนะนำอุปกรณ์ทางเลือกเสริมข้ามหมวด เช่น ถามหาคอมเล่นเกมแต่แนะนำคอนโซล):\n"
            "  1. เกริ่นนำสั้นๆ 1-2 ประโยคอย่างสุภาพและตรงประเด็น (หากหมวดหลักไม่มีอุปกรณ์ตรงรุ่น ให้แจ้งข้อเท็จจริงตามตรงก่อน แล้วเสนอทางเลือกเสริมอย่างสุภาพ)\n"
            "  2. จัดรูปแบบอุปกรณ์ที่แนะนำแต่ละชิ้นแยกเป็นบล็อกรายการอย่างสวยงาม สบายตาบนมือถือ (ห้ามเขียนรวมเป็นพารากราฟเดียวติดกันเป็นก้อนยาวเด็ดขาด, ห้ามใส่คำว่า 'ชื่ออุปกรณ์:' ให้ขึ้นต้นด้วยชื่ออุปกรณ์ตัวหนาโดยตรง และห้ามใส่ [ ] เด็ดขาด):\n"
            "     **ชื่ออุปกรณ์ตรงรุ่นเป๊ะๆ ตามรายการ**\n"
            "     - **รายละเอียด:** จุดเด่นหรือสเปกสั้นๆ 1 ประโยค\n"
            "     - **ราคาเช่า:** ราคาจำนวนเต็มไม่มีทศนิยม เช่น 700 บาท ต่อ วัน หรือ ชั่วโมง\n"
            "  3. ปิดท้ายด้วยการชวนแตะดูการ์ดด้านล่าง 1 บรรทัด เช่น 'คุณผู้ใช้งานสามารถแตะดูรายละเอียดเพิ่มเติมที่การ์ดด้านล่างนี้ได้เลยนะคะ'\n"
            "- หากไม่มีอุปกรณ์ที่ตรงกับที่ถามและไม่มีทางเลือกที่เหมาะสม: ตอบสั้นๆ 1-2 ประโยคอย่างสุภาพว่าขณะนี้ยังไม่มีอุปกรณ์ประเภทดังกล่าวให้เช่าในระบบ โดยไม่ต้องแนะนำหรือยัดเยียดอุปกรณ์หมวดหมู่อื่น และไม่ต้องแนะนำการ์ดอุปกรณ์ใดๆ เด็ดขาด"
        )

        final_prompt = "\n\n".join(prompt_parts)
        full_text = []

        async for chunk in self._llm.generate_stream(
            prompt=final_prompt,
            system_instruction=SYSTEM_PROMPT_CHATBOT,
            max_tokens=500,
            temperature=0.3,
        ):
            full_text.append(chunk)
            yield f"event: delta\ndata: {json.dumps({'text': chunk}, ensure_ascii=False)}\n\n"

        complete_answer = "".join(full_text)
        complete_answer = self._clean_square_brackets(complete_answer)
        matched_items = self._sync_recommended_items(candidate_items, complete_answer)
        matched_items_dto = [ItemDTO.from_entity(i).model_dump() for i in matched_items]

        done_payload = {
            "answer": complete_answer,
            "suggested_replies": [],
            "recommended_items": matched_items_dto,
            "questions": [],
            "search_sources": [SearchSourceDTO.from_entity(s).model_dump() for s in search_sources],
            "search_query": effective_search_query or decision.search_query or "",
        }
        yield f"event: done\ndata: {json.dumps(done_payload, ensure_ascii=False)}\n\n"
        yield "data: [DONE]\n\n"
