"""Synthetic app request regression: preserve answers while fitting native admission."""
import json
from pathlib import Path
from unittest.mock import AsyncMock

import pytest

from app.application.dtos.chat_dto import ChatRequestDTO
from app.application.services.review_input import compact_planning_input, restore_planning_input
from app.domain.entities.chat_result import SessionContext
from app.domain.entities.item import Item
from app.infrastructure.llm.groq_client import GroqClient
from app.core.config import settings


def test_nested_tables_and_aliases_preserve_exact_values_and_escaped_paths():
    choices = [dict(id=f'choice-{i}', label='คำตอบที่ผู้ใช้เห็นจริง', action_value=str(i),
                    description='', source_message_ids=['source-id-' * 12]) for i in range(4)]
    original = {'questions/~': [dict(id=f'q-{i}', choices=choices, step=i + 1, empty=None)
                                for i in range(3)],
                'context': {'questions': choices}, 'unstructured': ['text', {'x': None}]}
    encoded = compact_planning_input(original)
    assert encoded['input_tables'] and encoded['input_references']
    assert restore_planning_input(encoded) == original
    assert len(json.dumps(encoded, ensure_ascii=False)) < len(json.dumps(original, ensure_ascii=False))


def test_original_dictionary_marker_is_preserved_without_encoding_collision():
    original={'data':{'$text':2},'labels':['ข้อความซ้ำยาวมาก'*12]*5}
    compacted=compact_planning_input(original)
    assert 'input_dictionary' not in compacted
    assert restore_planning_input(compacted)==original


@pytest.mark.asyncio
async def test_completed_three_question_request_fits_without_losing_actual_answers():
    from test_response_repair import stack
    fixture = json.loads((Path(__file__).parent / 'fixtures/questionnaire_recovery_request.json').read_text(encoding='utf-8'))
    request = ChatRequestDTO.model_validate(fixture['request'])
    original=request.model_dump(mode='json')
    case, llm, _, _ = stack()
    rows = fixture['catalog_summary']['prices']['rows']
    case._items.get_all_items = AsyncMock(return_value=[
        Item(id=f'{i}-{j}', name='Budget fixture inventory', category=category,
             price=price, type=unit)
        for i, (category, unit, minimum, maximum) in enumerate(rows)
        for j, price in enumerate((minimum, maximum))])

    class Captured(Exception):
        pass

    async def capture(**kwargs):
        encoded = json.loads(kwargs['prompt'])
        restored = restore_planning_input(encoded)
        from app.application.services.recovery_evidence import request_evidence
        expected=request_evidence(request,case._limits)['context']
        assert SessionContext.model_validate(restored['client_context']['data']) == SessionContext.model_validate(expected)
        assert request.model_dump(mode='json')==original
        assert restored['questionnaire_answers']['data'] == [a.model_dump() for a in request.questionnaire_answers]
        assert restored['current_message']['content'] == request.effective_message
        assert len(restored['conversation']['messages'][1]['content']['questions']) == 3
        assert 'required_output_fields' not in restored
        from pydantic import ValidationError
        analysis = kwargs['schema'].model_fields['understanding'].annotation
        fact = analysis.model_fields['known_facts'].annotation.__args__[0]
        with pytest.raises(ValidationError):
            fact.model_validate({'dimension': 'budget_max', 'value': 500, 'source_message_ids': ['not-a-conversation-source']})
        client = GroqClient(api_key='fixture')
        for profile in client.runtime.providers:
            if not profile.enabled or profile.protocol != client.protocol:
                continue
            model = getattr(settings, profile.model_setting)
            cost = client.request_cost('generate_structured', model, kwargs)
            assert cost <= client.profile(model).quota.tokens_per_window
        raise Captured

    llm.generate_structured.side_effect = capture
    with pytest.raises(Captured):
        await case.execute(request)
