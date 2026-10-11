"""Expose question alternatives to the model before native decoding constrains them."""
import json
from typing import Literal

import pytest
from pydantic import BaseModel, Field

from app.core.config import settings
from app.domain.entities.turn_plan import ClarificationStage, NativePlannedQuestion, NativeQuestionChoice, NativeTurnPlan
from app.infrastructure.llm.groq_client import GroqClient
from app.infrastructure.llm.provider_client import native_schema
from test_schema_definition_compaction import expanded_schema


def section(instruction, label):
    return json.JSONDecoder().raw_decode(instruction.split(label + ': ', 1)[1])[0]


@pytest.mark.parametrize('model', settings.groq_models)
def test_planning_instruction_exposes_both_question_slot_shapes_and_meanings(model):
    payload = GroqClient(api_key='fixture').build_payload(model, 'fixture', schema=NativeTurnPlan)
    instruction = payload['messages'][0]['content']
    literals = section(instruction, 'Nested literals')
    assert set(literals['stage.questions[].slot.kind']) == {'spending_ceiling', 'other_requirement'}
    shapes = section(instruction, 'Nested keys')
    assert shapes['stage.questions[].slot'] == [['kind'], ['kind', 'dimension']]
    descriptions = section(instruction, 'Nested meanings')
    assert descriptions['stage.questions[].slot'] == [NativePlannedQuestion.model_fields['slot'].description]
    assert descriptions['stage.questions[].choices[].value_kind'] == [
        NativeQuestionChoice.model_fields['choice_kind'].description]
    assert descriptions['stage.questions[].branches'] == [NativePlannedQuestion.model_fields['branches'].description]
    assert descriptions['stage.questions'] == [ClarificationStage.model_fields['questions'].description]
    assert 'unique' in descriptions['stage.questions'][0].lower()
    assert 'at most one unrestricted' in descriptions['stage.questions[].choices'][0]
    assert 'stage.questions[].choices[].value_kind' in literals


def test_compacted_enum_references_and_nullable_array_objects_keep_all_alternatives():
    class Child(BaseModel):
        mode: Literal['first-long-machine-label', 'second-long-machine-label']
        other: Literal['first-long-machine-label', 'second-long-machine-label']

    class Document(BaseModel):
        children: list[Child | None] = Field(description='Each child has independent machine fields.',
                                            json_schema_extra={'x-provider-description': True})

    payload = GroqClient(api_key='fixture').build_payload(settings.GROQ_PRIMARY_MODEL, 'fixture', schema=Document)
    instruction = payload['messages'][0]['content']
    literals = section(instruction, 'Nested literals')
    for field in ('mode', 'other'):
        assert literals['children[].' + field] == ['first-long-machine-label', 'second-long-machine-label']
    assert section(instruction, 'Nested keys')['children[]'] == [['mode', 'other']]
    assert section(instruction, 'Nested meanings')['children'] == [Document.model_fields['children'].description]


def test_root_evidence_allowlists_are_not_repeated_as_required_nested_literals():
    class Document(BaseModel):
        knowledge_ids: list[Literal['approved-topic-a', 'approved-topic-b']]
        questions: list[NativePlannedQuestion]

    payload = GroqClient(api_key='fixture').build_payload(settings.GROQ_PRIMARY_MODEL, 'fixture', schema=Document)
    literals = section(payload['messages'][0]['content'], 'Nested literals')
    assert 'knowledge_ids[]' not in literals
    assert set(literals['questions[].slot.kind']) == {'spending_ceiling', 'other_requirement'}


def test_planning_instruction_exposes_required_analysis_keys_and_stage_labels():
    payload = GroqClient(api_key='fixture').build_payload(settings.GROQ_PRIMARY_MODEL, 'fixture', schema=NativeTurnPlan)
    instruction = payload['messages'][0]['content']
    shapes = section(instruction, 'Nested keys')
    original = native_schema(NativeTurnPlan)
    analysis = original['$defs'][original['properties']['analysis']['$ref'].removeprefix('#/$defs/')]
    assert shapes['analysis'] == [analysis['required']]
    literals = section(instruction, 'Nested literals')
    assert set(literals['stage.response_mode']) == {
        'clarification', 'equipment', 'catalog_overview', 'technical', 'documents', 'conversation', 'information'}
    assert 'inventory_search' in literals['analysis.intent']


def test_moving_shared_meanings_preserves_every_native_validation_constraint():
    original = native_schema(NativeTurnPlan)
    snapshot = json.loads(json.dumps(original))
    payload = GroqClient(api_key='fixture').build_payload(settings.GROQ_PRIMARY_MODEL, 'fixture', schema=NativeTurnPlan)

    def constraints(value):
        if isinstance(value, list):
            return [constraints(child) for child in value]
        if isinstance(value, dict):
            return {key: constraints(child) for key, child in value.items() if key != 'description'}
        return value

    assert constraints(expanded_schema(original)) == constraints(expanded_schema(
        payload['response_format']['json_schema']['schema']))
    assert original == snapshot


def test_recursive_array_definitions_do_not_repeat_or_recurse_forever():
    class Node(BaseModel):
        mode: Literal['selected', 'unrestricted']
        children: list['Node']

    class Document(BaseModel):
        nodes: list[Node]

    payload = GroqClient(api_key='fixture').build_payload(settings.GROQ_PRIMARY_MODEL, 'fixture', schema=Document)
    instruction = payload['messages'][0]['content']
    assert section(instruction, 'Nested literals') == {'nodes[].mode': ['selected', 'unrestricted']}
    assert section(instruction, 'Nested keys') == {'nodes[]': [['mode', 'children']]}
