"""Review wire regressions for completed phone-rental preferences."""
import json
from pathlib import Path

import pytest

from app.application.dtos.chat_dto import ChatRequestDTO, ChatResponseDTO
from app.application.services.recovery_evidence import request_evidence
from app.application.services.response_review import ResponseReviewService
from app.core.config import settings
from app.infrastructure.llm.groq_client import GroqClient
from app.domain.interfaces.generation_stage import Provenance


def completed_request():
    return ChatRequestDTO.model_validate({
        'message': 'ไม่เกิน 1,000 บาท/วัน, เล่นเกม', 'session_id': 'review-context-fixture',
        'history': [{'role': 'user', 'content': 'อยากเช่ามือถือ'}],
        'context': {'session_id': 'review-context-fixture', 'user_goal': 'เช่าโทรศัพท์มือถือ',
            'categories': ['โทรศัพท์และอุปกรณ์สื่อสาร'], 'questions': [
                {'id': 'budget-question', 'title': 'งบสูงสุดสำหรับการเช่า', 'dimension': 'budget_max',
                    'choices': [{'id': 'budget-selected', 'label': 'ไม่เกิน 1,000 บาท/วัน',
                                 'action_value': 'ไม่เกิน 1,000 บาท/วัน'},
                                {'id': 'budget-other', 'label': 'ไม่จำกัดงบ', 'action_value': 'ไม่จำกัดงบ'}]},
                {'id': 'use-question', 'title': 'วัตถุประสงค์หลัก', 'dimension': 'intended_use',
                    'choices': [{'id': 'use-selected', 'label': 'เล่นเกม', 'action_value': 'เล่นเกม'},
                                {'id': 'use-other', 'label': 'ถ่ายภาพ', 'action_value': 'ถ่ายภาพ'}]}]},
        'questionnaire_answers': [{'question_id': 'budget-question', 'option_id': 'budget-selected'},
                                  {'question_id': 'use-question', 'option_id': 'use-selected'}],
    })


@pytest.mark.asyncio
async def test_groq_review_wire_exposes_original_need_and_selected_answers_without_decoding():
    request = completed_request()
    expected = request_evidence(request, None)
    fixture = json.loads((Path(__file__).parent / 'fixtures/review_questionnaire.json').read_text(encoding='utf-8'))
    draft = ChatResponseDTO.model_validate(fixture['draft'])

    class Captured(Exception):
        pass

    class InspectWire:
        async def generate_structured(self, **kwargs):
            client = GroqClient(api_key='fixture')
            body = client.build_payload(model=settings.GROQ_PRIMARY_MODEL, **kwargs)
            wire = json.loads(body['messages'][-1]['content'])
            # ผู้ตรวจต้องอ่านความต้องการเดิมและคำตอบที่เลือกได้ตรง ๆ บน wire จริง
            assert wire['request']['history'][0]['content'] == expected['history'][0]['content']
            assert wire['request']['message'] == request.message
            actual = wire['request']['context']['questions']
            assert len(actual) == 2
            for question, selected in zip(actual, expected['context']['questions']):
                assert question['choices'][0]['label'] == selected['choices'][0]['label']
                assert question['choices'][0]['action_value'] == selected['choices'][0]['action_value']
                assert len(question['choices']) == 1
            assert [q['title'] for q in wire['draft']['questions']] == [q.title for q in draft.questions]
            assert [[c['label'] for c in q['choices']] for q in wire['draft']['questions']] == [
                [c.label for c in q.choices] for q in draft.questions]
            raise Captured

    reviewer = ResponseReviewService(InspectWire(), 'fixture', 0)
    with pytest.raises(Captured):
        await reviewer.execute(request, draft, [Provenance('fixture', 'writer')], [], [], [])


@pytest.mark.asyncio
async def test_completed_request_review_stays_within_configured_model_request_quota():
    from test_response_repair import stack
    fixture = json.loads((Path(__file__).parent / 'fixtures/questionnaire_recovery_request.json').read_text(encoding='utf-8'))
    request = ChatRequestDTO.model_validate(fixture['request'])
    case, _, _, _ = stack()
    draft = ChatResponseDTO.model_validate(json.loads(
        (Path(__file__).parent / 'fixtures/review_questionnaire.json').read_text(encoding='utf-8'))['draft'])

    class Captured(Exception):
        pass

    class CheckCost:
        async def generate_structured(self, **kwargs):
            client = GroqClient(api_key='fixture')
            for profile in client.runtime.providers:
                if profile.enabled and profile.protocol == client.protocol:
                    model = getattr(settings, profile.model_setting)
                    cost = client.request_cost('generate_structured', model, kwargs)
                    assert cost <= profile.quota.tokens_per_window
            raise Captured

    reviewer = ResponseReviewService(CheckCost(), case._review.instruction, 0,
                                    choice_policy=case._policy.choice_policy)
    with pytest.raises(Captured):
        await reviewer.execute(request, draft, [Provenance('fixture', 'writer')], [], [], [])
