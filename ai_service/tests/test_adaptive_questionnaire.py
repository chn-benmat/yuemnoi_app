"""Question dependencies and native operation constraints, without live providers."""
from types import SimpleNamespace

import pytest
from pydantic import ValidationError

from app.application.dtos.chat_dto import ChatRequestDTO
from app.application.services.conversation_context import ContextLimits
from app.application.services.recovery_evidence import request_evidence
from app.application.use_cases.plan_chat_turn_use_case import PlanChatTurnUseCase
from app.domain.entities.chat_result import SessionContext, QuestionnaireAnswer
from app.domain.entities.turn_plan import ConversationStage, EvidenceStage, NativeTurnPlan, PlannedQuestion
from app.infrastructure.llm.provider_client import native_schema


def choices(identifier, label):
    return dict(id=identifier, label=label, value=label, supporting_item_ids=[])


def planned():
    return [
        PlannedQuestion(id='kind', dimension='category', title='เลือกประเภท', choices=[
            choices('music', 'ดนตรี'), choices('tools', 'เครื่องมือ')]),
        PlannedQuestion(id='budget', dimension='budget_max', title='งบค่าเช่า',
            choices=[choices('day', 'ไม่เกิน 350 บาทต่อวัน'), choices('hour', 'ไม่เกิน 250 บาทต่อชั่วโมง')],
            unrestricted_choice=choices('unlimited', 'ไม่จำกัดงบ'), branches=[
                dict(source_question_id='kind', source_option_id='music', title='งบค่าเช่าต่อวัน',
                     choices=[choices('cap', 'ไม่เกิน 350 บาทต่อวัน')], unrestricted_choice=choices('none', 'ไม่จำกัดงบ')),
                dict(source_question_id='kind', source_option_id='tools', title='งบค่าเช่าต่อชั่วโมง',
                     choices=[choices('cap', 'ไม่เกิน 250 บาทต่อชั่วโมง')], unrestricted_choice=choices('none', 'ไม่จำกัดงบ'))]),
    ]


def test_native_stage_cannot_bypass_a_requested_catalog_operation():
    schema = native_schema(NativeTurnPlan)
    analysis = schema['$defs']['NativePlanningUnderstanding']['properties']
    assert 'catalog_operation' not in analysis
    assert not {'next_action', 'information_sufficient', 'missing_slots'} & analysis.keys()
    with pytest.raises(ValidationError):
        ConversationStage(response_mode='information', catalog_operation={'kind': 'selection'}, message='draft', questions=[])
    with pytest.raises(ValidationError):
        EvidenceStage(response_mode='equipment', catalog_operation={'kind': 'none'}, message='', questions=[])
    assert EvidenceStage(response_mode='equipment', catalog_operation={'kind': 'selection'}, message='', questions=[]).catalog_operation.kind == 'selection'
    for branch in schema['properties']['stage']['anyOf']:
        stage = schema['$defs'][branch['$ref'].split('/')[-1]]
        assert 'enum' in stage['properties']['response_mode']
        assert 'enum' not in stage['properties']['catalog_operation']


def test_native_question_stage_is_the_single_material_readiness_decision():
    from test_response_repair import decision
    from app.domain.entities.intent_decision import NativePlanningUnderstanding
    understanding = decision().model_dump(exclude={
        'catalog_operation', 'next_action', 'information_sufficient', 'missing_slots'})
    understanding['budget_period'] = None
    understanding.pop('budget_unit')
    native = dict(speaker_register='informal_ungendered', analysis=understanding,
        overview_available_only=False, knowledge_ids=[], unverified_topic_ids=[])
    pending = NativeTurnPlan.model_validate({**native, 'stage': {
        'response_mode': 'clarification', 'catalog_operation': {'kind': 'selection'},
        'text': 'เลือกข้อมูลเพิ่มเติม', 'questions': [planned()[0].model_dump()]}}).to_plan()
    assert pending.understanding.next_action == 'clarify'
    assert pending.understanding.information_sufficient is False
    assert pending.understanding.missing_slots == ['category']
    ready = NativeTurnPlan.model_validate({**native, 'stage': {
        'response_mode': 'equipment', 'catalog_operation': {'kind': 'selection'},
        'text': '', 'questions': []}}).to_plan()
    assert ready.understanding.next_action == 'answer'
    assert ready.understanding.information_sufficient is True
    assert ready.understanding.missing_slots == []
    with pytest.raises(ValidationError):
        NativePlanningUnderstanding.model_validate({**understanding, 'next_action': 'clarify'})


def test_branch_options_keep_scoped_choice_ids_and_completed_evidence_only_actual_answers():
    questions = PlanChatTurnUseCase._question_steps(planned(), 'batch')
    assert questions[1].branch_question_id == questions[0].id
    selected = questions[1].branch_choices['tools'][0]
    assert selected.id == 'tools:cap'
    assert selected.action_value == 'ไม่เกิน 250 บาทต่อชั่วโมง'
    assert questions[1].branch_choices['tools'][-1].action_value == 'ไม่จำกัดงบ'
    request = ChatRequestDTO(message='เครื่องมือ, ไม่เกิน 250 บาทต่อชั่วโมง', session_id='s',
        context=SessionContext(session_id='s', user_goal='เลือกอุปกรณ์', questions=questions), questionnaire_answers=[
            QuestionnaireAnswer(question_id='batch:kind', option_id='tools'),
            QuestionnaireAnswer(question_id='batch:budget', option_id=selected.id)])
    evidence = request_evidence(request, ContextLimits(16, 24000))
    question = evidence['context']['questions'][1]
    assert question['title'] == 'งบค่าเช่าต่อชั่วโมง'
    assert question['choices'] == [selected.model_dump(mode='json', exclude_defaults=True)]
    assert not any(key.startswith('branch_') for key in question)
    assert request.context.questions[1].branch_choices['music']


def test_budget_submission_preserves_the_visible_period_even_with_numeric_generation_value():
    question = planned()[1].model_copy(update={'branches': []})
    question.choices[0].value = '350'
    steps = PlanChatTurnUseCase._question_steps([question], 'batch')
    assert steps[0].choices[0].action_value == 'ไม่เกิน 350 บาทต่อวัน'
    assert steps[0].choices[-1].action_value == 'ไม่จำกัดงบ'


def test_previous_answer_change_cannot_submit_a_stale_budget_choice():
    questions = PlanChatTurnUseCase._question_steps(planned(), 'batch')
    with pytest.raises(ValidationError, match='selected question branch'):
        ChatRequestDTO(message='changed to tools', session_id='s',
            context=SessionContext(session_id='s', user_goal='เลือกอุปกรณ์', questions=questions), questionnaire_answers=[
                QuestionnaireAnswer(question_id='batch:kind', option_id='tools'),
                QuestionnaireAnswer(question_id='batch:budget', option_id='music:cap')])


def test_budget_versions_require_a_separate_unrestricted_choice_and_keep_distinct_periods():
    from test_response_repair import stack, decision
    from app.domain.entities.turn_plan import TurnPlan
    case, _, _, _ = stack()
    questions = planned()
    for choice in questions[1].choices:
        choice.value = '250'
    plan = TurnPlan(understanding=decision(missing_slots=['category', 'budget_max']),
        response_mode='clarification', questions=questions, message='เลือกข้อมูล',
        knowledge_ids=[], unverified_topic_ids=[])
    args = (set(), ChatRequestDTO(message='request'),
            SimpleNamespace(topics=[], articles=[]), {'items': [], 'categories': []})
    case._validate_plan(plan, *args)
    plan.questions[1].unrestricted_choice = None
    with pytest.raises(ValueError, match='no-ceiling'):
        case._validate_plan(plan, *args)


@pytest.mark.parametrize('changes', [dict(source_question_id='later'), dict(source_option_id='unknown')])
def test_branch_cannot_reference_unknown_or_later_answers(changes):
    from test_response_repair import stack, decision
    from app.domain.entities.turn_plan import TurnPlan
    case, _, _, _ = stack()
    questions = planned()
    questions[1] = questions[1].model_copy(update={'branches': [
        questions[1].branches[0].model_copy(update=changes), questions[1].branches[1]]})
    plan = TurnPlan(understanding=decision(missing_slots=['category', 'budget_max']),
        response_mode='clarification', questions=questions, message='เลือกข้อมูลที่ต้องการ',
        knowledge_ids=[], unverified_topic_ids=[])
    with pytest.raises(ValueError, match='earlier|exact'):
        case._validate_plan(plan, set(), ChatRequestDTO(message='request'),
                            SimpleNamespace(topics=[], articles=[]), {'items': [], 'categories': []})
