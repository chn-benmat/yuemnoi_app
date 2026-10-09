import json
from datetime import datetime, timezone
from typing import List, Optional

from app.application.prompts.intent_routing import INTENT_ROUTING_PROMPT
from app.application.services.conversation_context import ContextLimits, conversation_context
from app.domain.entities.chat_message import ChatMessage
from app.domain.entities.intent_decision import RequestUnderstanding
from app.domain.interfaces.llm_service import LLMServiceInterface
from app.application.services.catalog_guidance import validated_schema


class RouteIntentUseCase:
    """Analyze goals, sufficiency and supplied session context in one model call."""

    def __init__(self, llm_service: LLMServiceInterface,
                 context_limits: ContextLimits, temperature: float):
        self._llm = llm_service
        self._context_limits = context_limits
        self._temperature = temperature

    async def execute(self, message: str,
                      history: Optional[List[ChatMessage]] = None, *,
                      session_context=None, questionnaire_answers=(), questionnaire_skipped=False) -> RequestUnderstanding:
        context = conversation_context(history or [], self._context_limits)
        prompt = json.dumps({
            "current_time": datetime.now(timezone.utc).isoformat(),
            "conversation": context,
            "current_message": {"id": "current", "role": "user", "content": message},
            "client_context": {"id": "context", "data": session_context.model_dump()} if session_context else None,
            "questionnaire_answers": {"id": "answers", "data": [a.model_dump() for a in questionnaire_answers]},
            "questionnaire_skipped": questionnaire_skipped,
        }, ensure_ascii=False)
        valid_ids = {entry["id"] for entry in context["messages"]} | {"current"}
        if session_context:
            valid_ids.add("context")
        if questionnaire_answers:
            valid_ids.add("answers")

        def validate(decision):
            for fact in [*decision.known_facts, *decision.user_constraints]:
                if not set(fact.source_message_ids) <= valid_ids:
                    raise ValueError("Unknown conversation evidence ID")
            if questionnaire_skipped and (not decision.clarification_declined or decision.requires_clarification):
                raise ValueError("Explicit skip must be respected")

        schema = validated_schema(RequestUnderstanding, validate)
        decision = await self._llm.generate_structured(
            prompt=prompt, schema=schema,
            system_instruction=INTENT_ROUTING_PROMPT, temperature=self._temperature,
        )
        validated = schema.model_validate(decision.model_dump())
        return RequestUnderstanding.model_validate(validated.model_dump())
