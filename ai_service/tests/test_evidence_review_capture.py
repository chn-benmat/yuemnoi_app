from native_turn_fixture import native_fixture
import json

import pytest
from pydantic import ValidationError

from app.application.dtos.chat_dto import ChatRequestDTO
from app.application.services.response_review import ResponseReviewService
from evaluation.evidence_review_capture import capture_review
from evaluation.conversation_afterfix_20261004_v12.runner import digest, write
from test_fast_turn import make_fast, turn, equipment_answer, ITEM
from test_request_understanding import understanding


def fixture():
    plan = turn(understanding=understanding(intent='item_inquiry', catalog_operation='inspection',
        categories=[ITEM.category], target_items=[ITEM.name], budget_max=None, budget_unit=None,
        information_sufficient=True, next_action='answer', missing_slots=[]),
        knowledge_ids=[], response_mode='equipment', message='')
    answer = equipment_answer(purpose='inspection')
    fast, llm, _, _ = make_fast(plan)
    fast._review = ResponseReviewService(llm, 'fixture review', .1, fast._limits)
    return plan, answer, fast, llm


@pytest.mark.asyncio
async def test_authentic_evidence_projects_exact_rendered_text_and_actual_writer():
    plan, answer, fast, llm = fixture()
    answer.answer = '{{item:' + ITEM.id + ':name}} {{item:' + ITEM.id + ':price}}'
    captured = await capture_review(fast, ChatRequestDTO(message='fixture'),
        {'result': native_fixture(plan), 'provider': 'fixture', 'model': 'planner'},
        {'result': answer.model_dump(), 'provider': 'fixture', 'model': 'evidence-writer'})
    payload = json.loads(captured.record['prompt'])
    assert captured.record['phase'] == 'review'
    assert payload['draft']['response'] == ITEM.name + ' ' + str(ITEM.price)
    assert payload['draft']['items'][0]['id'] == ITEM.id
    assert captured.excluded == [{'provider': 'fixture', 'model': 'evidence-writer'}]
    llm.generate_structured.assert_not_awaited()
    assert fast._llm is llm


def recorded_fixture(tmp_path, monkeypatch):
    from evaluation import evidence_review_capture as module
    source = {'fixture-source': 'frozen'}
    request = {'message': 'fixture request'}
    plan = {'request': request, 'origin': {'generation_sha256': 'actual-plan'}}
    monkeypatch.setattr(module, 'recorded_plans', lambda _: [plan])
    write(tmp_path / 'checkpoint.json', {'source_fingerprints': source})
    generation = {'phase': 'evidence', 'prompt': 'actual input'}
    cell = {'request': request, 'origin': plan['origin'], 'generation': generation,
        'generation_sha256': digest(generation)}
    capture = tmp_path / 'captures.json'
    write(capture, {'captures': [cell]})
    probe = tmp_path / 'role_probes' / 'fixture'
    probe.mkdir(parents=True)
    import hashlib
    write(probe / 'config.json', {'stage': 'evidence', 'source_fingerprints': source,
        'capture_artifact': str(capture), 'capture_artifact_sha256': hashlib.sha256(capture.read_bytes()).hexdigest(),
        'corpus': [cell]})
    attempts = []
    for text in ('actual neutral output', 'actual bad style output'):
        result = {'answer': text}
        attempts.append({'outcome': 'completed', 'result': result, 'result_sha256': digest(result),
            'input_sha256': digest(generation), 'started_at': text})
    attempts.append({'outcome': 'contract_failed', 'started_at': 'no admitted result'})
    checkpoint = {'rows': [{'key': '0:fixture', 'corpus_index': 0, 'attempts': attempts}]}
    write(probe / 'checkpoint.json', checkpoint)
    return module, probe, checkpoint


def test_collector_retains_all_admitted_results_without_choosing_good_text(tmp_path, monkeypatch):
    module, _, _ = recorded_fixture(tmp_path, monkeypatch)
    pairs = module.recorded_pairs(tmp_path)
    assert [p['evidence']['result']['answer'] for p in pairs] == [
        'actual neutral output', 'actual bad style output']
    assert len({digest(p['origin']) for p in pairs}) == 2


@pytest.mark.parametrize('field', ['result_sha256', 'input_sha256'])
def test_collector_rejects_forged_evidence_or_request_hash(tmp_path, monkeypatch, field):
    module, probe, checkpoint = recorded_fixture(tmp_path, monkeypatch)
    checkpoint['rows'][0]['attempts'][0][field] = 'changed'
    write(probe / 'checkpoint.json', checkpoint)
    with pytest.raises(ValueError, match='hash mismatch'):
        module.recorded_pairs(tmp_path)


@pytest.mark.asyncio
async def test_bad_semantic_text_is_preserved_without_rewriting_before_judge():
    plan, answer, fast, llm = fixture()
    answer.answer = 'ข้อความผิดที่บันทึกจริงครับ {{item:' + ITEM.id + ':name}}'
    captured = await capture_review(fast, ChatRequestDTO(message='fixture'),
        {'result': native_fixture(plan), 'provider': 'fixture', 'model': 'planner'},
        {'result': answer.model_dump(), 'provider': 'fixture', 'model': 'evidence-writer'})
    assert json.loads(captured.record['prompt'])['draft']['response'] == 'ข้อความผิดที่บันทึกจริงครับ ' + ITEM.name
    llm.generate_structured.assert_not_awaited()


@pytest.mark.asyncio
async def test_invalid_recorded_evidence_cannot_bypass_production_validator():
    plan, answer, fast, llm = fixture()
    answer.selection.selected_items[0].id = 'unknown-item'
    with pytest.raises(ValidationError):
        await capture_review(fast, ChatRequestDTO(message='fixture'),
            {'result': native_fixture(plan), 'provider': 'fixture', 'model': 'planner'},
            {'result': answer.model_dump(), 'provider': 'fixture', 'model': 'evidence-writer'})
    llm.generate_structured.assert_not_awaited()
