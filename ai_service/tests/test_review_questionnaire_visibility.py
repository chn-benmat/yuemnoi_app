"""Regression for a live review which mistook a present questionnaire for absent."""
import json
from pathlib import Path
import pytest

from app.application.dtos.chat_dto import ChatRequestDTO, ChatResponseDTO
from app.application.services.response_review import ResponseReviewService
from app.domain.interfaces.generation_stage import Provenance
from app.infrastructure.llm.groq_client import GroqClient
from app.core.config import settings


class PromptCaptured(Exception):
    pass


@pytest.mark.asyncio
async def test_reviewer_sees_questionnaire_without_reconstructing_nested_tables():
    fixture = json.loads((Path(__file__).parent / 'fixtures/review_questionnaire.json').read_text(encoding='utf-8'))
    expected = fixture['draft']['questions']

    class InspectReview:
        async def generate_structured(self, **kwargs):
            payload = json.loads(kwargs['prompt'])
            # คำถามที่ผู้ใช้เห็นต้องอ่านได้โดยตรง ไม่กลายเป็น null ใน review
            assert payload['draft']['questions'] == expected
            raise PromptCaptured

    reviewer = ResponseReviewService(InspectReview(), 'fixture', 0)
    with pytest.raises(PromptCaptured):
        await reviewer.execute(
            ChatRequestDTO.model_validate(fixture['request']),
            ChatResponseDTO.model_validate(fixture['draft']),
            [Provenance('fixture', 'writer')], [], [], [],
        )


@pytest.mark.asyncio
async def test_groq_wire_keeps_the_visible_questions_and_choices_readable():
    fixture = json.loads((Path(__file__).parent / 'fixtures/review_questionnaire.json').read_text(encoding='utf-8'))

    class InspectWire:
        async def generate_structured(self, **kwargs):
            client = GroqClient(api_key='fixture')
            body = client.build_payload(model=settings.GROQ_PRIMARY_MODEL, **kwargs)
            wire = json.loads(body['messages'][-1]['content'])
            assert isinstance(wire['draft']['questions'], list)
            assert [q['title'] for q in wire['draft']['questions']] == [q['title'] for q in fixture['draft']['questions']]
            assert [[c['label'] for c in q['choices']] for q in wire['draft']['questions']] == [
                [c['label'] for c in q['choices']] for q in fixture['draft']['questions']]
            raise PromptCaptured

    reviewer = ResponseReviewService(InspectWire(), 'fixture', 0)
    with pytest.raises(PromptCaptured):
        await reviewer.execute(
            ChatRequestDTO.model_validate(fixture['request']),
            ChatResponseDTO.model_validate(fixture['draft']),
            [Provenance('fixture', 'writer')], [], [], [],
        )
