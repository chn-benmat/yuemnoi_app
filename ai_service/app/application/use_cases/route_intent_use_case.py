from typing import List, Optional
from app.domain.entities.chat_message import ChatMessage
from app.domain.entities.intent_decision import IntentDecision
from app.domain.interfaces.llm_service import LLMServiceInterface
from app.infrastructure.prompts.prompt_templates import INTENT_ROUTING_PROMPT


class RouteIntentUseCase:
    """Classifies user intent, ambiguity level, and extracts entities via semantic reasoning."""

    def __init__(self, llm_service: LLMServiceInterface):
        self._llm = llm_service

    async def execute(
        self,
        message: str,
        history: Optional[List[ChatMessage]] = None,
    ) -> IntentDecision:
        context_parts = []
        if history:
            recent_history = history[-4:]  # Keep last 4 turns for context awareness
            for msg in recent_history:
                content = msg.content
                if content.strip().startswith("{") and "}" in content:
                    try:
                        import json
                        parsed = json.loads(content)
                        ans = parsed.get("answer", "")
                        items = parsed.get("items", [])
                        item_names = [it.get("name") for it in items if isinstance(it, dict) and it.get("name")]
                        prefix = f"[อุปกรณ์ที่เพิ่งแนะนำในบริบท: {', '.join(item_names)}]\n" if item_names else ""
                        context_parts.append(f"{msg.role}: {prefix}{ans[:300]}")
                        continue
                    except Exception:
                        pass
                context_parts.append(f"{msg.role}: {content[:300]}")

        history_context = "\n".join(context_parts) if context_parts else "ไม่มีประวัติก่อนหน้า"

        from datetime import datetime
        current_year = datetime.now().year

        prompt = (
            f"บริบทเวลาปัจจุบัน: ปี ค.ศ. {current_year} (พ.ศ. {current_year + 543})\n\n"
            f"ประวัติการคุยล่าสุด:\n{history_context}\n\n"
            f"ข้อความปัจจุบันของผู้ใช้: '{message}'\n\n"
            "กรุณาวิเคราะห์เจตนาเชิงความหมาย (Semantic Intent) และความคลุมเครือตาม Schema ที่กำหนด "
            "โดยพิจารณาบริบทอุปกรณ์ที่อยู่ในประวัติการคุยล่าสุด และเส้นเวลาปัจจุบันอย่างรอบคอบ "
            f"(หากผู้ใช้ถามถึง 'รุ่นล่าสุด' หรือ 'ตัวล่าสุด' ให้อ้างอิงรุ่นล่าสุดจริง ณ ปี {current_year} เช่น iPhone รุ่นล่าสุด ณ ปี {current_year} คือ iPhone 17 ซีรีส์ ไม่ใช่รุ่นเก่าในอดีต)"
        )

        decision = await self._llm.generate_structured(
            prompt=prompt,
            schema=IntentDecision,
            system_instruction=INTENT_ROUTING_PROMPT,
            temperature=0.1,
        )
        return decision
