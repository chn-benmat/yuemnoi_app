"""Exercise fallback and distinguish usage limits from processing queues."""
import json

import httpx
import pytest

from app.core.exceptions import AllLLMProvidersExhaustedException
from app.domain.interfaces.generation_stage import generation_stage
from app.infrastructure.llm.cascade_llm_service import CascadeLLMService
from app.infrastructure.llm.groq_client import GroqClient
from app.infrastructure.llm.quota import QuotaGovernor
from app.infrastructure.runtime.execution import TURN_RESOURCES
from test_provider_runtime import RUNTIME, SmallResult, envelope
from test_turn_reservation import Result, stack


@pytest.mark.asyncio
@pytest.mark.parametrize('failure', [403, 429, 503, 'connection', 'timeout', 'invalid_output'])
async def test_groq_failure_switches_models_except_provider_auth_denial(failure):
    calls = []
    def respond(request):
        model = json.loads(request.content)['model']
        calls.append(model)
        if model == RUNTIME.providers[0].proposed_model:
            if failure == 'connection':
                raise httpx.ConnectError('fixture', request=request)
            if failure == 'timeout':
                raise httpx.ReadTimeout('fixture', request=request)
            if failure == 'invalid_output':
                return httpx.Response(200, json=envelope('{"unexpected":true}'))
            return httpx.Response(failure, json={'error': {'code': 'fixture'}})
        return httpx.Response(200, json=envelope())
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as http:
        service = CascadeLLMService(runtime=RUNTIME,
            groq_client=GroqClient(api_key='fixture', runtime=RUNTIME, http_client=http))
        try:
            if failure == 403:
                with pytest.raises(AllLLMProvidersExhaustedException):
                    await service.generate_structured('fixture', SmallResult)
                assert calls == [service.configuration.GROQ_PRIMARY_MODEL]
                assert service._auth_blocked == {'groq'}
            else:
                result = await service.generate_structured('fixture', SmallResult)
                assert result.value == 'valid'
                assert calls == list(service.configuration.groq_models[:2])
        finally:
            await service.aclose()


@pytest.mark.asyncio
async def test_occupied_processing_slots_report_queue_without_claiming_quota():
    runtime = RUNTIME.model_copy(update={"http": RUNTIME.http.model_copy(
        update={"logical_call_deadline_seconds": .03})})
    service = CascadeLLMService(runtime=runtime)
    for _ in range(runtime.load.concurrent_requests):
        await service._semaphore.acquire()
    try:
        with pytest.raises(AllLLMProvidersExhaustedException) as failed:
            await service.generate_structured("fixture", SmallResult)
        assert failed.value.code == "providers_busy"
        assert failed.value.retry_after is None
        assert not any(row.get("http_attempts") for row in service.telemetry)
    finally:
        for _ in range(runtime.load.concurrent_requests):
            service._semaphore.release()
        await service.aclose()


@pytest.mark.asyncio
async def test_review_failure_cannot_fall_back_to_the_draft_writer():
    from app.domain.interfaces.generation_stage import Provenance
    calls = []
    def respond(request):
        calls.append(json.loads(request.content)['model'])
        return httpx.Response(200, json=envelope('{"unexpected":true}'))
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as http:
        service = CascadeLLMService(runtime=RUNTIME,
            groq_client=GroqClient(api_key='fixture', runtime=RUNTIME, http_client=http))
        try:
            writer = Provenance('groq', service.configuration.GROQ_PRIMARY_MODEL)
            with generation_stage('review', excluded_models=[writer]):
                with pytest.raises(AllLLMProvidersExhaustedException):
                    await service.generate_structured('fixture', SmallResult)
            assert calls == [service.configuration.GROQ_FALLBACK_MODEL_1, service.configuration.GROQ_FALLBACK_MODEL_2]
        finally:
            await service.aclose()


@pytest.mark.asyncio
async def test_no_independent_reviewer_is_not_a_quota_or_queue_failure(tmp_path):
    service, groq = stack(tmp_path)
    service._review_candidates = lambda _: []
    token = TURN_RESOURCES.set({"cleanup": []})
    try:
        with generation_stage("planning", downstream=("review",)):
            with pytest.raises(AllLLMProvidersExhaustedException) as failed:
                await service.generate_structured("fixture", Result)
        assert failed.value.code == "review_unavailable"
        assert failed.value.retry_after is None
        groq.generate_structured.assert_not_awaited()
    finally:
        TURN_RESOURCES.reset(token)
        await service.aclose()


@pytest.mark.asyncio
@pytest.mark.parametrize("daily", [False, True])
async def test_local_usage_limit_is_classified_and_retry_admits_again(tmp_path, daily):
    service, groq = stack(tmp_path)
    clock = [0.0]
    policies = [state.policy for state in service.governor._buckets.values()]
    service.governor = QuotaGovernor(policies, clock=lambda: clock[0])
    for policy in policies:
        permit = await service.governor.reserve(policy.bucket, policy.tokens_per_window)
        assert permit is not None
        await service.governor.mark_sent(permit)
        await service.governor.finish(permit, {"usage": {
            "total_tokens": policy.tokens_per_day if daily else policy.tokens_per_window}})
    expected = "quota_exhausted" if daily else "quota_temporarily_unavailable"
    token = TURN_RESOURCES.set({"cleanup": []})
    try:
        with generation_stage("planning", downstream=("review",)):
            with pytest.raises(AllLLMProvidersExhaustedException) as failed:
                await service.generate_structured("fixture", Result)
        assert failed.value.code == expected
        assert failed.value.retry_after == (
            min(policy.day_seconds for policy in policies) if daily
            else min(policy.window_seconds for policy in policies))
        groq.generate_structured.assert_not_awaited()
    finally:
        TURN_RESOURCES.reset(token)
    clock[0] = failed.value.retry_after
    resources = {"cleanup": []}
    token = TURN_RESOURCES.set(resources)
    try:
        with generation_stage("planning", downstream=("review",)):
            assert (await service.generate_structured("fixture", Result)).value
    finally:
        for cleanup in resources["cleanup"]:
            await cleanup()
        TURN_RESOURCES.reset(token)
        await service.aclose()
