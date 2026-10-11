"""ป้องกันการเริ่มคำถามรอบใหม่หลังตอบชุดเดิมครบแล้ว"""
import json
from pathlib import Path
from types import SimpleNamespace

import pytest

from app.application.dtos.chat_dto import ChatRequestDTO
from app.domain.entities.chat_result import QuestionnaireAnswer, SessionContext
from app.application.services.conversation_context import ContextLimits
from app.application.services.recovery_evidence import request_evidence
from app.application.services.review_input import restore_planning_input
from app.domain.entities.turn_plan import NativePlannedQuestion, PlannedQuestion
from app.infrastructure.runtime.schema import InterpretationPolicy
from test_fast_turn import equipment_answer, make_fast, turn
from test_questionnaire_choice_policy import budget_wire, production_case, regular_question
from test_request_understanding import understanding


def completed_request():
    case, *_ = make_fast(turn())
    question = PlannedQuestion(id='purpose', dimension='intended_use', title='จะเอาไปใช้งานแบบไหน',
        choices=[{'id': identifier, 'label': label, 'value': label, 'supporting_item_ids': []}
                 for identifier, label in [('travel', 'ใช้งานทั่วไปหรือท่องเที่ยว'),
                                          ('video', 'ถ่ายวิดีโอ'), ('portrait', 'ถ่ายภาพบุคคล')]])
    steps = case._question_steps([question], 'batch')
    return ChatRequestDTO(
        message=steps[0].choices[0].label, session_id='session',
        context=SessionContext(session_id='session', user_goal='เลือกอุปกรณ์', questions=steps),
        questionnaire_answers=[QuestionnaireAnswer(question_id=steps[0].id,
                                                  option_id=steps[0].choices[0].id)],
    )


def next_budget_plan(**changes):
    decision = understanding(catalog_operation='selection', missing_slots=['budget_max'], **changes)
    return turn(understanding=decision, knowledge_ids=[], response_mode='clarification',
                questions=[NativePlannedQuestion.model_validate(budget_wire()).to_question()],
                message='ระบุงบประมาณเพิ่มเติม')


def test_completed_questionnaire_cannot_start_another_batch_for_the_same_goal():
    case = production_case()
    with pytest.raises(ValueError, match='completed questionnaire'):
        case._validate_plan(next_budget_plan(), set(), completed_request(),
                            SimpleNamespace(topics=[], articles=[]), {'items': [], 'categories': []})


def test_completed_answers_can_start_a_questionnaire_for_a_new_goal():
    production_case()._validate_plan(next_budget_plan(topic_changed=True), set(), completed_request(),
                                    SimpleNamespace(topics=[], articles=[]), {'items': [], 'categories': []})


def test_partial_answers_do_not_close_the_questionnaire():
    request = completed_request()
    request.context.questions += production_case()._question_steps([regular_question(3)], 'batch')
    assert not request.questionnaire_complete
    production_case()._validate_plan(next_budget_plan(), set(), request,
                                    SimpleNamespace(topics=[], articles=[]), {'items': [], 'categories': []})


@pytest.mark.parametrize('typed', [False, True])
def test_completion_uses_actual_answers_including_typed_answers(typed):
    request = completed_request()
    if typed:
        request.questionnaire_answers = [QuestionnaireAnswer(
            question_id=request.context.questions[0].id, text='ถ่ายภาพระหว่างท่องเที่ยว')]
    assert request.questionnaire_complete
    evidence = request_evidence(request, ContextLimits(16, 24000))
    assert evidence['questionnaire_complete'] is True
    assert len(evidence['context']['questions']) == 1
    if typed:
        assert evidence['context']['questions'][0]['typed_answer'] == 'ถ่ายภาพระหว่างท่องเที่ยว'


def test_active_question_without_an_answer_is_not_completion():
    request = completed_request()
    request.questionnaire_answers = []
    request.active_question_id = request.context.questions[0].id
    assert not request.questionnaire_complete
    assert not ChatRequestDTO(message='อยากเช่ากล้อง').questionnaire_complete


def test_initial_batch_cannot_defer_a_known_material_unknown():
    plan = next_budget_plan()
    plan.understanding.missing_slots.append('intended_use')
    with pytest.raises(ValueError, match='all material pending dimensions'):
        production_case()._validate_plan(plan, set(), ChatRequestDTO(message='อยากเช่ากล้อง'),
                                        SimpleNamespace(topics=[], articles=[]), {'items': [], 'categories': []})


def test_initial_batch_accepts_all_material_unknowns_together():
    plan = next_budget_plan()
    plan.questions.insert(0, regular_question(3))
    plan.understanding.missing_slots.insert(0, 'workload')
    production_case()._validate_plan(plan, set(), ChatRequestDTO(message='อยากเช่าคอม'),
                                    SimpleNamespace(topics=[], articles=[]), {'items': [], 'categories': []})


def test_single_batch_guard_follows_the_configured_policy():
    case = production_case()
    case._interpretation = {**case._interpretation, 'questionnaire_flow': {'single_batch_per_goal': False}}
    case._validate_plan(next_budget_plan(), set(), completed_request(),
                        SimpleNamespace(topics=[], articles=[]), {'items': [], 'categories': []})


@pytest.mark.asyncio
async def test_completed_questionnaire_proceeds_to_evidenced_answer():
    decision = understanding(catalog_operation='selection', information_sufficient=True,
                             next_action='answer', missing_slots=[], intended_use='ใช้งานทั่วไปหรือท่องเที่ยว')
    case, llm, *_ = make_fast(turn(understanding=decision, knowledge_ids=[], response_mode='equipment'),
                              equipment_answer())
    result = await case.execute(completed_request())
    assert result.next_action == 'answer'
    assert result.items and not result.questions and not result.context.questions
    payload = restore_planning_input(json.loads(llm.generate_structured.call_args_list[0].kwargs['prompt']))
    assert payload['questionnaire_complete'] is True
    assert payload['answered_values'][0]['value'] == 'ใช้งานทั่วไปหรือท่องเที่ยว'
    assert llm.generate_structured.await_count == 2


def test_exported_interpretation_schema_matches_single_batch_policy():
    path = Path(__file__).resolve().parents[1] / 'config/schemas/interpretation_policy.schema.json'
    assert json.loads(path.read_text(encoding='utf-8')) == InterpretationPolicy.model_json_schema()
