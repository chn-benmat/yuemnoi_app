import json

import pytest

from app.application.services.response_review import visible_text_fields
from app.application.services.review_input import compact_review_draft, restore_review_draft


def test_aliases_restore_every_visible_path_and_context_without_changing_text():
    choices = [{'label': 'ชื่อช้อยจริง' * 20, 'action_value': 'ค่าที่เลือกจริง' * 20}]
    questions = [{'id': 'opaque', 'title': 'คำถามจริง', 'choices': choices}]
    draft = {'response': 'เสียงผู้ช่วย และข้อความผู้ใช้ที่ยกมา', 'questions': questions,
        'clarification': {'options': choices, 'questions': questions},
        'context': {'questions': questions}, 'metadata/~': {'literal': {'$ref': 'data'}},
        'empty': [], 'missing': None}
    projected, aliases = compact_review_draft(draft)
    assert aliases
    restored = restore_review_draft(projected, aliases)
    assert restored == draft
    assert visible_text_fields(restored) == visible_text_fields(draft)
    assert len(json.dumps({'draft': projected, 'draft_references': aliases}, ensure_ascii=False)) < len(json.dumps(draft, ensure_ascii=False))
    restored['questions'][0]['title'] = 'changed copy'
    assert draft['questions'][0]['title'] == 'คำถามจริง'


@pytest.mark.parametrize('draft,aliases', [
    ({'a': None}, {'/a': '/absent'}),
    ({'a': None, 'b': None}, {'/a': '/b', '/b': '/a'}),
    ({'a': 'original', 'b': {}}, {'/a': '/b'}),
])
def test_invalid_aliases_are_rejected(draft, aliases):
    with pytest.raises(ValueError):
        restore_review_draft(draft, aliases)


def test_references_handle_escaped_pointer_keys():
    repeated = {'value': 'long exact content ' * 30}
    draft = {'first/~': repeated, 'second/~': repeated}
    projected, aliases = compact_review_draft(draft)
    assert aliases == {'/second~1~0': '/first~1~0'}
    assert restore_review_draft(projected, aliases) == draft


@pytest.mark.asyncio
async def test_issue_on_an_aliased_question_is_checked_against_original_draft():
    from pathlib import Path
    from app.application.dtos.chat_dto import ChatRequestDTO, ChatResponseDTO
    from app.application.services.response_review import ResponseReviewService
    from app.domain.interfaces.generation_stage import CURRENT_GENERATION, Provenance
    from app.domain.exceptions import GuidanceGenerationError
    root = Path(__file__).resolve().parents[1]
    captures = json.loads((root / 'evaluation/conversation_diagnostic_20261004_v14/'
        'role_input_captures/captured_roles_01/captures.json').read_text(encoding='utf-8'))['captures']
    original = next(json.loads(c['generation']['prompt']) for c in captures
        if c['generation']['phase'] == 'review' and len(json.loads(c['generation']['prompt'])['draft']['questions']) == 3)
    class RejectQuestion:
        async def generate_structured(self, **kwargs):
            from app.application.services.review_input import restore_planning_input
            encoded = restore_planning_input(json.loads(kwargs['prompt']))
            assert encoded['draft']['questions'] is None
            restored = restore_review_draft(encoded['draft'], encoded['draft_references'])
            assert restored == ChatResponseDTO.model_validate(original['draft']).model_dump(mode='json')
            CURRENT_GENERATION.get().provenance = Provenance('fixture', 'reviewer')
            from review_fixture import assessed
            return kwargs['schema'].model_validate(assessed({'semantic_pass': False, 'neutral_voice_pass': True,
                'issues': [{'kind': 'choice', 'field_path': '/questions/0/title',
                    'quoted_text': original['draft']['questions'][0]['title'], 'reason': 'fixture rejection'}]},paths=['/questions/0/title']))
    reviewer = ResponseReviewService(RejectQuestion(), 'fixture encoding instruction', .1)
    with pytest.raises(GuidanceGenerationError, match='response_quality_rejected') as error:
        await reviewer.execute(ChatRequestDTO.model_validate(original['request']),
            ChatResponseDTO.model_validate(original['draft']), [Provenance('fixture', 'writer')], [], [], [])
    assert error.value.draft == ChatResponseDTO.model_validate(original['draft']).model_dump(mode='json')
