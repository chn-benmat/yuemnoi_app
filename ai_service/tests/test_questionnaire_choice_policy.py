"""ตรวจจำนวนช้อยงบประมาณผ่านสัญญาที่โมเดลใช้จริง"""
from dataclasses import replace
from types import SimpleNamespace

import pytest

from app.domain.entities.turn_plan import NativePlannedQuestion, PlannedQuestion, QuestionBranch
from app.core.container import Container
from app.application.dtos.chat_dto import ChatRequestDTO
from test_fast_turn import make_fast, turn
from test_request_understanding import understanding


def budget_wire():
    choices = [
        {'id': identifier, 'label': label, 'value': label,
         'value_kind': 'specified', 'supporting_item_ids': []}
        for identifier, label in (
            ('daily_lower', 'สูงสุด 500 บาทต่อวัน'),
            ('daily_upper', 'สูงสุด 1,000 บาทต่อวัน'),
            ('hourly_lower', 'สูงสุด 200 บาทต่อชั่วโมง'),
            ('hourly_upper', 'สูงสุด 400 บาทต่อชั่วโมง'))
    ]
    choices.append({'id': 'unlimited', 'label': 'ไม่จำกัดงบประมาณ',
                    'value': 'ไม่จำกัดงบประมาณ', 'value_kind': 'unrestricted',
                    'supporting_item_ids': []})
    return {'id': 'budget', 'ask': 'มีงบประมาณสูงสุดต่อวันหรือต่อชั่วโมงเท่าไร?',
            'slot': {'kind': 'spending_ceiling'}, 'choices': choices, 'branches': []}


def test_native_budget_accepts_two_daily_two_hourly_and_unlimited():
    question = NativePlannedQuestion.model_validate(budget_wire()).to_question()
    assert len(question.choices) == 4
    assert question.unrestricted_choice.id == 'unlimited'


def production_case():
    case, *_ = make_fast(turn())
    case._policy = Container().guidance_policy
    return case


def regular_question(count):
    return PlannedQuestion(id='workload', dimension='workload', title='ใช้งานลักษณะใด?', choices=[
        {'id': str(i), 'label': label, 'value': label, 'supporting_item_ids': []}
        for i, label in enumerate(['งานเอกสารและประชุม', 'งานออกแบบ', 'เล่นเกม', 'เขียนโปรแกรม', 'ตัดต่อวิดีโอ'][:count])])


@pytest.mark.parametrize('count', [3, 4])
def test_ordinary_question_accepts_three_or_four_meaningful_choices(count):
    production_case()._validate_question_version(regular_question(count), set())


@pytest.mark.parametrize('count', [1, 2, 5])
def test_ordinary_question_rejects_too_few_or_too_many_choices(count):
    with pytest.raises(ValueError):
        production_case()._validate_question_version(regular_question(count), set())


def test_budget_requires_all_five_choices_and_keeps_period_in_submitted_answer():
    case = production_case()
    budget = NativePlannedQuestion.model_validate(budget_wire()).to_question()
    case._validate_question_version(budget, set(), preserve_label=True)
    projected = case._question_steps([budget], 'session')[0]
    assert [choice.action_value for choice in projected.choices] == [choice.label for choice in projected.choices]
    budget.choices.pop()
    with pytest.raises(ValueError, match='questionnaire policy'):
        case._validate_question_version(budget, set(), preserve_label=True)


def test_conditional_question_can_cover_each_of_the_five_budget_answers():
    case = production_case()
    budget = NativePlannedQuestion.model_validate(budget_wire()).to_question()
    workload = regular_question(3)
    workload.branches = [QuestionBranch(source_question_id=budget.id, source_option_id=choice.id,
        title=workload.title, choices=workload.choices) for choice in case._all_choices(budget)]
    # ตรวจ schema จริงด้วย ป้องกันจำนวน branch ถูกตัดเหลือสี่ทั้งที่งบมีห้าช้อย
    workload = PlannedQuestion.model_validate(workload.model_dump())
    decision = understanding(catalog_operation='none', missing_slots=['budget_max', 'workload'],
        next_action='clarify', information_sufficient=False)
    plan = turn(understanding=decision, knowledge_ids=[], questions=[budget, workload],
                message='ช่วยระบุความต้องการเพิ่มเติม', response_mode='clarification')
    case._validate_plan(plan, set(), ChatRequestDTO(message='อยากเช่าคอม'),
                        SimpleNamespace(topics=[], articles=[]), {'items': [], 'categories': []})
    projected = case._question_steps(plan.questions, 'session')
    assert len(projected[1].branch_choices) == 5
    assert all(len(choices) == 3 for choices in projected[1].branch_choices.values())


def test_choice_policy_cannot_exceed_the_configured_display_cap():
    policy = Container().guidance_policy
    with pytest.raises(ValueError, match='configured display limit'):
        replace(policy, max_options=4)
