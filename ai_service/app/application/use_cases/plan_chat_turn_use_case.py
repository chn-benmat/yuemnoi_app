"""Planning, optional evidence and one independent response review per turn."""
import asyncio
import json
from dataclasses import asdict
from uuid import uuid4
from pydantic import Field, create_model
from typing import Literal
from pydantic_core import PydanticCustomError

from app.application.dtos.chat_dto import ChatResponseDTO, ClarificationDTO, ItemDTO, SearchSourceDTO
from app.application.services.catalog_guidance import catalog_snapshot, compact_catalog, validated_schema, presented_record, presented_catalog
from app.application.services.conversation_context import conversation_context, message_source_id
from app.application.services.review_input import compact_planning_input
from app.domain.entities.app_knowledge import KnowledgeTopic
from app.domain.entities.chat_result import EvidenceReference, SessionContext
from app.domain.entities.clarification import ChoiceOption, QuestionStep
from app.domain.entities.turn_plan import TurnPlan, NativeTurnPlan, EvidenceAnswer, PlannedQuestion, ClarificationStage, EvidenceStage, ConversationStage
from app.domain.entities.intent_decision import RequestUnderstanding
from app.domain.entities.catalog_guidance import QuestionChoice, SelectionPlan, SelectedItem, PriceRequirement
from app.domain.exceptions import GuidanceGenerationError
from app.core.exceptions import DatabaseException
from app.application.services.response_review import ResponseReviewService
from app.domain.interfaces.generation_stage import generation_stage


def render_catalog_text(text, items, referenced_ids=None, presentation=None):
    """Resolve explicit evidence tokens; never interpret user intent or repair model names."""
    records = {item.id: presented_record(item, presentation) for item in items}
    parts = text.split("{{item:")
    if "item:" in parts[0]:
        raise PydanticCustomError("plan_malformed_catalog_text_reference", "Malformed catalog text reference")
    output = [parts[0]]
    for part in parts[1:]:
        token, separator, remainder = part.partition("}}")
        item_id, colon, field = token.rpartition(":")
        if not separator or not colon or item_id not in records or field not in records[item_id]:
            raise PydanticCustomError("plan_unknown_catalog_text_reference", "Unknown catalog text reference")
        if "item:" in remainder:
            raise PydanticCustomError("plan_malformed_catalog_text_reference", "Malformed catalog text reference")
        value = records[item_id][field]
        if not isinstance(value, (str, int, float)):
            raise PydanticCustomError("plan_catalog_text_reference_must_name_a_scalar_field", "Catalog text reference must name a scalar field")
        if referenced_ids is not None:
            referenced_ids.add(item_id)
        output.extend([str(value), remainder])
    return "".join(output)


class PlanChatTurnUseCase:
    def __init__(self, llm, item_repository, knowledge_repository, query_items, search_service,
                 context_limits, guidance_policy, interpretation_policy, execution_guard=None, review_service=None):
        self._llm, self._items, self._knowledge = llm, item_repository, knowledge_repository
        self._query, self._search = query_items, search_service
        self._limits, self._policy = context_limits, guidance_policy
        self._interpretation = interpretation_policy
        self._guard = execution_guard
        self._review = review_service if review_service is not None else ResponseReviewService(
            llm, interpretation_policy["review_instruction"], guidance_policy.temperature, context_limits)

    def _validate_plan(self, plan, valid_sources, request, knowledge, catalog):
        decision = plan.understanding
        for fact in [*decision.known_facts, *decision.user_constraints]:
            if not any(character.isalnum() for character in fact.value):
                raise PydanticCustomError("plan_fact_value_requires_meaningful_text", "Fact value requires meaningful text")
            if not set(fact.source_message_ids) <= valid_sources:
                raise PydanticCustomError("plan_unknown_conversation_evidence_id", "Unknown conversation evidence ID")
        if request.questionnaire_skipped and (not decision.clarification_declined or plan.questions):
            raise PydanticCustomError("plan_skip_cannot_ask_again", "Skip cannot ask again")
        topics = {topic.id: topic for topic in knowledge.topics}
        approved = {article.id for article in knowledge.articles}
        for ids, valid in ((plan.knowledge_ids, approved), (plan.unverified_topic_ids,
                {key for key, topic in topics.items() if topic.status != "approved"})):
            if len(ids) != len(set(ids)) or not set(ids) <= valid:
                raise PydanticCustomError("plan_unknown__duplicate_or_unapproved_topic_id", "Unknown, duplicate or unapproved topic ID")
        if bool(plan.questions) != decision.requires_clarification:
            raise PydanticCustomError("plan_questions_disagree_with_action", "Questions disagree with action")
        if len(plan.questions) > self._policy.max_questions:
            raise PydanticCustomError("plan_question_count_exceeds_limit", "Question count exceeds limit")
        ids, dimensions = [q.id for q in plan.questions], [q.dimension for q in plan.questions]
        known = {f.dimension for f in [*decision.known_facts, *decision.user_constraints]}
        if len(ids) != len(set(ids)) or len(dimensions) != len(set(dimensions)):
            raise PydanticCustomError("plan_duplicate_question_id_or_dimension", "Duplicate question ID or dimension")
        if not set(dimensions) <= set(decision.missing_slots) or set(dimensions) & known:
            raise PydanticCustomError("plan_question_must_address_an_unknown_material_dimension", "Question must address an unknown material dimension")
        actual_ids = {item["id"] for item in catalog["items"]}
        if decision.catalog_operation != "none" and not set(decision.categories) <= set(catalog["categories"]):
            raise PydanticCustomError("plan_unknown_catalog_category_identifier", "Unknown catalog category identifier")
        if request.context and not decision.topic_changed:
            answered = {a.question_id for a in request.questionnaire_answers}
            answered_dimensions = {q.dimension for q in request.context.questions if q.id in answered}
            if answered_dimensions & set(dimensions):
                raise PydanticCustomError("plan_an_answered_question_cannot_be_repeated", "An answered question cannot be repeated")
        for question in plan.questions:
            if len(question.title) > self._policy.title_max_characters or not 1 <= len(question.choices) <= self._policy.max_options:
                raise PydanticCustomError("plan_question_exceeds_ui_bounds", "Question exceeds UI bounds")
            for attr in ("id", "label"):
                values = [getattr(c, attr) for c in question.choices]
                if len(values) != len(set(values)):
                    raise PydanticCustomError("plan_duplicate_choice", "Duplicate choice")
            values = [c.value for c in question.choices]
            if len(values) != len(set(values)):
                raise PydanticCustomError("plan_distinct_choices_must_preserve_distinct_answer_values", "Distinct choices must preserve distinct answer values")
            for choice in question.choices:
                if len(choice.label) > self._policy.option_max_characters or not set(choice.supporting_item_ids) <= actual_ids:
                    raise PydanticCustomError("plan_invalid_choice_label_or_evidence", "Invalid choice label or evidence")
        if plan.questions and (not plan.message.strip() or plan.response_mode != "clarification"):
            raise PydanticCustomError("plan_questions_require_an_introduction_and_no_synthesis", "Questions require an introduction and no synthesis")
        if plan.response_mode == "clarification" and not plan.questions:
            raise PydanticCustomError("plan_clarification_requires_questions", "Clarification stage requires questions")
        if not plan.questions and plan.response_mode in ("equipment", "technical", "catalog_overview") and plan.message:
            raise PydanticCustomError("plan_ready_evidence_stage_requires_empty_message", "Ready evidence-stage prose belongs to its authoritative synthesis or projection")
        if plan.response_mode == "equipment" and (decision.catalog_operation == "none" or decision.requires_clarification):
            raise PydanticCustomError("plan_equipment_mode_requires_a_ready_catalog_operation", "Equipment mode requires a ready catalog operation")
        if plan.response_mode == "technical" and (not decision.needs_external_search or decision.requires_clarification):
            raise PydanticCustomError("plan_technical_mode_requires_verification", "Technical mode requires verification")
        if plan.response_mode == "catalog_overview" and (decision.catalog_operation == "none" or
                decision.budget_max is not None or decision.target_items or decision.user_constraints or
                decision.excluded_items or decision.needs_external_search):
            raise PydanticCustomError("plan_filtered_inventory_needs_evidence_selection", "Filtered inventory needs evidence selection")
        if not plan.questions and (decision.catalog_operation != "none" or decision.needs_external_search) and plan.response_mode not in ("catalog_overview", "equipment", "technical"):
            raise PydanticCustomError("plan_requested_evidence_cannot_be_bypassed", "Requested evidence cannot be bypassed")
        if plan.response_mode == "conversation" and not plan.questions:
            if decision.intent != "general_greeting" or decision.catalog_operation != "none" or plan.knowledge_ids or plan.unverified_topic_ids:
                raise PydanticCustomError("plan_factual_questions_cannot_use_a_social_reply", "Factual questions cannot use a social reply")
            if not plan.message.strip():
                raise PydanticCustomError("plan_empty_social_reply", "Empty social reply")
        if plan.response_mode == 'information' and (decision.intent != 'general_information' or
                decision.catalog_operation != 'none' or decision.needs_external_search or plan.knowledge_ids):
            raise PydanticCustomError('plan_information_requires_a_non_catalog_request', 'General information cannot invent catalog or live technical evidence')
        if plan.response_mode == "documents" and not plan.questions and plan.message:
            raise PydanticCustomError("plan_app_answers_must_come_from_approved_documents", "App answers must come from approved documents")

    async def execute(self, request):
        if self._guard:
            self._guard.select_flow("general")
        if request.context and len(request.context.model_dump_json()) > self._limits.max_characters:
            raise GuidanceGenerationError("context_too_large")
        # A real snapshot supplies IDs/categories; exact fields are refreshed for cards.
        async def read_catalog(refresh=False):
            try:
                items = await self._items.get_all_items(refresh=True) if refresh else await self._items.get_all_items()
                return items, True
            except DatabaseException:
                return [], False

        knowledge, catalog_read = await asyncio.gather(self._knowledge.get_approved_knowledge(), read_catalog())
        items, catalog_available = catalog_read
        if not knowledge.topics:
            knowledge = type(knowledge)(knowledge.document_id, knowledge.version, knowledge.document_sha256,
                knowledge.articles, tuple(KnowledgeTopic(a.id, a.title, "approved") for a in knowledge.articles))
        catalog = catalog_snapshot(items)
        price_groups = {}
        for item in items:
            if item.is_available:
                price_groups.setdefault((item.category, item.type), []).append(item.price)
        conversation = conversation_context(request.history, self._limits, include_source_ids=True)
        current_id = message_source_id('user', request.effective_message)
        sources = {identifier for m in conversation['messages'] for identifier in (m['id'], m['source_id'])} | {current_id}
        if request.questionnaire_answers:
            sources.add("answers")
        payload = {
            "required_output_fields": {model.__name__: list(model.model_fields) for model in
                                       (NativeTurnPlan, ClarificationStage, EvidenceStage, ConversationStage,
                                        RequestUnderstanding, PlannedQuestion, QuestionChoice)},
            "interpretation_policy": {key: value for key, value in self._interpretation.items()
                                      if key not in ("turn_instruction", "evidence_instruction", "review_instruction")},
            "limits": {"questions": self._policy.max_questions, "choices": self._policy.max_options,
                "title_characters": self._policy.title_max_characters, "choice_characters": self._policy.option_max_characters},
            "knowledge_index": [asdict(t) for t in knowledge.topics],
            "catalog_summary": {"categories": catalog["categories"], "item_count": len(items),
                "available_categories": list(dict.fromkeys(i.category for i in items if i.is_available)),
                "prices": {"columns": ["category", "unit", "minimum", "maximum"],
                    "rows": [[category, unit, min(prices), max(prices)] for (category, unit), prices in price_groups.items()]}},
            "catalog_available": catalog_available,
            "conversation": conversation,
            "current_message": {"id": current_id, "content": request.effective_message},
            "client_context": {"id": "context", "data": request.context.model_dump()} if request.context else None,
            "questionnaire_answers": {"id": "answers", "data": [a.model_dump() for a in request.questionnaire_answers]},
            "questionnaire_skipped": request.questionnaire_skipped,
            "active_question_id": request.active_question_id,
        }
        payload = compact_planning_input(payload)
        schema = validated_schema(NativeTurnPlan, lambda p: self._validate_plan(p.to_plan(), sources, request, knowledge, catalog))
        # Overlap a real read with remote planning to keep the pooled connection warm.
        # Its snapshot is not used to approve the answer: the final fresh read remains.
        warming = asyncio.create_task(read_catalog(refresh=True))
        try:
            with generation_stage("planning", downstream=("review",)) as planner:
                plan = await self._llm.generate_structured(prompt=json.dumps(payload, ensure_ascii=False, separators=(",", ":")), schema=schema,
                    system_instruction=self._interpretation["turn_instruction"], temperature=self._policy.temperature)
        finally:
            if not warming.done():
                warming.cancel()
            await asyncio.gather(warming, return_exceptions=True)
        if isinstance(plan, NativeTurnPlan):
            plan = schema.model_validate(plan.model_dump()).to_plan()
        else:
            # Internal legacy adapters remain valid; native provider decoding is strict.
            legacy_schema = validated_schema(TurnPlan, lambda p: self._validate_plan(p, sources | {'current', 'context'}, request, knowledge, catalog))
            plan = legacy_schema.model_validate(plan.model_dump())
        decision = plan.understanding
        if not catalog_available and decision.catalog_operation != "none":
            raise GuidanceGenerationError("catalog_unavailable")
        flow = "technical" if plan.response_mode == "technical" else (
            "equipment" if plan.response_mode == "equipment" else "general")
        if self._guard:
            self._guard.select_flow(flow)
        questions = []
        batch = uuid4().hex
        for index, q in enumerate(plan.questions):
            choices = [ChoiceOption(id=c.id, label=c.label, action_value=c.value) for c in q.choices]
            questions.append(QuestionStep(id=f"{batch}:{q.id}", dimension=q.dimension, title=q.title,
                choices=choices, options=[c.label for c in q.choices], step=index+1, total_steps=len(plan.questions)))
        clarification = ClarificationDTO(question=plan.message, missing_dimension=questions[0].dimension,
            options=questions[0].choices, questions=questions) if questions else None
        article_map = {a.id: a for a in knowledge.articles}
        references = [EvidenceReference(id=key, kind="app_knowledge", title=s.title, reference=s.reference,
            reviewed_at=article_map[key].reviewed_at.isoformat(), content_sha256=article_map[key].content_sha256)
            for key in plan.knowledge_ids for s in article_map[key].sources]
        blocks = [article_map[key].content for key in plan.knowledge_ids]
        if plan.unverified_topic_ids or (plan.response_mode == "documents" and not blocks and not questions):
            blocks.append(self._interpretation["unavailable_notice"])
        selection, cited_search, replies = None, [], []
        writers = [planner.provenance]
        review_catalog = items
        web = []
        if plan.response_mode == "catalog_overview":
            overview_items = await self._items.get_all_items(refresh=True)
            review_catalog = overview_items
            if decision.categories:
                overview_items = [i for i in overview_items if i.category in decision.categories]
            if plan.overview_available_only:
                overview_items = [i for i in overview_items if i.is_available]
            overview = catalog_snapshot(overview_items)
            blocks.append("\n".join(overview["categories"]) or self._interpretation["empty_catalog_notice"])
            references.extend(EvidenceReference(id=i.id, kind="catalog", title=i.name, reference=i.id) for i in overview_items)
        if plan.response_mode in ("equipment", "technical"):
            # Evidence combines selection/prose; an independent reviewer follows.
            fresh_items = await self._items.get_all_items(refresh=True) if decision.catalog_operation != "none" else []
            review_catalog = fresh_items
            # Category inference is not authoritative evidence of item identity/function.
            category_items = fresh_items
            candidates = category_items
            if decision.catalog_operation == "selection":
                candidates = [i for i in candidates if i.is_available]
            price_filter_applied = decision.budget_max is not None and decision.budget_unit in {i.type for i in candidates}
            if price_filter_applied:
                candidates = [i for i in candidates if i.type == decision.budget_unit and i.price <= decision.budget_max]
            candidate_ids = {i.id for i in candidates}
            evidence_catalog = presented_catalog(catalog_snapshot(fresh_items), fresh_items, self._interpretation['catalog_presentation'])
            web = await self._search.search(decision.search_query, max_results=self._policy.max_items) if decision.needs_external_search else []
            web_map = {f"web:{i}": source for i, source in enumerate(web)}

            def validate_answer(answer):
                if len(answer.search_ids) != len(set(answer.search_ids)) or not set(answer.search_ids) <= set(web_map):
                    raise PydanticCustomError("plan_unknown_web_evidence_id", "Unknown web evidence ID")
                if (answer.selection is not None) != (decision.catalog_operation != "none"):
                    raise PydanticCustomError("plan_missing_or_unsolicited_catalog_selection", "Missing or unsolicited catalog selection")
                # Consistency of model-generated conclusions, not an intent classifier.
                expected_fit = "not_assessed"
                if decision.catalog_operation == "selection" and answer.selection is not None:
                    if answer.selection.mode == "items":
                        expected_fit = "meets_request"
                    elif answer.selection.mode == "no_matches":
                        expected_fit = "no_supported_match"
                if answer.request_fit != expected_fit:
                    raise PydanticCustomError("plan_request_fit_disagrees_with_selection_outcome", "Request fit disagrees with selection outcome")
                if answer.selection is not None:
                    if not {i.id for i in answer.selection.selected_items} <= candidate_ids:
                        raise PydanticCustomError("plan_selection_exceeds_the_category_and_numeric_candidate_scope", "Selection exceeds the category and numeric candidate scope")
                    self._query.validate_selection(answer.selection, decision, fresh_items)
                    for item in answer.selection.selected_items:
                        if "{{item:" + item.id + ":name}}" not in answer.answer:
                            raise PydanticCustomError("plan_selected_item_prose_requires_an_authoritative_name_reference", "Selected item prose requires an authoritative name reference")
                render_catalog_text(answer.answer, fresh_items, presentation=self._interpretation['catalog_presentation'])
                for reply in answer.suggested_replies:
                    render_catalog_text(reply, fresh_items, presentation=self._interpretation['catalog_presentation'])

            allowed_purposes = ["recommendation"] if decision.catalog_operation == "selection" else list(
                SelectionPlan.model_fields["purpose"].annotation.__args__)
            established_unit = decision.budget_unit if decision.budget_max is not None and decision.budget_unit in {
                item.type for item in fresh_items} else None
            price_schema = create_model("EstablishedPriceRequirement", __base__=PriceRequirement,
                maximum=(float, Field(ge=decision.budget_max, le=decision.budget_max)), user_unit=(Literal[established_unit], ...),
                catalog_units=(list[Literal[established_unit]], Field(min_length=1))) if established_unit else PriceRequirement
            price_requirement_type = type(None) if decision.budget_max is None else price_schema | None
            selection_schema = create_model("ResolvedSelectionPlan", __base__=SelectionPlan,
                purpose=(Literal[tuple(allowed_purposes)], ...), price_requirement=(price_requirement_type, ...))
            grounded_schema = create_model("GroundedEvidenceAnswer", __base__=EvidenceAnswer,
                selection=(selection_schema if decision.catalog_operation != "none" else type(None), ...),
                search_ids=(list[str], Field(max_length=len(web_map))))
            response_schema = validated_schema(grounded_schema, validate_answer)
            with generation_stage("evidence", downstream=("review",)) as evidence_writer:
                answer = await self._generate_evidence(decision, response_schema, allowed_purposes, fresh_items,
                    evidence_catalog, candidate_ids, category_items, candidates, price_filter_applied, web_map, established_unit)
            # Equipment/technical branches publish evidence prose, not the
            # planning message. Exclude only actual visible-text writers.
            writers = [evidence_writer.provenance]
            answer = response_schema.model_validate(answer.model_dump())
            if answer.selection:
                selection = self._query.selection_from_snapshot(answer.selection, decision, fresh_items)
            cited_search = [web_map[key] for key in answer.search_ids]
            references.extend(EvidenceReference(id=key, kind="web", title=web_map[key].title,
                reference=web_map[key].url or web_map[key].link) for key in answer.search_ids)
            prose_item_ids = set()
            blocks.append(render_catalog_text(answer.answer, fresh_items, prose_item_ids, self._interpretation['catalog_presentation']))
            replies = [render_catalog_text(reply, fresh_items, prose_item_ids, self._interpretation['catalog_presentation']) for reply in answer.suggested_replies]
            references.extend(EvidenceReference(id=i.id, kind="catalog", title=i.name, reference=i.id)
                              for i in fresh_items if i.id in prose_item_ids)
            if selection and selection.mode == "categories":
                blocks.append(" / ".join(selection.available_categories))
        elif plan.message:
            blocks.append(plan.message)
        selected_items = selection.items if selection else []
        cited_catalog_ids = {r.id for r in references if r.kind == "catalog"}
        references.extend(EvidenceReference(id=i.id, kind="catalog", title=i.name, reference=i.id)
                          for i in selected_items if i.id not in cited_catalog_ids)
        context = SessionContext.from_decision(request.session_id or uuid4().hex, decision, questions,
                                             [i.id for i in selected_items])
        response_kind = ('clarification' if questions else {
            'conversation': 'conversation', 'information': 'information', 'documents': 'app_information',
            'technical': 'technical', 'catalog_overview': 'overview',
        }.get(plan.response_mode) or {'comparison': 'comparison', 'inspection': 'item_details',
                                     'selection': 'recommendation'}.get(decision.catalog_operation, 'information'))
        draft = ChatResponseDTO(response="\n\n".join(blocks), intent=decision.intent, response_kind=response_kind,
            request_scope=decision.request_scope, information_sufficient=decision.information_sufficient,
            next_action=decision.next_action, response_flow=flow,
            confidence=decision.confidence, ambiguity_level=decision.ambiguity_level,
            clarification=clarification, questions=questions,
            items=[ItemDTO.from_entity(i, self._interpretation['catalog_presentation']) for i in selected_items],
            search_query=decision.search_query or "", search_sources=[SearchSourceDTO.from_entity(s) for s in cited_search],
            suggested_replies=replies, context=context, references=references)
        await self._review.execute(request, draft, writers, review_catalog,
            [{"id":key, "content":article_map[key].content} for key in plan.knowledge_ids],
            [source.model_dump(mode="json") for source in web])
        if (await self._knowledge.get_approved_knowledge()).document_sha256 != knowledge.document_sha256:
            raise GuidanceGenerationError("knowledge_changed")
        if questions or plan.response_mode == "catalog_overview":
            fresh = catalog_snapshot(await self._items.get_all_items(refresh=True))
            original = catalog_snapshot(review_catalog)
            if {i["id"]: i for i in fresh["items"]} != {i["id"]: i for i in original["items"]}:
                raise GuidanceGenerationError("catalog_changed")
        if selection:
            final_selection = await self._query.refresh_selection(selection)
            # Review can cite unselected catalog rows as alternatives. Validate
            # the whole authoritative snapshot after review, including that prose.
            original = catalog_snapshot(review_catalog)
            if {i["id"]: i for i in final_selection.catalog_evidence["items"]} != {i["id"]: i for i in original["items"]}:
                raise GuidanceGenerationError("catalog_changed")
        return draft

    async def _generate_evidence(self, decision, response_schema, allowed_purposes, fresh_items,
                               evidence_catalog, candidate_ids, category_items, candidates, price_filter_applied, web_map, established_unit):
        return await self._llm.generate_structured(prompt=json.dumps({
                "required_output_fields": {model.__name__: list(model.model_fields) for model in
                                           (EvidenceAnswer, SelectionPlan, SelectedItem, PriceRequirement)},
                "selection_required": decision.catalog_operation != "none",
                "allowed_selection_purposes": allowed_purposes,
                "allowed_search_ids": list(web_map),
                "price_contract": {"ceiling": decision.budget_max, "established_period": decision.budget_unit,
                                   "catalog_periods": sorted({i.type for i in fresh_items}),
                                   "permitted_catalog_periods": [established_unit] if established_unit else [],
                                   "conversion_allowed": False},
                "understanding": decision.model_dump(), "catalog": compact_catalog(evidence_catalog),
                "catalog_scope": {
                    "inventory_item_count": len(fresh_items), "category_item_count": len(category_items),
                    "available_category_item_count": sum(i.is_available for i in category_items),
                    "candidate_item_count": len(candidates),
                    "full_catalog_included": True,
                    "eligible_item_ids": sorted(candidate_ids),
                    "categories": decision.categories,
                    "available_only": decision.catalog_operation == "selection",
                    "price_filter_applied": price_filter_applied,
                },
                "search_evidence": [{"id": key, **source.model_dump()} for key, source in web_map.items()],
                "max_items": self._policy.max_items, "neutrality": self._interpretation["neutrality"],
            }, ensure_ascii=False, separators=(",", ":")), schema=response_schema, system_instruction=self._interpretation["evidence_instruction"],
                temperature=self._policy.temperature)
