import json
import pytest
from app.infrastructure.llm.quota import QuotaGovernor,PersistentQuotaGovernor
from app.infrastructure.runtime.schema import QuotaPolicy
from app.core.exceptions import RuntimeConfigurationException


def policy():
    return QuotaPolicy(bucket='recovery-test',scope='model',requests_per_window=6,
        tokens_per_window=100,window_seconds=60,requests_per_day=10,tokens_per_day=1000,day_seconds=86400)


@pytest.mark.asyncio
async def test_failed_multi_replacement_restores_every_unsent_original_permit():
    governor=QuotaGovernor([policy()])
    unused=await governor.reserve('recovery-test',20)
    spent=await governor.reserve('recovery-test',20)
    await governor.mark_sent(spent)
    await governor.finish(spent,None)
    with pytest.raises(RuntimeConfigurationException):
        await governor.replace_unused_many([unused,spent],[('recovery-test',30)])
    assert governor._stored_permit(unused) is unused
    assert governor._stored_permit(spent) is spent
    assert sum(p.tokens for p in governor._buckets['recovery-test'].records)==40


@pytest.mark.asyncio
async def test_shared_recovery_holds_block_other_calls_until_unused_capacity_is_released(tmp_path):
    path=tmp_path/'quota.json'
    def instance():return PersistentQuotaGovernor([policy()],path,lock_timeout_seconds=1,poll_seconds=.01)
    first,other=instance(),instance()
    try:
        provisional=await first.reserve('recovery-test',20)
        snapshot=path.read_bytes()
        assert await first.replacement_status([provisional],[('recovery-test',30)]*3)==(None,0)
        assert path.read_bytes()==snapshot
        holds=await first.replace_unused_many([provisional],[('recovery-test',30)]*3)
        assert len(holds)==3
        assert await other.reserve('recovery-test',11) is None
        await first.mark_sent(holds[0])
        await first.finish(holds[0],{'usage':{'total_tokens':10},'headers':{
            'x-ratelimit-remaining-tokens':'90','x-ratelimit-reset-tokens':'60s'}})
        assert await other.reserve('recovery-test',31) is None
        for hold in holds[1:]:assert await first.release_unused(hold)
        saved=json.loads(path.read_text())['buckets']['recovery-test']
        assert len(saved['records'])==1 and saved['records'][0]['tokens']==10
        assert saved['records'][0]['sent'] and saved['observed_tokens']==90
        assert await other.reserve('recovery-test',90) is not None
    finally:
        await first.aclose()
        await other.aclose()
