"""Release-gate integrity tests; these do not measure a real model."""

import json
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from pydantic import ValidationError

from evaluation.acceptance import (
    AcceptanceConfig, HumanReview, ObservedRouter, RESPONSE_CHECK_KEYS, digest,
    fairness_items, interleaved_cases, main, release_gate, response_contract_checks, validate_inputs,
)
from evaluation.schema import load_suite
from evaluation.baseline import fingerprint
from evaluation.assessment import assess
from tests.test_request_understanding import understanding
from app.application.dtos.chat_dto import ChatResponseDTO, ItemDTO
from app.application.services.catalog_guidance import catalog_snapshot
from app.domain.entities.clarification import QuestionStep, ChoiceOption
from app.domain.entities.intent_decision import KnownFact
from app.domain.entities.item import Item

ROOT = Path(__file__).resolve().parents[1]
CONFIG = AcceptanceConfig.model_validate_json((ROOT / "evaluation/step6_config.json").read_text(encoding="utf-8"))
SUITE = load_suite(ROOT / "evaluation/heldout.json")
FAIRNESS = json.loads((ROOT / "evaluation/fairness.json").read_text(encoding="utf-8"))


def evidence():
    rows = []
    reviews = []
    summaries = []
    for round_number in range(1, 4):
        for case in SUITE.cases:
            row = dict(round=round_number, case_id=case.id, status="success", contract_checks={key: True for key in RESPONSE_CHECK_KEYS})
            row["result_sha256"] = digest(row)
            rows.append(row)
            reviews.append(HumanReview(row_key=f"{round_number}:{case.id}", result_sha256=row["result_sha256"],
                reviewed_by="fixture-reviewer", reviewed_at=datetime.now(timezone.utc), grounding_ok=True,
                constraints_ok=True, no_repeated_known_questions=True, neutral_reasoning_ok=True,
                requirements_ok=True, notes="Synthetic gate fixture only"))
        for group in dict.fromkeys(c.group for c in SUITE.cases):
            summaries.append(dict(round=round_number, group=group, planned=20, router_target_met=True))
    fairness = [dict(round=i + 1, case_id=f"fairness-{i}", status="success", expected_selection_correct=True,
                     human_reasoning_review=True) for i in range(30)]
    return summaries, rows, reviews, fairness


def gate(*data, **kwargs):
    return release_gate(*data, labels_approved=kwargs.get("labels_approved", True), planned_chat=360,
        planned_fairness=30, sources_unchanged=kwargs.get("sources_unchanged", True))


def test_success_requires_all_groups_rounds_outputs_and_independent_reviews():
    data = evidence()
    assert gate(*data)["status"] == "pass"
    assert gate(data[0], data[1], [], data[3])["status"] == "incomplete"
    assert gate(data[0], data[1][:-1], data[2][:-1], data[3])["status"] == "incomplete"
    assert gate(*data, labels_approved=False)["status"] == "incomplete"
    assert gate(*data, sources_unchanged=False)["status"] == "incomplete"


def test_low_group_accuracy_cannot_be_hidden_by_other_groups():
    data = evidence()
    data[0][0]["router_target_met"] = False
    assert gate(*data)["status"] == "fail"


@pytest.mark.parametrize("field", ["grounding_ok", "constraints_ok", "no_repeated_known_questions", "neutral_reasoning_ok", "requirements_ok"])
def test_one_semantic_violation_blocks_release(field):
    data = evidence()
    data[2][0] = data[2][0].model_copy(update={field: False})
    result = gate(*data)
    assert result["status"] == "fail"
    assert result["critical_or_accuracy_failures"][0]["type"] == field


def test_stale_tampered_duplicate_or_orphan_reviews_are_rejected():
    data = evidence()
    data[2][0] = data[2][0].model_copy(update={"result_sha256": "stale"})
    with pytest.raises(ValueError):
        gate(*data)
    data = evidence()
    data[1][0]["response"] = "tampered after review"
    with pytest.raises(ValueError):
        gate(*data)
    data = evidence()
    with pytest.raises(ValueError):
        gate(data[0], data[1], [*data[2], data[2][0]], data[3])
    with pytest.raises(ValueError):
        gate(data[0], data[1][1:], data[2], data[3])


def test_incomplete_or_failed_fairness_is_not_a_pass():
    data = evidence()
    assert gate(data[0], data[1], data[2], [])["status"] == "incomplete"
    data[3][0]["human_reasoning_review"] = None
    assert gate(*data)["status"] == "incomplete"
    data[3][0]["expected_selection_correct"] = False
    assert gate(*data)["status"] == "fail"


@pytest.mark.parametrize("change", [{"rounds": 2}, {"target_accuracy": .94}, {"measurement_mode": "legacy"}])
def test_acceptance_configuration_cannot_silently_lower_requirements(change):
    with pytest.raises(ValidationError):
        AcceptanceConfig.model_validate({**CONFIG.model_dump(), **change})


def test_heldout_coverage_and_interleaving_are_complete():
    validate_inputs(CONFIG, ROOT / "evaluation/step6_config.json")
    ordered = list(interleaved_cases(SUITE))
    assert len(ordered) == 120 and len({c.id for c in ordered}) == 120
    assert len({c.group for c in ordered[:6]}) == 6
    assert SUITE.label_status == "draft_pending_owner_review"


def test_counterfactuals_change_only_names_merchants_and_order():
    for scenario in FAIRNESS["scenarios"]:
        original = {item.id: item for item in fairness_items(scenario, FAIRNESS["variants"][0])}
        for variant in FAIRNESS["variants"]:
            actual = fairness_items(scenario, variant)
            for item in actual:
                before = original[item.id]
                assert item.model_dump(exclude={"name", "description"}) == before.model_dump(exclude={"name", "description"})
                assert item.description.split(" ผู้ให้เช่า: ")[0] == before.description.split(" ผู้ให้เช่า: ")[0]
            if variant["reverse_order"]:
                assert [item.id for item in actual] == list(reversed(list(original)))


@pytest.mark.asyncio
async def test_observed_router_forwards_only_original_inputs_not_expected_labels():
    delegate = SimpleNamespace(execute=AsyncMock(return_value=understanding()))
    router = ObservedRouter(delegate)
    case = SUITE.cases[0]
    await router.execute(case.message, case.history)
    delegate.execute.assert_awaited_once_with(case.message, case.history)
    assert router.decision is not None


def test_contract_checker_detects_fake_ids_changed_prices_and_repeated_known_questions():
    item = Item(id="real", name="fixture", category="fixture", price=100)
    snapshots = [catalog_snapshot([item])]
    decision = understanding(known_facts=[KnownFact(dimension="usage", value="known", source_message_ids=["current"])])
    response = ChatResponseDTO(response="fixture", items=[ItemDTO.from_entity(item.model_copy(update={"id": "fake"}))])
    knowledge = SimpleNamespace(articles=[])
    assert not response_contract_checks(response, decision, snapshots, knowledge)["real_unique_product_ids"]
    response.items = [ItemDTO.from_entity(item.model_copy(update={"price": 101}))]
    assert not response_contract_checks(response, decision, snapshots, knowledge)["catalog_fields_current"]
    response.items = []
    response.questions = [QuestionStep(id="q", title="fixture", dimension="usage", choices=[ChoiceOption(id="c", label="fixture")])]
    checks = response_contract_checks(response, decision, snapshots, knowledge)
    assert not checks["known_dimension_ids_not_reasked"] and not checks["missing_dimension_ids_only"]


def test_missing_contract_checks_cannot_be_used_as_complete_evidence():
    data = evidence()
    data[1][0]["contract_checks"] = {}
    data[1][0]["result_sha256"] = digest({k: v for k, v in data[1][0].items() if k != "result_sha256"})
    data[2][0] = data[2][0].model_copy(update={"result_sha256": data[1][0]["result_sha256"]})
    assert gate(*data)["status"] == "fail"


def test_cli_never_overwrites_prior_evidence(monkeypatch, tmp_path):
    path = tmp_path / "result.json"
    path.write_text("prior evidence", encoding="utf-8")
    monkeypatch.setattr("sys.argv", ["acceptance", "--config", str(ROOT / "evaluation/step6_config.json"),
        "--live", "--allow-heldout", "--output", str(path)])
    with pytest.raises(SystemExit) as stopped:
        main()
    assert stopped.value.code == 2 and path.read_text(encoding="utf-8") == "prior evidence"


def assessment_reports(tmp_path):
    config_path = ROOT / "evaluation/step6_config.json"
    suite, suite_path, fairness_path, _ = validate_inputs(CONFIG, config_path)
    hashes = fingerprint(CONFIG, config_path, suite_path)
    import hashlib
    hashes[str(fairness_path)] = hashlib.sha256(fairness_path.read_bytes()).hexdigest()
    dev_path = config_path.parent / CONFIG.development_path
    hashes[str(dev_path)] = hashlib.sha256(dev_path.read_bytes()).hexdigest()
    decision = understanding(request_scope="specific")
    routing = dict(round=1, case_id=suite.cases[0].id, group=suite.cases[0].group, status="success",
        decision=decision.model_dump(mode="json"), score={"all_automated_checks_correct": True})
    row = {k: v for k, v in routing.items() if k != "score"}
    row["result_sha256"] = digest(row)
    paths = {}
    for phase in ("router", "chat", "fairness"):
        report = dict(phase=phase, fingerprints=hashes, configuration=CONFIG.model_dump(mode="json"),
            routing_results=[routing] if phase == "router" else [], results=[row] if phase == "router" else [],
            status="incomplete_provider_exhaustion", elapsed_seconds=1, http_request_count=1,
            http_status_counts={"429": 1}, provider_attempt_count=1, token_usage_status="not_exposed")
        path = tmp_path / f"{phase}.json"
        path.write_text(json.dumps(report), encoding="utf-8")
        paths[phase] = path
    return config_path, paths


def test_assessment_regrades_frozen_decisions_and_keeps_all_eighteen_group_rounds(tmp_path):
    config, paths = assessment_reports(tmp_path)
    result = assess(config, paths)
    assert result["release_acceptance"]["status"] == "incomplete"
    summaries = result["router_group_round_summary"]
    assert len(summaries) == 18
    assert summaries[0]["metrics"]["all_automated_checks_correct"]["correct"] == 0
    assert all(summary["router_target_met"] is None for summary in summaries)


def test_assessment_rejects_different_fingerprints_and_tampered_outputs(tmp_path):
    config, paths = assessment_reports(tmp_path)
    chat = json.loads(paths["chat"].read_text(encoding="utf-8"))
    chat["fingerprints"]["unknown"] = "changed"
    paths["chat"].write_text(json.dumps(chat), encoding="utf-8")
    with pytest.raises(ValueError, match="different sources"):
        assess(config, paths)
    config, paths = assessment_reports(tmp_path)
    router = json.loads(paths["router"].read_text(encoding="utf-8"))
    router["results"][0]["decision"]["request_scope"] = "broad"
    paths["router"].write_text(json.dumps(router), encoding="utf-8")
    with pytest.raises(ValueError, match="modified"):
        assess(config, paths)
