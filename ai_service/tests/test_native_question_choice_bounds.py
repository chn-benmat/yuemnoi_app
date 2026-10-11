import json
from pathlib import Path
import pytest
from pydantic import ValidationError

from app.domain.entities.turn_plan import NativeTurnPlan
from native_turn_fixture import native_questions


def test_native_contract_rejects_six_displayed_options_before_ui_validation():
    value = json.loads((Path(__file__).parent / 'fixtures/planning_five_choices.json').read_text(encoding='utf-8'))
    native_questions(value['stage']['questions'])
    question = value['stage']['questions'][0]
    question['choices'].append({**question['choices'][0], 'id': 'sixth-choice'})
    with pytest.raises(ValidationError):
        NativeTurnPlan.model_validate(value)


def test_native_contract_accepts_four_options_including_unrestricted():
    value = json.loads((Path(__file__).parent / 'fixtures/planning_five_choices.json').read_text(encoding='utf-8'))
    for question in value['stage']['questions']:
        question['choices'] = question['choices'][:3]
    native_questions(value['stage']['questions'])
    plan = NativeTurnPlan.model_validate(value)
    assert len(plan.stage.questions) == 3


def test_native_contract_preserves_four_regular_options():
    value = json.loads((Path(__file__).parent / 'fixtures/planning_five_choices.json').read_text(encoding='utf-8'))
    for question in value['stage']['questions']:
        question['unrestricted_choice'] = None
    native_questions(value['stage']['questions'])
    plan = NativeTurnPlan.model_validate(value)
    assert len(plan.stage.questions[0].choices) == 4


def test_native_choices_roundtrip_without_reading_labels_or_changing_ids():
    value = json.loads((Path(__file__).parent / 'fixtures/planning_five_choices.json').read_text(encoding='utf-8'))
    for question in value['stage']['questions']:
        question['choices'] = question['choices'][:3]
    expected = json.loads(json.dumps(value['stage']['questions']))
    native_questions(value['stage']['questions'])
    plan = NativeTurnPlan.model_validate(value).to_plan()
    for actual, original in zip(plan.questions, expected):
        assert actual.choices == [type(actual.choices[0]).model_validate(choice) for choice in original['choices']]
        assert actual.unrestricted_choice.model_dump() == original['unrestricted_choice']
