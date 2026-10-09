import json
import pytest
from app.application.dtos.chat_dto import ChatRequestDTO
from app.application.services.review_input import restore_planning_input
from app.core.config import settings
from app.infrastructure.llm.groq_client import GroqClient
from test_fast_turn import make_fast, turn, ITEM
from test_request_understanding import understanding


@pytest.mark.asyncio
async def test_social_review_and_repair_do_not_carry_unrelated_catalog_rows():
    plan = turn(understanding=understanding(intent='general_greeting', catalog_operation='none',
        next_action='answer', information_sufficient=True, missing_slots=[], request_scope='not_applicable'),
        knowledge_ids=[], message='พักคุยกันได้เลย', response_mode='conversation')
    fast, _, repo, _ = make_fast(plan)
    repo.get_all_items.return_value = [ITEM.model_copy(update={'id': f'inventory-{index}',
        'name': f'รายการ {index}', 'description': 'รายละเอียดคลังที่ไม่เกี่ยวกับคำทักทาย' * 10})
        for index in range(34)]
    await fast.execute(ChatRequestDTO(message='เลิกงานแล้วเหนื่อยมาก'))
    call = fast._review.execute.call_args.kwargs
    assert 'catalog_summary' in call
    preview = call['recovery_request']
    payload = restore_planning_input(json.loads(preview.prompt))
    assert 'catalog' not in payload
    assert 'catalog_summary' in payload
    client = GroqClient(api_key='fixture')
    kwargs = dict(prompt=preview.prompt, schema=preview.schema, system_instruction=preview.system_instruction,
                  temperature=preview.temperature)
    for profile in client.runtime.providers:
        if profile.enabled and profile.protocol == client.protocol:
            model = getattr(settings, profile.model_setting)
            assert client.request_cost('generate_structured', model, kwargs) <= profile.quota.tokens_per_window
