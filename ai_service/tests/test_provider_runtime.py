"""Quota/circuit/deadline/config integration. These tests do not certify an LLM."""

import asyncio
import hashlib
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock
from datetime import datetime, timedelta, timezone
from email.utils import format_datetime
from pathlib import Path

import httpx
import pytest
from pydantic import BaseModel, ConfigDict

from app.core.config import Settings, settings
from app.core.exceptions import AllLLMProvidersExhaustedException, LLMProviderException, RuntimeConfigurationException
from app.infrastructure.llm.cascade_llm_service import CascadeLLMService
from app.infrastructure.llm.gemini_client import GeminiClient
from app.infrastructure.llm.groq_client import GroqClient
from app.infrastructure.llm.quota import QuotaGovernor, duration_seconds, retry_after_seconds
from app.infrastructure.runtime.audit import effective_settings
from app.infrastructure.runtime.documents import ValidatedFile
from app.infrastructure.runtime.execution import REQUEST_DEADLINE, RuntimeExecutionGuard
from app.infrastructure.runtime.schema import InterpretationPolicy, RuntimeDocument

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ValidatedFile(ROOT / "config/ai_runtime.json", RuntimeDocument).read()[0]
POLICY = ValidatedFile(ROOT / "knowledge/interpretation_policy.json", InterpretationPolicy).read()[0]


def test_rate_limit_reset_accepts_millisecond_units():
    assert duration_seconds("1ms") == .001
    assert duration_seconds("2s50ms") == 2.05
    assert duration_seconds("1m2.5s") == 62.5


@pytest.mark.asyncio
async def test_quota_waits_for_near_window_expiry_inside_deadline():
    policy = RUNTIME.providers[-1].quota.model_copy(update={"bucket": "short-window", "tokens_per_window": 1000, "window_seconds": .025})
    governor = QuotaGovernor([policy])
    permit = await governor.reserve(policy.bucket, 700)
    await governor.finish(permit, {"http_status": 200, "usage": {"total_tokens": 600}, "headers": {}})
    started = asyncio.get_running_loop().time()
    assert await governor.wait_reserve(policy.bucket, 700, deadline=started+.2) is not None
    assert asyncio.get_running_loop().time()-started >= .015


@pytest.mark.asyncio
async def test_quota_does_not_wait_past_turn_deadline():
    governor = QuotaGovernor([RUNTIME.providers[-1].quota])
    policy = RUNTIME.providers[-1].quota
    permit = await governor.reserve(policy.bucket, policy.tokens_per_window)
    await governor.finish(permit, {"http_status": 200, "usage": {"total_tokens": policy.tokens_per_window}, "headers": {}})
    assert await governor.wait_reserve(policy.bucket, 1, deadline=asyncio.get_running_loop().time()+.01) is None


@pytest.mark.asyncio
async def test_failed_generation_is_not_assumed_to_have_zero_token_usage():
    policy = RUNTIME.providers[-1].quota
    governor = QuotaGovernor([policy])
    permit = await governor.reserve(policy.bucket, 5000)
    await governor.finish(permit, {"http_status": 400, "error_code": "json_validate_failed", "headers": {}, "usage": {}})
    assert permit.tokens == 5000


@pytest.mark.asyncio
async def test_model_validation_error_is_transient_and_telemetry_omits_error_message():
    called = []
    def respond(request):
        called.append(json.loads(request.content)["model"])
        if len(called) == 1:
            return httpx.Response(400, json={"error": {"code": "json_validate_failed", "type": "invalid_request_error", "message": "secret-message-never-log"}})
        return httpx.Response(200, json=envelope())
    service, http = stack(respond)
    try:
        result = await service.generate_structured("fixture", SmallResult)
        assert result.value == "valid" and len(called) == 2
        assert ("groq", called[0]) not in service._model_open_until
        assert "secret-message-never-log" not in json.dumps(list(service.telemetry))
        assert service.telemetry[0]["error_code"] == "json_validate_failed"
    finally:
        await http.aclose()


class SmallResult(BaseModel):
    model_config = ConfigDict(extra="forbid")
    value: str


def signed(data, schema=RuntimeDocument):
    data["approval"]["content_sha256"] = hashlib.sha256(json.dumps(
        {k: v for k, v in data.items() if k != "approval"}, ensure_ascii=False,
        sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    return schema.model_validate(data)


def runtime(**http_changes):
    data = RUNTIME.model_dump(mode="json")
    data["http"].update(http_changes)
    return signed(data)


def envelope(text='{"value":"valid"}', **usage):
    return {"choices": [{"message": {"content": text}}], "usage": {"total_tokens": 50, **usage}}


def stack(handler, cfg=None):
    cfg = cfg or RUNTIME
    # ชุดนี้ทดสอบโควตา Groq โดยแยกจาก provider อื่นและ credentials จริง
    data = cfg.model_dump(mode="json")
    for profile in data["providers"]:
        if profile["protocol"] == "gemini_json_schema":
            profile.update(enabled=False, disabled_reason="isolated_groq_unit_fixture")
    cfg = signed(data)
    transport = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    client = GroqClient(api_key="fixture-secret", http_client=transport, runtime=cfg)
    return CascadeLLMService(groq_client=client, runtime=cfg), transport


@pytest.mark.asyncio
async def test_invalid_structured_turn_does_not_disable_model_for_other_chats():
    called = []
    def respond(request):
        model = json.loads(request.content)["model"]
        called.append(model)
        text = '{"unexpected":true}' if len(called) == 1 else '{"value":"valid"}'
        return httpx.Response(200, json=envelope(text))
    service, http = stack(respond)
    async with http:
        assert (await service.generate_structured("first fixture", SmallResult)).value == "valid"
        assert (await service.generate_structured("different fixture", SmallResult)).value == "valid"
    assert called == [settings.GROQ_PRIMARY_MODEL, settings.GROQ_FALLBACK_MODEL_1, settings.GROQ_PRIMARY_MODEL]


@pytest.mark.asyncio
async def test_startup_permission_probe_prevents_cold_provider_blocking_five_chats():
    counts = {"gemini": 0, "groq": 0}
    async def respond(request):
        payload = json.loads(request.content)
        provider = "gemini" if "contents" in payload else "groq"
        counts[provider] += 1
        await asyncio.sleep(.25 if counts[provider] == 1 else .01)
        if provider == "gemini":
            return httpx.Response(200, json={"candidates": [{"content": {"parts": [{"text": '{"value":"valid"}'}]}}], "usageMetadata": {"totalTokenCount": 50}})
        return httpx.Response(200, json=envelope())
    transport = httpx.AsyncClient(transport=httpx.MockTransport(respond))
    service = CascadeLLMService(gemini_client=GeminiClient(api_key="fixture", http_client=transport),
                               groq_client=GroqClient(api_key="fixture", http_client=transport))
    # This assertion isolates a cold HTTP permission probe, not Windows disk
    # scheduling. Persistent ledger restart/concurrency is covered separately.
    service.governor = QuotaGovernor([state.policy for state in service.governor._buckets.values()])
    try:
        await service.start()
        results = await asyncio.wait_for(asyncio.gather(*(service.generate_structured("fixture", SmallResult) for _ in range(5))), .15)
        assert all(r.value == "valid" for r in results)
    finally:
        await service.aclose()
        await transport.aclose()


@pytest.mark.asyncio
async def test_primary_token_limit_does_not_block_independent_backup_model():
    called = []
    def respond(request):
        called.append(json.loads(request.content)["model"])
        return httpx.Response(200, json=envelope(total_tokens=7500 if len(called) == 1 else 50))
    service, http = stack(respond)
    try:
        await service.generate_structured("fixture", SmallResult)
        result = await service.generate_structured("fixture", SmallResult)
        assert result.value == "valid"
        assert len(called) == 2 and called[0] != called[1]
    finally:
        await http.aclose()


@pytest.mark.asyncio
async def test_model_aliases_share_one_admission_balance():
    called = []
    def respond(request):
        called.append(json.loads(request.content)["model"])
        return httpx.Response(200, json=envelope(total_tokens=7500 if len(called) == 1 else 50))
    cfg = settings.model_copy(update={"GROQ_FALLBACK_MODEL_1": settings.GROQ_PRIMARY_MODEL})
    transport = httpx.AsyncClient(transport=httpx.MockTransport(respond))
    client = GroqClient(api_key="fixture", http_client=transport, runtime=RUNTIME, configuration=cfg)
    service = CascadeLLMService(gemini_client=GeminiClient(api_key="", runtime=RUNTIME, configuration=cfg),
                               groq_client=client, runtime=RUNTIME, configuration=cfg)
    try:
        await service.generate_structured("fixture", SmallResult)
        await service.generate_structured("fixture", SmallResult)
        assert called == [cfg.GROQ_PRIMARY_MODEL, cfg.GROQ_FALLBACK_MODEL_2]
    finally:
        await transport.aclose()


@pytest.mark.asyncio
async def test_model_scoped_rate_limit_can_use_one_healthy_backup():
    called = []
    def respond(request):
        model = json.loads(request.content)["model"]
        called.append(model)
        if model == settings.GROQ_PRIMARY_MODEL:
            return httpx.Response(429, headers={"Retry-After": "120"})
        return httpx.Response(200, json=envelope())
    service, http = stack(respond)
    try:
        await service.generate_structured("fixture", SmallResult)
        await service.generate_structured("fixture", SmallResult)
        assert called == [settings.GROQ_PRIMARY_MODEL, settings.GROQ_FALLBACK_MODEL_1, settings.GROQ_FALLBACK_MODEL_1]
    finally:
        await http.aclose()


def test_conflicting_policies_for_same_effective_model_are_rejected():
    data = RUNTIME.model_dump(mode="json")
    next(p for p in data["providers"] if p["id"] == "groq-fallback-1")["quota"]["tokens_per_window"] = 4000
    cfg = settings.model_copy(update={"GROQ_FALLBACK_MODEL_1": settings.GROQ_PRIMARY_MODEL})
    with pytest.raises(ValueError, match="conflicting"):
        CascadeLLMService(runtime=signed(data), configuration=cfg)


@pytest.mark.asyncio
async def test_busy_primary_does_not_consume_backup_deadline_waiting_for_quota():
    started, release = asyncio.Event(), asyncio.Event()
    called = []
    async def respond(request):
        model = json.loads(request.content)["model"]
        called.append(model)
        if model == settings.GROQ_PRIMARY_MODEL:
            started.set()
            await release.wait()
        return httpx.Response(200, json=envelope())
    data = RUNTIME.model_dump(mode="json")
    next(p for p in data["providers"] if p["id"] == "groq-primary")["quota"]["tokens_per_window"] = 2000
    service, http = stack(respond, signed(data))
    service._permission_confirmed.add("groq")
    first = asyncio.create_task(service.generate_structured("fixture", SmallResult))
    await started.wait()
    try:
        result = await asyncio.wait_for(service.generate_structured("fixture", SmallResult), .5)
        assert result.value == "valid"
        assert called == [settings.GROQ_PRIMARY_MODEL, settings.GROQ_FALLBACK_MODEL_1]
    finally:
        release.set()
        await first
        await http.aclose()


def write(path, document):
    path.write_text(document.model_dump_json(indent=2), encoding="utf-8")


def test_approved_json_is_the_settings_default():
    config = Settings(_env_file=None)
    assert config.STRUCTURED_MAX_OUTPUT_TOKENS == RUNTIME.limits.output_tokens
    assert config.INTENT_CONTEXT_MAX_MESSAGES == RUNTIME.limits.messages
    assert config.INTERPRETATION_POLICY_PATH == ROOT / RUNTIME.interpretation_policy_path


def test_precedence_and_safe_audit(tmp_path, monkeypatch):
    dotenv = tmp_path / "settings.env"
    dotenv.write_text('INTENT_CONTEXT_MAX_MESSAGES=7\nGROQ_API_KEY=private-dotenv-key\n', encoding="utf-8")
    monkeypatch.setenv("INTENT_CONTEXT_MAX_MESSAGES", "8")
    cfg = Settings(_env_file=dotenv, INTENT_CONTEXT_MAX_MESSAGES=9)
    assert cfg.INTENT_CONTEXT_MAX_MESSAGES == 9
    audit = effective_settings(cfg, RUNTIME)
    assert audit["INTENT_CONTEXT_MAX_MESSAGES"]["source"] == "explicit_settings"
    assert "private-dotenv-key" not in json.dumps(audit)
    assert "GROQ_API_KEY" not in audit
    cfg = Settings(_env_file=dotenv)
    assert cfg.INTENT_CONTEXT_MAX_MESSAGES == 8
    assert effective_settings(cfg, RUNTIME)["INTENT_CONTEXT_MAX_MESSAGES"]["source"] == "environment"
    monkeypatch.delenv("INTENT_CONTEXT_MAX_MESSAGES")
    cfg = Settings(_env_file=dotenv)
    assert cfg.INTENT_CONTEXT_MAX_MESSAGES == 7
    assert effective_settings(cfg, RUNTIME)["INTENT_CONTEXT_MAX_MESSAGES"]["source"] == "dotenv"


def test_existing_file_settings_override_json(tmp_path):
    (tmp_path / "INTENT_CONTEXT_MAX_MESSAGES").write_text("6", encoding="utf-8")
    cfg = Settings(_env_file=None, _secrets_dir=tmp_path)
    assert cfg.INTENT_CONTEXT_MAX_MESSAGES == 6
    assert effective_settings(cfg, RUNTIME)["INTENT_CONTEXT_MAX_MESSAGES"]["source"] == "file_secret_settings"


@pytest.mark.parametrize("change", ["hash", "duplicate", "revoke", "missing"])
def test_runtime_snapshot_never_falls_back_to_stale_document(tmp_path, change):
    path = tmp_path / "runtime.json"
    write(path, RUNTIME)
    reader = ValidatedFile(path, RuntimeDocument)
    original, fingerprint = reader.read()
    assert reader.read()[0] is original
    if change == "missing":
        path.unlink()
    else:
        data = RUNTIME.model_dump(mode="json")
        if change == "revoke":
            data["production_enabled"] = False
        else:
            data["limits"]["questions"] = 1
        text = json.dumps(data)
        if change == "duplicate":
            text = text.replace('"questions": 1', '"questions": 1,"questions": 3')
        path.write_text(text, encoding="utf-8")
    with pytest.raises(RuntimeConfigurationException):
        reader.read()
    write(path, RUNTIME)
    restored, _ = reader.read()
    assert restored == original and restored is not original


@pytest.mark.parametrize("header,expected", [("7.66s", 7.66), ("2m59.56s", 179.56), ("1h2m3s", 3723), ("garbage", None), ("-1s", None)])
def test_protocol_duration_parser(header, expected):
    assert duration_seconds(header) == expected


def test_retry_after_seconds_date_and_invalid_values():
    assert retry_after_seconds("21", 60) == 21
    assert retry_after_seconds("nan", 60) == 60
    assert retry_after_seconds("-1", 60) == 60
    date = format_datetime(datetime.now(timezone.utc) + timedelta(seconds=30), usegmt=True)
    assert 28 <= retry_after_seconds(date, 60) <= 30


@pytest.mark.asyncio
async def test_concurrent_admission_cannot_overspend_shared_bucket():
    cfg = next(p.quota for p in RUNTIME.providers if p.quota.bucket == "groq")
    now = [0.0]
    governor = QuotaGovernor([cfg], clock=lambda: now[0])
    permits = await asyncio.gather(*(governor.reserve("groq", 3000) for _ in range(5)))
    assert sum(p is not None for p in permits) == 2
    now[0] = cfg.window_seconds
    assert await governor.reserve("groq", 3000) is not None


@pytest.mark.asyncio
async def test_unknown_usage_cancellation_remains_reserved():
    cfg = next(p.quota for p in RUNTIME.providers if p.quota.bucket == "groq")
    governor = QuotaGovernor([cfg])
    permit = await governor.reserve("groq", cfg.tokens_per_window)
    await governor.finish(permit, None)
    assert await governor.reserve("groq", 1) is None


@pytest.mark.asyncio
async def test_actual_usage_reconciles_reservation_and_external_headers_limit_admission():
    cfg = next(p.quota for p in RUNTIME.providers if p.quota.bucket == "groq")
    governor = QuotaGovernor([cfg])
    permit = await governor.reserve("groq", 6000)
    await governor.finish(permit, {"http_status": 200, "usage": {"total_tokens": 100}, "headers": {}})
    second = await governor.reserve("groq", 6000)
    assert second is not None
    await governor.finish(second, {"http_status": 200, "usage": {"total_tokens": 100},
        "headers": {"x-ratelimit-remaining-tokens": "0", "x-ratelimit-reset-tokens": "1m0s"}})
    assert await governor.reserve("groq", 1) is None


@pytest.mark.asyncio
async def test_waiting_admission_refunds_unused_estimate_and_preserves_server_floor():
    cfg = next(p.quota for p in RUNTIME.providers if p.quota.bucket == "groq")
    governor = QuotaGovernor([cfg])
    first = await governor.reserve("groq", 6000)
    waiter = asyncio.create_task(governor.wait_reserve("groq", 6000))
    await asyncio.sleep(0)
    assert not waiter.done()
    await governor.finish(first, {"http_status": 200, "usage": {"total_tokens": 1000},
        "headers": {"x-ratelimit-remaining-tokens": "7000", "x-ratelimit-reset-tokens": "1m0s"}})
    second = await asyncio.wait_for(waiter, 1)
    assert second is not None
    await governor.finish(second, {"http_status": 200, "usage": {"total_tokens": 1000},
        "headers": {"x-ratelimit-remaining-tokens": "6000", "x-ratelimit-reset-tokens": "1m0s"}})
    assert await governor.reserve("groq", 6000) is not None


@pytest.mark.asyncio
async def test_waiting_admission_cancellation_does_not_create_a_reservation():
    cfg = next(p.quota for p in RUNTIME.providers if p.quota.bucket == "groq")
    governor = QuotaGovernor([cfg])
    first = await governor.reserve("groq", 7000)
    waiter = asyncio.create_task(governor.wait_reserve("groq", 7000))
    await asyncio.sleep(0)
    waiter.cancel()
    with pytest.raises(asyncio.CancelledError):
        await waiter
    assert len(governor._buckets["groq"].records) == 1
    await governor.finish(first, {"http_status": 200, "usage": {"total_tokens": 100}, "headers": {}})
    assert await governor.reserve("groq", 7000) is not None


@pytest.mark.asyncio
async def test_rate_limit_cooldown_is_shared_across_calls_and_models():
    calls = []
    def respond(request):
        calls.append(request)
        return httpx.Response(429, text="private provider diagnostics", headers={"Retry-After": "120"})
    data = RUNTIME.model_dump(mode="json")
    for profile in data["providers"]:
        profile["quota"]["scope"] = "provider"
    service, http = stack(respond, signed(data))
    async with http:
        for _ in range(2):
            with pytest.raises(AllLLMProvidersExhaustedException) as failure:
                await service.generate_structured("input", SmallResult)
            assert failure.value.code == "providers_rate_limited"
            assert failure.value.retry_after > 100
    assert len(calls) == 1
    assert "fixture-secret" not in json.dumps(list(service.telemetry))
    assert "private provider diagnostics" not in str(failure.value)


@pytest.mark.asyncio
async def test_first_wave_permission_denied_does_not_repeat_for_every_chat():
    calls = []
    async def respond(request):
        calls.append(request)
        await asyncio.sleep(.01)
        return httpx.Response(403, json={"error": {"message": "private diagnostic"}})
    service, http = stack(respond)
    async with http:
        results = await asyncio.gather(*(service.generate_structured("input", SmallResult) for _ in range(5)), return_exceptions=True)
    assert all(isinstance(r, AllLLMProvidersExhaustedException) for r in results)
    assert len(calls) == 1


@pytest.mark.asyncio
async def test_disabled_gemini_gets_no_http_request():
    called = []
    def respond(request):
        called.append(str(request.url))
        return httpx.Response(200, json=envelope())
    service, http = stack(respond)
    async with http:
        assert (await service.generate_structured("input", SmallResult)).value == "valid"
    assert len(called) == 1 and all("groq" in u for u in called)


@pytest.mark.asyncio
async def test_one_failover_only_and_recovery_is_not_partial_output():
    models = []
    def respond(request):
        models.append(json.loads(request.content)["model"])
        return httpx.Response(200, json=envelope('{"wrong":1}'))
    service, http = stack(respond)
    async with http:
        with pytest.raises(AllLLMProvidersExhaustedException):
            await service.generate_structured("input", SmallResult)
    assert len(models) == 2
    assert models == [settings.GROQ_PRIMARY_MODEL, settings.GROQ_FALLBACK_MODEL_1]


@pytest.mark.asyncio
async def test_five_healthy_requests_pool_limit_and_task_local_usage():
    active, peak = 0, 0
    all_entered = asyncio.Event()
    async def respond(request):
        nonlocal active, peak
        active += 1
        peak = max(peak, active)
        payload = json.loads(request.content)
        value = payload["messages"][-1]["content"]
        if active == 5:
            all_entered.set()
        await asyncio.wait_for(all_entered.wait(), 1)
        active -= 1
        return httpx.Response(200, json=envelope(json.dumps({"value": value}), prompt_tokens=int(value)))
    service, http = stack(respond)
    service._permission_confirmed.add("groq")  # healthy warm provider; no cold permission serialization
    async with http:
        results = await asyncio.gather(*(service.generate_structured(str(i), SmallResult) for i in range(5)))
    assert [r.value for r in results] == [str(i) for i in range(5)]
    assert 3 <= peak <= RUNTIME.load.concurrent_requests
    assert sorted(r["usage"]["prompt_tokens"] for r in service.telemetry if r["status"] == "success") == list(range(5))


@pytest.mark.asyncio
async def test_call_deadline_cancels_transport_and_releases_permission_and_pool_slots():
    canceled = []
    async def respond(request):
        try:
            await asyncio.sleep(1)
        except asyncio.CancelledError:
            canceled.append(True)
            raise
    service, http = stack(respond, runtime(logical_call_deadline_seconds=.2))
    # Isolate cancellation from filesystem scheduling, which has its own tests.
    service.governor = QuotaGovernor([b.policy for b in service.governor._buckets.values()])
    async with http:
        with pytest.raises(AllLLMProvidersExhaustedException) as failure:
            await service.generate_structured("input", SmallResult)
        assert failure.value.code == "deadline_exceeded"
    assert canceled == [True, True]  # both bounded HTTP attempts, one logical call
    assert not service._permission_locks["groq"].locked()
    assert service.telemetry[-1]["http_attempts"] == 1


@pytest.mark.asyncio
async def test_upstream_cancellation_propagates():
    entered = asyncio.Event()
    async def respond(request):
        entered.set()
        await asyncio.sleep(1)
    service, http = stack(respond)
    async with http:
        task = asyncio.create_task(service.generate_structured("input", SmallResult))
        await entered.wait()
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
    assert not service._permission_locks["groq"].locked()


@pytest.mark.asyncio
async def test_turn_hash_guard_checks_again_before_return(tmp_path):
    r, p = tmp_path / "runtime.json", tmp_path / "policy.json"
    write(r, RUNTIME)
    write(p, POLICY)
    guard = RuntimeExecutionGuard(r, p)
    with pytest.raises(RuntimeConfigurationException):
        async with guard.turn():
            data = POLICY.model_dump(mode="json")
            data["context"] = ["changed policy"]
            write(p, signed(data, InterpretationPolicy))
    assert REQUEST_DEADLINE.get() is None


@pytest.mark.asyncio
async def test_turn_deadlines_are_task_local_and_include_routing_time(tmp_path):
    r, p = tmp_path / "runtime.json", tmp_path / "policy.json"
    write(r, RUNTIME)
    write(p, POLICY)
    guard = RuntimeExecutionGuard(r, p)
    ready = asyncio.Event()
    deadlines = {}
    async def task(flow):
        if flow == "equipment":
            await ready.wait()
            await asyncio.sleep(.02)
        async with guard.turn():
            initial_deadline = REQUEST_DEADLINE.get()
            await asyncio.sleep(.02)
            guard.select_flow(flow)
            deadlines[flow] = REQUEST_DEADLINE.get()
            assert deadlines[flow] == initial_deadline
            if flow == "general":
                ready.set()
            else:
                await ready.wait()
            assert REQUEST_DEADLINE.get() == deadlines[flow]
    await asyncio.gather(task("general"), task("equipment"))
    assert deadlines["equipment"] > deadlines["general"]
    assert deadlines["equipment"] - deadlines["general"] < 1
    assert REQUEST_DEADLINE.get() is None


@pytest.mark.asyncio
async def test_native_duplicate_key_rejection_can_use_one_fallback():
    calls = []
    def respond(request):
        calls.append(request)
        raw = '{"value":"first","value":"second"}' if len(calls) == 1 else '{"value":"valid"}'
        return httpx.Response(200, json=envelope(raw))
    service, http = stack(respond)
    async with http:
        assert (await service.generate_structured("input", SmallResult)).value == "valid"
    assert len(calls) == 2


@pytest.mark.asyncio
async def test_oversized_request_is_distinct_from_a_temporary_quota_limit():
    calls = []
    def respond(request):
        calls.append(request)
        return httpx.Response(200, json=envelope())
    service, http = stack(respond)
    async with http:
        with pytest.raises(AllLLMProvidersExhaustedException) as failure:
            await service.generate_structured("fixture " * 10000, SmallResult)
    assert failure.value.code == "request_budget_exceeded"
    assert failure.value.retry_after is None
    assert calls == []
    assert all(row["estimated_tokens"] > RUNTIME.providers[-1].quota.tokens_per_window for row in service.telemetry)


@pytest.mark.asyncio
async def test_owned_transport_is_reused_and_closed(monkeypatch):
    original = httpx.AsyncClient
    created = []
    def create(*args, **kwargs):
        client = original(transport=httpx.MockTransport(lambda request: httpx.Response(200, json=envelope())), **kwargs)
        created.append(client)
        return client
    monkeypatch.setattr(httpx, "AsyncClient", create)
    service = CascadeLLMService(gemini_client=GeminiClient(api_key=""), groq_client=GroqClient(api_key="fixture"))
    await service.start()
    for _ in range(3):
        await service.generate_structured("input", SmallResult)
    assert len(created) == 2  # One owned pool for each configured provider.
    await service.aclose()
    assert all(client.is_closed for client in created)


@pytest.mark.asyncio
@pytest.mark.parametrize("error", [
    RuntimeConfigurationException("runtime_document_invalid"),
    AllLLMProvidersExhaustedException(code="providers_rate_limited", retry_after=60),
    AllLLMProvidersExhaustedException(code="deadline_exceeded"),
])
async def test_runtime_errors_have_safe_json_and_sse_codes(monkeypatch, error):
    from fastapi import HTTPException
    from app.application.dtos.chat_dto import ChatRequestDTO
    from app.interface.api.v1.endpoints import chat
    async def failing_stream(request):
        raise error
        yield "unreachable"
    monkeypatch.setattr(chat.settings, "INTERNAL_SERVICE_KEY", "")
    monkeypatch.setattr(chat.container, "process_chat_message_use_case", SimpleNamespace(
        execute=AsyncMock(side_effect=error), execute_stream=failing_stream))
    request = ChatRequestDTO(message="fixture")
    with pytest.raises(HTTPException) as failure:
        await chat.chat_endpoint(request)
    assert failure.value.status_code == 503
    assert failure.value.detail == {"error_code": error.code}
    response = await chat.chat_stream_endpoint(request)
    body = b"".join([part async for part in response.body_iterator]).decode()
    assert error.code in body
    if getattr(error, "retry_after", None) is not None:
        assert failure.value.headers["Retry-After"] == "60"
        assert '"retry_after_seconds": 60' in body
