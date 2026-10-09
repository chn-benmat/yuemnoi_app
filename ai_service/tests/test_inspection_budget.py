import pytest
from pydantic import ValidationError

from app.application.dtos.chat_dto import ChatRequestDTO
from test_fast_turn import ITEM, equipment_answer, make_fast, turn
from test_request_understanding import understanding


@pytest.mark.asyncio
async def test_named_item_inspection_answers_even_when_over_previous_budget():
    decision = understanding(
        catalog_operation='inspection', intent='item_inquiry',
        information_sufficient=True, next_action='answer', missing_slots=[],
        target_items=[ITEM.name], budget_max=800,
    )
    fast, _, repo, _ = make_fast(
        turn(understanding=decision, knowledge_ids=[], response_mode='equipment'),
        equipment_answer(purpose='inspection'),
    )
    repo.get_all_items.return_value = [ITEM.model_copy(update={'price': 900})]
    response = await fast.execute(ChatRequestDTO(message='เปลี่ยนเป็นรุ่นนี้ ขอราคาสองวัน'))
    assert response.items[0].price == 900


@pytest.mark.asyncio
async def test_selection_keeps_the_price_ceiling():
    decision = understanding(
        catalog_operation='selection', information_sufficient=True,
        next_action='answer', missing_slots=[], budget_max=800,
    )
    fast, _, repo, _ = make_fast(
        turn(understanding=decision, knowledge_ids=[], response_mode='equipment'),
        equipment_answer(price_requirement={
            'maximum': 800, 'user_unit': ITEM.type, 'catalog_units': [ITEM.type],
            'interpretation': 'เพดานงบตามหน่วยที่ผู้ใช้ระบุ',
        }),
    )
    repo.get_all_items.return_value = [ITEM.model_copy(update={'price': 900})]
    with pytest.raises(ValidationError):
        await fast.execute(ChatRequestDTO(message='เลือกของในงบที่กำหนด'))
