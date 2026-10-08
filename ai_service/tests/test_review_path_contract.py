import json
import pytest
from app.application.dtos.chat_dto import ChatRequestDTO, ChatResponseDTO, ItemDTO
from app.application.services.response_review import ResponseReviewService
from app.domain.interfaces.generation_stage import Provenance, CURRENT_GENERATION
from pydantic import ValidationError
from review_fixture import assessed
from app.infrastructure.llm.provider_client import native_schema


@pytest.mark.asyncio
@pytest.mark.parametrize('path, valid', [('/items/0/description', True), ('/draft/response', False), ('/items/1/description', False)])
async def test_review_validates_actual_nested_paths_without_a_large_native_enum(path, valid):
    draft = ChatResponseDTO(response='รายละเอียดตามแคตตาล็อก', items=[
        ItemDTO(id='fixture', name='อุปกรณ์ทดสอบ', category='fixture', price=1, description='รายละเอียด')])
    class Inspect:
        async def generate_structured(self, **kwargs):
            schema = native_schema(kwargs['schema'])
            named = schema['$defs'][schema['properties']['assessments']['$ref'].removeprefix('#/$defs/')]
            assert 'ungendered_speaker' in named['properties']
            assert 'neutral_voice' not in named['properties']
            for field in named['properties'].values():
                assessment = schema['$defs'][field['$ref'].removeprefix('#/$defs/')]
                assert 'enum' not in assessment['properties']['field_paths']['items']
            value = assessed({'semantic_pass': True, 'neutral_voice_pass': True, 'issues': [],
                'reviewed_surface_groups': ['items', 'response'], 'checks': {name: True for name in
                ('relevance', 'completeness', 'neutral_voice', 'choice_equivalence', 'grounding', 'context', 'followups')}})
            value['assessments']['grounding']['field_paths'] = [path]
            CURRENT_GENERATION.get().provenance = Provenance('fixture', 'reviewer')
            return kwargs['schema'].model_validate(value)
    service = ResponseReviewService(Inspect(), 'fixture', 0)
    if valid:
        await service.execute(ChatRequestDTO(message='รายละเอียดสินค้า'), draft, [Provenance('fixture', 'writer')], [], [], [])
    else:
        with pytest.raises(ValidationError, match='review_unknown_assessment_path'):
            await service.execute(
                ChatRequestDTO(message='รายละเอียดสินค้า'), draft, [Provenance('fixture', 'writer')], [], [], [])
