"""Acceptance accounting tests with synthetic outputs, never a live certificate."""
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path

import pytest
from pydantic import ValidationError

from evaluation.fast_contract import load_document
from evaluation.fast_qualification import (QualificationSuite, QualificationConfig, CONTRACT_KEYS,
    check_retired_inputs, digest, group_scores, planned_rows, release_gate)

ROOT = Path(__file__).resolve().parents[1]
SUITE = load_document(ROOT / "evaluation/fast_qualification_cases.json", QualificationSuite)
CONFIG = load_document(ROOT / "evaluation/fast_qualification_config.json", QualificationConfig)


def synthetic_complete():
    suite = SUITE.model_copy(update={"label_status": "approved", "family_review_status": "approved",
        "labels_approved_at": datetime(2026, 1, 1, tzinfo=timezone.utc), "labels_approved_by": "test-human-only"})
    rows = planned_rows(suite, CONFIG.rounds)
    cases = {c.id: c for c in suite.cases}
    reviews = []
    for row in rows:
        case = cases[row["case_id"]]
        row.update(outcome="completed", result={"request_scope": case.expected.request_scope,
            "next_action": case.expected.next_action}, contract_checks={k: True for k in CONTRACT_KEYS})
        row["result_sha256"] = digest(row["result"])
        reviews.append({"row_key": row["row_key"], "result_sha256": row["result_sha256"],
            "reviewer_kind": "independent_human", "reviewed_by": "unit-test-fixture", "reviewed_at": "2026-01-03T00:00:00+00:00",
            "grounding_ok": True, "constraints_ok": True, "no_repeated_known_questions": True,
            "neutral_reasoning_ok": True, "requirements_ok": True})
    report = {"created_at": "2026-01-02T00:00:00+00:00", "rows": rows, "source_files_unchanged": True}
    return suite, report, reviews


def test_six_groups_twenty_cases_three_rounds_and_no_exact_retired_inputs():
    assert len(SUITE.cases) == 120
    assert len(planned_rows(SUITE, CONFIG.rounds)) == 360
    check_retired_inputs(SUITE, [ROOT / p for p in CONFIG.retired_suite_paths])
    assert SUITE.family_review_status == "pending_semantic_review"
    assert SUITE.label_status == "draft_pending_independent_review"
    assert sum(bool(c.questionnaire_answers) for c in SUITE.cases) == 2


def test_actual_model_input_excludes_expected_labels_and_review_rationale():
    for case in SUITE.cases:
        request = case.request().model_dump()
        assert "expected" not in request and "rationale" not in request and "family_id" not in request


@pytest.mark.parametrize("field,value", [("rounds", 2), ("target_accuracy", .94),
    ("concurrent_requests", 1), ("batch_interval_seconds", 0)])
def test_config_cannot_weaken_release_requirements(field, value):
    data = CONFIG.model_dump()
    data[field] = value
    with pytest.raises(ValidationError):
        QualificationConfig.model_validate(data)


def test_missing_or_error_rows_fail_with_full_planned_denominator():
    scores = group_scores([], SUITE, CONFIG.rounds, CONFIG.target_accuracy)
    assert len(scores) == 18
    assert all(s["planned"] == 20 and s["scope_accuracy"] == 0 for s in scores)
    row = planned_rows(SUITE, CONFIG.rounds)[0]
    row.update(outcome="controlled_error", scope_correct=True, action_correct=True,
               result={"request_scope": "broad", "next_action": "answer"})
    scores = group_scores([row], SUITE, CONFIG.rounds, CONFIG.target_accuracy)
    assert scores[0]["scope_accuracy"] == 0


def test_numeric_pass_without_review_or_approved_labels_is_never_a_certificate():
    _, report, _ = synthetic_complete()
    gate = release_gate(report, SUITE, CONFIG)
    assert all(s["threshold_met"] for s in gate["group_round_metrics"])
    assert gate["certificate_95_percent"] is False
    assert "independent_output_review_missing_or_stale" in gate["reasons"]


def test_complete_reviewed_classification_does_not_certify_ui_or_deployment():
    suite, report, reviews = synthetic_complete()
    gate = release_gate(report, suite, CONFIG, reviews)
    assert gate["certificate_95_percent"] is True
    assert gate["release_ready"] is False
    assert "profile_device_ui_load_not_measured" in gate["reasons"]


def test_two_errors_in_one_group_round_cannot_be_hidden_by_average():
    suite, report, reviews = synthetic_complete()
    broken = [r for r in report["rows"] if r["group"] == "broad_rental" and r["round"] == 3][:2]
    for row in broken:
        row["result"]["request_scope"] = "specific"
        row["result_sha256"] = digest(row["result"])
        next(r for r in reviews if r["row_key"] == row["row_key"])["result_sha256"] = row["result_sha256"]
    gate = release_gate(report, suite, CONFIG, reviews)
    score = next(s for s in gate["group_round_metrics"] if s["group"] == "broad_rental" and s["round"] == 3)
    assert score["scope_accuracy"] == .9 and score["action_accuracy"] == 1
    assert gate["certificate_95_percent"] is False


@pytest.mark.parametrize("change", ["stale_review", "critical_issue", "source_drift", "missing_check", "forged_hash"])
def test_missing_grounding_or_tampered_evidence_blocks_certificate(change):
    suite, report, reviews = synthetic_complete()
    if change == "stale_review":
        reviews[0]["result_sha256"] = "stale"
    elif change == "critical_issue":
        reviews[0]["grounding_ok"] = False
    elif change == "source_drift":
        report["source_files_unchanged"] = False
    elif change == "missing_check":
        report["rows"][0]["contract_checks"].pop(next(iter(CONTRACT_KEYS)))
    else:
        report["rows"][0]["result_sha256"] = "forged"
    assert release_gate(report, suite, CONFIG, reviews)["certificate_95_percent"] is False


def test_duplicate_rows_or_reviews_rejected():
    suite, report, reviews = synthetic_complete()
    with pytest.raises(ValueError, match="Duplicate human"):
        release_gate(report, suite, CONFIG, reviews + [deepcopy(reviews[0])])
    report["rows"].append(deepcopy(report["rows"][0]))
    with pytest.raises(ValueError, match="Duplicate or unplanned"):
        release_gate(report, suite, CONFIG)


def test_label_approval_after_run_cannot_retroactively_seal_candidates():
    suite, report, reviews = synthetic_complete()
    suite.labels_approved_at = datetime(2026, 1, 4, tzinfo=timezone.utc)
    gate = release_gate(report, suite, CONFIG, reviews)
    assert "label_approval_not_before_freeze" in gate["classification_reasons"]
    assert gate["certificate_95_percent"] is False
