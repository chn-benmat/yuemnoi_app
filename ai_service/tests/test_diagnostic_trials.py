"""Diagnostic bookkeeping cannot manufacture qualification results."""
import json
from pathlib import Path
import pytest
from evaluation.conversation_diagnostic_20261004_v13 import runner
from evaluation.conversation_trials import adapt_runner
from app.infrastructure.llm.telemetry import safe_telemetry


def test_original_suite_and_config_are_byte_identical_but_only_ninety_rows():
    before = runner.ROOT.parent / 'conversation_20261004'
    assert (runner.ROOT/'suite.json').read_bytes() == (before/'suite.json').read_bytes()
    assert (runner.ROOT/'config.json').read_bytes() == (before/'config.json').read_bytes()
    rows = runner.planned_rows(runner.read(runner.ROOT/'config.json'))
    assert len(rows)==90 and {r['case_index'] for r in rows}==set(range(5))
    assert len({r['key'] for r in rows})==90
    assert runner.read(runner.ROOT/'trial_kind.json')['qualification_eligible'] is False


def test_diagnostic_never_emits_a_human_certificate_even_if_all_scores_pass():
    config = runner.read(runner.ROOT/'config.json')
    rows = runner.planned_rows(config)
    reviews = {'entries':[]}
    for row in rows:
        row.update(status='completed', turns=[{'synthetic_fixture':True}],contract_checks={'fixture':True})
        reviews['entries'].append(dict(key=row['key'],turns_sha256=runner.digest(row['turns']),
            semantic_pass=True,reviewer_kind='independent_human',reviewed_by='synthetic-unit-only'))
    report={'rows':rows}
    runner.scores(report,config,reviews)
    assert report['certificate_95_percent'] is False


def test_runner_template_compiles_and_failure_does_not_complete_a_case():
    source=(runner.ROOT.parent/'conversation_afterfix_20261004_v12/runner.py').read_text(encoding='utf-8')
    adapted=adapt_runner(source.replace('conversation_afterfix_20261004_v12','fixture_trial'),'fixture_trial')
    compile(adapted,'fixture_trial','exec')
    assert adapted.index('if attempt["outcome"] != "completed"') > adapted.index('attempt = {')
    assert 'if row["status"] in ("completed", "quality_failed", "contract_failed")' in adapted


def test_safe_telemetry_includes_stage_validation_but_omits_body_and_secrets():
    result=safe_telemetry([{'phase':'review','validation_errors':[{'type':'fixture','loc':['answer']}],
                          'provider_body':'secret','api_key':'secret','prompt':'secret'}])
    assert result == [{'phase':'review','validation_errors':[{'type':'fixture','loc':['answer']}]}]
