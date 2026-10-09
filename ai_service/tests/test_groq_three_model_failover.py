"""Real adapter, model-scoped quota and independent review under partial failures."""
import json
import time
from contextlib import asynccontextmanager

import httpx
import pytest

from app.core.config import settings
from app.core.exceptions import AllLLMProvidersExhaustedException
from app.domain.interfaces.generation_stage import generation_stage, Provenance
from app.infrastructure.llm.cascade_llm_service import CascadeLLMService
from app.infrastructure.llm.groq_client import GroqClient
from app.infrastructure.runtime.execution import TURN_RESOURCES
from test_provider_runtime import RUNTIME, SmallResult, envelope


PRIMARY = settings.GROQ_PRIMARY_MODEL
REVIEWER = settings.GROQ_FALLBACK_MODEL_1
QWEN = settings.GROQ_FALLBACK_MODEL_2
THREE_MODELS = RUNTIME.model_copy(update={"providers": tuple(
    p.model_copy(update={"enabled": True, "disabled_reason": None}) for p in RUNTIME.providers)})


@asynccontextmanager
async def stack(tmp_path, respond, runtime=THREE_MODELS):
    configuration = settings.model_copy(update={"AI_QUOTA_LEDGER_PATH": tmp_path / "quota.json",
        "STRUCTURED_MAX_OUTPUT_TOKENS": 20})
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as http:
        client = GroqClient(api_key="fixture", runtime=runtime, configuration=configuration, http_client=http)
        service = CascadeLLMService(groq_client=client, runtime=runtime, configuration=configuration)
        resources = {"cleanup": []}
        token = TURN_RESOURCES.set(resources)
        try:
            yield service, resources
        finally:
            for cleanup in resources["cleanup"]:
                await cleanup()
            TURN_RESOURCES.reset(token)
            await service.aclose()


@pytest.mark.asyncio
@pytest.mark.parametrize("unavailable", [None, PRIMARY, REVIEWER])
async def test_partial_failure_keeps_a_distinct_writer_and_reviewer(tmp_path, unavailable):
    calls = []
    def respond(request):
        payload = json.loads(request.content)
        model = payload["model"]
        calls.append(model)
        assert payload["response_format"]["json_schema"]["strict"] is True
        if model == QWEN:
            assert payload["reasoning_effort"] == "none"
        if model == unavailable:
            return httpx.Response(429, headers={"Retry-After": "45"},
                json={"error": {"code": "rate_limit_exceeded"}})
        return httpx.Response(200, json=envelope())
    async with stack(tmp_path, respond) as (service, resources):
        with generation_stage("planning") as writer:
            await service.generate_structured("fixture request", SmallResult)
        with generation_stage("review", excluded_models=[writer.provenance]) as reviewer:
            await service.generate_structured("fixture draft", SmallResult)
        expected = {
            None: ([PRIMARY, REVIEWER], PRIMARY, REVIEWER),
            PRIMARY: ([PRIMARY, QWEN, REVIEWER], QWEN, REVIEWER),
            REVIEWER: ([PRIMARY, REVIEWER, QWEN], PRIMARY, QWEN),
        }[unavailable]
        assert calls == expected[0]
        assert writer.provenance == Provenance("groq", expected[1])
        assert reviewer.provenance == Provenance("groq", expected[2])
        assert writer.provenance != reviewer.provenance
        assert resources[("review_hold", id(service))]["permit"].sent


@pytest.mark.asyncio
async def test_disabled_preview_is_skipped_without_changing_the_primary_pair(tmp_path):
    runtime = THREE_MODELS.model_copy(update={"providers": tuple(p.model_copy(update={
        "enabled": p.id != "groq-fallback-2", "disabled_reason": "preview_disabled" if p.id == "groq-fallback-2" else None})
        for p in THREE_MODELS.providers)})
    calls = []
    def respond(request):
        calls.append(json.loads(request.content)["model"])
        return httpx.Response(200, json=envelope())
    async with stack(tmp_path, respond, runtime) as (service, _):
        with generation_stage("planning") as writer:
            await service.generate_structured("request", SmallResult)
        with generation_stage("review", excluded_models=[writer.provenance]):
            await service.generate_structured("draft", SmallResult)
        assert calls == [PRIMARY, REVIEWER]


@pytest.mark.asyncio
@pytest.mark.parametrize("provider_code", ["model_permission_blocked_org", "model_permission_blocked_project"])
@pytest.mark.parametrize("denied_model", [PRIMARY, QWEN])
async def test_model_permission_denial_keeps_other_models_available(tmp_path, provider_code, denied_model):
    calls = []
    def respond(request):
        model = json.loads(request.content)["model"]
        calls.append(model)
        if model == denied_model:
            return httpx.Response(403, json={"error": {"type": "permissions_error", "code": provider_code}})
        return httpx.Response(200, json=envelope())
    async with stack(tmp_path, respond) as (service, _):
        excluded = [Provenance("groq", PRIMARY)] if denied_model == QWEN else []
        with generation_stage("planning", excluded_models=excluded) as writer:
            await service.generate_structured("request", SmallResult)
        with generation_stage("review", excluded_models=[writer.provenance]) as reviewer:
            await service.generate_structured("draft", SmallResult)
        assert calls == ([PRIMARY, QWEN, REVIEWER] if denied_model == PRIMARY else [QWEN, REVIEWER, PRIMARY])
        assert writer.provenance != reviewer.provenance
        assert service._auth_blocked == set()
        assert service._model_open_until[("groq", denied_model)] > time.monotonic()
        assert service.telemetry[0]["status"] == "model_permission_denied"


@pytest.mark.asyncio
async def test_one_available_model_is_insufficient_even_with_three_profiles(tmp_path):
    calls = []
    def respond(request):
        calls.append(json.loads(request.content)["model"])
        return httpx.Response(200, json=envelope())
    async with stack(tmp_path, respond) as (service, resources):
        for model in (PRIMARY, REVIEWER):
            await service.governor.cooldown(service._quota_bucket(service._profile("groq", model), "groq", model), 45)
        with generation_stage("planning"):
            with pytest.raises(AllLLMProvidersExhaustedException) as failed:
                await service.generate_structured("request", SmallResult)
        assert failed.value.code == "quota_temporarily_unavailable"
        assert calls == []
        assert ("review_hold", id(service)) not in resources


@pytest.mark.asyncio
async def test_three_candidates_still_allow_at_most_two_http_attempts(tmp_path):
    calls = []
    def respond(request):
        calls.append(json.loads(request.content)["model"])
        return httpx.Response(503, json={"error": {"code": "unavailable"}})
    async with stack(tmp_path, respond) as (service, _):
        with generation_stage("planning"):
            with pytest.raises(AllLLMProvidersExhaustedException):
                await service.generate_structured("request", SmallResult)
        assert calls == [PRIMARY, QWEN]
        assert len(calls) == 1 + service.runtime.max_failovers_per_logical_call


@pytest.mark.asyncio
async def test_qwen_invalid_output_fails_over_without_reviewing_its_own_draft(tmp_path):
    calls = []
    def respond(request):
        model = json.loads(request.content)["model"]
        calls.append(model)
        content = '{"wrong":true}' if model == QWEN else None
        return httpx.Response(200, json=envelope(content)) if content else httpx.Response(200, json=envelope())
    async with stack(tmp_path, respond) as (service, _):
        with generation_stage("planning", excluded_models=[Provenance("groq", PRIMARY)]) as writer:
            await service.generate_structured("request", SmallResult)
        with generation_stage("review", excluded_models=[writer.provenance]) as reviewer:
            await service.generate_structured("draft", SmallResult)
        assert calls == [QWEN, REVIEWER, QWEN, PRIMARY]
        assert writer.provenance == Provenance("groq", REVIEWER)
        assert reviewer.provenance == Provenance("groq", PRIMARY)


@pytest.mark.asyncio
async def test_qwen_reviewer_is_reserved_fresh_after_bounded_repair(tmp_path):
    calls = []
    def respond(request):
        calls.append(json.loads(request.content)["model"])
        return httpx.Response(200, json=envelope())
    async with stack(tmp_path, respond) as (service, resources):
        await service.governor.cooldown(service._quota_bucket(service._profile("groq", REVIEWER), "groq", REVIEWER), 45)
        with generation_stage("planning") as writer:
            await service.generate_structured("request", SmallResult)
        with generation_stage("review", excluded_models=[writer.provenance]):
            await service.generate_structured("first draft", SmallResult)
        first_permit = resources[("review_hold", id(service))]["permit"]
        with generation_stage("repair") as repaired:
            await service.generate_structured("corrected answer", SmallResult)
        fresh = resources[("review_hold", id(service))]
        assert fresh["permit"] is not first_permit
        assert fresh["identity"] == ("groq", QWEN)
        with generation_stage("review", excluded_models=[repaired.provenance]) as reviewer:
            await service.generate_structured("corrected draft", SmallResult)
        assert calls == [PRIMARY, QWEN, PRIMARY, QWEN]
        assert reviewer.provenance != repaired.provenance
        assert first_permit.sent
