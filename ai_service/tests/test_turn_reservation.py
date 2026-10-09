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
from test_provider_runtime import RUNTIME


class Result(BaseModel):
    value: str


def stack(tmp_path):
    groq = MagicMock()
    groq.generate_structured = AsyncMock(return_value=Result(value='valid'))
    config = settings.model_copy(update={'AI_QUOTA_LEDGER_PATH': tmp_path / 'quota.json',
        'STRUCTURED_MAX_OUTPUT_TOKENS': 20})
    return CascadeLLMService(groq_client=groq, configuration=config, runtime=RUNTIME), groq


@pytest.mark.asyncio
async def test_review_hold_survives_writing_and_is_shrunk_for_actual_request(tmp_path):
    cascade, groq = stack(tmp_path)
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
        assert groq.generate_structured.await_count == 2
    finally:
        for cleanup in resources['cleanup']:
            await cleanup()
        TURN_RESOURCES.reset(token)
        await cascade.aclose()


@pytest.mark.asyncio
async def test_repair_reserves_a_fresh_independent_review_without_refunding_spent_usage(tmp_path):
    cascade, groq = stack(tmp_path)
    resources = {'cleanup': []}
    token = TURN_RESOURCES.set(resources)
    try:
        with generation_stage('planning') as first_writer:
            await cascade.generate_structured('request', Result)
        with generation_stage('review', excluded_models=[first_writer.provenance]):
            await cascade.generate_structured('first review', Result)
        first_permit = resources[('review_hold', id(cascade))]['permit']
        with generation_stage('repair', downstream=('review',)) as repaired_writer:
            await cascade.generate_structured('correct rejected answer', Result)
        fresh_hold = resources[('review_hold', id(cascade))]
        assert fresh_hold['permit'] is not first_permit and not fresh_hold['permit'].sent
        assert fresh_hold['identity'] != (repaired_writer.provenance.provider, repaired_writer.provenance.model)
        with generation_stage('review', excluded_models=[repaired_writer.provenance]) as final_reviewer:
            await cascade.generate_structured('whole corrected draft', Result)
        assert final_reviewer.provenance != repaired_writer.provenance
        charged = [p for b in cascade.governor._buckets.values() for p in b.records if p.sent]
        assert len(charged) == 4 and first_permit in charged
        assert groq.generate_structured.await_count == 4
    finally:
        for cleanup in resources['cleanup']:
            await cleanup()
        TURN_RESOURCES.reset(token)
        await cascade.aclose()


@pytest.mark.asyncio
async def test_repair_pair_quota_denial_calls_no_provider_and_reports_actual_wait(tmp_path):
    cascade, groq = stack(tmp_path)
    resources = {'cleanup': []}
    token = TURN_RESOURCES.set(resources)
    try:
        for provider, model in cascade._get_cascade_tiers():
            await cascade.governor.cooldown(cascade._quota_bucket(cascade._profile(provider, model),provider,model),45)
        with generation_stage('repair',downstream=('review',)):
            with pytest.raises(AllLLMProvidersExhaustedException) as caught:
                await cascade.generate_structured('correct rejected answer',Result)
        assert caught.value.code == 'quota_temporarily_unavailable' and 0 < caught.value.retry_after <= 45
        groq.generate_structured.assert_not_awaited()
        assert ('review_hold',id(cascade)) not in resources
    finally:
        for cleanup in resources['cleanup']:
            await cleanup()
        TURN_RESOURCES.reset(token)
        await cascade.aclose()


@pytest.mark.asyncio
async def test_first_review_wait_is_not_reported_as_daily_quota_for_a_speculative_repair(tmp_path):
    from app.domain.interfaces.generation_stage import GenerationRequest
    cascade,groq=stack(tmp_path)
    identities=[i for i in cascade._get_cascade_tiers() if i[0]=='groq'][:2]
    enabled={cascade._profile(*i).id for i in identities}
    profiles=[p.model_copy(update={'enabled':p.id in enabled,
        'quota':p.quota.model_copy(update={'tokens_per_window':1000,'tokens_per_day':1000})})
        for p in cascade.runtime.providers]
    cascade.runtime=cascade.runtime.model_copy(update={'providers':profiles,
        'stages':cascade.runtime.stages.model_copy(update={'initial_review_reserve_tokens':200,
            'repair':cascade.runtime.stages.repair.model_copy(update={'profiles':[cascade._profile(*identities[0]).id]})})})
    await cascade.governor.aclose()
    clock=[0.0]
    cascade.governor=QuotaGovernor([p.quota.model_copy(update={'bucket':cascade._quota_bucket(p,
        p.protocol.removesuffix('_json_schema'),getattr(cascade.configuration,p.model_setting))})
        for p in profiles],clock=lambda:clock[0])
    writer_bucket=cascade._quota_bucket(cascade._profile(*identities[0]),*identities[0])
    spent=await cascade.governor.reserve(writer_bucket,900)
    await cascade.governor.mark_sent(spent)
    await cascade.governor.finish(spent,None)
    clock[0]=70
    cascade._request_cost=lambda client,method,model,kw:980 if kw['prompt']=='recovery request' else 50
    resources={'cleanup':[]}
    token=TURN_RESOURCES.set(resources)
    try:
        with generation_stage('planning') as writer:
            await cascade.generate_structured('request',Result)
        reviewer=resources[('review_hold',id(cascade))]['identity']
        review_bucket=cascade._quota_bucket(cascade._profile(*reviewer),*reviewer)
        await cascade.governor.cooldown(review_bucket,60)
        recovery=GenerationRequest('recovery request',Result,None,.1)
        with generation_stage('review',excluded_models=[writer.provenance],recovery_request=recovery):
            with pytest.raises(AllLLMProvidersExhaustedException) as caught:
                await cascade.generate_structured('first review',Result)
        assert caught.value.code=='quota_temporarily_unavailable'
        assert caught.value.retry_after==60
        assert groq.generate_structured.await_count==1
    finally:
        for cleanup in resources['cleanup']:await cleanup()
        TURN_RESOURCES.reset(token)
        await cascade.aclose()


@pytest.mark.asyncio
async def test_first_review_reserves_repair_and_final_review_atomically(tmp_path):
    from app.domain.interfaces.generation_stage import GenerationRequest
    cascade, groq = stack(tmp_path)
    resources = {'cleanup': []}
    token = TURN_RESOURCES.set(resources)
    try:
        with generation_stage('planning') as writer:
            await cascade.generate_structured('request', Result)
        recovery = GenerationRequest('correct rejected answer', Result, None, .1)
        with generation_stage('review', excluded_models=[writer.provenance], recovery_request=recovery):
            await cascade.generate_structured('first complete review', Result)
        recovery_hold = resources[('recovery_hold', id(cascade))]
        final_hold = resources[('final_review_hold', id(cascade))]
        assert not recovery_hold['permit'].sent and not final_hold['permit'].sent
        assert recovery_hold['identity'] != final_hold['identity']
        with generation_stage('repair') as repaired_writer:
            await cascade.generate_structured(recovery.prompt, Result)
        with generation_stage('review', excluded_models=[repaired_writer.provenance]) as final:
            await cascade.generate_structured('final complete review', Result)
        assert final.provenance != repaired_writer.provenance
        assert recovery_hold['permit'].sent and final_hold['permit'].sent
        assert groq.generate_structured.await_count == 4
    finally:
        for cleanup in resources['cleanup']:
            await cleanup()
        TURN_RESOURCES.reset(token)
        await cascade.aclose()


@pytest.mark.asyncio
async def test_insufficient_recovery_capacity_allows_review_but_prevents_repair_http_and_keeps_spent_usage(tmp_path):
    from app.domain.interfaces.generation_stage import GenerationRequest
    cascade,groq=stack(tmp_path)
    identities=[i for i in cascade._get_cascade_tiers() if i[0]=='groq'][:2]
    enabled={cascade._profile(*i).id for i in identities}
    profiles=[p.model_copy(update={'enabled':p.id in enabled,
        'quota':p.quota.model_copy(update={'tokens_per_window':1000,'tokens_per_day':10000})})
        for p in cascade.runtime.providers]
    cascade.runtime=cascade.runtime.model_copy(update={'providers':profiles,
        'stages':cascade.runtime.stages.model_copy(update={'initial_review_reserve_tokens':200})})
    await cascade.governor.aclose()
    clock=[0.0]
    cascade.governor=QuotaGovernor([p.quota.model_copy(update={'bucket':cascade._quota_bucket(p,
        p.protocol.removesuffix('_json_schema'),getattr(cascade.configuration,p.model_setting))})
        for p in profiles],clock=lambda:clock[0])
    cascade._request_cost=lambda client,method,model,kw:980 if kw['prompt']=='reserved recovery request' else 50
    resources={'cleanup':[]}
    token=TURN_RESOURCES.set(resources)
    try:
        with generation_stage('planning') as writer:
            await cascade.generate_structured('request',Result)
        request=GenerationRequest('reserved recovery request',Result,None,.1)
        with generation_stage('review',excluded_models=[writer.provenance],recovery_request=request):
            await cascade.generate_structured('first complete review',Result)
        assert groq.generate_structured.await_count==2
        assert ('recovery_hold',id(cascade)) not in resources
        with generation_stage('repair'):
            with pytest.raises(AllLLMProvidersExhaustedException) as failure:
                await cascade.generate_structured('reserved recovery request',Result)
        assert failure.value.code=='quota_temporarily_unavailable'
        assert failure.value.retry_after==60
        assert groq.generate_structured.await_count==2
        assert not any((key,id(cascade)) in resources for key in ('review_hold','recovery_hold','final_review_hold'))
        charged=[p for b in cascade.governor._buckets.values() for p in b.records]
        assert len(charged)==2 and all(p.sent and p.tokens==50 for p in charged)
    finally:
        for cleanup in resources['cleanup']:await cleanup()
        TURN_RESOURCES.reset(token)
        await cascade.aclose()


@pytest.mark.asyncio
async def test_evidence_can_atomically_move_review_hold_to_a_different_model(tmp_path):
    cascade,groq=stack(tmp_path)
    resources={'cleanup':[]}
    token=TURN_RESOURCES.set(resources)
    try:
        with generation_stage('planning') as planner:
            await cascade.generate_structured('request',Result)
        hold=resources[('review_hold',id(cascade))]
        original_identity,original_permit=hold['identity'],hold['permit']
        with generation_stage('evidence') as writer:
            await cascade._run('generate_structured',dict(prompt='evidence',schema=Result,
                system_instruction=None,temperature=.1),tiers=[original_identity])
        assert writer.provenance==Provenance(*original_identity)
        assert hold['identity']!=original_identity
        assert cascade.governor._stored_permit(original_permit) is None
        with generation_stage('review',excluded_models=[writer.provenance]) as reviewer:
            await cascade.generate_structured('complete draft',Result)
        assert reviewer.provenance!=writer.provenance
        assert groq.generate_structured.await_count==3
    finally:
        for cleanup in resources['cleanup']:await cleanup()
        TURN_RESOURCES.reset(token)
        await cascade.aclose()


@pytest.mark.asyncio
@pytest.mark.parametrize('blocked_before_http', [False, True])
async def test_two_available_models_need_an_independent_reviewer_when_one_is_rate_limited(tmp_path, blocked_before_http):
    cascade, groq = stack(tmp_path)
    cascade.runtime = cascade.runtime.model_copy(update={'providers': tuple(p.model_copy(update={
        'enabled': p.id != 'groq-fallback-2',
        'disabled_reason': 'preview_disabled' if p.id == 'groq-fallback-2' else None})
        for p in cascade.runtime.providers)})
    primary = cascade._get_cascade_tiers()[0]
    bucket = cascade._quota_bucket(cascade._profile(*primary), *primary)
    if blocked_before_http:
        await cascade.governor.cooldown(bucket, 45)
    else:
        async def generate(*, model, **kwargs):
            if model == primary[1]:
                raise LLMProviderException(*primary, 'queued', status_code=429, retry_after=45)
            return Result(value='fallback')
        groq.generate_structured.side_effect = generate
    resources = {'cleanup': []}
    token = TURN_RESOURCES.set(resources)
    try:
        with generation_stage('planning'):
            with pytest.raises(AllLLMProvidersExhaustedException) as failed:
                await cascade.generate_structured('request', Result)
        assert failed.value.code == ('quota_temporarily_unavailable' if blocked_before_http else 'providers_rate_limited')
        assert 0 < failed.value.retry_after <= 45
        assert groq.generate_structured.await_count == (0 if blocked_before_http else 1)
        assert ('review_hold', id(cascade)) not in resources
    finally:
        for cleanup in resources['cleanup']:
            await cleanup()
        TURN_RESOURCES.reset(token)
        await cascade.aclose()


@pytest.mark.asyncio
async def test_quota_notice_is_not_used_when_groq_fails_validation_with_capacity_left(tmp_path):
    cascade, groq = stack(tmp_path)
    groq.generate_structured.side_effect = LLMProviderException('groq', 'test model',
        'invalid structured output', status_code=400, error_code='structured_output_invalid')
    resources = {'cleanup': []}
    token = TURN_RESOURCES.set(resources)
    try:
        with generation_stage('planning'):
            with pytest.raises(AllLLMProvidersExhaustedException) as caught:
                await cascade.generate_structured('request', Result)
        assert caught.value.code == 'structured_output_invalid'
        assert caught.value.retry_after is None
        assert groq.generate_structured.await_count == 1 + cascade.runtime.max_failovers_per_logical_call
    finally:
        for cleanup in resources['cleanup']:
            await cleanup()
        TURN_RESOURCES.reset(token)
        await cascade.aclose()


@pytest.mark.asyncio
async def test_quota_failure_checks_enabled_groq_paths_before_notifying(tmp_path):
    cascade, groq = stack(tmp_path)
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
        assert caught.value.code == 'quota_temporarily_unavailable'
        assert caught.value.retry_after > 0
        groq.generate_structured.assert_not_awaited()
    finally:
        for cleanup in resources['cleanup']:
            await cleanup()
        TURN_RESOURCES.reset(token)
        await cascade.aclose()


@pytest.mark.asyncio
async def test_no_independent_review_capacity_prevents_wasting_writer_http(tmp_path):
    cascade, groq = stack(tmp_path)
    cascade._review_candidates = lambda _: []
    token = TURN_RESOURCES.set({'cleanup': []})
    from app.core.exceptions import AllLLMProvidersExhaustedException
    try:
        with generation_stage('planning', downstream=('review',)):
            with pytest.raises(AllLLMProvidersExhaustedException):
                await cascade.generate_structured('request', Result)
        groq.generate_structured.assert_not_awaited()
        assert all(row['http_attempts'] == 0 for row in cascade.telemetry)
    finally:
        TURN_RESOURCES.reset(token)
        await cascade.aclose()


@pytest.mark.asyncio
async def test_cancellation_releases_only_unsent_review_capacity(tmp_path):
    cascade, _ = stack(tmp_path)
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
    cascade, groq = stack(tmp_path)
    with generation_stage('planning'):
        ordered = cascade._get_cascade_tiers()
    first, fallback = ordered[:2]
    calls = []

    async def generate(*, model, **kwargs):
        calls.append(model)
        if model == first[1]:
            raise LLMProviderException(first[0], model, 'invalid structured output',
                status_code=400, error_code='structured_output_invalid')
        return Result(value='fallback')

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
    cascade, groq = stack(tmp_path)
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
        assert caught.value.code == 'quota_exhausted'
        assert caught.value.retry_after == 860
        assert ('review_hold', id(cascade)) not in resources
    finally:
        for cleanup in resources['cleanup']:
            await cleanup()
        TURN_RESOURCES.reset(token)
        await cascade.aclose()


@pytest.mark.asyncio
async def test_temporary_rate_limit_recovers_after_reported_quota_wait(tmp_path):
    cascade, groq = stack(tmp_path)
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
        assert groq.generate_structured.await_count <= 2
        clock[0] += caught.value.retry_after
        for cleanup in resources['cleanup']:
            await cleanup()
        resources.clear()
        resources['cleanup'] = []
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
