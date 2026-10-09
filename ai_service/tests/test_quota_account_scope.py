"""Account isolation uses real admission and review with simulated HTTP only."""

import asyncio
import json
import multiprocessing
import time
from pathlib import Path
from unittest.mock import AsyncMock
from uuid import uuid4

import httpx
import pytest

from app.application.dtos.chat_dto import ChatRequestDTO
from app.application.services.conversation_context import ContextLimits
from app.application.use_cases.plan_chat_turn_use_case import PlanChatTurnUseCase
from app.core.config import Settings
from app.core.exceptions import AllLLMProvidersExhaustedException
from app.domain.entities.catalog_guidance import GuidancePolicy
from app.domain.entities.response_review import ResponseChecks
from app.infrastructure.knowledge.file_knowledge_repository import FileKnowledgeRepository
from app.infrastructure.llm.cascade_llm_service import CascadeLLMService
from app.infrastructure.llm.groq_client import GroqClient
from app.infrastructure.runtime.execution import RuntimeExecutionGuard
from test_provider_runtime import RUNTIME


ROOT = Path(__file__).resolve().parents[1]


def configuration(path, groq_scope=None, **changes):
    return Settings(
        _env_file=None,
        AI_QUOTA_LEDGER_PATH=path,
        GROQ_API_KEY="fixture-groq",
        GROQ_QUOTA_ACCOUNT_ID=groq_scope,
        **changes,
    )


def cascade(cfg, http):
    return CascadeLLMService(
        configuration=cfg,
        runtime=RUNTIME,
        groq_client=GroqClient(configuration=cfg, http_client=http, runtime=RUNTIME),
    )


def bucket(service, provider="groq", model=None):
    model = model or getattr(service.configuration, f"{provider.upper()}_PRIMARY_MODEL")
    return service._quota_bucket(service._profile(provider, model), provider, model)


def seed_legacy(service):
    # จำลองยอดบัญชีเก่าในไฟล์ชั่วคราว โดยไม่อ่านหรือแก้ ledger ที่ใช้งานจริง
    rows = {}
    for name, state in service.governor._buckets.items():
        rows[name] = {
            "policy": state.policy.model_dump(mode="json"),
            "records": [{"bucket": name, "started": time.time() - 120,
                "tokens": state.policy.tokens_per_day - 1000, "pending": False,
                "sent": True, "reservation_id": uuid4().hex}],
            "cooldown_until": 0.0, "observed_tokens": None,
            "observed_requests": None, "tokens_reset": 0.0,
            "requests_reset": 0.0, "token_limit": None,
            "request_limit": None, "cooldown_reported": True,
        }
    service.governor.path.write_text(json.dumps({"version": 1, "buckets": rows}), encoding="utf-8")
    return rows


@pytest.mark.parametrize("field", ["GROQ_QUOTA_ACCOUNT_ID"])
@pytest.mark.parametrize("value,expected", [(None, None), ("", None), ("   ", None), (" project-a ", "project-a")])
def test_scope_settings_are_optional_and_trimmed(tmp_path, field, value, expected):
    cfg = configuration(tmp_path / "ledger.json").model_dump()
    cfg[field] = value
    assert getattr(Settings(_env_file=None, **cfg), field) == expected


@pytest.mark.parametrize("provider", ["groq"])
@pytest.mark.asyncio
async def test_new_account_isolated_and_legacy_rows_preserved(tmp_path, provider):
    path = tmp_path / "ledger.json"
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(500))) as http:
        old = cascade(configuration(path), http)
        rows = seed_legacy(old)
        new = cascade(configuration(path, groq_scope="new-org"), http)
        try:
            assert await old.governor.reserve(bucket(old, provider), 2000) is None
            assert await new.governor.reserve(bucket(new, provider), 2000) is not None
            saved = json.loads(path.read_text(encoding="utf-8"))["buckets"]
            assert all(saved[name] == row for name, row in rows.items())
            assert json.loads(bucket(new, provider)) == ["account", provider,
                "new-org", *json.loads(bucket(old, provider))]
        finally:
            await old.aclose()
            await new.aclose()


@pytest.mark.parametrize("provider", ["groq"])
@pytest.mark.asyncio
async def test_same_account_key_rotation_and_restart_keep_balance(tmp_path, provider):
    path = tmp_path / "ledger.json"
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(500))) as http:
        first = cascade(configuration(path, "org"), http)
        permit = await first.governor.reserve(bucket(first, provider), 5000)
        assert permit is not None
        await first.governor.mark_sent(permit)
        await first.governor.finish(permit, {"http_status": 200, "usage": {"total_tokens": 5000}, "headers": {}})
        await first.aclose()
        cfg = configuration(path, "org").model_dump()
        cfg[f"{provider.upper()}_API_KEY"] = "rotated-fixture-key"
        restarted = cascade(Settings(_env_file=None, **cfg), http)
        try:
            assert await restarted.governor.reserve(bucket(restarted, provider), 4000) is None
            assert await restarted.governor.reserve(bucket(restarted, provider), 3000) is not None
        finally:
            await restarted.aclose()


@pytest.mark.asyncio
async def test_model_aliases_share_scoped_balance(tmp_path):
    cfg = configuration(tmp_path / "ledger.json", groq_scope="org")
    cfg.GROQ_FALLBACK_MODEL_1 = cfg.GROQ_PRIMARY_MODEL
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(500))) as http:
        service = cascade(cfg, http)
        try:
            profiles = [p for p in service.runtime.providers if p.protocol == "groq_json_schema"]
            names = [service._quota_bucket(p, "groq", getattr(cfg, p.model_setting)) for p in profiles[:2]]
            assert names[0] == names[1]
            assert await service.governor.reserve(names[0], 5000) is not None
            assert await service.governor.reserve(names[1], 4000) is None
        finally:
            await service.aclose()


def reserve_worker(path, output):
    async def reserve():
        async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(500))) as http:
            service = cascade(configuration(path, groq_scope="shared-org"), http)
            try:
                output.put(await service.governor.reserve(bucket(service), 4500) is not None)
            finally:
                await service.aclose()
    asyncio.run(reserve())


def test_scoped_balance_is_shared_between_processes(tmp_path):
    context = multiprocessing.get_context("spawn")
    output = context.Queue()
    workers = [context.Process(target=reserve_worker, args=(tmp_path / "ledger.json", output)) for _ in range(2)]
    try:
        for worker in workers:
            worker.start()
        for worker in workers:
            worker.join(10)
            assert worker.exitcode == 0
        assert sorted(output.get(timeout=1) for _ in workers) == [False, True]
    finally:
        for worker in workers:
            if worker.is_alive():
                worker.terminate()
                worker.join(2)
        output.close()


def native_reply(request, calls):
    payload = json.loads(request.content)
    schema = payload.get("response_format", {}).get("json_schema", {}).get("schema", {})
    if "assessments" in schema.get("properties", {}):
        phase = "review"
        result = {"assessments": {name: {"reason": "Simulated assessment of /response.",
            "field_paths": ["/response"], "passed": True} for name in ResponseChecks.model_fields},
            "issues": [], "reviewed_surface_groups": ["response"]}
        from app.domain.entities.response_review import NativeResponseReview
        result = NativeResponseReview.model_validate(result).model_dump(mode="json", by_alias=True)
    elif schema:
        phase = "planning"
        from test_fast_turn import turn
        from native_turn_fixture import native_fixture
        from test_request_understanding import understanding
        social = understanding(intent='general_greeting', catalog_operation='none', request_scope='not_applicable', information_sufficient=True, next_action='answer', missing_slots=[], user_goal='ทักทาย')
        plan = turn(understanding=social, knowledge_ids=[], response_mode='conversation', message='สวัสดี มีอะไรให้ช่วยบ้าง')
        value = native_fixture(plan, message='สวัสดี')
        # Apply native aliases and required defaults exactly as the adapter expects.
        from app.domain.entities.turn_plan import NativeTurnPlan
        result = NativeTurnPlan.model_validate(value).model_dump(mode='json', by_alias=True)
    else:
        phase, result = "startup_permission_probe", "fixture"
    calls.append((phase, payload["model"]))
    text = json.dumps(result, ensure_ascii=False) if isinstance(result, dict) else result
    return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {"content": text}}], "usage": {"total_tokens": 50}})


def planner(service):
    guard = RuntimeExecutionGuard(ROOT / "config/ai_runtime.json", ROOT / "knowledge/interpretation_policy.json")
    items = AsyncMock()
    items.get_all_items.return_value = []
    policy = GuidancePolicy(3, 4, 80, 80, 3, 2, .1)
    interpretation = guard.policy.model_dump(mode="json", exclude={"approval", "schema_version", "version", "status", "production_enabled"})
    return PlanChatTurnUseCase(service, items, FileKnowledgeRepository(ROOT / "knowledge/app_knowledge.json"),
        AsyncMock(), AsyncMock(), ContextLimits(16, 24000), policy, interpretation, guard), guard


@pytest.mark.asyncio
async def test_new_account_completes_groq_chat_and_independent_review(tmp_path):
    path = tmp_path / "ledger.json"
    calls = []
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda req: native_reply(req, calls))) as http:
        old = cascade(configuration(path), http)
        rows = seed_legacy(old)
        old_planner, guard = planner(old)
        try:
            async with guard.turn():
                with pytest.raises(AllLLMProvidersExhaustedException) as failed:
                    await old_planner.execute(ChatRequestDTO(message="สวัสดี"))
            assert failed.value.code == "quota_exhausted"
            assert not calls
            assert all(row["http_attempts"] == 0 for row in old.telemetry)
        finally:
            await old.aclose()
        new = cascade(configuration(path, "new-org"), http)
        try:
            await new.start()
            calls.clear()
            fast, guard = planner(new)
            async with guard.turn():
                result = await fast.execute(ChatRequestDTO(message="สวัสดี"))
            assert result.response == "สวัสดี มีอะไรให้ช่วยบ้าง"
            assert [phase for phase, _ in calls] == ["planning", "review"]
            assert len({model for _, model in calls}) == 2
            saved = json.loads(path.read_text(encoding="utf-8"))["buckets"]
            assert all(saved[name] == row for name, row in rows.items())
            new_rows = [row for name, row in saved.items() if name not in rows]
            assert new_rows and all(not record["pending"] for row in new_rows for record in row["records"])
        finally:
            await new.aclose()


@pytest.mark.asyncio
async def test_new_account_own_daily_limit_still_blocks_full_chat(tmp_path):
    calls = []
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda req: native_reply(req, calls))) as http:
        service = cascade(configuration(tmp_path / "ledger.json", "org"), http)
        seed_legacy(service)
        fast, guard = planner(service)
        try:
            async with guard.turn():
                with pytest.raises(AllLLMProvidersExhaustedException) as failure:
                    await fast.execute(ChatRequestDTO(message="สวัสดี"))
            assert failure.value.code == "quota_exhausted" and failure.value.retry_after > 0
            assert not calls
        finally:
            await service.aclose()
