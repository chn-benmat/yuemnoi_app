"""Offline checks for measurement integrity, never cloud or production tests."""

import ast
from pathlib import Path
from types import SimpleNamespace

import httpx
import pytest
from pydantic import ValidationError

from app.domain.entities.intent_decision import IntentDecision
from evaluation.baseline import HTTPRecorder, ObservedClient, RequestBudgetExceeded, main, project_legacy_action, score, summarize
from evaluation.schema import RunConfig, dump_json, load_suite, validate_splits

ROOT = Path(__file__).resolve().parents[1]
CONFIG = RunConfig.model_validate_json((ROOT / "evaluation/baseline_config.json").read_text(encoding="utf-8"))
DEV = load_suite(ROOT / "evaluation/development.json")
HELDOUT = load_suite(ROOT / "evaluation/heldout.json")


def test_splits_have_distinct_inputs_and_required_coverage():
    validate_splits(DEV, HELDOUT)
    assert len(DEV.cases) == 24
    assert len(HELDOUT.cases) == 120


def test_duplicate_ids_and_inputs_are_rejected():
    payload = DEV.model_dump()
    payload["cases"].append(payload["cases"][0])
    with pytest.raises(ValidationError):
        type(DEV).model_validate(payload)




def test_budget_correction_is_scored_in_addition_to_intent():
    case = next(c for c in DEV.cases if c.group == "correction_and_topic_change" and c.expected.exact_fields.get("budget_max") == 900)
    correct_intent_wrong_budget = IntentDecision(intent="inventory_search", budget_max=500)
    result = score(case, correct_intent_wrong_budget, CONFIG)
    assert result["intent_correct"]
    assert not result["all_automated_checks_correct"]
    assert result["checked_fields"] == {"budget_max": False}


def test_no_substring_grading_for_target_names():
    case = next(c for c in DEV.cases if c.expected.required_target_aliases == [["Sony A7 IV"]])
    result = score(case, IntentDecision(intent="item_inquiry", target_items=["Sony A7 IV unrelated model"]), CONFIG)
    assert result["required_targets_correct"] == [False]


def test_incomplete_groups_and_errors_cannot_pass():
    row = {"round": 1, "group": DEV.cases[0].group, "status": "success",
           "score": {"intent_correct": True, "action_correct": True, "all_automated_checks_correct": True}}
    summaries = summarize(DEV, [row], CONFIG)
    assert all(group["router_target_met"] is None for group in summaries)
    attempted = [dict(row, status="error") for _ in range(4)]
    summary = summarize(DEV, attempted, CONFIG)[0]
    assert summary["complete"] and summary["errors"] == 4
    assert summary["metrics"]["intent_correct"]["accuracy_among_successful"] is None
    assert summary["router_target_met"] is None


def test_group_failure_is_not_hidden_by_an_aggregate():
    results = [{"round": 1, "group": case.group, "status": "success", "score": {
        "intent_correct": case.group != "broad_rental", "action_correct": True,
        "all_automated_checks_correct": case.group != "broad_rental"}} for case in DEV.cases]
    summaries = summarize(DEV, results, CONFIG)
    assert summaries[0]["router_target_met"] is False
    assert all(s["router_target_met"] is True for s in summaries[1:])


def test_checkpoint_writes_valid_json(tmp_path):
    path = tmp_path / "report.json"
    dump_json(path, {"status": "running", "text": "ข้อมูล"})
    dump_json(path, {"status": "completed"})
    assert path.read_text(encoding="utf-8").strip() == '{\n  "status": "completed"\n}'
    assert not path.with_suffix(".json.tmp").exists()


def test_cli_preserves_existing_evidence_before_live_calls(monkeypatch, tmp_path):
    evidence = tmp_path / "existing-report.json"
    evidence.write_text("original evidence", encoding="utf-8")
    monkeypatch.setattr("sys.argv", ["baseline", "--config", str(ROOT / "evaluation/baseline_config.json"),
                                    "--live", "--output", str(evidence)])
    with pytest.raises(SystemExit) as stopped:
        main()
    assert stopped.value.code == 2
    assert evidence.read_text(encoding="utf-8") == "original evidence"


@pytest.mark.asyncio
async def test_http_recorder_counts_requests_without_retaining_secrets():
    recorder = HTTPRecorder(maximum=1)
    request = httpx.Request("POST", "https://example.invalid/?key=secret-fixture", headers={"Authorization": "secret-fixture"})
    await recorder.on_request(request)
    await recorder.on_response(httpx.Response(200, request=request))
    assert recorder.requests[0]["status_code"] == 200
    assert "secret-fixture" not in str(recorder.requests)
    with pytest.raises(RequestBudgetExceeded):
        await recorder.on_request(httpx.Request("POST", "https://example.invalid/"))
    assert len(recorder.requests) == 1


@pytest.mark.asyncio
async def test_provider_attempts_include_multiple_http_calls_and_safe_errors():
    recorder = HTTPRecorder(maximum=2)
    attempts = []

    async def generate_structured(**kwargs):
        for status in (400, 200):
            request = httpx.Request("POST", "https://example.invalid/")
            await recorder.on_request(request)
            await recorder.on_response(httpx.Response(status, request=request))
        return IntentDecision(intent="inventory_search")

    observed = ObservedClient("fixture-provider", SimpleNamespace(generate_structured=generate_structured), recorder, attempts)
    await observed.generate_structured(model="fixture-model")
    assert len(attempts) == 1 and len(attempts[0]["http_requests"]) == 2
    assert attempts[0]["status"] == "success"

    async def fail(**kwargs):
        raise RuntimeError("sensitive provider error fixture")

    failing = ObservedClient("fixture-provider", SimpleNamespace(generate_structured=fail), recorder, attempts)
    with pytest.raises(RuntimeError):
        await failing.generate_structured(model="fixture-model")
    assert attempts[-1]["error_type"] == "RuntimeError"
    assert "sensitive" not in str(attempts)
