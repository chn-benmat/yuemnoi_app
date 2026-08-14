import json
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
            print(f"[Ollama Warmup Warning]: {exc}")

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
            "the complete natural reply in "
            "direct_answer without making claims about current inventory. Reply in the "
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

    async def _route_request(
        self, user_query: str, history: Optional[List[dict]]
    ) -> RoutingDecision:
        raw_decision = await self.ollama.chat_json(
            messages=self._routing_messages(user_query, history),
            schema=RoutingDecision.model_json_schema(),
            max_tokens=settings.ROUTING_MAX_TOKENS,
            timeout=30.0,
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
    def _inventory_no_results_answer(cls, user_query: str) -> str:
        if cls._is_thai(user_query):
            return "ขออภัยค่ะ ตอนนี้ไม่พบรายการให้เช่าที่ตรงกับคำขอนี้"
        return "Sorry, there are currently no rental items matching your request."

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
            print(f"[LLM Language Repair Error]: {exc}")
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
        inventory_items: list[dict] = []
        search_status = "tool_no_results"

        for tool_call in tool_calls[:2]:
            function = tool_call.get("function", {})
            tool_name = function.get("name", "")
            arguments = self._parse_tool_arguments(tool_call)

            if tool_name in {"browse_inventory", "search_inventory"}:
                try:
                    catalog_items = await self.db_tool.list_items()
                except InventoryCatalogError as exc:
                    print(f"[Inventory Catalog Error]: {exc}")
                    search_status = "inventory_unavailable"
                    tool_payload = {"error": "Inventory catalog is unavailable"}
                else:
                    catalog_items = self._filter_catalog_by_rental_type(
                        catalog_items, user_query
                    )
                    try:
                        if tool_name == "browse_inventory":
                            items = [
                                item
                                for item in catalog_items
                                if str(item.get("status") or "").casefold()
                                == "available"
                            ][: settings.MAX_SEARCH_RESULTS]
                        else:
                            items = await self.inventory_grounder.match(
                                user_query=user_query,
                                history=history,
                                catalog_items=catalog_items,
                            )
                    except InventoryGroundingError as exc:
                        print(f"[Inventory Grounding Error]: {exc}")
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

        mentioned_ids = []
        if answer:
            normalized_answer = answer.casefold()
            mentioned_ids = [
                item.get("id")
                for item in db_results
                if str(item.get("item_name") or "").casefold() in normalized_answer
            ]

        visible_ids = set(mentioned_ids)
        if not visible_ids and selected_id is not None:
            visible_ids = {selected_id}

        recommended_items = []
        for item in db_results[: settings.MAX_SEARCH_RESULTS]:
            item_id = item.get("id")
            if visible_ids and item_id not in visible_ids:
                continue

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

    async def run_pipeline_non_stream(
        self, user_query: str, history: Optional[List[dict]] = None
    ) -> dict:
        cleaned_query = user_query.strip()
        if len(cleaned_query) > 200:
            answer = (
                "กรุณาพิมพ์คำถามให้กระชับและสั้นลงค่ะ"
                if self._is_thai(cleaned_query)
                else "Please shorten your question."
            )
            return {
                "status": "failed",
                "search_status": "input_too_long",
                "items_found": 0,
                "answer": answer,
                "recommended_items": [],
            }

        try:
            decision = await self._route_request(cleaned_query, history)
        except Exception as exc:
            print(f"[LLM Routing Error]: {exc}")
            answer = (
                "ขออภัยค่ะ ระบบผู้ช่วยไม่พร้อมใช้งานชั่วคราว"
                if self._is_thai(cleaned_query)
                else "Sorry, the assistant is temporarily unavailable."
            )
            return {
                "status": "failed",
                "search_status": "llm_failed",
                "items_found": 0,
                "answer": answer,
                "recommended_items": [],
            }

        recommendation_limit = self._requested_recommendation_limit(cleaned_query)
        if recommendation_limit is None:
            recommendation_limit = getattr(decision, "recommendation_limit", None)

        if decision.action == "direct_response":
            answer = str(decision.direct_answer or "").strip()
            if not answer:
                answer = (
                    "สอบถามเรื่องอุปกรณ์เช่าได้เลยค่ะ"
                    if self._is_thai(cleaned_query)
                    else "How can I help with your rental equipment needs?"
                )
            answer = await self._ensure_answer_language(answer, cleaned_query)
            return {
                "status": "success",
                "search_status": "direct_response",
                "items_found": 0,
                "answer": answer,
                "recommended_items": [],
            }

        tool_calls = self._decision_tool_calls(decision, cleaned_query)
        messages = self._conversation_messages(cleaned_query, history)
        first_message = {
            "role": "assistant",
            "content": "",
            "tool_calls": tool_calls,
        }
        messages.append(first_message)
        db_results, search_status = await self._execute_tools(
            tool_calls=tool_calls,
            messages=messages,
            user_query=cleaned_query,
            history=history,
            recommendation_limit=recommendation_limit,
        )
        reference_context = self._web_reference_context(messages)

        if search_status in {"inventory_unavailable", "inventory_match_failed"}:
            return {
                "status": "failed",
                "search_status": search_status,
                "items_found": 0,
                "answer": self._inventory_unavailable_answer(cleaned_query),
                "recommended_items": [],
            }

        if decision.action in {"browse_inventory", "search_inventory"} and not db_results:
            return {
                "status": "success",
                "search_status": "inventory_no_results",
                "items_found": 0,
                "answer": self._inventory_no_results_answer(cleaned_query),
                "recommended_items": [],
            }

        if decision.action == "search_web_specs" and not reference_context:
            return {
                "status": "success",
                "search_status": search_status,
                "items_found": 0,
                "answer": self._web_unverified_answer(cleaned_query),
                "recommended_items": [],
            }

        try:
            raw_content = await self.ollama.chat_json(
                messages=messages,
                schema=AssistantResponse.model_json_schema(),
                max_tokens=settings.FINAL_RESPONSE_MAX_TOKENS,
                timeout=35.0,
            )
            parsed = AssistantResponse.model_validate_json(raw_content)
            if (
                decision.action == "search_web_specs"
                and not self._web_answer_has_sufficient_sources(
                    parsed,
                    reference_context=reference_context,
                    minimum_sources=(
                        1
                        if getattr(decision, "web_question_type", None)
                        == "single_fact"
                        else 2
                    ),
                )
            ):
                return {
                    "status": "success",
                    "search_status": search_status,
                    "items_found": 0,
                    "answer": self._web_unverified_answer(cleaned_query),
                    "recommended_items": [],
                }
            answer = await self._ensure_answer_language(
                self._normalize_inventory_answer(
                    parsed.answer.strip(), user_query=cleaned_query
                ),
                cleaned_query,
            )
            selected_id = parsed.selected_item_id
        except Exception as exc:
            print(f"[LLM Final Response Error]: {type(exc).__name__}")
            answer = (
                self._inventory_results_answer(cleaned_query)
                if db_results
                else (
                    "ขออภัยค่ะ ยังไม่สามารถสรุปข้อมูลให้ได้ในขณะนี้"
                    if self._is_thai(cleaned_query)
                    else "Sorry, I couldn't summarize the results right now."
                )
            )
            selected_id = None

        recommended_items = self._recommended_items(db_results, selected_id, answer)
        return {
            "status": "success",
            "search_status": search_status,
            "items_found": len(recommended_items),
            "answer": answer,
            "recommended_items": recommended_items,
        }
