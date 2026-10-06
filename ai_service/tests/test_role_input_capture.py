from native_turn_fixture import native_fixture
import json

import pytest
from pydantic import ValidationError

from app.application.dtos.chat_dto import ChatRequestDTO
from app.application.services.response_review import ResponseReviewService
from evaluation.role_input_capture import capture_next
from test_fast_turn import make_fast, turn, ITEM
from test_request_understanding import understanding


def projection(plan):
    fast, llm, _, _ = make_fast(plan)
    fast._review = ResponseReviewService(llm, 'fixture review', .1, fast._limits)
    return fast, llm


@pytest.mark.asyncio
async def test_capture_uses_actual_projection_and_writer_without_model_call():
    plan = turn(understanding=understanding(intent='general_greeting', catalog_operation='none',
        information_sufficient=True, next_action='answer', missing_slots=[], request_scope='not_applicable'),
        knowledge_ids=[], response_mode='conversation', message='ข้อความที่บันทึกจริง')
    fast, llm = projection(plan)
    captured = await capture_next(fast, ChatRequestDTO(message='fixture'),
        native_fixture(plan), 'fixture-provider', 'actual-writer')
    assert captured.record['phase'] == 'review'
    payload = json.loads(captured.record['prompt'])
    assert payload['draft']['response'] == plan.message
    assert captured.excluded == [{'provider': 'fixture-provider', 'model': 'actual-writer'}]
    llm.generate_structured.assert_not_awaited()
    assert fast._llm is llm  # Only the isolated copy was replayed.


@pytest.mark.asyncio
async def test_capture_equipment_input_keeps_real_native_budget_contract():
    plan = turn(understanding=understanding(intent='item_inquiry', catalog_operation='inspection',
        categories=[ITEM.category], target_items=[ITEM.name], budget_max=None, budget_unit=None,
        information_sufficient=True, next_action='answer', missing_slots=[]),
        knowledge_ids=[], response_mode='equipment', message='')
    fast, llm = projection(plan)
    captured = await capture_next(fast, ChatRequestDTO(message='fixture'),
        native_fixture(plan), 'fixture-provider', 'actual-writer')
    assert captured.record['phase'] == 'evidence'
    payload = json.loads(captured.record['prompt'])
    assert payload['selection_required'] is True
    assert payload['price_contract']['ceiling'] is None
    definition = captured.record['schema']['$defs']['ResolvedSelectionPlan']
    assert definition['properties']['price_requirement']['type'] == 'null'
    assert captured.excluded == []
    llm.generate_structured.assert_not_awaited()


@pytest.mark.asyncio
async def test_invalid_recorded_plan_cannot_bypass_production_validator():
    plan = turn(knowledge_ids=['not-approved'])
    fast, llm = projection(plan)
    with pytest.raises(ValidationError):
        await capture_next(fast, ChatRequestDTO(message='fixture'),
            native_fixture(plan), 'fixture-provider', 'actual-writer')
    llm.generate_structured.assert_not_awaited()


@pytest.mark.asyncio
async def test_ready_catalog_plan_cannot_write_facts_before_evidence_stage():
    plan = turn(understanding=understanding(intent='item_inquiry', catalog_operation='inspection',
        categories=[ITEM.category], target_items=[ITEM.name], budget_max=None, budget_unit=None,
        information_sufficient=True, next_action='answer', missing_slots=[]),
        knowledge_ids=[], response_mode='equipment', message='ข้อเท็จจริงที่ planner ยังไม่มีหลักฐานรายสินค้า')
    fast, llm = projection(plan)
    with pytest.raises(ValidationError):
        await capture_next(fast, ChatRequestDTO(message='fixture'),
            native_fixture(plan), 'fixture-provider', 'actual-writer')
    llm.generate_structured.assert_not_awaited()
