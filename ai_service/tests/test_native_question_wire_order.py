"""Alphabetically emitted native keys put question/answer text before its role."""
from app.domain.entities.turn_plan import NativePlannedQuestion, NativeQuestionChoice
from app.infrastructure.llm.provider_client import native_schema


def test_question_text_is_available_before_question_slot_and_choices():
    names = sorted(native_schema(NativePlannedQuestion)['properties'])
    assert names.index('ask') < names.index('choices') < names.index('slot')


def test_choice_meaning_is_available_before_its_constraint_kind():
    names = sorted(native_schema(NativeQuestionChoice)['properties'])
    assert names.index('label') < names.index('value') < names.index('value_kind')


def test_wire_aliases_project_without_changing_question_or_answer_text():
    wire = {'ask': 'original question', 'id': 'q1',
            'slot': {'kind': 'other_requirement', 'dimension': 'workload'},
            'choices': [{'id': 'c1', 'label': 'original label', 'value': 'original value',
                         'value_kind': 'specified', 'supporting_item_ids': []}], 'branches': []}
    native = NativePlannedQuestion.model_validate(wire, by_alias=True, by_name=False)
    assert native.model_dump(by_alias=True) == wire
    projected = native.to_question()
    assert projected.title == wire['ask']
    assert projected.choices[0].value == wire['choices'][0]['value']
