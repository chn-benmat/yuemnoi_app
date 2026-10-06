import asyncio
import json
from dataclasses import asdict
from uuid import uuid4
from typing import AsyncGenerator

from app.application.dtos.chat_dto import ChatRequestDTO, ChatResponseDTO, ClarificationDTO, ItemDTO, SearchSourceDTO
from app.application.prompts.chat_answer import ANSWER_PROMPT, ANSWER_REVIEW_PROMPT
from app.application.services.catalog_guidance import catalog_snapshot, generate_reviewed, validated_schema
from app.application.services.conversation_context import ContextLimits, conversation_context
from app.application.use_cases.route_intent_use_case import RouteIntentUseCase
from app.application.use_cases.query_items_use_case import QueryItemsUseCase
from app.application.use_cases.generate_clarification_use_case import GenerateClarificationUseCase
from app.domain.entities.catalog_guidance import GuidancePolicy
from app.domain.entities.chat_result import AnswerPlan, EvidenceReference, SessionContext
from app.domain.exceptions import GuidanceGenerationError
from app.domain.interfaces.knowledge_repository import KnowledgeRepositoryInterface
from app.domain.interfaces.llm_service import LLMServiceInterface
from app.domain.interfaces.search_service import SearchServiceInterface
from app.domain.interfaces.execution_guard import ExecutionGuard


class ProcessChatMessageUseCase:
    """One validated result is projected to both JSON and legacy SSE events."""

    def __init__(self, route_intent: RouteIntentUseCase, query_items: QueryItemsUseCase,
                 generate_clarification: GenerateClarificationUseCase,
                 llm_service: LLMServiceInterface, search_service: SearchServiceInterface, context_limits: ContextLimits,
                 knowledge_repository: KnowledgeRepositoryInterface, policy: GuidancePolicy,
                 stream_heartbeat_seconds: float, stream_chunk_characters: int,
                 execution_guard: ExecutionGuard | None = None, fast_path=None):
        self._route_intent = route_intent
        self._query_items = query_items
        self._generate_clarification = generate_clarification
        self._llm = llm_service
        self._search = search_service
        self._context_limits = context_limits
        self._knowledge = knowledge_repository
        self._policy = policy
        self._heartbeat = stream_heartbeat_seconds
        self._chunk_size = stream_chunk_characters
        self._execution_guard = execution_guard
        self._fast_path = fast_path

    async def execute(self, request: ChatRequestDTO) -> ChatResponseDTO:
        if self._execution_guard is not None:
            async with self._execution_guard.turn():
                return await self._execute(request)
        return await self._execute(request)

    async def _execute(self, request: ChatRequestDTO) -> ChatResponseDTO:
        if self._fast_path is not None:
            return await self._fast_path.execute(request)
        if request.context and len(request.context.model_dump_json()) > self._context_limits.max_characters:
            raise GuidanceGenerationError("context_too_large")
        decision = await self._route_intent.execute(
            request.effective_message, request.history, session_context=request.context,
            questionnaire_answers=request.questionnaire_answers,
            questionnaire_skipped=request.questionnaire_skipped)
        if self._execution_guard is not None:
            flow = "technical" if decision.needs_external_search and not decision.requires_clarification else (
                "general" if decision.requires_clarification or decision.catalog_operation == "none" else "equipment")
            self._execution_guard.select_flow(flow)
        knowledge = await self._knowledge.get_approved_knowledge()
        questions = []
        clarification_dto = None
        selection = None
        if decision.requires_clarification:
            clarification = await self._generate_clarification.execute(request.effective_message, decision)
            batch_id = uuid4().hex
            questions = [q.model_copy(update={"id": f"{batch_id}:{q.id}"}) for q in clarification.questions]
            clarification_dto = ClarificationDTO(
                question=clarification.question, missing_dimension=clarification.missing_dimension,
                options=clarification.options, questions=questions)
        elif decision.catalog_operation != "none":
            selection = await self._query_items.execute_selection(decision)
        items = selection.items if selection else []
        sources = []
        if decision.needs_external_search and not questions:
            sources = await self._search.search(decision.search_query, max_results=self._policy.max_items)
        source_map = {f"web:{index}": source for index, source in enumerate(sources)}
        article_map = {article.id: article for article in knowledge.articles}
        item_map = {item.id: item for item in items}
        payload = {
            "user_message": request.effective_message,
            "conversation": conversation_context(request.history, self._context_limits),
            "understanding": decision.model_dump(),
            "approved_knowledge": [json.loads(json.dumps(asdict(a), default=str)) for a in knowledge.articles],
            "catalog": catalog_snapshot(items),
            "validated_selection": {
                "mode": selection.mode, "available_categories": selection.available_categories,
                "reasoning": selection.reasoning,
                "selected_items": [i.model_dump() for i in selection.selected_items],
            } if selection else None,
            "questions": [q.model_dump() for q in questions],
            "search_evidence": [{"id": key, **value.model_dump()} for key, value in source_map.items()],
        }

        def validate(plan):
            for ids, valid in ((plan.item_ids, item_map), (plan.knowledge_ids, article_map), (plan.search_ids, source_map)):
                if len(ids) != len(set(ids)) or not set(ids) <= set(valid):
                    raise ValueError("Unknown or duplicate evidence ID")
            if questions and (plan.item_ids or plan.suggested_replies):
                raise ValueError("Clarification cannot have cards or competing suggestions")

        plan = await generate_reviewed(self._llm, self._policy, payload,
            validated_schema(AnswerPlan, validate), ANSWER_PROMPT, ANSWER_REVIEW_PROMPT)
        if (await self._knowledge.get_approved_knowledge()).document_sha256 != knowledge.document_sha256:
            raise GuidanceGenerationError("knowledge_changed")
        if selection is not None:
            fresh_selection = await self._query_items.refresh_selection(selection)
            item_map = {item.id: item for item in fresh_selection.items}
        references = []
        for article_id in plan.knowledge_ids:
            article = article_map[article_id]
            references.extend(EvidenceReference(id=article_id, kind="app_knowledge", title=source.title,
                reference=source.reference, reviewed_at=article.reviewed_at.isoformat(),
                content_sha256=article.content_sha256) for source in article.sources)
        for source_id in plan.search_ids:
            source = source_map[source_id]
            references.append(EvidenceReference(id=source_id, kind="web", title=source.title,
                reference=source.url or source.link))
        references.extend(EvidenceReference(id=item_id, kind="catalog", title=item_map[item_id].name,
                          reference=item_id) for item_id in plan.item_ids)
        context = SessionContext.from_decision(request.session_id or uuid4().hex, decision, questions, plan.item_ids)
        answer = plan.answer
        if plan.knowledge_ids and (questions or decision.catalog_operation == "none"):
            # App facts are projected from approved document IDs, not model prose.
            # This prevents inferred workflow steps from escaping a permissive review.
            answer = "\n\n".join(article_map[key].content for key in plan.knowledge_ids)
            if questions:
                answer += "\n\n" + clarification_dto.question
        return ChatResponseDTO(response=answer, intent=decision.intent,
            confidence=decision.confidence, ambiguity_level=decision.ambiguity_level,
            clarification=clarification_dto, questions=questions,
            items=[ItemDTO.from_entity(item_map[item_id]) for item_id in plan.item_ids],
            search_query=decision.search_query or "",
            search_sources=[SearchSourceDTO.from_entity(source_map[key]) for key in plan.search_ids],
            suggested_replies=plan.suggested_replies, context=context, references=references)

    @staticmethod
    def _event(name: str, payload: dict) -> str:
        return f"event: {name}\ndata: {json.dumps(payload, ensure_ascii=False)}\n\n"

    async def execute_stream(self, request: ChatRequestDTO) -> AsyncGenerator[str, None]:
        yield self._event("status", {"step": "processing", "message": "กำลังวิเคราะห์คำถาม..."})
        task = asyncio.create_task(self.execute(request))
        try:
            while not task.done():
                done, _ = await asyncio.wait({task}, timeout=self._heartbeat)
                if not done:
                    yield ": keep-alive\n\n"
            result = await task
            payload = result.model_dump(mode="json")
            # Legacy names and events remain projections of the same validated result.
            payload.update(answer=result.response, recommended_items=payload["items"])
            # ส่งคำตอบครบที่ตรวจแล้วก่อนแบ่งตัวอักษร เพื่อวัดเวลารอคำตอบแยกจากการแสดงผล
            yield self._event("ready", payload)
            yield self._event("metadata", {
                "mode": "clarification" if result.questions else "recommendation",
                "recommended_items": payload["items"], "questions": payload["questions"],
                "references": payload["references"],
                "request_scope": result.request_scope,
                "information_sufficient": result.information_sufficient,
                "next_action": result.next_action,
                "response_flow": result.response_flow,
                "response_kind": result.response_kind,
            })
            for start in range(0, len(result.response), self._chunk_size):
                yield self._event("delta", {"text": result.response[start:start + self._chunk_size]})
            yield self._event("done", payload)
            yield "data: [DONE]\n\n"
        finally:
            if not task.done():
                task.cancel()
            await asyncio.gather(task, return_exceptions=True)
