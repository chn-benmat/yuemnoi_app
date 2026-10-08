"""Provider data controls admission; local estimates cannot invent API limits."""
import asyncio
import json
import math
import time
from pathlib import Path

import httpx
import pytest

from app.core.config import Settings
from app.core.exceptions import AllLLMProvidersExhaustedException, LLMProviderException, RuntimeConfigurationException
from app.infrastructure.llm.cascade_llm_service import CascadeLLMService
from app.infrastructure.llm.gemini_client import GeminiClient
from app.infrastructure.llm.groq_client import GroqClient
from app.infrastructure.llm.quota import PersistentQuotaGovernor, QuotaGovernor
from app.infrastructure.runtime.documents import ValidatedFile
from app.infrastructure.runtime.schema import QuotaPolicy, RuntimeDocument
from test_provider_runtime import SmallResult, envelope

ROOT = Path(__file__).resolve().parents[1]
PRODUCTION = ValidatedFile(ROOT / 'config/ai_runtime.json', RuntimeDocument).read()[0]


def policy(**changes):
    values = dict(bucket='test', authority='provider', scope='model',
        requests_per_window=1, tokens_per_window=100, window_seconds=60.,
        requests_per_day=2, tokens_per_day=200, day_seconds=86400.)
    return QuotaPolicy(**(values | changes))


async def observe(governor, **headers):
    permit = await governor.reserve('test', 1)
    assert permit is not None
    await governor.mark_sent(permit)
    await governor.finish(permit, {'usage': {'total_tokens': 1}, 'headers': headers})


def persistent(path, quota):
    return PersistentQuotaGovernor([quota], path, lock_timeout_seconds=1, poll_seconds=.005)


def test_production_gemini_and_groq_use_api_authority():
    assert {p.protocol for p in PRODUCTION.providers} == {'gemini_json_schema', 'groq_json_schema'}
    assert all(p.quota.authority == 'provider' for p in PRODUCTION.providers)


@pytest.mark.asyncio
async def test_unknown_limits_do_not_block_on_local_minute_or_daily_usage():
    governor = QuotaGovernor([policy()])
    for _ in range(3):
        permit = await governor.reserve('test', 10000)
        assert permit is not None
        await governor.mark_sent(permit)
        await governor.finish(permit, {'usage': {'total_tokens': 10000}})
    assert await governor.next_admission_status([('test', 10000)] * 3) == (None, 0)
    assert sum(r.tokens for r in governor._buckets['test'].records) == 30000


@pytest.mark.asyncio
async def test_real_caps_can_exceed_configured_caps_and_daily_history_is_not_charged_twice():
    governor = QuotaGovernor([policy()])
    await observe(governor, **{'x-ratelimit-limit-tokens': '2000',
        'x-ratelimit-remaining-tokens': '1800', 'x-ratelimit-reset-tokens': '60s',
        'x-ratelimit-limit-requests': '1000', 'x-ratelimit-remaining-requests': '800',
        'x-ratelimit-reset-requests': '12h'})
    held = await governor.reserve_many([('test', 900), ('test', 900)])
    assert held is not None
    assert await governor.reserve('test', 1) is None
    assert await governor.release_unused(held[0])
    assert await governor.reserve('test', 900) is not None


@pytest.mark.asyncio
async def test_lower_real_cap_classifies_oversized_request_without_wait():
    governor = QuotaGovernor([policy(tokens_per_window=10000)])
    await observe(governor, **{'x-ratelimit-limit-tokens': '500',
        'x-ratelimit-remaining-tokens': '500', 'x-ratelimit-reset-tokens': '60s'})
    assert await governor.next_admission_status([('test', 501)]) == ('request_budget_exceeded', math.inf)
    assert governor.cost_exceeds_capacity('test', 501)


@pytest.mark.asyncio
@pytest.mark.parametrize('metric,code,delay', [('tokens', 'quota_temporarily_unavailable', 45),
    ('requests', 'quota_exhausted', 3600)])
async def test_header_balance_and_reset_are_authoritative(metric, code, delay):
    clock = [100.]
    governor = QuotaGovernor([policy()], clock=lambda: clock[0])
    await observe(governor, **{f'x-ratelimit-remaining-{metric}': '0',
        f'x-ratelimit-reset-{metric}': f'{delay}s'})
    assert await governor.next_admission_status([('test', 1)]) == (code, delay)
    assert await governor.reserve('test', 1) is None
    clock[0] += delay
    assert await governor.reserve('test', 1) is not None


@pytest.mark.asyncio
async def test_missing_reset_is_unknown_and_not_configured_one_minute_or_day():
    governor = QuotaGovernor([policy()])
    await observe(governor, **{'x-ratelimit-remaining-tokens': '0'})
    assert governor._buckets['test'].tokens_reset == 0
    # A snapshot with unknown expiry cannot block all future refresh calls.
    # The next actual API response decides; a real 429 still enforces backoff.
    assert await governor.next_admission_status([('test', 1)]) == (None, 0)
    assert await governor.wait_reserve('test', 1, deadline=time.monotonic() + .01) is not None


@pytest.mark.asyncio
async def test_abandoned_holds_cannot_lock_api_capacity_beyond_turn_deadline():
    clock = [100.]
    governor = QuotaGovernor([policy()], clock=lambda: clock[0], reservation_seconds=30)
    await observe(governor, **{'x-ratelimit-limit-tokens': '1000',
        'x-ratelimit-remaining-tokens': '1000', 'x-ratelimit-reset-tokens': '10s'})
    held = await governor.reserve('test', 1000)
    clock[0] += 31
    assert await governor.reserve('test', 1000) is not None
    assert governor._stored_permit(held).pending  # Evidence is retained.


@pytest.mark.asyncio
async def test_fresh_header_increase_replaces_old_balance_and_discounts_other_http_and_recovery_holds():
    governor = QuotaGovernor([policy()])
    await observe(governor, **{'x-ratelimit-limit-tokens': '5000',
        'x-ratelimit-remaining-tokens': '2000', 'x-ratelimit-reset-tokens': '60s'})
    current, in_flight, held = await governor.reserve_many([('test', 1), ('test', 500), ('test', 600)])
    await governor.mark_sent(current)
    await governor.mark_sent(in_flight)
    await governor.finish(current, {'usage': {'total_tokens': 1}, 'headers': {
        'x-ratelimit-remaining-tokens': '3000', 'x-ratelimit-reset-tokens': '30s'}})
    assert governor._buckets['test'].observed_tokens == 1900
    assert await governor.reserve_many([('test', 1000), ('test', 901)]) is None
    assert governor._buckets['test'].observed_tokens == 1900
    assert await governor.release_unused(held)
    assert governor._buckets['test'].observed_tokens == 2500


@pytest.mark.asyncio
async def test_authority_migration_preserves_usage_ids_cooldown_and_other_accounts(tmp_path):
    path = tmp_path / 'ledger.json'
    old = persistent(path, policy(authority='configured'))
    permit = await old.reserve('test', 50)
    await old.mark_sent(permit)
    await old.finish(permit, {'usage': {'total_tokens': 50}})
    await old.cooldown('test', 45)
    before = json.loads(path.read_text())['buckets']['test']
    # An unowned account stays opaque and unchanged by migration.
    document = json.loads(path.read_text())
    document['buckets']['other-account'] = before.copy()
    path.write_text(json.dumps(document))
    new = persistent(path, policy())
    code, delay = await new.next_admission_status([('test', 1000)])
    after = json.loads(path.read_text())['buckets']
    assert code == 'quota_temporarily_unavailable' and 0 < delay <= 45
    assert after['test']['records'] == before['records']
    assert after['test']['cooldown_until'] == before['cooldown_until']
    assert after['other-account'] == before
    assert after['test']['policy']['authority'] == 'provider'
    await old.aclose()
    await new.aclose()


@pytest.mark.asyncio
async def test_migration_does_not_accept_unrelated_policy_change(tmp_path):
    path = tmp_path / 'ledger.json'
    first = persistent(path, policy(authority='configured'))
    await first.reserve('test', 1)
    second = persistent(path, policy(tokens_per_day=201))
    with pytest.raises(RuntimeConfigurationException, match='quota_ledger_invalid'):
        await second.reserve('test', 1)


@pytest.mark.asyncio
async def test_provider_balance_and_atomic_recovery_holds_survive_restart(tmp_path):
    path = tmp_path / 'ledger.json'
    first = persistent(path, policy())
    await observe(first, **{'x-ratelimit-limit-tokens': '1000',
        'x-ratelimit-remaining-tokens': '900', 'x-ratelimit-reset-tokens': '60s',
        'x-ratelimit-limit-requests': '500', 'x-ratelimit-remaining-requests': '3',
        'x-ratelimit-reset-requests': '1h'})
    holds = await first.reserve_many([('test', 400), ('test', 400)])
    second = persistent(path, policy())
    assert await second.reserve_many([('test', 101), ('test', 1)]) is None
    await first.release_unused(holds[0])
    assert await second.reserve('test', 500) is not None
    assert await second.reserve('test', 1) is None


@pytest.mark.asyncio
@pytest.mark.parametrize('retry_header,details,expected', [
    ('12', [{'@type': 'type.googleapis.com/google.rpc.RetryInfo', 'retryDelay': '45s'}], 12),
    (None, [{'@type': 'type.googleapis.com/google.rpc.RetryInfo', 'retryDelay': '45.5s'}], 45.5),
    (None, [{'@type': 'other-type', 'retryDelay': '45s'}], None),
    (None, [{'@type': 'type.googleapis.com/google.rpc.RetryInfo', 'retryDelay': '-1s'}], None),
    (None, [{'@type': 'type.googleapis.com/google.rpc.RetryInfo', 'retryDelay': 'nans'}], None),
    (None, {'invalid': 'shape'}, None),
])
async def test_gemini_retry_uses_typed_api_details_only(retry_header, details, expected):
    response = httpx.Response(429, headers={'retry-after': retry_header} if retry_header else {},
        json={'error': {'status': 'RESOURCE_EXHAUSTED', 'message': 'secret-wait-99s', 'details': details}})
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: response)) as http:
        client = GeminiClient(api_key='fixture', http_client=http, runtime=PRODUCTION)
        with pytest.raises(LLMProviderException) as failure:
            await client.generate_text(client.configuration.GEMINI_PRIMARY_MODEL, 'fixture')
        assert failure.value.retry_after == expected
        assert 'secret-wait' not in json.dumps(client.observation())


@pytest.mark.asyncio
@pytest.mark.parametrize('provider', ['gemini', 'groq'])
async def test_unknown_429_wait_is_not_advertised_as_configured_backoff(tmp_path, provider):
    cfg = Settings(_env_file=None, AI_QUOTA_LEDGER_PATH=tmp_path/'ledger.json',
        GEMINI_API_KEY='fixture', GROQ_API_KEY='fixture')
    profiles = tuple(p.model_copy(update={'enabled': p.id == f'{provider}-primary'}) for p in PRODUCTION.providers)
    runtime = PRODUCTION.model_copy(update={'providers': profiles})
    clock, calls = [100.], []
    def respond(request):
        calls.append(request)
        return httpx.Response(429, headers={'x-ratelimit-remaining-tokens': '0'},
            json={'error': {'status': 'RESOURCE_EXHAUSTED'}})
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as http:
        service = CascadeLLMService(runtime=runtime, configuration=cfg,
            gemini_client=GeminiClient(runtime=runtime, configuration=cfg, http_client=http),
            groq_client=GroqClient(runtime=runtime, configuration=cfg, http_client=http))
        service.governor._clock = lambda: clock[0]
        for _ in range(2):
            with pytest.raises(AllLLMProvidersExhaustedException) as failure:
                await service.generate_structured('fixture', SmallResult)
            assert failure.value.code in ('providers_rate_limited', 'quota_temporarily_unavailable')
            assert failure.value.retry_after is None
        assert len(calls) == 1
        clock[0] += runtime.quota_backoff_seconds
        with pytest.raises(AllLLMProvidersExhaustedException):
            await service.generate_structured('fixture', SmallResult)
        assert len(calls) == 2  # Refresh missing-reset data through the API.
        await service.aclose()


@pytest.mark.asyncio
async def test_api_daily_request_exhaustion_survives_429_and_is_not_labelled_minute_limit(tmp_path):
    cfg = Settings(_env_file=None, AI_QUOTA_LEDGER_PATH=tmp_path/'ledger.json',
        GEMINI_API_KEY='', GROQ_API_KEY='fixture')
    headers = {'retry-after': '45', 'x-ratelimit-limit-requests': '1000',
        'x-ratelimit-remaining-requests': '0', 'x-ratelimit-reset-requests': '2h'}
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(429,
            headers=headers, json={'error': {'code': 'rate_limit_exceeded'}}))) as http:
        service = CascadeLLMService(runtime=PRODUCTION, configuration=cfg,
            groq_client=GroqClient(runtime=PRODUCTION, configuration=cfg, http_client=http))
        with pytest.raises(AllLLMProvidersExhaustedException) as failure:
            await service.generate_structured('fixture', SmallResult)
        assert failure.value.code == 'quota_exhausted'
        assert 7190 < failure.value.retry_after <= 7200
        await service.aclose()


@pytest.mark.asyncio
async def test_gemini_denial_falls_back_to_groq_despite_local_daily_history(tmp_path):
    calls = []
    cfg = Settings(_env_file=None, AI_QUOTA_LEDGER_PATH=tmp_path/'ledger.json',
        GEMINI_API_KEY='fixture', GROQ_API_KEY='fixture')
    def respond(request):
        provider = 'gemini' if 'contents' in json.loads(request.content) else 'groq'
        calls.append(provider)
        return (httpx.Response(403, json={'error': {'status': 'PERMISSION_DENIED'}}) if provider == 'gemini'
                else httpx.Response(200, json=envelope()))
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as http:
        service = CascadeLLMService(runtime=PRODUCTION, configuration=cfg,
            gemini_client=GeminiClient(runtime=PRODUCTION, configuration=cfg, http_client=http),
            groq_client=GroqClient(runtime=PRODUCTION, configuration=cfg, http_client=http))
        for name, state in service.governor._buckets.items():
            old = await service.governor.reserve(name, state.policy.tokens_per_day * 2)
            await service.governor.mark_sent(old)
            await service.governor.finish(old, {'usage': {'total_tokens': old.tokens}})
        assert (await service.generate_structured('fixture', SmallResult)).value == 'valid'
        assert calls == ['gemini', 'groq']
        await service.aclose()
