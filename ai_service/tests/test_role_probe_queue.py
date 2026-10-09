import hashlib
from pathlib import Path

import pytest

from evaluation.conversation_afterfix_20261004_v12.runner import read, write
from evaluation import role_probes_fair as fair
from evaluation import role_probe_reporting as reporting


def predecessor(tmp_path, monkeypatch):
    source = tmp_path / 'source'
    previous = source / 'role_probes' / 'planning'
    previous.mkdir(parents=True)
    monkeypatch.setattr(fair, 'trial_sources', lambda root: {})
    monkeypatch.setattr(reporting, 'trial_sources', lambda root: {})
    controller = Path(fair.replay_schema.__code__.co_filename)
    write(previous / 'config.json', {
        'source_root': str(source), 'source_fingerprints': {},
        'probe_runner_sha256': hashlib.sha256(controller.read_bytes()).hexdigest(),
        'stage': 'planning', 'profiles': ['fixture'], 'inventory_sha256': 'fixture',
        'corpus': [{'generation_sha256': 'fixture'}],
    })
    write(previous / 'checkpoint.json', {'rows': [{
        'key': '0:fixture', 'status': 'contract_failed', 'profile': 'fixture',
        'corpus_index': 0, 'attempts': [{
            'started_at': 'fixture', 'outcome': 'contract_failed',
            'telemetry': [{'phase': 'planning', 'provider': 'fixture', 'model': 'fixture',
                'http_attempts': 1, 'status': 'structured_output_invalid',
                'elapsed_seconds': 1, 'usage': {}}],
        }],
    }], 'invocations': []})
    write(source / 'checkpoint.json', {'source_fingerprints': {}, 'rows': []})
    write(source / 'diagnostic.json', {})
    return source, previous


def test_fair_queue_does_not_starve_unattempted_cells():
    rows = [{'key': 'repeated', 'attempts': [1, 2]},
            {'key': 'first-new', 'attempts': []},
            {'key': 'second-new', 'attempts': []},
            {'key': 'once', 'attempts': [1]}]
    assert [r['key'] for r in fair.ready_rows(rows)] == [
        'first-new', 'second-new', 'once', 'repeated']
    assert rows[0]['key'] == 'repeated'


def test_transition_keeps_failed_attempt_and_rejects_replacement(tmp_path, monkeypatch):
    _, previous = predecessor(tmp_path, monkeypatch)
    before = (previous / 'checkpoint.json').read_bytes()
    root = fair.transition(previous, 'planning_fair')
    assert (previous / 'checkpoint.json').read_bytes() == before
    current = read(root / 'checkpoint.json')
    assert current == read(previous / 'checkpoint.json')
    current['rows'][0]['attempts'] = []
    write(root / 'checkpoint.json', current)
    with pytest.raises(ValueError, match='attempts were replaced'):
        fair.validate_predecessor(root, read(root / 'config.json'))


def test_changed_predecessor_evidence_fails_closed(tmp_path, monkeypatch):
    _, previous = predecessor(tmp_path, monkeypatch)
    root = fair.transition(previous, 'planning_fair')
    (previous / 'checkpoint.json').write_text('{}', encoding='utf-8')
    with pytest.raises(ValueError, match='Predecessor evidence changed'):
        fair.validate_predecessor(root, read(root / 'config.json'))


def test_calibration_counts_copied_failure_once(tmp_path, monkeypatch):
    source, previous = predecessor(tmp_path, monkeypatch)
    fair.transition(previous, 'planning_fair')
    result = reporting.proposal(source)
    assert result['profiles'][0]['statuses'] == {'structured_output_invalid': 1}
    assert result['profiles'][0]['quality_accuracy'] == 0
    assert result['qualification_credit'] is False


def test_role_ranking_uses_complete_stage_latency_including_admission(tmp_path, monkeypatch):
    from types import SimpleNamespace
    from app.core import config as configuration
    from app.infrastructure.runtime import documents
    from evaluation.conversation_afterfix_20261004_v12.runner import digest
    source = tmp_path / 'source'
    source.mkdir()
    monkeypatch.setattr(reporting, 'trial_sources', lambda root: {})
    monkeypatch.setattr(configuration, 'settings', SimpleNamespace(
        AI_RUNTIME_PATH=tmp_path / 'fixture', FIRST='first-model', SECOND='second-model'))
    profiles = [SimpleNamespace(id='first', enabled=True, protocol='fixture_json_schema', model_setting='FIRST'),
                SimpleNamespace(id='second', enabled=True, protocol='fixture_json_schema', model_setting='SECOND')]
    monkeypatch.setattr(documents, 'ValidatedFile', lambda *args: SimpleNamespace(
        read=lambda: (SimpleNamespace(providers=profiles), 'fixture')))
    write(source / 'checkpoint.json', {'source_fingerprints': {}, 'rows': []})
    write(source / 'diagnostic.json', {'minimum_reviewed_calls_per_role_model': 1})
    probe = source / 'role_probes' / 'fixture'
    probe.mkdir(parents=True)
    write(probe / 'config.json', {'stage': 'planning', 'source_fingerprints': {}})
    rows, reviews = [], []
    # The first transport is faster but admission/bookkeeping makes its stage slower.
    for model, transport, complete in [('first-model', .05, .5), ('second-model', .1, .2)]:
        result = {'fixture': model}
        attempt = {'started_at': model, 'outcome': 'completed', 'result': result,
            'result_sha256': digest(result), 'elapsed_seconds': complete,
            'telemetry': [{'phase': 'planning', 'provider': 'fixture', 'model': model,
                'status': 'success', 'http_attempts': 1, 'elapsed_seconds': transport,
                'usage': {'total_tokens': 10}}]}
        rows.append({'key': model, 'attempts': [attempt]})
        reviews.append({'cell_key': model, 'attempt_started_at': model, 'attempt_sha256': digest(attempt),
            'result_sha256': attempt['result_sha256'], 'quality_pass': True,
            'reviewer_kind': 'codex_ai', 'reviewed_by': 'Codex', 'reviewed_at': 'fixture', 'notes': 'fixture'})
    write(probe / 'checkpoint.json', {'rows': rows})
    write(probe / 'reviews.json', {'entries': reviews})
    proposal = reporting.proposal(source)
    assert proposal['routes']['planning']['profiles'] == ['second', 'first']
    assert proposal['routes']['planning']['p95_seconds'] == {'second': .2, 'first': .5}
