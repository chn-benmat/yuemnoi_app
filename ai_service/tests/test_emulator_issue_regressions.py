"""Recorded emulator contracts, not live quality/qualification scores."""
import json
from pathlib import Path
import pytest

from app.application.services.review_input import compact_planning_input, restore_planning_input
from app.domain.entities.turn_plan import NativeTurnPlan
from app.infrastructure.llm.provider_client import native_schema

ROOT = Path(__file__).resolve().parents[1]

@pytest.mark.parametrize('name', ['turn_09a8d063c48d44fea9c6c98dc9622705.json', 'turn_80353fa8e23a43db86380fa70642701d.json', 'turn_397a1c1fac94444f84943559e5f135a7.json'])
def test_recorded_questionnaire_payload_roundtrips_and_fits(name):
    from app.infrastructure.llm.groq_client import GroqClient
    from app.core.config import settings
    record = json.loads((ROOT/'evaluation/emulator_detailed_20261005'/name).read_text(encoding='utf-8'))
    generation = record['generation_records'][0]
    original = json.loads(generation['prompt'])
    compact = compact_planning_input(original)
    assert restore_planning_input(compact) == original
    assert len(json.dumps(compact,ensure_ascii=False)) < len(json.dumps(original,ensure_ascii=False))
    client = GroqClient(api_key='fixture')
    cost = client.request_cost('generate_structured',settings.GROQ_PRIMARY_MODEL,dict(prompt=json.dumps(compact,ensure_ascii=False,separators=(',',':')),system_instruction=json.loads((ROOT/'knowledge/interpretation_policy.json').read_text(encoding='utf-8'))['turn_instruction'],schema=NativeTurnPlan))
    assert cost <= client.profile(settings.GROQ_PRIMARY_MODEL).quota.tokens_per_window

def test_native_stage_schema_has_no_ready_stage_prose():
    schema = native_schema(NativeTurnPlan)
    branches = schema['properties']['stage']['anyOf']
    assert len(branches) >= 3
    ready = schema['$defs']['EvidenceStage']
    assert ready['properties']['text']['enum'] == ['']
    assert ready['properties']['questions']['maxItems'] == 0


@pytest.mark.asyncio
async def test_actual_current_source_cannot_alias_old_current_fact():
    from test_fast_turn import make_fast, turn
    from test_request_understanding import understanding
    from native_turn_fixture import native_fixture
    from app.application.dtos.chat_dto import ChatRequestDTO
    from app.application.services.conversation_context import message_source_id
    from pydantic import ValidationError
    decision = understanding(intent='general_greeting', catalog_operation='none',
        request_scope='not_applicable', information_sufficient=True, missing_slots=[], next_action='answer')
    plan = turn(understanding=decision, knowledge_ids=[], response_mode='conversation', message='คุยกันได้')
    fast, llm, _, _ = make_fast(plan)
    async def native(**kwargs):
        value = native_fixture(plan, 'คำขอใหม่')
        value['understanding']['known_facts'] = [{'dimension': 'intended_use', 'value': 'ข้อมูลเก่า',
                                                'source_message_ids': ['current']}]
        payload = restore_planning_input(json.loads(kwargs['prompt']))
        assert payload['current_message']['id'] == message_source_id('user', 'คำขอใหม่')
        return kwargs['schema'].model_validate(value)
    llm.generate_structured.side_effect = native
    with pytest.raises(ValidationError, match='literal_error'):
        await fast.execute(ChatRequestDTO(message='คำขอใหม่'))


@pytest.mark.asyncio
async def test_selection_can_match_real_item_outside_provisional_category():
    from test_fast_turn import make_fast, turn, equipment_answer, ITEM
    from test_request_understanding import understanding
    from app.application.dtos.chat_dto import ChatRequestDTO
    from unittest.mock import AsyncMock
    item = ITEM.model_copy(update={'category': 'different-canonical-category'})
    decision = understanding(catalog_operation='selection', information_sufficient=True,
        next_action='answer', missing_slots=[], categories=['provisional-category'])
    plan = turn(understanding=decision, knowledge_ids=[], response_mode='equipment')
    fast, llm, repo, _ = make_fast(plan, equipment_answer())
    # Both categories really exist; requested function is assessed over the full catalog.
    other = ITEM.model_copy(update={'id': 'different-item', 'category': 'provisional-category'})
    repo.get_all_items = AsyncMock(return_value=[item, other])
    result = await fast.execute(ChatRequestDTO(message='อุปกรณ์ตามหน้าที่ที่ระบุ'))
    assert result.items[0].id == item.id
    payload = json.loads(llm.generate_structured.call_args_list[1].kwargs['prompt'])
    assert set(row[0] for row in payload['catalog']['rows']) == {item.id, other.id}
    assert result.response_kind == 'recommendation'
