"""Whole-turn admission tests; simulated models do not certify AI quality."""
from unittest.mock import AsyncMock, MagicMock

import pytest
from pydantic import BaseModel

from app.core.config import settings
from app.domain.interfaces.generation_stage import generation_stage, Provenance
from app.infrastructure.llm.cascade_llm_service import CascadeLLMService
from app.infrastructure.runtime.execution import TURN_RESOURCES
from app.core.exceptions import AllLLMProvidersExhaustedException, LLMProviderException
from app.infrastructure.llm.quota import QuotaGovernor


class Result(BaseModel):
    value: str


def stack(tmp_path):
    gemini, groq = MagicMock(), MagicMock()
    gemini.generate_structured = AsyncMock(return_value=Result(value='writer'))
    groq.generate_structured = AsyncMock(return_value=Result(value='reviewer'))
    config = settings.model_copy(update={'AI_QUOTA_LEDGER_PATH': tmp_path / 'quota.json',
        'STRUCTURED_MAX_OUTPUT_TOKENS': 20})
    cascade = CascadeLLMService(gemini, groq, configuration=config)
    # Existing enabled profiles and model identities remain unchanged.
    return cascade, gemini, groq


@pytest.mark.asyncio
async def test_review_hold_survives_writing_and_is_shrunk_for_actual_request(tmp_path):
    cascade, gemini, groq = stack(tmp_path)
    resources = {'cleanup': []}
    token = TURN_RESOURCES.set(resources)
    try:
        with generation_stage('planning', downstream=('review',)) as writer:
            await cascade.generate_structured('short request', Result)
        hold = resources[('review_hold', id(cascade))]
        reviewer_identity = hold['identity']
        assert reviewer_identity != (writer.provenance.provider, writer.provenance.model)
        assert not hold['permit'].sent
        with generation_stage('review', excluded_models=[writer.provenance]) as reviewer:
            await cascade.generate_structured('complete rendered draft', Result)
        assert (reviewer.provenance.provider, reviewer.provenance.model) == reviewer_identity
        assert hold['permit'].sent and not hold['permit'].pending
        assert hold['permit'].tokens < cascade._profile(*reviewer_identity).quota.tokens_per_window
        assert gemini.generate_structured.await_count + groq.generate_structured.await_count == 2
    finally:
        for cleanup in resources['cleanup']:
            await cleanup()
        TURN_RESOURCES.reset(token)
        await cascade.aclose()


@pytest.mark.asyncio
@pytest.mark.parametrize('blocked_before_http', [False, True])
async def test_gemini_rate_limit_automatically_uses_two_distinct_groq_models(tmp_path, blocked_before_http):
    cascade, gemini, groq = stack(tmp_path)
    gemini_identity = next(identity for identity in cascade._get_cascade_tiers() if identity[0] == 'gemini')
    bucket = cascade._quota_bucket(cascade._profile(*gemini_identity), *gemini_identity)
    if blocked_before_http:
        await cascade.governor.cooldown(bucket, cascade.runtime.quota_backoff_seconds)
    else:
        gemini.generate_structured.side_effect = LLMProviderException(*gemini_identity,
            'queued', status_code=429, retry_after=cascade.runtime.quota_backoff_seconds)
    resources = {'cleanup': []}
    token = TURN_RESOURCES.set(resources)
    try:
        with generation_stage('planning') as writer:
            await cascade.generate_structured('request', Result)
        with generation_stage('review', excluded_models=[writer.provenance]) as review:
            await cascade.generate_structured('complete rendered draft', Result)
        assert writer.provenance.provider == review.provenance.provider == 'groq'
        assert writer.provenance.model != review.provenance.model
        assert gemini.generate_structured.await_count == (0 if blocked_before_http else 1)
        assert groq.generate_structured.await_count == 2
    finally:
        for cleanup in resources['cleanup']:
            await cleanup()
        TURN_RESOURCES.reset(token)
        await cascade.aclose()


@pytest.mark.asyncio
async def test_quota_notice_is_not_used_when_groq_fails_validation_with_capacity_left(tmp_path):
    cascade, gemini, groq = stack(tmp_path)
    gemini_identity = next(identity for identity in cascade._get_cascade_tiers() if identity[0] == 'gemini')
    bucket = cascade._quota_bucket(cascade._profile(*gemini_identity), *gemini_identity)
    await cascade.governor.cooldown(bucket, cascade.runtime.quota_backoff_seconds)
    groq.generate_structured.side_effect = LLMProviderException('groq', 'test model',
        'invalid structured output', status_code=400, error_code='structured_output_invalid')
    resources = {'cleanup': []}
    token = TURN_RESOURCES.set(resources)
    try:
        with generation_stage('planning'):
            with pytest.raises(AllLLMProvidersExhaustedException) as caught:
                await cascade.generate_structured('request', Result)
        assert caught.value.code == 'providers_exhausted'
        assert caught.value.retry_after is None
        gemini.generate_structured.assert_not_awaited()
        assert groq.generate_structured.await_count == 1 + cascade.runtime.max_failovers_per_logical_call
    finally:
        for cleanup in resources['cleanup']:
            await cleanup()
        TURN_RESOURCES.reset(token)
        await cascade.aclose()


@pytest.mark.asyncio
async def test_quota_failure_checks_enabled_groq_paths_before_notifying(tmp_path):
    cascade, gemini, groq = stack(tmp_path)
    for provider, model in cascade._get_cascade_tiers():
        bucket = cascade._quota_bucket(cascade._profile(provider, model), provider, model)
        await cascade.governor.cooldown(bucket, cascade.runtime.quota_backoff_seconds)
    resources = {'cleanup': []}
    token = TURN_RESOURCES.set(resources)
    try:
        with generation_stage('planning'):
            with pytest.raises(AllLLMProvidersExhaustedException) as caught:
                await cascade.generate_structured('request', Result)
        checked = {(row['provider'], row['model']) for row in cascade.telemetry}
        assert checked == set(cascade._get_cascade_tiers())
        assert caught.value.code == 'providers_rate_limited'
        assert caught.value.retry_after > 0
        gemini.generate_structured.assert_not_awaited()
        groq.generate_structured.assert_not_awaited()
    finally:
        for cleanup in resources['cleanup']:
            await cleanup()
        TURN_RESOURCES.reset(token)
        await cascade.aclose()


@pytest.mark.asyncio
async def test_no_independent_review_capacity_prevents_wasting_writer_http(tmp_path):
    cascade, gemini, groq = stack(tmp_path)
    cascade._review_candidates = lambda _: []
    token = TURN_RESOURCES.set({'cleanup': []})
    from app.core.exceptions import AllLLMProvidersExhaustedException
    try:
        with generation_stage('planning', downstream=('review',)):
            with pytest.raises(AllLLMProvidersExhaustedException):
                await cascade.generate_structured('request', Result)
        gemini.generate_structured.assert_not_awaited()
        groq.generate_structured.assert_not_awaited()
        assert all(row['http_attempts'] == 0 for row in cascade.telemetry)
    finally:
        TURN_RESOURCES.reset(token)
        await cascade.aclose()


@pytest.mark.asyncio
async def test_cancellation_releases_only_unsent_review_capacity(tmp_path):
    cascade, _, _ = stack(tmp_path)
    resources = {'cleanup': []}
    token = TURN_RESOURCES.set(resources)
    try:
        with generation_stage('planning'):
            await cascade.generate_structured('request', Result)
        hold = resources[('review_hold', id(cascade))]['permit']
        for cleanup in resources['cleanup']:
            await cleanup()
        assert cascade.governor._stored_permit(hold) is None
        charged = [p for bucket in cascade.governor._buckets.values() for p in bucket.records]
        assert len(charged) == 1 and charged[0].sent and charged[0].tokens > 0
    finally:
        TURN_RESOURCES.reset(token)
        await cascade.aclose()


@pytest.mark.asyncio
async def test_failed_writer_releases_review_hold_for_fallback(tmp_path):
    cascade, gemini, groq = stack(tmp_path)
    ordered = cascade._get_cascade_tiers()
    first, fallback = ordered[:2]
    calls = []

    async def generate(*, model, **kwargs):
        calls.append(model)
        if model == first[1]:
            raise LLMProviderException(first[0], model, 'invalid structured output',
                status_code=400, error_code='structured_output_invalid')
        return Result(value='fallback')

    gemini.generate_structured.side_effect = generate
    groq.generate_structured.side_effect = generate
    resources = {'cleanup': []}
    token = TURN_RESOURCES.set(resources)
    try:
        with generation_stage('planning') as writer:
            result = await cascade.generate_structured('request', Result)
        assert result.value == 'fallback'
        assert writer.provenance == Provenance(*fallback)
        assert calls == [first[1], fallback[1]]
        hold = resources[('review_hold', id(cascade))]
        assert hold['identity'] != fallback
        charged = [p for b in cascade.governor._buckets.values() for p in b.records if p.sent]
        assert len(charged) == 2
    finally:
        for cleanup in resources['cleanup']:
            await cleanup()
        TURN_RESOURCES.reset(token)
        await cascade.aclose()


@pytest.mark.asyncio
async def test_failed_writer_retry_uses_daily_pair_capacity_not_held_minute(tmp_path):
    cascade, gemini, groq = stack(tmp_path)
    identities = cascade._get_cascade_tiers()[:2]
    enabled = {cascade._profile(*identity).id for identity in identities}
    providers = []
    quotas = []
    for profile in cascade.runtime.providers:
        quota = profile.quota.model_copy(update={'tokens_per_window': 100,
            'tokens_per_day': 150, 'window_seconds': 60, 'day_seconds': 1000})
        updated = profile.model_copy(update={'quota': quota, 'enabled': profile.id in enabled})
        providers.append(updated)
        provider = profile.protocol.removesuffix('_json_schema')
        model = getattr(cascade.configuration, profile.model_setting)
        quotas.append(quota.model_copy(update={'bucket': cascade._quota_bucket(updated, provider, model)}))
    cascade.runtime = cascade.runtime.model_copy(update={'providers': providers})
    await cascade.governor.aclose()
    clock = [0.0]
    cascade.governor = QuotaGovernor(quotas, clock=lambda: clock[0])
    bucket = cascade._quota_bucket(cascade._profile(*identities[0]), *identities[0])
    for moment, amount in [(0, 90), (70, 35)]:
        clock[0] = moment
        permit = await cascade.governor.reserve(bucket, amount)
        await cascade.governor.mark_sent(permit)
        await cascade.governor.finish(permit, None)
    clock[0] = 140
    client = cascade._clients[identities[0][0]]
    client.generate_structured.side_effect = LLMProviderException(*identities[0],
        'invalid structured output', status_code=400, error_code='structured_output_invalid')
    resources = {'cleanup': []}
    token = TURN_RESOURCES.set(resources)
    try:
        with generation_stage('planning'):
            with pytest.raises(AllLLMProvidersExhaustedException) as caught:
                await cascade.generate_structured('xxxx', Result)
        assert caught.value.code == 'providers_rate_limited'
        assert caught.value.retry_after == 860
        assert ('review_hold', id(cascade)) not in resources
    finally:
        for cleanup in resources['cleanup']:
            await cleanup()
        TURN_RESOURCES.reset(token)
        await cascade.aclose()


@pytest.mark.asyncio
async def test_temporary_rate_limit_recovers_after_reported_quota_wait(tmp_path):
    cascade, gemini, groq = stack(tmp_path)
    identities = cascade._get_cascade_tiers()[:2]
    enabled = {cascade._profile(*identity).id for identity in identities}
    cascade.runtime = cascade.runtime.model_copy(update={'providers': [
        profile.model_copy(update={'enabled': profile.id in enabled})
        for profile in cascade.runtime.providers]})
    await cascade.governor.aclose()
    clock = [0.0]
    quotas = [p.quota.model_copy(update={'bucket': cascade._quota_bucket(p,
        p.protocol.removesuffix('_json_schema'), getattr(cascade.configuration, p.model_setting))})
        for p in cascade.runtime.providers]
    cascade.governor = QuotaGovernor(quotas, clock=lambda: clock[0])
    for provider, model in identities:
        cascade._clients[provider].generate_structured.side_effect = LLMProviderException(
            provider, model, 'queued', status_code=429, retry_after=5)
    resources = {'cleanup': []}
    token = TURN_RESOURCES.set(resources)
    try:
        with generation_stage('planning'):
            with pytest.raises(AllLLMProvidersExhaustedException) as caught:
                await cascade.generate_structured('request', Result)
        assert caught.value.retry_after > 0
        assert gemini.generate_structured.await_count + groq.generate_structured.await_count <= 2
        clock[0] += caught.value.retry_after
        for cleanup in resources['cleanup']:
            await cleanup()
        resources.clear()
        resources['cleanup'] = []
        gemini.generate_structured.side_effect = None
        groq.generate_structured.side_effect = None
        with generation_stage('planning') as writer:
            await cascade.generate_structured('request', Result)
        with generation_stage('review', excluded_models=[writer.provenance]) as review:
            await cascade.generate_structured('complete rendered draft', Result)
        assert review.provenance != writer.provenance
    finally:
        for cleanup in resources['cleanup']:
            await cleanup()
        TURN_RESOURCES.reset(token)
        await cascade.aclose()
