"""Bounded recovery exercises real planning, review, projection and SSE code."""
import json
from pathlib import Path
from unittest.mock import AsyncMock

import pytest

from app.application.dtos.chat_dto import ChatRequestDTO
from app.application.services.conversation_context import ContextLimits
from app.application.services.response_review import visible_text_fields
from app.application.use_cases.plan_chat_turn_use_case import PlanChatTurnUseCase
from app.application.use_cases.process_chat_message_use_case import ProcessChatMessageUseCase
from app.application.use_cases.query_items_use_case import QueryItemsUseCase
from app.core.exceptions import AllLLMProvidersExhaustedException
from app.domain.entities.catalog_guidance import GuidancePolicy
from app.domain.entities.intent_decision import RequestUnderstanding
from app.domain.entities.turn_plan import TurnPlan, PlannedQuestion
from app.domain.exceptions import GuidanceGenerationError
from app.domain.interfaces.generation_stage import CURRENT_GENERATION, Provenance
from app.infrastructure.knowledge.file_knowledge_repository import FileKnowledgeRepository
from app.infrastructure.runtime.documents import ValidatedFile
from app.infrastructure.runtime.schema import InterpretationPolicy

ROOT = Path(__file__).resolve().parents[1]
QUERY = 'ช่วยหาอุปกรณ์สำหรับถ่ายคอนเทนต์ให้หน่อย'


def decision(**changes):
    values = dict(intent='inventory_search', ambiguity_level=.5, confidence=.8,
        target_items=[], categories=[], budget_max=None, budget_unit=None, intended_use=None,
        missing_slots=['budget'], needs_external_search=False, search_query=None,
        user_goal='Find equipment for content creation', catalog_operation='selection',
        additional_goals=[], request_scope='broad', information_sufficient=False,
        next_action='clarify', known_facts=[], user_constraints=[], excluded_items=[],
        topic_changed=False, clarification_declined=False,
        reference_resolution='Current request', decision_reason='Budget remains unknown')
    return RequestUnderstanding(**(values | changes))


def questions(label='ไม่เกิน 500 บาทต่อวัน'):
    return [PlannedQuestion(id='budget', dimension='budget', title='งบประมาณสูงสุดต่อวัน',
        choices=[dict(id='cap', label=label, value=label, supporting_item_ids=[])])]


def reviewed(payload, reject):
    from app.application.services.review_input import restore_planning_input, restore_review_draft
    payload = restore_planning_input(payload)
    draft = restore_review_draft(payload['draft'], payload['draft_references'])
    names = ('relevance', 'completeness', 'neutral_voice', 'choice_equivalence', 'grounding', 'context', 'followups')
    return dict(assessments={name:dict(reason='Simulated assessment for bounded recovery test',
        field_paths=['/response'], passed=not (reject and name == 'relevance')) for name in names},
        issues=[dict(kind='semantic', field_path='/response', quoted_text=draft['response'],
            reason='Fixture rejection of the exact response')] if reject else [],
        reviewed_surface_groups=sorted({path.split('/')[1] for path in visible_text_fields(draft)}))


def stack(*, second_rejection=False, repair_error=None):
    llm, repo, search = AsyncMock(), AsyncMock(), AsyncMock()
    repo.get_all_items.return_value = []
    knowledge = FileKnowledgeRepository(ROOT / 'knowledge/app_knowledge.json')
    policy = GuidancePolicy(3, 4, 80, 80, 3, 2, .1)
    interpretation = ValidatedFile(ROOT / 'knowledge/interpretation_policy.json', InterpretationPolicy).read()[0].model_dump(
        mode='json', exclude={'approval', 'status', 'production_enabled', 'schema_version', 'version'})
    use_case = PlanChatTurnUseCase(llm, repo, knowledge, QueryItemsUseCase(repo, llm, policy), search,
        ContextLimits(16, 24000), policy, interpretation)
    stages, drafts = [], []
    async def generate(**kwargs):
        stage = CURRENT_GENERATION.get()
        stages.append(stage.name)
        stage.provenance = Provenance('fixture', 'reviewer' if stage.name == 'review' else 'writer')
        if stage.name == 'planning':
            return TurnPlan(understanding=decision(), knowledge_ids=[], unverified_topic_ids=[],
                questions=questions('เกิน 2,000 บาทต่อวัน'), message=QUERY, response_mode='clarification')
        if stage.name == 'repair':
            if repair_error:
                raise repair_error
            return kwargs['schema'].model_validate(dict(speaker_register='informal_ungendered',
                answer='เลือกงบประมาณสูงสุดเพื่อช่วยหาอุปกรณ์ที่เหมาะกับงาน', questions=[q.model_dump() for q in questions()],
                request_fit='not_assessed', selection=None, search_ids=[], suggested_replies=[]))
        payload = json.loads(kwargs['prompt'])
        drafts.append(payload)
        return kwargs['schema'].model_validate(reviewed(payload, len(drafts) == 1 or second_rejection))
    llm.generate_structured.side_effect = generate
    return use_case, llm, stages, drafts


@pytest.mark.asyncio
async def test_rejected_questionnaire_is_repaired_once_and_fully_reviewed():
    use_case, llm, stages, drafts = stack()
    result = await use_case.execute(ChatRequestDTO(message=QUERY, session_id='same-session'))
    assert stages == ['planning', 'review', 'repair', 'review']
    assert result.response != QUERY
    assert result.questions[0].choices[0].label == 'ไม่เกิน 500 บาทต่อวัน'
    assert result.context.session_id == 'same-session'
    assert result.context.questions == result.questions
    assert result.clarification.questions == result.questions
    assert llm.generate_structured.await_count == 4
    from app.application.services.review_input import restore_planning_input
    repair_input = restore_planning_input(json.loads(llm.generate_structured.call_args_list[2].kwargs['prompt']))
    assert repair_input['catalog_summary']['item_count'] == 0
    assert 'catalog' not in repair_input
    from app.application.services.review_input import restore_review_draft
    original_review = restore_planning_input(drafts[0])
    original_draft = restore_review_draft(original_review['draft'], original_review['draft_references'])
    rejected_draft = restore_review_draft(repair_input['rejected_draft'], repair_input['draft_references'])
    assert visible_text_fields(rejected_draft) == visible_text_fields(original_draft)


@pytest.mark.asyncio
async def test_sse_publishes_only_the_repaired_approved_response():
    use_case, _, stages, _ = stack()
    stream = ProcessChatMessageUseCase(None, None, None, None, None, None, None, None,
        .1, 64, fast_path=use_case)
    events = [event async for event in stream.execute_stream(ChatRequestDTO(message=QUERY))]
    ready = next(event for event in events if event.startswith('event: ready'))
    assert json.loads(ready.split('data: ', 1)[1])['response'] != QUERY
    assert stages == ['planning', 'review', 'repair', 'review']
    assert sum(event.startswith('event: ready') for event in events) == 1
    statuses = [json.loads(event.split('data: ', 1)[1]) for event in events if event.startswith('event: status')]
    assert [status['step'] for status in statuses] == ['preparing', *stages]
    assert statuses[3]['message'] == 'กำลังสรุปคำคำตอบ'


@pytest.mark.asyncio
async def test_second_rejection_is_final_and_no_draft_is_streamed():
    use_case, _, stages, _ = stack(second_rejection=True)
    stream = ProcessChatMessageUseCase(None, None, None, None, None, None, None, None,
        .1, 64, fast_path=use_case)
    events = []
    with pytest.raises(GuidanceGenerationError, match='response_quality_rejected'):
        async for event in stream.execute_stream(ChatRequestDTO(message=QUERY)):
            events.append(event)
    assert stages == ['planning', 'review', 'repair', 'review']
    assert not any(event.startswith(('event: ready', 'event: metadata', 'event: delta', 'event: done')) for event in events)


@pytest.mark.asyncio
async def test_repair_quota_denial_preserves_the_real_error_and_wait():
    use_case, _, stages, _ = stack(repair_error=AllLLMProvidersExhaustedException(
        code='quota_temporarily_unavailable', retry_after=35))
    with pytest.raises(AllLLMProvidersExhaustedException) as failure:
        await use_case.execute(ChatRequestDTO(message=QUERY))
    assert failure.value.code == 'quota_temporarily_unavailable'
    assert failure.value.retry_after == 35
    assert stages == ['planning', 'review', 'repair']


@pytest.mark.asyncio
async def test_equipment_repair_reuses_eligibility_and_projects_only_final_selection():
    from app.domain.entities.item import Item
    use_case, llm, stages, drafts = stack()
    use_case._items.get_all_items.return_value = [
        Item(id='camera', name='Source camera', category='camera', price=400, type='วัน'),
        Item(id='expensive', name='Over budget', category='camera', price=900, type='วัน')]
    understanding = decision(categories=['camera'], budget_max=500, budget_unit='วัน',
        information_sufficient=True, missing_slots=[], next_action='answer', intended_use='ถ่ายภาพนิ่ง')
    selection = dict(mode='items', purpose='recommendation', selected_items=[
        dict(id='camera', reason='Source supports photographs', evidence_fields=['description'])],
        price_requirement=dict(maximum=500, user_unit='วัน', catalog_units=['วัน'], interpretation='Daily ceiling'),
        reasoning='Within the preserved daily budget')
    async def generate(**kwargs):
        stage = CURRENT_GENERATION.get()
        stages.append(stage.name)
        stage.provenance = Provenance('fixture', 'reviewer' if stage.name == 'review' else 'writer')
        if stage.name == 'planning':
            return TurnPlan(understanding=understanding, response_mode='equipment', message='', questions=[],
                knowledge_ids=[], unverified_topic_ids=[])
        if stage.name in ('evidence', 'repair'):
            answer = dict(speaker_register='informal_ungendered', request_fit='meets_request', selection=selection,
                answer='{{item:camera:name}} ราคา {{item:camera:price_display}}' + (' เหมาะกับภาพนิ่ง' if stage.name == 'repair' else ''),
                search_ids=[], suggested_replies=[])
            if stage.name == 'repair':
                from pydantic import ValidationError
                with pytest.raises(ValidationError):
                    kwargs['schema'].model_validate(answer | {'questions': [], 'selection': selection | {
                        'selected_items':[dict(id='expensive', reason='Invalid replacement', evidence_fields=['price'])]}})
                answer['questions'] = []
            return kwargs['schema'].model_validate(answer)
        payload = json.loads(kwargs['prompt'])
        drafts.append(payload)
        return kwargs['schema'].model_validate(reviewed(payload, len(drafts) == 1))
    llm.generate_structured.side_effect = generate
    result = await use_case.execute(ChatRequestDTO(message='ถ่ายภาพนิ่ง งบไม่เกิน 500 บาทต่อวัน',session_id='equipment'))
    assert stages == ['planning', 'evidence', 'review', 'repair', 'review']
    assert [item.id for item in result.items] == result.context.referenced_item_ids == ['camera']
    assert result.context.budget_max == 500
    assert 'Source camera' in result.response and '400 บาทต่อวัน' in result.response
    assert 'เหมาะกับภาพนิ่ง' in result.response and '{{item:' not in result.response
    assert 'expensive' not in [ref.id for ref in result.references]


@pytest.mark.asyncio
async def test_nonquality_failure_does_not_enter_recovery():
    use_case, llm, stages, _ = stack()
    use_case._review.execute = AsyncMock(side_effect=GuidanceGenerationError('review_model_not_independent'))
    with pytest.raises(GuidanceGenerationError,match='review_model_not_independent'):
        await use_case.execute(ChatRequestDTO(message=QUERY))
    assert stages == ['planning'] and llm.generate_structured.await_count == 1


@pytest.mark.asyncio
async def test_questionnaire_repair_exposes_only_existing_pending_dimensions_to_provider():
    from app.infrastructure.llm.provider_client import native_schema
    use_case, llm, stages, _ = stack()
    original = llm.generate_structured.side_effect

    async def inspect_repair(**kwargs):
        if CURRENT_GENERATION.get().name == 'repair':
            document = native_schema(kwargs['schema'])
            questions_schema = document['properties']['questions']
            reference = questions_schema['items']['$ref'].removeprefix('#/$defs/')
            dimension = document['$defs'][reference]['properties']['dimension']
            assert dimension.get('enum') == ['budget']
            # รหัสที่ใช้ต่อบทสนทนาต้องไม่กลายเป็นชื่อใหม่เมื่อแก้ข้อความ
            from pydantic import ValidationError
            invalid = dict(speaker_register='informal_ungendered', answer='repaired invitation',
                questions=[questions()[0].model_dump() | {'dimension': 'budget_option'}],
                request_fit='not_assessed', selection=None, search_ids=[], suggested_replies=[])
            with pytest.raises(ValidationError) as failure:
                kwargs['schema'].model_validate(invalid)
            assert any(entry['type'] == 'literal_error' for entry in failure.value.errors())
        return await original(**kwargs)

    llm.generate_structured.side_effect = inspect_repair
    result = await use_case.execute(ChatRequestDTO(message=QUERY))
    assert stages == ['planning', 'review', 'repair', 'review']
    assert [question.dimension for question in result.questions] == ['budget']


@pytest.mark.asyncio
async def test_repair_is_cancelled_by_total_turn_deadline_before_sse_ready():
    import asyncio
    from app.infrastructure.runtime.execution import RuntimeExecutionGuard
    guard = RuntimeExecutionGuard(ROOT/'config/ai_runtime.json',ROOT/'knowledge/interpretation_policy.json')
    guard.runtime = guard.runtime.model_copy(update={'technical_hard_deadline_seconds':.05,
        'general':guard.runtime.general.model_copy(update={'hard_deadline_seconds':.05})})
    use_case, llm, stages, _ = stack()
    original = llm.generate_structured.side_effect
    cancelled = asyncio.Event()
    async def slow_repair(**kwargs):
        if CURRENT_GENERATION.get().name == 'repair':
            try:
                await asyncio.sleep(5)
            finally:
                cancelled.set()
        return await original(**kwargs)
    llm.generate_structured.side_effect = slow_repair
    stream = ProcessChatMessageUseCase(None,None,None,None,None,None,None,None,.01,64,
        execution_guard=guard,fast_path=use_case)
    events=[]
    with pytest.raises(AllLLMProvidersExhaustedException) as error:
        async for event in stream.execute_stream(ChatRequestDTO(message=QUERY)):
            events.append(event)
    assert error.value.code=='deadline_exceeded' and cancelled.is_set()
    assert not any(event.startswith(('event: ready','event: delta','event: done')) for event in events)
