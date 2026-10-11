"""Replay the actual named-item plan; simulated validation is not live approval."""
import json
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.domain.entities.turn_plan import NativeTurnPlan


def recorded_plan():
    return json.loads((Path(__file__).parent / 'fixtures/native_named_item_stage.json').read_text(encoding='utf-8'))


@pytest.mark.parametrize('operation', ['inspection', 'comparison'])
def test_named_item_operation_cannot_be_generated_as_a_category_overview(operation):
    value = recorded_plan()
    value['stage']['catalog_operation']['kind'] = operation
    with pytest.raises(ValidationError):
        NativeTurnPlan.model_validate(value)


def test_named_item_equipment_stage_preserves_the_model_interpretation():
    value = recorded_plan()
    value['stage']['response_mode'] = 'equipment'
    plan = NativeTurnPlan.model_validate(value).to_plan()
    assert plan.response_mode == 'equipment'
    assert plan.understanding.catalog_operation == 'inspection'
    assert plan.understanding.target_items == value['analysis']['target_items']
    assert plan.questions == []


def test_unfiltered_category_overview_remains_available():
    value = recorded_plan()
    value['analysis']['target_items'] = []
    value['analysis']['request_scope'] = 'broad'
    value['stage']['catalog_operation']['kind'] = 'selection'
    plan = NativeTurnPlan.model_validate(value).to_plan()
    assert plan.response_mode == 'catalog_overview'
    assert plan.understanding.catalog_operation == 'selection'
