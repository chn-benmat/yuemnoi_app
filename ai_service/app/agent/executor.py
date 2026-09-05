import json
import asyncio
from uuid import uuid4
from .conversation_context import resolve, kinds
from .dialogue import Intent, Answer, AnswerValidationError, compact_schema, interpretation_messages, answer_messages, hard_filter, candidates, validate_answer
from ..telemetry import logger, stage, request_id, model_calls
import re
from typing import Any, List, Literal, Optional

import httpx
from pydantic import BaseModel, ConfigDict, Field

from config import settings
from .inventory_grounding import InventoryGrounder, InventoryGroundingError
from ..llm.ollama_client import OllamaClient
from ..tools.database_tool import DatabaseTool, InventoryCatalogError
from ..tools.google_tool import GoogleTool


class AssistantResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    answer: str
    selected_item_id: Optional[int] = Field(
        default=None,
        description=(
            "Set to the recommended inventory item whenever the answer reaches one clear "
            "winner, including comparison questions. Use null only when the answer presents "
            "multiple options without choosing one."
        ),
    )
    source_urls: list[str] = Field(
        default_factory=list,
        max_length=5,
        description=(
            "For external specification answers, copy only the URLs that directly support "
            "the answer from the supplied reference context. Otherwise use an empty list."
        ),
    )


class RoutingDecision(BaseModel):
    """One structured semantic decision for routing or a direct reply."""

    model_config = ConfigDict(extra="forbid")

    action: Literal[
        "direct_response",
        "browse_inventory",
        "search_inventory",
        "search_web_specs",
    ] = Field(
        description=(
            "Use browse_inventory only for a generic request to list the catalog with no "
            "named physical item, product type, use case, budget, capacity, or other "
            "constraint. If any such detail exists, use search_inventory even when the "
            "requested item may not exist in the catalog."
        )
    )
    requested_item_kind: Optional[str] = Field(
        default=None,
        max_length=100,
        description=(
            "The concrete physical item kind requested by the user, even if it may be "
            "absent from the catalog. Use null for generic words such as equipment, items, "
            "rentals, recommendations, or catalog."
        ),
    )
    recommendation_limit: Optional[int] = Field(
        default=None,
        ge=1,
        le=settings.MAX_SEARCH_RESULTS,
        description=(
            "The number of inventory recommendations explicitly requested by the user. "
            "Use 1 for a single or best recommendation. Preserve the prior limit only "
            "when the latest message clearly refines the same request; otherwise use null."
        ),
    )
    web_query: Optional[str] = Field(default=None, max_length=200)
    web_question_type: Optional[Literal["single_fact", "comparison"]] = Field(
        default=None,
        description=(
            "For search_web_specs, classify the meaning of the question. Use comparison "
            "for any comparison, ranking, winner, extreme, or best-choice question even "
            "when it uses indirect wording. Use single_fact for one factual attribute. "
            "For other actions use null."
        ),
    )
    direct_answer: Optional[str] = Field(default=None, max_length=500)


class RewrittenAnswer(BaseModel):
    model_config = ConfigDict(extra="forbid")

    answer: str


class AgentExecutor:
    BRAND_NAME = "Yuemnoi"

    def __init__(self):
        self.http_client = httpx.AsyncClient(
            limits=httpx.Limits(max_connections=20, max_keepalive_connections=10)
        )
        self.ollama = OllamaClient(self.http_client)
        self.inventory_grounder = InventoryGrounder(self.ollama)
        self.db_tool = DatabaseTool(self.http_client)
        self.google_tool = GoogleTool(self.http_client)

    async def warmup_model(self) -> None:
        try:
            await self.ollama.warmup()
            print(f"[Ollama Warmup]: {settings.MODEL_NAME} is ready")
        except Exception as exc:
            logger.warning("Ollama Warmup Warning error=%s", type(exc).__name__)

    async def aclose(self) -> None:
        await self.http_client.aclose()

    @staticmethod
    def _is_thai(text: str) -> bool:
        return any("\u0e00" <= char <= "\u0e7f" for char in text)

    @staticmethod
    def _requested_rental_type(user_query: str) -> Optional[str]:
        normalized_query = user_query.casefold()
        rental_type_terms = {
            "รายชั่วโมง": ("รายชั่วโมง", "ต่อชั่วโมง", "hourly", "per hour"),
            "รายวัน": ("รายวัน", "ต่อวัน", "daily", "per day"),
        }
        for rental_type, terms in rental_type_terms.items():
            if any(term in normalized_query for term in terms):
                return rental_type
        return None

    @staticmethod
    def _requested_recommendation_limit(user_query: str) -> Optional[int]:
        normalized_query = user_query.casefold()
        single_item_terms = (
            "แค่ 1",
            "เพียง 1",
            "1 รายการ",
            "หนึ่งรายการ",
            "รายการเดียว",
            "อันเดียว",
            "ชิ้นเดียว",
            "ตัวเดียว",
            "one recommendation",
            "one item",
            "single recommendation",
            "best option",
        )
        if any(term in normalized_query for term in single_item_terms):
            return 1

        quantity_match = re.search(
            r"(?:แค่|เพียง|เอา|ขอ|แนะนำ(?:มา)?|recommend(?: only)?)?\s*"
            r"([1-5])\s*(?:รายการ|อัน|ชิ้น|ตัว|items?|recommendations?)",
            normalized_query,
        )
        return int(quantity_match.group(1)) if quantity_match else None

    @classmethod
    def _filter_catalog_by_rental_type(
        cls, catalog_items: list[dict], user_query: str
    ) -> list[dict]:
        requested_type = cls._requested_rental_type(user_query)
        if requested_type is None:
            return catalog_items

        type_aliases = {
            "รายชั่วโมง": {"รายชั่วโมง", "hourly"},
            "รายวัน": {"รายวัน", "daily"},
        }
        allowed_types = type_aliases[requested_type]
        return [
            item
            for item in catalog_items
            if str(item.get("type") or "").strip().casefold() in allowed_types
        ]

    @staticmethod
    def _system_prompt() -> str:
        return (
            "You are the natural, friendly customer assistant for Yuemnoi, an equipment "
            "rental platform. Your identity and display name is exactly 'Yuemnoi'. "
            "The Thai meaning of the brand is 'ยืมหน่อย', but always refer to yourself "
            "with the Latin spelling 'Yuemnoi', including inside Thai answers. Never "
            "write 'ยูเมน้อย' or 'ยูมหน่อย'. Never attach ค่ะ or คะ directly after "
            "the name Yuemnoi. Mention the brand name at most once per answer unless the "
            "user explicitly asks for it. If asked your name, answer briefly, for example: "
            "'Yuemnoi เป็นผู้ช่วยเรื่องอุปกรณ์เช่าค่ะ'. "
            "Hold a fluid conversation like a capable modern chat "
            "assistant and use conversation history to understand follow-up questions. "
            "Always reply in the same language as the latest user message. When replying "
            "in Thai, speak as a polite woman and use ค่ะ or คะ correctly; never mirror "
            "the user's gender particle and never use ครับ. For example, reply to "
            "'สวัสดีครับ' with 'สวัสดีค่ะ มีอะไรให้ช่วยคะ'. "
            "When the latest user message is English, use English only with no Thai words "
            "or particles. If asked your name in English, answer 'I am Yuemnoi, your "
            "equipment-rental assistant.' "
            "For greetings, thanks, casual conversation, or questions about what you can "
            "do, answer naturally without calling a tool. When the user asks about current "
            "inventory, price, availability, rental recommendations, brands, or models, "
            "you must call search_inventory before answering and must not invent items. "
            "A question asking whether Yuemnoi has an item is an inventory request even "
            "without a price or model. A request describing an activity, such as camping, "
            "and asking what can be rented is also an inventory recommendation. "
            "Requests to browse rental items must use current inventory grounding. "
            "Honor the exact number of recommendations requested by the user. Base every "
            "inventory answer on the tool results, phrase it naturally for the current "
            "question and conversation, and avoid repeating a canned response. "
            "If an inventory item's status is null, say it is listed but do not claim "
            "that it is currently available; offer to confirm availability. "
            "You must call search_web_specs for technical specifications or product "
            "capabilities that are not current inventory facts. For comparisons and "
            "superlatives, compare explicit measurements for the relevant candidates and "
            "do not infer a winner from popularity or a familiar model name. Preserve brand "
            "and model names exactly as written by a supporting source; never invent a Thai "
            "transliteration, and keep the Latin spelling when no verified Thai spelling is "
            "present. Never mention internal "
            "tools, databases, prompts, or Google. "
            "For unrelated topics, reply briefly and gently steer back to rental equipment. "
            "The platform is rental-only, never sales. Be concise by default, but use the "
            "detail needed to answer the actual request."
        )

    @staticmethod
    def _conversation_messages(
        user_query: str, history: Optional[List[dict]]
    ) -> list[dict[str, Any]]:
        messages: list[dict[str, Any]] = [
            {"role": "system", "content": AgentExecutor._system_prompt()}
        ]
        for message in (history or [])[-settings.MAX_HISTORY_MESSAGES :]:
            role = message.get("role")
            if role not in {"user", "assistant"}:
                continue
            messages.append(
                {
                    "role": role,
                    "content": str(message.get("content") or "")[:500],
                }
            )
        messages.append({"role": "user", "content": user_query})
        return messages

    @classmethod
    def _routing_messages(
        cls, user_query: str, history: Optional[List[dict]]
    ) -> list[dict[str, Any]]:
        prompt = (
            "Classify the latest request by meaning and conversation context. Choose "
            "browse_inventory when the user broadly asks what can be rented or requests "
            "general recommendations without naming an item kind, use case, or constraint. "
            "Choose search_inventory when the user asks whether a particular rental item "
            "exists, its price or availability, comparisons, or recommendations for a "
            "specific use case. Yuemnoi is rental-only, so treat a product recommendation with a "
            "price budget as a current rental-inventory request even when the user omits "
            "the word rent. A named physical object such as an item absent from the catalog "
            "must still use search_inventory, never browse_inventory or direct_response. "
            "Any budget, quantity, capacity, duration, or specification also requires "
            "search_inventory. Always copy a concrete requested physical item kind into "
            "requested_item_kind; use null only when no concrete kind was requested. "
            "Set recommendation_limit to the exact number of recommendations requested. "
            "Use 1 when the user asks for one, a single option, or the best option. When a "
            "follow-up clearly refines the same search, preserve its previous limit; do not "
            "reuse a limit for a new request. "
            "Choose search_web_specs only for external technical "
            "specifications or capabilities; never use it to recommend products within a "
            "budget. Choose direct_response for "
            "conversation that needs neither current inventory nor external specifications. "
            "For search_web_specs, preserve the user's complete technical question in "
            "web_query and classify its semantic web_question_type. Treat indirect "
            "comparisons, rankings, extremes, winners, and best-choice questions as "
            "comparison without relying on particular words. For direct_response, provide "
            "only the routing action, never an answer. Reply in the "
            "language of the latest user message."
        )
        messages: list[dict[str, Any]] = [{"role": "system", "content": prompt}]
        for message in (history or [])[-settings.MAX_HISTORY_MESSAGES :]:
            role = message.get("role")
            if role not in {"user", "assistant"}:
                continue
            messages.append(
                {
                    "role": role,
                    "content": str(message.get("content") or "")[:500],
                }
            )
        messages.append({"role": "user", "content": user_query})
        return messages

    @classmethod
    def _fast_route_decision(
        cls, user_query: str, history: Optional[List[dict]] = None
    ) -> Optional[RoutingDecision]:
        q = " ".join([str(m.get("content") or "") for m in (history or [])] + [user_query]).casefold()

        # 1. Spec research & comparison
        spec_terms = (
            "เปรียบเทียบ", "เทียบ", "สเปค", " vs ", "ความละเอียดกี่", "ดีกว่ายังไง",
            "ต่างกันยังไง", "จุดเด่น", "specification"
        )
        if any(term in q for term in spec_terms):
            return RoutingDecision(
                action="search_web_specs",
                web_query=user_query,
                web_question_type="comparison",
            )

        # 2. General browsing / Immediate Recommendation
        browse_terms = (
            "มีอุปกรณ์แนะนำให้เช่าบ้างไหม", "มีอะไรให้เช่าบ้าง", "มีอะไรบ้าง", "ขอดูรายการเช่า", "ขอดูของทั้งหมด",
            "แนะนำของหน่อย", "มีสินค้าอะไรบ้าง", "ของให้เช่ามีอะไรบ้าง", "ดูรายการของ",
            "ดูของทั้งหมด", "ของทั้งหมด", "รายการทั้งหมด", "เช่าอะไรได้บ้าง",
            "แนะนำสินค้า", "แนะนำสินค้าหน่อย", "มีอะไรแนะนำบ้าง", "แนะนำของ", "ขอดูของหน่อย"
        )
        if any(term in q for term in browse_terms):
            return RoutingDecision(
                action="browse_inventory",
            )

        # 3. Direct rental search
        rental_intents = (
            "เช่า", "ยืม", "อยากได้", "หา", "มีไหม", "มีมั้ย", "ตัวไหนดี", "อันไหนดี",
            "แนะนำ", "ช่วยแนะนำ", "ต้องการ", "มองหา", "rent", "recommend", "find"
        )
        product_terms = (
            "กล้อง", "ถ่ายภาพ", "ถ่ายรูป", "เลนส์", "ไมค์", "เสียง", "ลำโพง", "ไฟ", "สตูดิโอ",
            "เต็นท์", "แคมป์", "เกม", "ps5", "คอม", "โน้ตบุ๊ก", "macbook", "สว่าน", "เครื่องมือ",
            "รถ", "บ้าน", "พูลวิลล่า", "โปรเจคเตอร์", "โดรน", "จักรยาน", "โทรศัพท์", "iphone", "samsung",
            "อุปกรณ์", "คอนเสิต", "คอนเสิร์ต", "แคมป์", "camera", "camping", "บ้านพัก"
        )
        has_intent = any(term in q for term in rental_intents)
        has_product = any(term in q for term in product_terms)

        if (has_intent and has_product) or (kinds(q) and not any(term in q for term in ("กี่", "อย่างไร", "ยังไง", "why", "how"))):
            return RoutingDecision(
                action="search_inventory",
                requested_item_kind=user_query,
            )

        return None

    async def _route_request(
        self, user_query: str, history: Optional[List[dict]]
    ) -> RoutingDecision:
        schema = RoutingDecision.model_json_schema()
        schema["properties"].pop("direct_answer", None)
        for field in schema["properties"].values():
            field.pop("description", None)
            field.pop("title", None)
        raw_decision = await self.ollama.chat_json(
            messages=self._routing_messages(user_query, history),
            schema=schema,
            max_tokens=settings.ROUTING_MAX_TOKENS,
            timeout=settings.ROUTING_TIMEOUT,
        )
        decision = RoutingDecision.model_validate_json(raw_decision)
        if decision.action == "browse_inventory" and decision.requested_item_kind:
            return decision.model_copy(update={"action": "search_inventory"})
        if decision.action == "search_web_specs" and decision.web_question_type is None:
            return decision.model_copy(update={"web_question_type": "comparison"})
        return decision

    @staticmethod
    def _decision_tool_calls(
        decision: RoutingDecision, user_query: str
    ) -> list[dict[str, Any]]:
        if decision.action in {"browse_inventory", "search_inventory"}:
            return [
                {
                    "id": "route-inventory",
                    "function": {
                        "name": decision.action,
                        "arguments": {},
                    },
                }
            ]

        if decision.action == "search_web_specs":
            return [
                {
                    "id": "route-web-specs",
                    "function": {
                        "name": "search_web_specs",
                        "arguments": {"query": decision.web_query or user_query},
                    },
                }
            ]

        return []

    @staticmethod
    def _compact_items(items: list[dict]) -> list[dict]:
        return [
            {
                "id": item.get("id"),
                "item_name": item.get("item_name"),
                "price": item.get("price"),
                "status": item.get("status"),
                "category": item.get("category"),
                "type": item.get("type"),
                "description": str(item.get("description") or "")[:400],
            }
            for item in items[: settings.MAX_SEARCH_RESULTS]
        ]

    @staticmethod
    def _parse_tool_arguments(tool_call: dict[str, Any]) -> dict[str, Any]:
        arguments = tool_call.get("function", {}).get("arguments", {})
        if isinstance(arguments, dict):
            return arguments
        if isinstance(arguments, str):
            try:
                parsed = json.loads(arguments)
                return parsed if isinstance(parsed, dict) else {}
            except json.JSONDecodeError:
                return {}
        return {}

    @staticmethod
    def _web_reference_context(messages: list[dict[str, Any]]) -> str:
        for message in reversed(messages):
            if message.get("role") != "tool":
                continue
            try:
                payload = json.loads(str(message.get("content") or ""))
            except json.JSONDecodeError:
                continue
            if isinstance(payload, dict) and "reference_context" in payload:
                return str(payload.get("reference_context") or "")
        return ""

    @classmethod
    def _quick_greeting_response(cls, user_query: str) -> Optional[str]:
        cleaned = user_query.strip().casefold()
        greeting_terms = {
            "สวัสดี", "สวัสดีครับ", "สวัสดีค่ะ", "สวัสดีคะ", "หวัดดี", "หวัดดีครับ", "หวัดดีค่ะ",
            "ดีครับ", "ดีค่ะ", "hello", "hi", "hey", "good morning", "good afternoon"
        }
        if cleaned in greeting_terms:
            if cls._is_thai(user_query):
                return (
                    "สวัสดีค่ะ! ยินดีต้อนรับสู่ **Yuemnoi** ผู้ช่วยค้นหาและแนะนำอุปกรณ์เช่าค่ะ ✨\n\n"
                    "สามารถบอกสิ่งที่กำลังมองหา เช่น ประเภทอุปกรณ์ งบประมาณ หรือกิจกรรมที่ต้องการใช้งานได้เลยนะคะ 😊"
                )
            return (
                "Hello! Welcome to **Yuemnoi**, your equipment rental assistant ✨\n\n"
                "Feel free to ask for any rental equipment, budget, or activity you need! 😊"
            )

        thanks_terms = {
            "ขอบคุณ", "ขอบคุณครับ", "ขอบคุณค่ะ", "ขอบคุณคะ", "ขอบคุณมาก", "ขอบคุณมากๆ",
            "thank you", "thanks", "thx"
        }
        if cleaned in thanks_terms:
            if cls._is_thai(user_query):
                return "ยินดีให้บริการเสมอค่ะ! หากต้องการค้นหาหรือสอบถามเรื่องอุปกรณ์เช่าเพิ่มเติม บอก Yuemnoi ได้ตลอดเลยนะคะ ✨"
            return "You're very welcome! If you need help with any other rental items, feel free to ask anytime ✨"

        identity_terms = {
            "คุณคือใคร", "คุณชื่ออะไร", "เธอคือใคร", "ชื่ออะไร", "yuemnoi คืออะไร",
            "ยืมหน่อยคืออะไร", "ทำอะไรได้บ้าง", "ทำไรได้บ้าง", "what can you do", "who are you", "what is yuemnoi"
        }
        if cleaned in identity_terms:
            if cls._is_thai(user_query):
                return (
                    "**Yuemnoi** เป็นผู้ช่วยอัจฉริยะสำหรับค้นหาและแนะนำอุปกรณ์เช่าในแพลตฟอร์มยืมหน่อยค่ะ 🛠️\n\n"
                    "ช่วยแนะนำอุปกรณ์ เช่น กล้องถ่ายภาพ, โดรน, อุปกรณ์แคมป์ปิ้ง, เครื่องเสียงจัดงาน และอื่น ๆ ได้ตามงบประมาณและระยะเวลาที่ต้องการเลยค่ะ ✨"
                )
            return (
                "I am **Yuemnoi**, your smart equipment rental assistant! 🛠️\n\n"
                "I can help you find and recommend rental gear such as cameras, camping equipment, party gear, and more based on your budget and needs ✨"
            )

        return None

    @classmethod
    def _is_consultative_query(
        cls, user_query: str, history: Optional[List[dict]] = None
    ) -> bool:
        """ตรวจสอบว่าผู้ใช้ต้องการคำปรึกษา/ยังไม่แน่ใจ โดยยังไม่ได้ระบุงบ/สเปก/ของชัดเจน และไม่ได้สั่งให้แนะนำสินค้าเลย"""
        q = user_query.strip().casefold()

        # 1. ข้ามทันทีถ้ามีคีย์เวิร์ดร้องขอการแนะนำสินค้าโดยตรง (ให้แนะนำสินค้าทันทีตามความต้องการผู้ใช้)
        direct_recommend_triggers = (
            "แนะนำสินค้า", "มีอะไรแนะนำ", "แนะนำของ", "แนะนำหน่อย", "ขอดูของ",
            "มีอะไรให้เช่าบ้าง", "มีอะไรบ้าง", "มีสินค้าอะไรบ้าง", "แนะนำให้หน่อย",
            "แนะนำกล้องหน่อย", "แนะนำเต็นท์หน่อย", "แนะนำโดรนหน่อย", "แนะนำไมค์หน่อย",
            "แนะนำเครื่องเสียงหน่อย", "มีกล้องอะไรแนะนำ", "มีเต็นท์อะไรแนะนำ",
            "ดูของทั้งหมด", "ของทั้งหมด", "รายการทั้งหมด"
        )
        if any(trigger in q for trigger in direct_recommend_triggers):
            return False

        # 2. ข้ามถ้าผู้ใช้ระบุงบประมาณ, ระยะเวลา, หรือสเปกชัดเจนมาแล้ว
        if re.search(r"(?:งบ|งบประมาณ|ราคา|ไม่เกิน|ต่ำกว่า)\s*[0-9,]+", q):
            return False
        if re.search(r"[0-9,]+\s*(?:บาท|thb)", q):
            return False
        if re.search(r"\d+\s*(?:วัน|ชั่วโมง|ชม|คน|ท่าน)", q):
            return False

        # 3. ข้ามถ้าประวัติการสนทนาเพิ่งถามคำถามปรึกษาไปแล้ว (ป้องกันการถามวนซ้ำ)
        if history:
            last_assistant_msgs = [
                str(m.get("content") or "")
                for m in history[-3:]
                if m.get("role") == "assistant"
            ]
            if any("งบประมาณ" in msg and "ระยะเวลา" in msg for msg in last_assistant_msgs):
                return False

        # 4. คำศัพท์ที่แสดงว่าต้องการคำปรึกษา / เลือกไม่ถูก / ถามว่าต้องใช้อะไรบ้าง
        consultative_triggers = (
            "เลือกไม่ถูก", "ช่วยเลือก", "ต้องใช้อะไรบ้าง", "ใช้อะไรดี", "เอาอะไรดี",
            "มีอะไรจำเป็นบ้าง", "ต้องเตรียมอะไรบ้าง", "สำหรับมือใหม่", "มือใหม่เลือกยังไง",
            "อยากเช่าของไป", "อยากเช่าอุปกรณ์ไป", "จะจัดงาน", "จะไปทำคลิป", "จะไปเที่ยว",
            "อยากได้อุปกรณ์ไป", "ช่วยจัดเซ็ต", "ควรเช่าอะไรดี", "แนะนำยังไงดี", "ช่วยแนะนำทีว่าต้องใช้อะไร"
        )
        return any(term in q for term in consultative_triggers)

    @classmethod
    def _consultative_question_response(cls, user_query: str) -> str:
        return "ต้องการใช้อุปกรณ์สำหรับกิจกรรมอะไรคะ" if cls._is_thai(user_query) else "What activity do you need equipment for?"

    @classmethod
    def _format_inventory_answer(
        cls, user_query: str, items: list[dict], history: Optional[List[dict]] = None
    ) -> str:
        is_thai = cls._is_thai(user_query)
        if not items:
            return cls._inventory_no_results_answer(user_query)

        lines = []
        if is_thai:
            signals = InventoryGrounder._extract_intent_signals(user_query, history)
            budget_max = signals.get("budget_max")
            activities = signals.get("activities", set())
            specs = signals.get("specs", [])
            summary_parts = []
            if budget_max is not None:
                summary_parts.append(f"งบประมาณไม่เกิน **{budget_max:,.2f} บาท**")
            if activities:
                summary_parts.append(f"สำหรับกิจกรรม **{', '.join(sorted(activities))}**")
            if specs:
                summary_parts.append(f"สเปก **{', '.join(specs)}**")

            if summary_parts and history:
                lines.append(f"Yuemnoi สรุปความต้องการของคุณ ({', '.join(summary_parts)}) และคัดสรรอุปกรณ์ที่ตอบโจทย์ที่สุดดังนี้ค่ะ:")
            elif summary_parts:
                lines.append(f"Yuemnoi คัดสรรอุปกรณ์ที่ตรงกับความต้องการ ({', '.join(summary_parts)}) ให้ดังนี้ค่ะ:")
            else:
                lines.append("Yuemnoi มีอุปกรณ์ให้เช่าที่ตรงกับคำขอของคุณดังนี้ค่ะ:")
            lines.append("")
            for item in items[: settings.MAX_SEARCH_RESULTS]:
                name = str(item.get("item_name") or "อุปกรณ์").strip()
                price = item.get("price")
                db_type = str(item.get("type", "")).strip().casefold()
                unit = (
                    "ชั่วโมง"
                    if ("ชั่วโมง" in db_type or "hour" in db_type)
                    else ("สัปดาห์" if "week" in db_type else "วัน")
                )
                desc = str(item.get("description") or "").strip()
                if len(desc) > 80:
                    desc = desc[:77] + "..."
                price_str = (
                    f"{price:,.2f}".removesuffix(".00")
                    if isinstance(price, (int, float))
                    else str(price or "")
                )
                if desc:
                    lines.append(
                        f"• **{name}** — {desc} | ราคา **{price_str} บาท/{unit}**"
                    )
                else:
                    lines.append(f"• **{name}** | ราคา **{price_str} บาท/{unit}**")

            lines.append("")
            lines.append(
                "💡 *เลือกดูรายละเอียดเพิ่มเติมและทำการจองเช่าผ่านการ์ดด้านล่างได้เลยนะคะ*"
            )
        else:
            lines.append(
                "Yuemnoi found these rental items that match your request:"
            )
            lines.append("")
            for item in items[: settings.MAX_SEARCH_RESULTS]:
                name = str(item.get("item_name") or "Equipment").strip()
                price = item.get("price")
                db_type = str(item.get("type", "")).strip().casefold()
                unit = (
                    "hour"
                    if ("ชั่วโมง" in db_type or "hour" in db_type)
                    else "day"
                )
                desc = str(item.get("description") or "").strip()
                if len(desc) > 80:
                    desc = desc[:77] + "..."
                price_str = (
                    f"{price:,.2f}".removesuffix(".00")
                    if isinstance(price, (int, float))
                    else str(price or "")
                )
                if desc:
                    lines.append(
                        f"• **{name}** — {desc} | Price: **{price_str} THB/{unit}**"
                    )
                else:
                    lines.append(f"• **{name}** | Price: **{price_str} THB/{unit}**")

            lines.append("")
            lines.append(
                "💡 *You can select and rent any item directly from the cards below.*"
            )

        return "\n".join(lines)

    @classmethod
    def _inventory_no_results_answer(cls, user_query: str) -> str:
        if cls._is_thai(user_query):
            return "ขออภัยค่ะ ไม่พบรายการที่ตรงกับคำขอในรายการที่ตรวจสอบครั้งนี้"
        return "Sorry, no matching rental items were found in the catalog entries checked."

    @classmethod
    def _inventory_results_answer(cls, user_query: str) -> str:
        if cls._is_thai(user_query):
            return "พบรายการที่ตรงกับคำขอค่ะ เลือกเช่าได้จากด้านล่างเลยค่ะ"
        return "I found matching rental items. Choose one from the cards below."

    @classmethod
    def _normalize_inventory_answer(
        cls, answer: str, user_query: str = ""
    ) -> str:
        list_prefix = re.compile(r"^\s*(?:\d+[.)]|[-*\u2022])\s+")
        if not any(list_prefix.match(line) for line in answer.splitlines()):
            return answer

        normalized_lines = []
        for line in answer.splitlines():
            stripped = line.strip()
            if not stripped:
                continue
            if list_prefix.match(line):
                stripped = list_prefix.sub("", line).strip()
                normalized_lines.append(f"\u2022 {stripped}")
            else:
                normalized_lines.append(stripped)

        if (
            user_query
            and normalized_lines
            and normalized_lines[0].startswith("\u2022 ")
        ):
            intro = (
                "Yuemnoi มีอุปกรณ์ให้เช่าที่ตรงกับคำขอของคุณดังนี้ค่ะ:"
                if cls._is_thai(user_query)
                else "Yuemnoi found these rental items that match your request:"
            )
            normalized_lines.insert(0, intro)
        return "\n".join(normalized_lines)

    @classmethod
    def _inventory_unavailable_answer(cls, user_query: str) -> str:
        if cls._is_thai(user_query):
            return "ขออภัยค่ะ ระบบค้นหารายการเช่ายังไม่พร้อมใช้งานชั่วคราว"
        return "Sorry, inventory search is temporarily unavailable."

    @classmethod
    def _web_unverified_answer(cls, user_query: str) -> str:
        if cls._is_thai(user_query):
            return "ขออภัยค่ะ ตอนนี้ยังไม่มีหลักฐานเพียงพอที่จะยืนยันคำตอบนี้ได้อย่างถูกต้อง"
        return "Sorry, there is not enough evidence to verify this answer accurately."

    @staticmethod
    def _web_answer_has_sufficient_sources(
        response: AssistantResponse,
        *,
        reference_context: str,
        minimum_sources: int,
    ) -> bool:
        copied_sources = {
            source.strip()
            for source in response.source_urls
            if source.strip() and source.strip() in reference_context
        }
        return len(copied_sources) >= minimum_sources

    @classmethod
    def _normalize_answer_style(cls, answer: str, user_query: str) -> str:
        if not cls._is_thai(user_query):
            return answer

        normalized = answer
        normalized = normalized.replace("ยูเมน้อย", cls.BRAND_NAME)
        normalized = normalized.replace("ยูเมโนอิ", cls.BRAND_NAME)
        normalized = normalized.replace("ยูเมโนอี้", cls.BRAND_NAME)
        normalized = normalized.replace("ยูมหน่อย", cls.BRAND_NAME)
        normalized = normalized.replace("ยืมหน่อย", cls.BRAND_NAME)
        normalized = re.sub(
            rf"{cls.BRAND_NAME}\s*(?:ค่ะ|คะ)", cls.BRAND_NAME, normalized
        )
        normalized = re.sub(
            rf"{cls.BRAND_NAME}(?=[\u0E00-\u0E7F])",
            f"{cls.BRAND_NAME} ",
            normalized,
        )
        normalized = re.sub(r"นะครับ(?=[!?\s]|$)", "นะคะ", normalized)
        normalized = re.sub(r"ไหมครับ(?=[!?\s]|$)", "ไหมคะ", normalized)
        normalized = re.sub(r"ครับ(?=[?])", "คะ", normalized)
        normalized = normalized.replace("ครับ", "ค่ะ")
        normalized = normalized.replace("ผม", "ดิฉัน")
        normalized = re.sub(r"\s+(ค่ะ|คะ)(?=[\s.!?]|$)", r"\1", normalized)
        return normalized

    @classmethod
    def _answer_matches_user_language(cls, answer: str, user_query: str) -> bool:
        return cls._is_thai(answer) == cls._is_thai(user_query)

    async def _ensure_answer_language(self, answer: str, user_query: str) -> str:
        normalized = self._normalize_answer_style(answer, user_query)
        if not normalized or self._answer_matches_user_language(normalized, user_query):
            return normalized

        target_language = "Thai" if self._is_thai(user_query) else "English"
        repair_prompt = (
            f"Rewrite the candidate answer in {target_language} only. Preserve every factual "
            "claim and do not add products, prices, availability, or technical facts. Keep it "
            "to at most two short sentences. In Thai, use polite feminine particles ค่ะ/คะ "
            "and never ครับ. In English, use no Thai words or particles. Return only the "
            "provided JSON schema."
        )
        try:
            raw_rewrite = await self.ollama.chat_json(
                messages=[
                    {"role": "system", "content": repair_prompt},
                    {
                        "role": "user",
                        "content": (
                            f"Latest user message:\n{user_query}\n\n"
                            f"Candidate answer:\n{normalized}"
                        ),
                    },
                ],
                schema=RewrittenAnswer.model_json_schema(),
                max_tokens=settings.LANGUAGE_REPAIR_MAX_TOKENS,
                timeout=25.0,
            )
            rewritten = RewrittenAnswer.model_validate_json(raw_rewrite).answer.strip()
            return self._normalize_answer_style(rewritten, user_query)
        except Exception as exc:
            logger.warning("LLM Language Repair Error error=%s", type(exc).__name__)
            return normalized

    async def _execute_tools(
        self,
        *,
        tool_calls: list[dict[str, Any]],
        messages: list[dict[str, Any]],
        user_query: str,
        history: Optional[List[dict]],
        recommendation_limit: Optional[int] = None,
    ) -> tuple[list[dict], str]:
        user_query = " ".join([str(m.get("content") or "") for m in (history or [])] + [user_query])
        history = []
        inventory_items: list[dict] = []
        search_status = "tool_no_results"

        for tool_call in tool_calls[:2]:
            function = tool_call.get("function", {})
            tool_name = function.get("name", "")
            arguments = self._parse_tool_arguments(tool_call)

            if tool_name in {"browse_inventory", "search_inventory"}:
                try:
                    with stage("catalog"):
                        catalog_items = await self.db_tool.list_items()
                except InventoryCatalogError as exc:
                    logger.warning("Inventory Catalog Error error=%s", type(exc).__name__)
                    search_status = "inventory_unavailable"
                    tool_payload = {"error": "Inventory catalog is unavailable"}
                else:
                    catalog_items = self._filter_catalog_by_rental_type(
                        catalog_items, user_query
                    )
                    try:
                        if tool_name == "browse_inventory":
                            items = self.inventory_grounder.diverse_browse_items(
                                catalog_items, limit=settings.MAX_SEARCH_RESULTS
                            )
                        else:
                            items = await self.inventory_grounder.match(
                                user_query=user_query,
                                history=history,
                                catalog_items=catalog_items,
                            )
                        with stage("verification"):
                            fresh = await self.db_tool.get_items([int(item["id"]) for item in items]) if items else []
                            fresh_by_id = {int(item["id"]): item for item in fresh}
                            for item in items:
                                latest = fresh_by_id.get(int(item["id"]))
                                if latest and any(latest.get(key) != item.get(key) for key in ("item_name", "category", "description")):
                                    raise InventoryGroundingError("Selected item changed during verification")
                            items = [fresh_by_id[int(item["id"])] for item in items if int(item["id"]) in fresh_by_id]
                            items = InventoryGrounder.eligible_items(user_query, items)
                            items = self._filter_catalog_by_rental_type(items, user_query)
                    except InventoryCatalogError:
                        search_status = "inventory_unavailable"
                        tool_payload = {"error": "Inventory verification unavailable"}
                    except InventoryGroundingError as exc:
                        logger.warning("Inventory Grounding Error error=%s", type(exc).__name__)
                        search_status = "inventory_match_failed"
                        tool_payload = {
                            "error": "Inventory matching is temporarily unavailable"
                        }
                    else:
                        if recommendation_limit is not None:
                            items = items[:recommendation_limit]
                        inventory_items = items
                        search_status = (
                            "using_supabase" if items else "inventory_no_results"
                        )
                        language_instruction = (
                            "Reply in Thai with polite feminine particles."
                            if self._is_thai(user_query)
                            else (
                                "Reply in English only. Translate generic Thai product "
                                "wording into English while preserving brand names, model "
                                "names, and prices."
                            )
                        )
                        tool_payload = {
                            "items": self._compact_items(items),
                            "count": len(items),
                            "instruction": (
                                "Answer only from these semantically matched current "
                                "inventory results. Respond naturally to the user's actual "
                                "question. Start with one short explanatory sentence tailored "
                                "to the user's need. Then use one concise bullet line beginning "
                                "with '\u2022' for each recommended item. Include a brief reason "
                                "or useful description plus its price and rental unit in each "
                                "bullet, and keep every bullet aligned with the item cards. "
                                + language_instruction
                            ),
                        }
            elif tool_name == "search_web_specs":
                query = str(arguments.get("query") or user_query)[:200]
                context, web_status = await self.google_tool.search_spec(query)
                search_status = web_status
                tool_payload = {
                    "reference_context": context[:3000],
                    "instruction": (
                        "Treat snippets as references, not inventory. Make only claims "
                        "directly supported by the reference context. For comparisons or "
                        "superlatives, compare explicit measurements for the relevant "
                        "candidates and require at least two supporting source URLs. Copy "
                        "each supporting URL exactly into source_urls. Preserve brand and "
                        "model names exactly as a supporting source writes them; do not "
                        "invent Thai transliterations, and use Latin spelling if needed."
                    ),
                }
            else:
                tool_payload = {"error": "Unsupported tool"}

            messages.append(
                {
                    "role": "tool",
                    "tool_name": tool_name,
                    "content": json.dumps(tool_payload, ensure_ascii=False),
                }
            )

        return inventory_items, search_status

    @staticmethod
    def _recommended_items(
        db_results: list[dict], selected_id: Optional[int], answer: str = ""
    ) -> list[dict]:
        valid_ids = {item.get("id") for item in db_results}
        if selected_id not in valid_ids:
            selected_id = None

        items_map = {item.get("id"): item for item in db_results}

        # รักษาลำดับตามที่ถูกกล่าวถึงในคำตอบ (Answer order) หรือลำดับที่ AI จัดอันดับไว้
        ordered_ids: list[Any] = []
        if answer:
            normalized_answer = answer.casefold()
            found_positions: list[tuple[int, Any]] = []
            for item in db_results:
                name = str(item.get("item_name") or "").casefold()
                if name and name in normalized_answer:
                    pos = normalized_answer.find(name)
                    found_positions.append((pos, item.get("id")))
            found_positions.sort(key=lambda x: x[0])
            for _, item_id in found_positions:
                if item_id not in ordered_ids:
                    ordered_ids.append(item_id)

        # หากไม่ได้ระบุชื่อในคำตอบ ให้ใช้ลำดับตามความตรงใจที่จัดอันดับไว้ใน db_results (ไม่เรียงตาม ID)
        if not ordered_ids:
            if selected_id is not None:
                ordered_ids = [selected_id]
            else:
                ordered_ids = [
                    item.get("id")
                    for item in db_results[: settings.MAX_SEARCH_RESULTS]
                ]

        recommended_items = []
        seen = set()
        for item_id in ordered_ids:
            if item_id in seen or item_id not in items_map:
                continue
            seen.add(item_id)
            item = items_map[item_id]

            db_type = str(item.get("type", "")).strip()
            normalized_type = db_type.casefold()
            if "ชั่วโมง" in normalized_type or "hour" in normalized_type:
                unit = "ชั่วโมง"
            elif "สัปดาห์" in normalized_type or "week" in normalized_type:
                unit = "สัปดาห์"
            else:
                unit = "วัน"
            image_array = item.get("item_image_url")
            cover_image = "https://placeholder.com/image.png"
            image_candidates = (
                image_array if isinstance(image_array, list) else [image_array]
            )
            for candidate in image_candidates:
                if not isinstance(candidate, str):
                    continue
                candidate = candidate.strip()
                if candidate.startswith(("https://", "http://")):
                    cover_image = candidate
                    break

            recommended_items.append(
                {
                    "id": item_id,
                    "item_name": item.get("item_name"),
                    "price": item.get("price"),
                    "unit": unit,
                    "image_url": cover_image,
                    "status": item.get("status"),
                    "category": item.get("category"),
                    "description": item.get("description"),
                }
            )
        return recommended_items

    async def run_pipeline_non_stream(self, user_query: str, history=None) -> dict:
        token = request_id.set(uuid4().hex if request_id.get() == "-" else request_id.get())
        count_token = model_calls.set(0)
        try:
            with stage("total"):
                async with asyncio.timeout(settings.PIPELINE_TIMEOUT):
                    return await self._run_pipeline(user_query, history)
        except TimeoutError:
            logger.warning("ai_timeout request_id=%s", request_id.get())
            return {"status": "failed", "search_status": "inventory_match_failed", "items_found": 0,
                    "answer": self._inventory_unavailable_answer(user_query), "recommended_items": []}
        finally:
            logger.info("ai_complete request_id=%s model_calls=%s", request_id.get(), model_calls.get())
            model_calls.reset(count_token)
            request_id.reset(token)

    @staticmethod
    def _envelope(answer: str, status: str = "direct_response", items=None, failed=False) -> dict:
        cards = items or []
        return {"status": "failed" if failed else "success", "search_status": status,
                "items_found": len(cards), "answer": answer, "recommended_items": cards}

    async def _interpret(self, query: str, history: list[dict]) -> Intent:
        with stage("interpretation"):
            raw = await self.ollama.chat_json(
                messages=interpretation_messages(query, history), schema=compact_schema(Intent),
                max_tokens=settings.INTERPRETATION_MAX_TOKENS, timeout=settings.ROUTING_TIMEOUT,
            )
        return Intent.model_validate_json(raw)

    async def _compose(self, intent: Intent, items: list[dict], source: str, query: str) -> Answer:
        with stage("answer"):
            raw = await self.ollama.chat_json(
                messages=answer_messages(intent, items, source, query), schema=compact_schema(Answer),
                max_tokens=settings.CONVERSATIONAL_MAX_TOKENS, timeout=settings.MATCH_TIMEOUT,
            )
        return Answer.model_validate_json(raw)

    async def _run_pipeline(self, user_query: str, history=None) -> dict:
        query = user_query.strip()
        if not query or len(query) > 200:
            return self._envelope("กรุณาพิมพ์คำถามให้กระชับค่ะ" if self._is_thai(query) else "Please enter a short question.", "input_too_long", failed=True)
        greeting = self._quick_greeting_response(query)
        if greeting:
            return self._envelope(greeting)
        bounded_history = [
            {"role": message["role"], "content": str(message.get("content") or "")[:500]}
            for message in (history or [])[-settings.MAX_HISTORY_MESSAGES:]
            if message.get("role") in {"user", "assistant"}
        ]
        try:
            intent = await self._interpret(query, bounded_history)
        except Exception as exc:
            logger.warning("ai_interpretation_failure request_id=%s error=%s", request_id.get(), type(exc).__name__)
            return self._envelope(self._inventory_unavailable_answer(query), "inventory_match_failed", failed=True)
        logger.info("ai_route request_id=%s action=%s relation=%s", request_id.get(), intent.action, intent.relation)
        if intent.action == "reply":
            if not intent.reply.strip():
                return self._envelope(self._inventory_unavailable_answer(query), failed=True)
            return self._envelope(intent.reply.strip())

        inventory = intent.action in {"inventory", "inventory_specs"}
        source = ""
        current_items = []
        search_status = "direct_response"
        if inventory:
            try:
                with stage("catalog"):
                    catalog = await self.db_tool.list_items()
                    shortlist = candidates(catalog, intent)
                with stage("freshness"):
                    fresh = await self.db_tool.get_items([item["id"] for item in shortlist]) if shortlist else []
                    current_items = hard_filter(fresh, intent)
                logger.info("ai_candidates request_id=%s catalog=%s shortlisted=%s fresh=%s filtered=%s", request_id.get(), len(catalog), len(shortlist), len(current_items), len(fresh) - len(current_items))
                search_status = "using_supabase" if current_items else "inventory_no_results"
            except InventoryCatalogError:
                return self._envelope(self._inventory_unavailable_answer(query), "inventory_unavailable", failed=True)
        if intent.action in {"specs", "inventory_specs"}:
            with stage("specifications"):
                source, web_status = await self.google_tool.search_spec(intent.web_query or intent.request)
            if not inventory:
                search_status = web_status
            if web_status == "google_search_failed":
                return self._envelope(self._web_unverified_answer(query), web_status, failed=True)
        try:
            parsed = await self._compose(intent, current_items, source, query)
            selected = validate_answer(parsed, current_items, source, intent)
        except Exception as exc:
            reason = str(exc) if isinstance(exc, AnswerValidationError) else "invalid_model_response"
            logger.warning("ai_answer_failure request_id=%s error=%s reason=%s", request_id.get(), type(exc).__name__, reason)
            return self._envelope(self._inventory_unavailable_answer(query), "inventory_match_failed", failed=True)
        if inventory:
            search_status = "using_supabase" if selected else "direct_response" if parsed.outcome == "insufficient" and current_items else "inventory_no_results"
        logger.info("ai_selection request_id=%s outcome=%s candidates=%s selected=%s", request_id.get(), parsed.outcome, len(current_items), len(selected))
        if selected:
            try:
                with stage("final_freshness"):
                    refreshed = await self.db_tool.get_items([item["id"] for item in selected])
                    refreshed_by_id = {item["id"]: item for item in hard_filter(refreshed, intent)}
                    for item in selected:
                        fresh = refreshed_by_id.get(item["id"])
                        if fresh is None or any(fresh.get(field) != item.get(field) for field in ("item_name", "description", "category")):
                            raise InventoryCatalogError("Selected inventory changed")
                    selected = [refreshed_by_id[item["id"]] for item in selected]
            except InventoryCatalogError:
                return self._envelope(self._inventory_unavailable_answer(query), "inventory_unavailable", failed=True)
        answer = parsed.answer.strip()
        if inventory and parsed.outcome == "no_match":
            # จำกัดข้อสรุปไว้ที่ผลค้นหาครั้งนี้ แม้โมเดลเขียนว่าไม่มีทั้งระบบ
            answer = self._inventory_no_results_answer(query)
        cards = self._recommended_items(selected, None)
        if cards:
            thai = self._is_thai(query)
            lines = []
            for card in cards:
                price = f"{card['price']:,.2f}".removesuffix(".00")
                rental_unit = card["unit"] if thai else {"วัน": "day", "ชั่วโมง": "hour", "สัปดาห์": "week"}.get(card["unit"], "day")
                currency = "บาท" if thai else "THB"
                lines.append(f"• **{card['item_name']}** — **{price} {currency}/{rental_unit}**")
            answer += "\n\n" + "\n".join(lines)
        if parsed.source_urls:
            answer += "\n\n" + " · ".join(f"[Source {index}]({url})" for index, url in enumerate(parsed.source_urls, 1))
        return self._envelope(answer, search_status, cards)
