from evaluation.conversation_afterfix_20261004_v12.runner import write, digest
from evaluation.planning_input_capture import collect_inputs
import pytest


def source(tmp_path):
    generation = {'phase': 'planning', 'logical_call_id': 'first-call',
        'prompt': 'actual captured input', 'system_instruction': 'actual instruction', 'schema': {'type': 'object'}}
    request = {'message': 'actual request', 'session_id': 'original-session', 'history': []}
    attempt = {'started_at': 'first-attempt', 'request': request, 'generation_records': [generation]}
    row = {'key': 'original-case', 'group': 'fixture', 'attempts': [attempt]}
    checkpoint = {'source_fingerprints': {'fixture': 'frozen'}, 'rows': [row]}
    write(tmp_path / 'checkpoint.json', checkpoint)
    return generation, request, checkpoint


def test_preserves_authentic_input_request_and_origin_without_synthesis(tmp_path):
    generation, request, _ = source(tmp_path)
    cells = collect_inputs(tmp_path)
    assert len(cells) == 1
    assert cells[0]['request'] == request
    assert cells[0]['generation']['prompt'] == generation['prompt']
    assert cells[0]['origin']['record_sha256'] == digest(generation)
    assert cells[0]['excluded_models'] == []


def test_availability_retry_is_not_a_new_model_probe_input(tmp_path):
    generation, _, checkpoint = source(tmp_path)
    old = checkpoint['rows'][0]['attempts'][0]
    checkpoint['rows'][0]['attempts'].append({**old, 'started_at': 'retry',
        'generation_records': [{**generation, 'logical_call_id': 'another-call'}]})
    write(tmp_path / 'checkpoint.json', checkpoint)
    assert len(collect_inputs(tmp_path)) == 1
    probe = tmp_path / 'role_probes' / 'existing'
    probe.mkdir(parents=True)
    write(probe / 'config.json', {'stage': 'planning', 'source_fingerprints': checkpoint['source_fingerprints'],
        'corpus': collect_inputs(tmp_path)})
    assert collect_inputs(tmp_path) == []


def test_foreign_source_corpus_cannot_exclude_or_supply_current_inputs(tmp_path):
    source(tmp_path)
    probe = tmp_path / 'role_probes' / 'foreign'
    probe.mkdir(parents=True)
    write(probe / 'config.json', {'stage': 'planning', 'source_fingerprints': {'foreign': 'source'}, 'corpus': []})
    with pytest.raises(ValueError, match='source'):
        collect_inputs(tmp_path)
