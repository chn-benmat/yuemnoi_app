"""Canonical slot projection; these protocol tests do not certify LLM semantics."""
from types import SimpleNamespace

import pytest
from pydantic import ValidationError

from app.application.dtos.chat_dto import ChatRequestDTO
from app.domain.entities.turn_plan import NativePlannedQuestion, TurnPlan
from test_response_repair import stack, decision


def choice(identifier='cap', kind='specified'):
    return dict(id=identifier, label='native choice text', value='native choice value',
                supporting_item_ids=[], choice_kind=kind)


def question(**changes):
    return dict(id='q1', title='native question', choices=[choice()], branches=[], **changes)


def test_free_dimension_cannot_bypass_the_native_budget_slot_contract():
    # Live planning emitted budget rather than the budget_max protocol field.
    with pytest.raises(ValidationError):
        NativePlannedQuestion.model_validate(question(dimension='budget'))


def test_spending_role_projects_canonical_dimension_without_reading_choice_text():
    native = NativePlannedQuestion.model_validate(question(slot={'kind': 'spending_ceiling'}))
    projected = native.to_question()
    assert native.dimension == projected.dimension == 'budget_max'
    assert projected.id == 'q1'
    assert projected.choices[0].label == 'native choice text'
    assert projected.choices[0].value == 'native choice value'


def test_other_requirement_preserves_its_stable_identifier():
    native = NativePlannedQuestion.model_validate(question(slot={
        'kind': 'other_requirement', 'dimension': 'workload-detail'}))
    assert native.to_question().dimension == 'workload-detail'


def test_other_requirement_cannot_claim_the_canonical_spending_dimension():
    with pytest.raises(ValidationError):
        NativePlannedQuestion.model_validate(question(slot={
            'kind': 'other_requirement', 'dimension': 'budget_max'}))


def validate_budget(native):
    case, _, _, _ = stack()
    plan = TurnPlan(understanding=decision(missing_slots=['budget_max']),
                    knowledge_ids=[], unverified_topic_ids=[], response_mode='clarification',
                    message='native invitation', questions=[native.to_question()])
    case._validate_plan(plan, set(), ChatRequestDTO(message='request'),
                        SimpleNamespace(topics=[], articles=[]), {'items': [], 'categories': []})


def test_spending_role_cannot_skip_the_existing_no_ceiling_guard():
    native = NativePlannedQuestion.model_validate(question(slot={'kind': 'spending_ceiling'}))
    with pytest.raises(ValueError, match='no-ceiling'):
        validate_budget(native)


def test_spending_role_with_explicit_unrestricted_choice_passes_the_guard():
    value = question(slot={'kind': 'spending_ceiling'})
    value['choices'].append(choice('unlimited', 'unrestricted'))
    value['choices'][-1]['label'] = 'unrestricted choice text'
    value['choices'][-1]['value'] = 'unrestricted choice value'
    native = NativePlannedQuestion.model_validate(value)
    validate_budget(native)
    assert native.to_question().unrestricted_choice.id == 'unlimited'
