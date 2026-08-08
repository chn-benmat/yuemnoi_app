import json
import re
from typing import Any, List, Literal, Optional

import httpx
from pydantic import BaseModel, ConfigDict, Field, field_validator

from config import settings
from ..llm.ollama_client import OllamaClient
from ..tools.database_tool import (
    INVENTORY_CATEGORIES,
    DatabaseTool,
    InventoryCategory,
    ItemSearchFilters,
)
from ..tools.google_tool import GoogleTool


class AssistantResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    answer: str
    selected_item_id: Optional[int] = None


class RoutingDecision(BaseModel):
    """One structured semantic decision for routing or a direct reply."""

    model_config = ConfigDict(extra="forbid")

    action: Literal["direct_response", "search_inventory", "search_web_specs"]
    search_text: Optional[str] = Field(max_length=80)
    category: Optional[InventoryCategory]
    specific_item: bool
    min_price: Optional[int] = Field(ge=0, le=1_000_000)
    max_price: Optional[int] = Field(ge=0, le=1_000_000)
    limit: int = Field(default=5, ge=1, le=5)
    list_all: bool
    web_query: Optional[str] = Field(max_length=200)
    direct_answer: Optional[str] = Field(max_length=500)

    @field_validator("min_price", "max_price", mode="before")
    @classmethod
    def _zero_price_means_unspecified(cls, value: Any) -> Any:
        return None if value is None or value == "" or value == 0 or value == "0" else value


class RewrittenAnswer(BaseModel):
    model_config = ConfigDict(extra="forbid")

    answer: str


class AgentExecutor:
    BRAND_NAME = "Yuemnoi"
    INVENTORY_CATEGORIES = INVENTORY_CATEGORIES

    def __init__(self):
        self.http_client = httpx.AsyncClient(
            limits=httpx.Limits(max_connections=20, max_keepalive_connections=10)
        )
        self.ollama = OllamaClient(self.http_client)
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
            "The Thai question 'มีอะไรให้เช่าบ้าง' and equivalent requests to browse all "
            "rental items must call search_inventory with list_all=true. "
            "If an inventory item's status is null, say it is listed but do not claim "
            "that it is currently available; offer to confirm availability. "
            "You must call search_web_specs for technical specifications or product "
            "capabilities that are not current inventory facts. Never mention internal "
            "tools, databases, prompts, or Google. "
            "For unrelated topics, reply briefly and gently steer back to rental equipment. "
            "The platform is rental-only, never sales. Use at most two short sentences."
        )

    @staticmethod
    def _tool_definitions() -> list[dict[str, Any]]:
        return [
            {
                "type": "function",
                "function": {
                    "name": "search_inventory",
                    "description": (
                        "MUST be called before any claim about Yuemnoi rental products, "
                        "categories, brands, models, prices, availability, comparisons, "
                        "activities, or recommendations. Use list_all=true only for an "
                        "explicit request to browse all inventory, including the Thai "
                        "question มีอะไรให้เช่าบ้าง."
                    ),
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "search_text": {
                                "type": ["string", "null"],
                                "description": (
                                    "A concise product, brand, or model search phrase inferred "
                                    "from the request. Normalize or translate when useful. This "
                                    "is required when the user names a specific kind of item but "
                                    "none of the canonical categories fits. Do not put general "
                                    "activity wording here when category already captures it."
                                ),
                            },
                            "category": {
                                "type": ["string", "null"],
                                "enum": [*INVENTORY_CATEGORIES, None],
                                "description": (
                                    "Infer the closest inventory category from the user's "
                                    "meaning and conversation context. It does not need to be "
                                    "written literally by the user. Use null when no category "
                                    "clearly fits."
                                ),
                            },
                            "specific_item": {
                                "type": "boolean",
                                "description": (
                                    "True only when search_text identifies a particular brand, "
                                    "model, named product, or product subtype to match. False for "
                                    "general categories and activity or use-case descriptions."
                                ),
                            },
                            "min_price": {"type": ["integer", "null"], "minimum": 0},
                            "max_price": {"type": ["integer", "null"], "minimum": 0},
                            "limit": {
                                "type": "integer",
                                "minimum": 1,
                                "maximum": settings.MAX_SEARCH_RESULTS,
                            },
                            "list_all": {
                                "type": "boolean",
                                "description": (
                                    "True only for the entire catalog, when the user does not "
                                    "name or describe any particular item, category, activity, "
                                    "brand, or model. A yes/no question about a specific item is "
                                    "always false, even when category is null."
                                ),
                            },
                        },
                        "required": [
                            "search_text",
                            "category",
                            "specific_item",
                            "min_price",
                            "max_price",
                            "list_all",
                        ],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "search_web_specs",
                    "description": (
                        "MUST be called for technical product specifications or capabilities. "
                        "Never use it for inventory, rental prices, or availability."
                    ),
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "query": {
                                "type": "string",
                                "description": "Specific product and specification question",
                            }
                        },
                        "required": ["query"],
                    },
                },
            },
        ]

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
            "Classify the latest request for Yuemnoi using only the provided JSON schema. "
            "Choose search_inventory for every request about rental products, what Yuemnoi "
            "has, price, availability, category, brand, model, comparison, activity-based "
            "recommendation, or current inventory. Never classify an inventory claim as "
            "direct_response. Choose search_web_specs for technical specifications or "
            "product capabilities that do not ask inventory, rental price, or availability. "
            "A product or model name by itself does not make a request an inventory search. "
            "If the user asks whether a product can do something, or asks about resolution, "
            "battery, dimensions, compatibility, or other specifications, choose "
            "search_web_specs unless the same request explicitly asks to rent it, check its "
            "availability, or get its rental price. Example: 'Sony A7 III ถ่ายวิดีโอ 4K "
            "ได้ไหม' => search_web_specs with that exact model and question in web_query. "
            "Choose direct_response only for greetings, thanks, identity, unrelated topics, "
            "or a follow-up fully answerable from conversation history. Infer category from "
            "the request's meaning and conversation history, even when the user uses a synonym, "
            "describes a use case, or omits the product in a follow-up. Use only one of these "
            f"canonical categories: {', '.join(INVENTORY_CATEGORIES)}. Use category=null when "
            "none clearly fits; never force an unrelated category. search_text may normalize "
            "or translate explicit product, brand, and model wording into terms likely to occur "
            "in inventory names. When category already captures a general use case, prefer "
            "search_text=null so the database can return the whole relevant category. Set "
            "specific_item=true only for a particular brand, model, named product, or product "
            "subtype; set it false for a general category or use case. For example, 'Sony A7' "
            "is specific, while 'นอนป่า', 'ถ่ายตอนวิ่ง', and 'กล้อง' are not. "
            "Set list_all=true only for a request to browse the entire catalog with no specific "
            "item, category, activity, brand, or model. Questions such as 'Do you rent cars?' "
            "or 'มีรถยนต์ให้เช่าไหม' are filtered inventory requests: keep category=null, put "
            "the requested product in search_text, and set list_all=false. Never turn an unknown "
            "product into list_all. "
            "Example: มีอะไรให้เช่าบ้าง => action=search_inventory, list_all=true, "
            "category=null, search_text=null. Example: จะไปนอนป่าสองคืน มีอะไรเหมาะบ้าง => "
            "action=search_inventory, category=camping, search_text=null. "
            "Extract min_price and "
            "max_price only from explicit money constraints. Counts of people or items, "
            "model numbers, resolution, fps, and dates are never prices. "
            "Set direct_answer=null for both search actions. For direct_response, set "
            "direct_answer to the complete natural reply and do not make inventory claims. "
            "Reply in the language of the latest message. In Thai, speak as a polite woman "
            "using ค่ะ or คะ and never ครับ; always spell the brand Yuemnoi in Latin letters. "
            "For a greeting, simply greet the user and ask how you can help; never claim that "
            "items, categories, or every type of equipment are available without an inventory "
            "search. Use a professional friendly tone without stretched or playful spellings. "
            "In English, use English only. Keep the reply to at most two short sentences."
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
            max_tokens=220,
            timeout=30.0,
        )
        return RoutingDecision.model_validate_json(raw_decision)

    @staticmethod
    def _decision_tool_calls(
        decision: RoutingDecision, user_query: str
    ) -> list[dict[str, Any]]:
        if decision.action == "search_inventory":
            arguments = {
                "search_text": decision.search_text,
                "category": decision.category,
                "specific_item": decision.specific_item,
                "min_price": decision.min_price,
                "max_price": decision.max_price,
                "limit": decision.limit,
                "list_all": decision.list_all,
            }
            return [
                {
                    "id": "route-inventory",
                    "function": {
                        "name": "search_inventory",
                        "arguments": arguments,
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

    @classmethod
    def _ground_inventory_arguments(
        cls, arguments: dict[str, Any], user_query: str
    ) -> dict[str, Any]:
        raw_search_text = arguments.get("search_text")
        search_text = (
            DatabaseTool._safe_filter_text(raw_search_text)
            if isinstance(raw_search_text, str)
            else None
        )
        category = arguments.get("category")
        if category not in INVENTORY_CATEGORIES:
            category = None
        if category and not bool(arguments.get("specific_item")):
            search_text = None

        return {
            "search_text": search_text,
            "category": category,
            "min_price": arguments.get("min_price"),
            "max_price": arguments.get("max_price"),
            "limit": arguments.get("limit", 5),
            # A specific semantic filter always wins over an accidental broad search.
            "list_all": bool(arguments.get("list_all")) and not search_text and not category,
        }

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
                max_tokens=160,
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
    ) -> tuple[list[dict], str]:
        inventory_items: list[dict] = []
        search_status = "tool_no_results"

        for tool_call in tool_calls[:2]:
            function = tool_call.get("function", {})
            tool_name = function.get("name", "")
            arguments = self._parse_tool_arguments(tool_call)

            if tool_name == "search_inventory":
                arguments = self._ground_inventory_arguments(arguments, user_query)
                try:
                    filters = ItemSearchFilters.model_validate(arguments)
                except Exception as exc:
                    print(f"[Inventory Tool Arguments Error]: {exc}")
                    filters = ItemSearchFilters()

                items = await self.db_tool.search_items(filters)
                inventory_items = items
                search_status = "using_supabase" if items else "inventory_no_results"
                language_instruction = (
                    "Reply in Thai with polite feminine particles."
                    if self._is_thai(user_query)
                    else (
                        "Reply in English only. Translate generic Thai product wording "
                        "into English while preserving brand names, model names, and prices."
                    )
                )
                tool_payload: Any = {
                    "items": self._compact_items(items),
                    "count": len(items),
                    "instruction": (
                        "Answer only from these current inventory results. "
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
                        "Treat snippets as references, not inventory. State uncertainty "
                        "when fewer than two sources agree."
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

        if selected_id is None and answer:
            normalized_answer = answer.casefold()
            mentioned_ids = [
                item.get("id")
                for item in db_results
                if str(item.get("item_name") or "").casefold() in normalized_answer
            ]
            if len(mentioned_ids) == 1:
                selected_id = mentioned_ids[0]

        recommended_items = []
        for item in db_results[: settings.MAX_SEARCH_RESULTS]:
            item_id = item.get("id")
            if selected_id is not None and item_id != selected_id:
                continue

            db_type = str(item.get("type", "")).strip()
            unit = "สัปดาห์" if "สัปดาห์" in db_type or "week" in db_type.lower() else "วัน"
            image_array = item.get("item_image_url")
            cover_image = "https://placeholder.com/image.png"
            if isinstance(image_array, list) and image_array:
                cover_image = image_array[0]
            elif isinstance(image_array, str) and image_array:
                cover_image = image_array

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
        )

        try:
            raw_content = await self.ollama.chat_json(
                messages=messages,
                schema=AssistantResponse.model_json_schema(),
                max_tokens=220,
                timeout=35.0,
            )
            parsed = AssistantResponse.model_validate_json(raw_content)
            answer = await self._ensure_answer_language(
                parsed.answer.strip(), cleaned_query
            )
            selected_id = parsed.selected_item_id
        except Exception as exc:
            print(f"[LLM Final Response Error]: {exc}")
            answer = (
                "ขออภัยค่ะ ยังไม่สามารถสรุปข้อมูลให้ได้ในขณะนี้"
                if self._is_thai(cleaned_query)
                else "Sorry, I couldn't summarize the results right now."
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
