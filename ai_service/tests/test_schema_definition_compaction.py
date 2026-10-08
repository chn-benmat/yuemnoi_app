import copy
import json
import pytest
from app.domain.entities.turn_plan import NativeTurnPlan
from app.domain.entities.response_review import NativeResponseReview
from app.infrastructure.llm.provider_client import native_schema, compact_schema_definitions


def expanded_schema(document):
    definitions = document.get('$defs', {})
    def visit(value):
        if isinstance(value, list):
            return [visit(child) for child in value]
        if not isinstance(value, dict):
            return value
        if '$ref' in value:
            name = value['$ref'].removeprefix('#/$defs/')
            assert name in definitions
            return visit({**definitions[name], **{key: child for key, child in value.items() if key != '$ref'}})
        return {key: visit(child) for key, child in value.items() if key != '$defs'}
    return visit(document)


@pytest.mark.parametrize('model', [NativeTurnPlan, NativeResponseReview])
def test_short_definition_names_preserve_every_constraint_and_leave_source_unchanged(model):
    original = native_schema(model)
    snapshot = copy.deepcopy(original)
    compact = compact_schema_definitions(original)
    assert original == snapshot
    assert expanded_schema(original) == expanded_schema(compact)
    assert len(json.dumps(compact)) < len(json.dumps(original))


def test_repeated_draft_path_enums_share_one_definition_losslessly():
    path = {'type': 'string', 'enum': ['/items/' + str(i) + '/description' for i in range(20)]}
    original = {'type': 'object', 'properties': {
        'grounding': {'type': 'array', 'items': path},
        'context': {'type': 'array', 'items': copy.deepcopy(path)},
        'voice': {'type': 'array', 'items': copy.deepcopy(path)}},
        'required': ['grounding', 'context', 'voice'], 'additionalProperties': False}
    snapshot = copy.deepcopy(original)
    compact = compact_schema_definitions(original)
    assert original == snapshot
    assert expanded_schema(original) == expanded_schema(compact)
    assert len(json.dumps(compact)) < len(json.dumps(original)) / 2
