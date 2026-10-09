import json
from pathlib import Path

import pytest

from app.application.dtos.chat_dto import ChatRequestDTO, ChatResponseDTO
from app.application.services.response_review import ResponseReviewService
from app.application.services.review_input import restore_planning_input
from app.domain.entities.item import Item
from app.domain.interfaces.generation_stage import CURRENT_GENERATION, Provenance
from app.infrastructure.llm.groq_client import GroqClient
from app.infrastructure.runtime.documents import ValidatedFile
from app.infrastructure.runtime.schema import RuntimeDocument
from app.core.config import settings


@pytest.mark.asyncio
async def test_actual_three_question_review_fits_unchanged_bucket_capacity():
    root = Path(__file__).resolve().parents[1]
    payload = json.loads((root / 'tests/fixtures/review_questionnaire.json').read_text(encoding='utf-8'))
    payload.update(approved_articles=[], search_evidence=[])
    inventory = {'items': []}
    runtime = ValidatedFile(settings.AI_RUNTIME_PATH, RuntimeDocument).read()[0]
    client = GroqClient(api_key='fixture', runtime=runtime)
    profile = next(p for p in runtime.providers if p.enabled and p.protocol == client.protocol)
    model = getattr(settings, profile.model_setting)
    class CostOnlyReview:
        async def generate_structured(self, **kwargs):
            cost = client.request_cost('generate_structured', model, kwargs)
            assert cost <= profile.quota.tokens_per_window
            CURRENT_GENERATION.get().provenance = Provenance('fixture', 'reviewer')
            surface = restore_planning_input(json.loads(kwargs['prompt']))['surface_groups']
            from review_fixture import assessed
            return kwargs['schema'].model_validate(assessed({'semantic_pass': True,
                'neutral_voice_pass': True, 'issues': [], 'reviewed_surface_groups': surface,
                'checks': {key: True for key in ('relevance', 'completeness', 'neutral_voice',
                    'choice_equivalence', 'grounding', 'context', 'followups')}}))
    reviewer = ResponseReviewService(CostOnlyReview(), settings_source_review_instruction(root), .1)
    await reviewer.execute(ChatRequestDTO.model_validate(payload['request']),
        ChatResponseDTO.model_validate(payload['draft']), [Provenance('fixture', 'writer')],
        [Item.model_validate(i) for i in inventory['items']], payload['approved_articles'], payload['search_evidence'])


def settings_source_review_instruction(root):
    return json.loads((root / 'knowledge/interpretation_policy.json').read_text(encoding='utf-8'))['review_instruction']
