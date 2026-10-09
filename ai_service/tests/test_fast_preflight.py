"""Draft contract and probe integrity tests, not model accuracy tests."""

import json
from pathlib import Path

import httpx
import pytest
from pydantic import ValidationError

from evaluation.fast_contract import (
    CertificationProtocol, InterpretationPolicy, LabelReview, ProbeTurn,
    RuntimeDraft, load_document, validate_family_splits,
)
from evaluation.fast_preflight import (
    probe, prompt_for, read_inputs, request_for, structural_checks,
)
from evaluation.export_fast_schemas import SCHEMAS

ROOT = Path(__file__).resolve().parents[1]
INPUTS = read_inputs(ROOT / "evaluation/fast_preflight_config.json")
CONFIG, RUNTIME, POLICY, LABELS, KNOWLEDGE = INPUTS
CASE = next(c for c in LABELS.cases if c.id == "fast-app-1")
PROFILE = next(p for p in RUNTIME.providers if p.protocol == "groq_json_schema")


def plan():
    return ProbeTurn(user_goal="อธิบายภาพรวมแอป", request_scope="broad", information_sufficient=True,
                     next_action="answer", known_facts=[], missing_dimensions=[], reference_resolution="ไม่มีสิ่งอ้างถึง",
                     topic_changed=False, approved_article_ids=["platform.overview"], unverified_article_ids=[], questions=[])


def test_all_drafts_and_generated_schemas_are_consistent():
    load_document(ROOT / "evaluation/fast_certification_protocol.json", CertificationProtocol)
    assert len(LABELS.cases) == 25
    assert all(not d.production_enabled for d in (RUNTIME, POLICY, LABELS))
    assert sum(a.status == "approved" for a in KNOWLEDGE.articles) == 12
    assert sum(a.status == "unverified" for a in KNOWLEDGE.articles) == 10
    for name, schema in SCHEMAS.items():
        assert json.loads((ROOT / "config/schemas" / f"{name}.schema.json").read_text(encoding="utf-8")) == schema.model_json_schema()


def test_duplicate_nested_json_properties_rejected(tmp_path):
    path = tmp_path / "policy.json"
    path.write_text('{"scope":{"broad":"one","broad":"two"}}', encoding="utf-8")
    with pytest.raises(ValueError, match="Duplicate"):
        load_document(path, InterpretationPolicy)


@pytest.mark.parametrize("url", ["http://example.test/api", "https://key@example.test/api", "https://example.test/api?key=secret"])
def test_credential_or_insecure_endpoint_rejected(url):
    data = RUNTIME.model_dump(mode="json")
    data["providers"][0]["endpoint"] = url
    with pytest.raises(ValidationError):
        RuntimeDraft.model_validate(data)


def test_draft_cannot_be_accidentally_activated():
    data = RUNTIME.model_dump()
    data["production_enabled"] = True
    with pytest.raises(ValidationError):
        RuntimeDraft.model_validate(data)


def test_deadline_and_question_limits_rejected():
    data = RUNTIME.model_dump()
    data["general"]["hard_deadline_seconds"] = 1
    with pytest.raises(ValidationError):
        RuntimeDraft.model_validate(data)
    data = RUNTIME.model_dump()
    data["limits"]["questions"] = 4
    with pytest.raises(ValidationError):
        RuntimeDraft.model_validate(data)


def test_not_applicable_cannot_remove_a_question_from_primary_labels():
    data = LABELS.model_dump()
    data["cases"][0]["expected"]["request_scope"] = "not_applicable"
    with pytest.raises(ValidationError):
        LabelReview.model_validate(data)


def test_paraphrase_family_leakage_rejected():
    with pytest.raises(ValueError, match="family"):
        validate_family_splits(LABELS, LABELS)


def test_renaming_family_cannot_hide_exact_input_leakage():
    data = LABELS.model_dump()
    for case in data["cases"]:
        case["id"] = "new-" + case["id"]
        case["family_id"] = "new-" + case["family_id"]
    with pytest.raises(ValueError, match="exact inputs"):
        validate_family_splits(LABELS, LabelReview.model_validate(data))


def test_protocol_cannot_average_metrics_or_relax_coverage():
    data = load_document(ROOT / "evaluation/fast_certification_protocol.json", CertificationProtocol).model_dump()
    data["metrics"] = ["request_scope", "request_scope"]
    with pytest.raises(ValidationError):
        CertificationProtocol.model_validate(data)
    data["metrics"] = ["request_scope", "next_action"]
    data["minimum_cases_per_group"] = 10
    with pytest.raises(ValidationError):
        CertificationProtocol.model_validate(data)


def test_prompts_never_include_expected_labels_or_rationales():
    _, prompt = prompt_for(CONFIG, RUNTIME, POLICY, KNOWLEDGE, CASE)
    data = json.loads(prompt)
    assert "expected" not in data and "rationale" not in data
    assert data["current"]["content"] == CASE.message
    assert all(set(a) == {"id", "title", "status"} for a in data["knowledge_index"])


def test_native_schema_payload_and_safe_groq_auth():
    url, headers, payload = request_for(PROFILE, "fixture-model", "secret", "instruction", "input", 100, .1)
    assert "secret" not in url
    assert headers["Authorization"] == "Bearer secret"
    assert payload["response_format"]["type"] == "json_schema"
    assert payload["response_format"]["json_schema"]["strict"] is True
    assert payload["reasoning_effort"] == PROFILE.reasoning_effort


def test_unknown_article_and_invalid_provenance_rejected():
    data = plan().model_dump()
    data["approved_article_ids"] = ["fabricated"]
    data["known_facts"] = [{"dimension": "budget", "value": "200", "source_message_ids": ["other-session"]}]
    checks = structural_checks(ProbeTurn.model_validate(data), CASE, RUNTIME, KNOWLEDGE)
    assert not checks["approved_ids"] and not checks["provenance"]


@pytest.mark.asyncio
@pytest.mark.parametrize("status", [403, 429, 500])
async def test_http_failure_is_not_retried_or_leaked(status):
    count = 0
    def handler(request):
        nonlocal count
        count += 1
        return httpx.Response(status, text="SECRET_KEY provider diagnostics", headers={"retry-after": "60", "private": "SECRET_KEY"})
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        row = await probe(client, PROFILE, "fixture-model", "SECRET_KEY", CASE, INPUTS, "batch", 100)
    assert count == 1 and row["http_attempts"] == 1
    assert row["status"] == "http_error" and not row["within_general_provider_target"]
    assert "SECRET_KEY" not in json.dumps(row)
    assert row["rate_limit_headers"] == {"retry-after": "60"}


@pytest.mark.asyncio
async def test_http_200_malformed_output_never_counts_as_success():
    response = {"choices": [{"message": {"content": '{"wrong":1}'}}], "usage": {"prompt_tokens": 50, "completion_tokens": 4}}
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda request: httpx.Response(200, json=response))) as client:
        row = await probe(client, PROFILE, "fixture-model", "secret", CASE, INPUTS, "batch", 100)
    assert row["status"] == "invalid_structured_output"
    assert row["usage"]["prompt_tokens"] == 50
    assert not row["within_general_provider_target"]


@pytest.mark.asyncio
async def test_duplicate_llm_properties_do_not_silently_override():
    raw = plan().model_dump_json().replace('"next_action":"answer"', '"next_action":"clarify","next_action":"answer"')
    response = {"choices": [{"message": {"content": raw}}]}
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda request: httpx.Response(200, json=response))) as client:
        row = await probe(client, PROFILE, "fixture-model", "secret", CASE, INPUTS, "batch", 100)
    assert row["status"] == "invalid_structured_output"


@pytest.mark.asyncio
async def test_valid_native_output_keeps_independent_label_metrics():
    data = plan().model_dump()
    data["request_scope"] = "specific"
    response = {"choices": [{"message": {"content": json.dumps(data)}}], "usage": {"prompt_tokens": 50, "completion_tokens": 100}}
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda request: httpx.Response(200, json=response))) as client:
        row = await probe(client, PROFILE, "fixture-model", "secret", CASE, INPUTS, "batch", 100)
    assert row["status"] == "success"
    assert row["draft_label_matches"] == {"scope": False, "action": True, "sufficiency": True}
    assert not row["within_general_provider_target"]
