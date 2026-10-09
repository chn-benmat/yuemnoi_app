"""Admission retry metadata must include actual request cost and rolling quotas."""
import pytest
from app.infrastructure.llm.quota import QuotaGovernor, PersistentQuotaGovernor
from app.infrastructure.runtime.schema import QuotaPolicy


def policy(bucket='window-test'):
    return QuotaPolicy(bucket=bucket,requests_per_window=10,tokens_per_window=100,
        window_seconds=60,requests_per_day=20,tokens_per_day=150,day_seconds=1000)


@pytest.mark.asyncio
async def test_retry_waits_for_enough_daily_tokens_not_next_minute():
    clock=[0.0];governor=QuotaGovernor([policy()],clock=lambda:clock[0])
    first=await governor.reserve('window-test',90)
    await governor.mark_sent(first);await governor.finish(first,None)
    clock[0]=70
    second=await governor.reserve('window-test',50)
    await governor.mark_sent(second);await governor.finish(second,None)
    clock[0]=140
    assert await governor.reserve('window-test',30) is None
    assert governor.retry_after('window-test',30)==860
    clock[0]=1000
    assert governor.retry_after('window-test',30)==0
    assert await governor.reserve('window-test',30) is not None


@pytest.mark.asyncio
async def test_retry_releases_multiple_records_until_cost_fits():
    clock=[0.0];governor=QuotaGovernor([policy()],clock=lambda:clock[0])
    await governor.reserve('window-test',30)
    clock[0]=10;await governor.reserve('window-test',30)
    clock[0]=20
    assert governor.retry_after('window-test',90)==50


@pytest.mark.asyncio
async def test_persistent_retry_matches_restart_admission(tmp_path):
    path=tmp_path/'ledger.json';clock=[0.0]
    first=PersistentQuotaGovernor([policy()],path,lock_timeout_seconds=1,poll_seconds=.01)
    first._clock=lambda:clock[0]
    await first.reserve('window-test',90)
    clock[0]=70;await first.reserve('window-test',50)
    clock[0]=140
    restarted=PersistentQuotaGovernor([policy()],path,lock_timeout_seconds=1,poll_seconds=.01)
    restarted._clock=lambda:clock[0]
    assert await restarted.reserve('window-test',30) is None
    assert restarted.retry_after('window-test',30)==860


@pytest.mark.asyncio
async def test_atomic_writer_review_delay_uses_both_buckets():
    clock=[0.0];governor=QuotaGovernor([policy('writer'),policy('review')],clock=lambda:clock[0])
    await governor.reserve('review',90)
    clock[0]=70;await governor.reserve('review',50)
    clock[0]=140
    assert await governor.reserve_many([('writer',30),('review',100)]) is None
    assert governor.retry_after_many([('writer',30),('review',100)])==860
    assert await governor.reserve('writer',100) is not None


@pytest.mark.asyncio
async def test_observed_balance_reset_applies_only_when_cost_is_denied():
    clock=[0.0];governor=QuotaGovernor([policy()],clock=lambda:clock[0])
    state=governor._buckets['window-test'];state.observed_tokens=50;state.tokens_reset=80
    assert governor.retry_after('window-test',30)==0
    assert governor.retry_after('window-test',60)==80
    clock[0]=80
    assert governor.retry_after('window-test',60)==0


@pytest.mark.asyncio
async def test_read_only_preflight_loads_other_process_usage_without_reserving(tmp_path):
    path=tmp_path/'ledger.json';clock=[0.0]
    first=PersistentQuotaGovernor([policy()],path,lock_timeout_seconds=1,poll_seconds=.01)
    first._clock=lambda:clock[0]
    await first.reserve('window-test',90)
    clock[0]=70;await first.reserve('window-test',50)
    clock[0]=140
    before=path.read_bytes()
    restarted=PersistentQuotaGovernor([policy()],path,lock_timeout_seconds=1,poll_seconds=.01)
    restarted._clock=lambda:clock[0]
    assert await restarted.next_admission_delay([('window-test',30)])==860
    assert path.read_bytes()==before
