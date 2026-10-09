"""Planning, evidence and independent review with one bounded draft recovery."""
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
from app.application.services.review_input import compact_planning_input, compact_review_draft
from app.application.services.recovery_evidence import request_evidence,catalog_evidence
from app.domain.entities.app_knowledge import KnowledgeTopic
from app.domain.entities.chat_result import EvidenceReference, SessionContext
from app.domain.entities.clarification import ChoiceOption, QuestionStep
from app.domain.entities.turn_plan import TurnPlan, NativeTurnPlan, EvidenceAnswer, ReplyRepair, PlannedQuestion, ClarificationStage, CatalogOverviewStage
from app.domain.entities.intent_decision import RequestUnderstanding,NativePlanningUnderstanding,NativeBudgetPeriod,NativeKnownFact
from app.domain.entities.catalog_guidance import SelectionPlan, SelectedItem, PriceRequirement
from app.domain.exceptions import GuidanceGenerationError
from app.core.exceptions import DatabaseException
from app.application.services.response_review import ResponseReviewService, VISIBLE_TEXT_SURFACES
from app.domain.interfaces.generation_stage import generation_stage, GenerationRequest


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
            llm, interpretation_policy["review_instruction"], guidance_policy.temperature, context_limits,
            choice_policy=guidance_policy.choice_policy)

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
        previous_questions = {}
        for question in plan.questions:
            if question.branches:
                sources = {branch.source_question_id for branch in question.branches}
                if len(sources) != 1 or not sources <= previous_questions.keys():
                    raise PydanticCustomError('plan_branch_requires_an_earlier_question', 'A conditional question must reference one earlier question')
                source = previous_questions[next(iter(sources))]
                option_ids = [branch.source_option_id for branch in question.branches]
                if len(option_ids) != len(set(option_ids)) or set(option_ids) != {choice.id for choice in self._all_choices(source)}:
                    raise PydanticCustomError('plan_branch_choice_coverage_invalid', 'Conditional versions must cover the exact earlier choice IDs')
            versions = [question, *question.branches]
            for version in versions:
                if question.dimension == 'budget_max' and version.unrestricted_choice is None:
                    raise PydanticCustomError('plan_budget_requires_an_unrestricted_choice', 'Budget versions must include an explicit no-ceiling choice')
                self._validate_question_version(version, actual_ids, preserve_label=question.dimension == 'budget_max')
            projected_ids = [c.id for c in self._all_choices(question)] + [
                f'{branch.source_option_id}:{c.id}' for branch in question.branches for c in self._all_choices(branch)]
            if len(projected_ids) != len(set(projected_ids)):
                raise PydanticCustomError('plan_duplicate_projected_choice_id', 'Conditional choice IDs must remain unique')
            previous_questions[question.id] = question
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
            raise PydanticCustomError("plan_filtered_inventory_needs_evidence_selection", "Filtered inventory needs evidence selection",
                {'provider_requirement': CatalogOverviewStage.model_fields['response_mode'].description + ' ' +
                    TurnPlan.model_fields['response_mode'].description})
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

    def _validate_question_version(self, question, actual_ids, *, preserve_label=False):
        choices = self._all_choices(question)
        if len(question.title) > self._policy.title_max_characters or not 1 <= len(choices) <= self._policy.max_options:
            raise PydanticCustomError("plan_question_exceeds_ui_bounds", "Question exceeds UI bounds")
        policy = self._policy.choice_policy
        if policy is not None:
            minimum, maximum = ((policy.budget_total, policy.budget_total) if preserve_label
                                else (policy.regular_min, policy.regular_max))
            if not minimum <= len(choices) <= maximum:
                raise PydanticCustomError('plan_question_choice_count_mismatch', 'Choice count violates the questionnaire policy',
                    {'provider_requirement': 'Use the configured questionnaire choice policy: ' + policy.model_dump_json() +
                        '. Budget choices include one unrestricted option; ordinary choices answer the actual unknown dimension.'})
        for attr in ("id", "label"):
            values = [getattr(c, attr) for c in choices]
            if len(values) != len(set(values)):
                raise PydanticCustomError("plan_duplicate_choice", "Duplicate choice")
        values = [c.label if preserve_label else c.value for c in choices]
        if len(values) != len(set(values)):
            raise PydanticCustomError("plan_distinct_choices_must_preserve_distinct_answer_values", "Distinct choices must preserve distinct answer values")
        for choice in choices:
            if len(choice.label) > self._policy.option_max_characters or not set(choice.supporting_item_ids) <= actual_ids:
                raise PydanticCustomError("plan_invalid_choice_label_or_evidence", "Invalid choice label or evidence")

    @staticmethod
    def _all_choices(question):
        return [*question.choices, *([question.unrestricted_choice] if question.unrestricted_choice else [])]

    @staticmethod
    def _question_steps(planned, batch):
        questions = []
        for index, question in enumerate(planned):
            # งบส่งข้อความที่ผู้ใช้เลือกทั้งประโยค ป้องกันค่าตัวเลขล้วนทำหน่วยหาย
            def projected(c, prefix=''):
                return ChoiceOption(id=prefix+c.id, label=c.label,
                    action_value=c.label if question.dimension == 'budget_max' else c.value)
            choices = [projected(c) for c in PlanChatTurnUseCase._all_choices(question)]
            branches = {branch.source_option_id: [projected(c, f'{branch.source_option_id}:')
                for c in PlanChatTurnUseCase._all_choices(branch)] for branch in question.branches}
            questions.append(QuestionStep(id=f'{batch}:{question.id}', dimension=question.dimension,
                title=question.title, options=[c.label for c in choices],
                choices=choices + [c for branch in branches.values() for c in branch],
                step=index+1, total_steps=len(planned),
                branch_question_id=f'{batch}:{question.branches[0].source_question_id}' if question.branches else None,
                branch_choices=branches,
                branch_titles={branch.source_option_id: branch.title for branch in question.branches},
                branch_options={key: [c.label for c in value] for key, value in branches.items()}))
        return questions

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
        planning_request=request_evidence(request,self._limits)
        for message,view in zip(conversation['messages'],planning_request['history']):
            # Keep the original source IDs and actual selected answer text;
            # completed, unchosen UI controls need no further interpretation.
            message['content']=view['content']
        current_id = message_source_id('user', request.effective_message)
        sources = {identifier for m in conversation['messages'] for identifier in (m['id'], m['source_id'])} | {current_id}
        if request.questionnaire_answers:
            sources.add("answers")
        answered_values = []
        if request.context:
            by_id = {question.id:question for question in request.context.questions}
            for answer in request.questionnaire_answers:
                question = by_id[answer.question_id]
                choice = next((choice for choice in question.choices if choice.id == answer.option_id),None)
                answered_values.append({'question_id':question.id,'dimension':question.dimension,
                    'label':choice.label if choice else answer.text,
                    'value':choice.action_value if choice else answer.text,'source_id':'answers'})
        payload = {
            # จับคู่ด้วย ID เท่านั้น ให้โมเดลอ่าน label/value จริงก่อนบริบท UI ซ้ำ ๆ
            'answered_values': answered_values,
            # ใช้คำสั่งที่อนุมัติใน system แล้ว ไม่ส่งคำอธิบายขอบเขตตรวจงานซ้ำ
            "limits": {"questions": self._policy.max_questions, "choices": self._policy.max_options,
                "choice_policy": self._policy.choice_policy.model_dump() if self._policy.choice_policy else None,
                "title_characters": self._policy.title_max_characters, "choice_characters": self._policy.option_max_characters},
            "knowledge_index": [asdict(t) for t in knowledge.topics],
            "catalog_summary": {"categories": catalog["categories"], "item_count": len(items),
                "currency": self._interpretation['catalog_presentation']['currency'],
                "unit_labels": self._interpretation['catalog_presentation']['unit_labels'],
                "available_categories": list(dict.fromkeys(i.category for i in items if i.is_available)),
                # ขั้นถามใช้ชนิด/ชื่อจริง ส่วนคุณสมบัติเต็มอ่านในขั้นเลือกก่อนแนะนำเสมอ
                "equipment": {"columns": ["id", "name", "category"],
                    "rows": [[i.id, i.name, i.category] for i in items if i.is_available]},
                "prices": {"columns": ["category", "unit", "minimum", "maximum"],
                    "rows": [[category, unit, min(prices), max(prices)] for (category, unit), prices in price_groups.items()]}},
            "catalog_available": catalog_available,
            "conversation": conversation,
            "current_message": {"id": current_id, "content": request.effective_message},
            "client_context": {"id": "context", "data": planning_request['context']} if request.context else None,
            "questionnaire_answers": {"id": "answers", "data": [a.model_dump() for a in request.questionnaire_answers]},
            "questionnaire_skipped": request.questionnaire_skipped,
            "active_question_id": request.active_question_id,
        }
        planning_catalog_summary = payload['catalog_summary']
        payload = compact_planning_input(payload)
        units=tuple(sorted({item.type for item in items}))
        period_schema=create_model('CatalogBudgetPeriod',__base__=NativeBudgetPeriod,
            catalog_unit=(Literal[units] | None if units else type(None),NativeBudgetPeriod.model_fields['catalog_unit']))
        # รหัสหลักฐานมาจากข้อความจริง ป้องกันนำรหัสสินค้าหรือบทความมาอ้างเป็นคำตอบผู้ใช้
        fact_schema=create_model('ConversationSourceFact',__base__=NativeKnownFact,
            source_message_ids=(list[Literal[tuple(sorted(sources))]], Field(min_length=1)))
        understanding_schema=create_model('CatalogRequestUnderstanding',__base__=NativePlanningUnderstanding,
            budget_unit=(period_schema | None,NativePlanningUnderstanding.model_fields['budget_unit']),
            known_facts=(list[fact_schema], ...), user_constraints=(list[fact_schema], ...))
        approved_ids=tuple(article.id for article in knowledge.articles)
        unverified_ids=tuple(topic.id for topic in knowledge.topics if topic.status != 'approved')
        # ผูก ID ตามเอกสารจริงโดยคงคำอธิบายขอบเขต ไม่ให้โมเดลเลือกทุกหัวข้อ
        native_plan=create_model('CatalogNativeTurnPlan',__base__=NativeTurnPlan,
            understanding=(understanding_schema,NativeTurnPlan.model_fields['understanding']),
            knowledge_ids=(list[Literal[approved_ids]] if approved_ids else list[None],
                Field(max_length=len(approved_ids), description=NativeTurnPlan.model_fields['knowledge_ids'].description,
                      json_schema_extra={'x-provider-description': True})),
            unverified_topic_ids=(list[Literal[unverified_ids]] if unverified_ids else list[None],
                Field(max_length=len(unverified_ids), description=NativeTurnPlan.model_fields['unverified_topic_ids'].description,
                      json_schema_extra={'x-provider-description': True})))
        schema = validated_schema(native_plan, lambda p: self._validate_plan(p.to_plan(), sources, request, knowledge, catalog))
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
        batch = uuid4().hex
        questions = self._question_steps(plan.questions, batch)
        clarification = ClarificationDTO(question=plan.message, missing_dimension=questions[0].dimension,
            options=questions[0].choices, questions=questions) if questions else None
        article_map = {a.id: a for a in knowledge.articles}
        references = [EvidenceReference(id=key, kind="app_knowledge", title=s.title, reference=s.reference,
            reviewed_at=article_map[key].reviewed_at.isoformat(), content_sha256=article_map[key].content_sha256)
            for key in plan.knowledge_ids for s in article_map[key].sources]
        blocks = [article_map[key].content for key in plan.knowledge_ids]
        if plan.unverified_topic_ids or (plan.response_mode == "documents" and not blocks and not questions):
            blocks.append(self._interpretation["unavailable_notice"])
        prefix_blocks = list(blocks)
        response_schema = None
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
            price_filter_applied = decision.catalog_operation == 'selection' and decision.budget_max is not None and decision.budget_unit in {i.type for i in candidates}
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

            allowed_purposes = ["recommendation"] if decision.catalog_operation == "selection" else ["inspection"]
            established_unit = decision.budget_unit if decision.catalog_operation == 'selection' and decision.budget_max is not None and decision.budget_unit in {
                item.type for item in fresh_items} else None
            price_schema = create_model("EstablishedPriceRequirement", __base__=PriceRequirement,
                maximum=(float, Field(ge=decision.budget_max, le=decision.budget_max)), user_unit=(Literal[established_unit], ...),
                catalog_units=(list[Literal[established_unit]], Field(min_length=1))) if established_unit else PriceRequirement
            price_requirement_type = type(None) if decision.catalog_operation != 'selection' or decision.budget_max is None else price_schema | None
            eligible_item = create_model('EligibleSelectedItem', __base__=SelectedItem,
                id=(Literal[tuple(sorted(candidate_ids))], ...)) if candidate_ids else type(None)
            selection_schema = create_model("ResolvedSelectionPlan", __base__=SelectionPlan,
                purpose=(Literal[tuple(allowed_purposes)], ...), price_requirement=(price_requirement_type, ...),
                selected_items=(list[eligible_item], Field(max_length=self._policy.max_items if candidate_ids else 0)))
            grounded_schema = create_model("GroundedEvidenceAnswer", __base__=EvidenceAnswer,
                selection=(selection_schema if decision.catalog_operation != "none" else type(None), ...),
                request_fit=(EvidenceAnswer.model_fields['request_fit'].annotation if decision.catalog_operation == 'selection'
                             else Literal['not_assessed'], EvidenceAnswer.model_fields['request_fit']),
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
        articles = [{"id": key, "content": article_map[key].content} for key in plan.knowledge_ids]
        web_evidence = [source.model_dump(mode="json") for source in web]
        recovery_request = await self._repair_draft(request, plan, draft, {'issues': [], 'assessments': []},
            review_catalog, articles, web, knowledge, sources, prefix_blocks, selection, response_schema,
            planning_catalog_summary, preview=True)
        review_scope = ({'catalog_summary': planning_catalog_summary}
            if questions or plan.response_mode in ('conversation', 'information', 'documents') else {})
        try:
            await self._review.execute(request, draft, writers, review_catalog, articles, web_evidence,
                recovery_request=recovery_request, **review_scope)
        except GuidanceGenerationError as rejection:
            if rejection.code != "response_quality_rejected":
                raise
            # แก้ได้เพียงครั้งเดียวและตรวจ draft ทั้งชุดใหม่ ก่อนเปิดเผยข้อความใด ๆ
            draft, selection, repair_writer = await self._repair_draft(request, plan, draft, rejection.review,
                review_catalog, articles, web, knowledge, sources, prefix_blocks, selection, response_schema,
                planning_catalog_summary)
            await self._review.execute(request, draft, [repair_writer], review_catalog, articles, web_evidence, **review_scope)
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

    async def _repair_draft(self, request, plan, draft, review, catalog, articles, web,
                            knowledge, sources, prefix_blocks, selection, evidence_schema, planning_catalog_summary, *, preview=False):
        evidence_mode = plan.response_mode in ("equipment", "technical")
        projected_mode = plan.response_mode in ("documents", "catalog_overview")
        web_map = {f"web:{index}": source for index, source in enumerate(web)}

        def validate_repair(reply):
            if plan.response_mode == "clarification":
                replacement = plan.model_copy(update={"message": reply.answer, "questions": reply.questions})
                self._validate_plan(replacement, sources | {"current", "context"}, request, knowledge, catalog_snapshot(catalog))
            elif reply.questions:
                raise PydanticCustomError("repair_response_mode_changed", "Recovery cannot introduce a different response mode")
            if evidence_mode:
                evidence_schema.model_validate(reply.model_dump(exclude={"questions"}))
            elif reply.selection is not None or reply.search_ids or reply.request_fit != "not_assessed":
                raise PydanticCustomError("repair_unsolicited_evidence", "Recovery cannot invent a new evidence operation")
            if projected_mode and reply.answer != draft.response:
                raise PydanticCustomError("repair_authoritative_projection_changed", "Approved document and inventory projections remain authoritative")

        question_type = PlannedQuestion
        if plan.questions:
            # ส่งรหัสข้อมูลที่ยังขาดใน schema เพื่อไม่ให้ขั้นแก้ข้อความเปลี่ยนรหัสที่ใช้ต่อบทสนทนา
            question_type = create_model("PendingRepairQuestion", __base__=PlannedQuestion,
                dimension=(Literal[tuple(plan.understanding.missing_slots)], ...))
        fields = {"questions": (list[question_type] if plan.questions else list[None], Field(min_length=1 if plan.questions else 0,
                    max_length=self._policy.max_questions if plan.questions else 0))}
        if evidence_mode:
            fields.update({key:(evidence_schema.model_fields[key].annotation,evidence_schema.model_fields[key])
                           for key in ('selection','request_fit','search_ids')})
        if not evidence_mode:
            fields.update(selection=(type(None), ...), request_fit=(Literal["not_assessed"], ...),
                          search_ids=(list[str], Field(max_length=0)))
            fields['answer'] = (str, Field(alias='text',min_length=1, description=ClarificationStage.model_fields['message'].description
                if plan.response_mode == 'clarification' else 'The complete corrected assistant reply in natural ungendered Thai.',
                json_schema_extra={'x-provider-description': True}))
        if projected_mode:
            fields["answer"] = (Literal[draft.response], Field(alias='text'))
        schema = validated_schema(create_model("BoundedReplyRepair", __base__=ReplyRepair, **fields), validate_repair)
        request_data = request_evidence(request,self._limits)
        # คงข้อความที่มองเห็นทุกฟิลด์ ส่วน metadata ใช้ understanding เดิมที่ส่งแยกไว้
        projected, references = compact_review_draft(draft.model_dump(mode="json",include=VISIBLE_TEXT_SURFACES))
        payload = {"request": request_data, "response_mode": plan.response_mode,
            "understanding": plan.understanding.model_dump(mode="json"),
            "rejected_draft": projected, "draft_references": references,
            "issues": review["issues"],
            "failed_checks": [assessment['check'] for assessment in review.get('assessments',[]) if not assessment['passed']],
            "approved_articles": articles, "search_evidence": [dict(id=key, **source.model_dump(mode="json"))
                for key, source in web_map.items()],
            "limits": {"questions": self._policy.max_questions, "choices": self._policy.max_options,
                "choice_policy": self._policy.choice_policy.model_dump() if self._policy.choice_policy else None,
                "title_characters": self._policy.title_max_characters, "choice_characters": self._policy.option_max_characters},
            "catalog_presentation": self._interpretation['catalog_presentation']}
        # แบบสอบถามใช้สรุปเดิม ส่วนคำตอบสินค้าใช้ scalar facts ทั้งคลังและรายละเอียดที่อ้าง
        repair_evidence = ({'catalog_summary': planning_catalog_summary}
            if plan.response_mode in ('clarification', 'conversation', 'information', 'documents')
            else {'catalog': catalog_evidence(catalog,draft)})
        payload = compact_planning_input({**payload, **repair_evidence})
        prompt = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
        if preview:
            return GenerationRequest(prompt, schema, self._interpretation['repair_instruction'], self._policy.temperature)
        with generation_stage("repair", downstream=("review",)) as writer:
            repaired = await self._llm.generate_structured(prompt=prompt,
                schema=schema, system_instruction=self._interpretation["repair_instruction"], temperature=self._policy.temperature)
            repaired = schema.model_validate(repaired.model_dump())
        if writer.provenance is None:
            raise GuidanceGenerationError("review_provenance_unavailable")
        batch = uuid4().hex
        questions = self._question_steps(repaired.questions, batch)
        response = repaired.answer
        references = [reference for reference in draft.references if reference.kind == 'app_knowledge']
        replies = repaired.suggested_replies
        search_sources = []
        if evidence_mode:
            selection = self._query.selection_from_snapshot(repaired.selection, plan.understanding, catalog) if repaired.selection else None
            prose_ids = set()
            response = render_catalog_text(repaired.answer, catalog, prose_ids, self._interpretation['catalog_presentation'])
            replies = [render_catalog_text(reply, catalog, prose_ids, self._interpretation['catalog_presentation']) for reply in replies]
            if selection and selection.mode == "categories":
                response += "\n\n" + " / ".join(selection.available_categories)
            prose_ids.update(item.id for item in (selection.items if selection else []))
            references.extend(EvidenceReference(id=item.id, kind="catalog", title=item.name, reference=item.id)
                for item in catalog if item.id in prose_ids)
            selected_web = [web_map[key] for key in repaired.search_ids]
            search_sources = [SearchSourceDTO.from_entity(source) for source in selected_web]
            references.extend(EvidenceReference(id=key, kind="web", title=web_map[key].title,
                reference=web_map[key].url or web_map[key].link) for key in repaired.search_ids)
        elif projected_mode:
            references = draft.references
        if not projected_mode:
            response = "\n\n".join([*prefix_blocks, response])
        items = selection.items if selection else []
        context = SessionContext.from_decision(draft.context.session_id, plan.understanding, questions, [item.id for item in items])
        clarification = ClarificationDTO(question=repaired.answer, missing_dimension=questions[0].dimension,
            options=questions[0].choices, questions=questions) if questions else None
        result = draft.model_copy(update={"response": response, "questions": questions, "clarification": clarification,
            "items": [ItemDTO.from_entity(item, self._interpretation['catalog_presentation']) for item in items],
            "suggested_replies": replies, "search_sources": search_sources, "references": references, "context": context})
        return result, selection, writer.provenance

    async def _generate_evidence(self, decision, response_schema, allowed_purposes, fresh_items,
                               evidence_catalog, candidate_ids, category_items, candidates, price_filter_applied, web_map, established_unit):
        return await self._llm.generate_structured(prompt=json.dumps(compact_planning_input({
                "selection_required": decision.catalog_operation != "none",
                "allowed_selection_purposes": allowed_purposes,
                "allowed_search_ids": list(web_map),
                "price_contract": {"ceiling": decision.budget_max if decision.catalog_operation == 'selection' else None,
                                   "established_period": decision.budget_unit if decision.catalog_operation == 'selection' else None,
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
            }), ensure_ascii=False, separators=(",", ":")), schema=response_schema, system_instruction=self._interpretation["evidence_instruction"],
                temperature=self._policy.temperature)
