"""Cross-process admission regressions; simulated quotas never certify live quality."""
import asyncio
import json
import multiprocessing

import pytest

from app.infrastructure.runtime.schema import QuotaPolicy


def policy():
    return QuotaPolicy(bucket="shared-test", requests_per_window=2, tokens_per_window=100,
        window_seconds=60, requests_per_day=3, tokens_per_day=200, day_seconds=86400)


def governor(path):
    from app.infrastructure.llm.quota import PersistentQuotaGovernor
    return PersistentQuotaGovernor([policy()], path, lock_timeout_seconds=1, poll_seconds=.01)


def reserve_worker(path, output):
    output.put(asyncio.run(governor(path).reserve("shared-test", 60)) is not None)


@pytest.mark.asyncio
async def test_restart_keeps_unknown_canceled_usage_and_cooldown(tmp_path):
    path = tmp_path / "ledger.json"
    first = governor(path)
    permit = await first.reserve("shared-test", 60)
    await first.finish(permit, None)
    assert await governor(path).reserve("shared-test", 60) is None
    await first.cooldown("shared-test", 120)
    assert await governor(path).reserve("shared-test", 1) is None


@pytest.mark.asyncio
async def test_another_instance_finishes_by_reservation_id(tmp_path):
    path = tmp_path / "ledger.json"
    first = governor(path)
    permit = await first.reserve("shared-test", 90)
    await governor(path).finish(permit, {"http_status":200, "usage":{"total_tokens":20}, "headers":{}})
    assert await first.reserve("shared-test", 60) is not None
    assert await first.reserve("shared-test", 1) is None  # request count remains charged


def test_two_processes_cannot_spend_same_balance(tmp_path):
    context = multiprocessing.get_context("spawn")
    output = context.Queue()
    workers = [context.Process(target=reserve_worker, args=(tmp_path / "ledger.json", output)) for _ in range(2)]
    for worker in workers:
        worker.start()
    for worker in workers:
        worker.join(10)
        assert worker.exitcode == 0
    assert sorted(output.get(timeout=1) for _ in workers) == [False, True]


@pytest.mark.asyncio
async def test_corrupt_ledger_fails_closed_without_reset(tmp_path):
    path = tmp_path / "ledger.json"
    path.write_text('{"broken":true}', encoding="utf-8")
    from app.core.exceptions import RuntimeConfigurationException
    with pytest.raises(RuntimeConfigurationException, match="quota_ledger"):
        await governor(path).reserve("shared-test", 1)
    assert json.loads(path.read_text()) == {"broken": True}


@pytest.mark.asyncio
async def test_pending_crash_does_not_wait_forever(tmp_path):
    path = tmp_path / "ledger.json"
    await governor(path).reserve("shared-test", 90)
    loop = asyncio.get_running_loop()
    assert await asyncio.wait_for(governor(path).wait_reserve("shared-test", 60, loop.time()+.03), .2) is None


@pytest.mark.asyncio
async def test_canceled_admission_releases_only_reservation_not_returned_to_http(tmp_path, monkeypatch):
    import threading
    path=tmp_path/'ledger.json'
    admission=governor(path)
    entered, release = threading.Event(), threading.Event()
    transaction=admission._transaction
    def slow(action):
        result=transaction(action)
        entered.set()
        release.wait(2)
        return result
    monkeypatch.setattr(admission,'_transaction',slow)
    task=asyncio.create_task(admission.reserve('shared-test',90))
    await asyncio.to_thread(entered.wait,1)
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    release.set()
    if hasattr(admission,'aclose'):
        await admission.aclose()
    assert await governor(path).reserve('shared-test',90) is not None


@pytest.mark.asyncio
async def test_batch_admission_is_atomic_across_restart(tmp_path):
    path = tmp_path / 'ledger.json'
    first = governor(path)
    assert await first.reserve_many([('shared-test', 60), ('shared-test', 60)]) is None
    permits = await governor(path).reserve_many([('shared-test', 40), ('shared-test', 60)])
    assert len(permits) == 2
    assert await first.reserve('shared-test', 1) is None
    assert await first.release_unused(permits[1]) is True
    assert await governor(path).reserve('shared-test', 60) is not None


@pytest.mark.asyncio
async def test_replace_hold_failure_retains_exact_original_and_sent_never_refunds(tmp_path):
    path = tmp_path / 'ledger.json'
    first = governor(path)
    writer, review = await first.reserve_many([('shared-test', 40), ('shared-test', 60)])
    assert await governor(path).replace_unused(review, 'shared-test', 70) is None
    rows = json.loads(path.read_text())['buckets']['shared-test']['records']
    assert {r['reservation_id'] for r in rows} == {writer.reservation_id, review.reservation_id}
    replacement = await governor(path).replace_unused(review, 'shared-test', 30)
    assert replacement.reservation_id != review.reservation_id
    await first.mark_sent(replacement)
    await first.finish(replacement, {'http_status': 400, 'usage': {}, 'headers': {}})
    assert await governor(path).release_unused(replacement) is False
    rows = json.loads(path.read_text())['buckets']['shared-test']['records']
    assert next(r for r in rows if r['reservation_id'] == replacement.reservation_id)['tokens'] == 30


@pytest.mark.asyncio
async def test_balance_headers_do_not_erase_unsent_review_hold(tmp_path):
    first = governor(tmp_path / 'ledger.json')
    writer, review = await first.reserve_many([('shared-test', 40), ('shared-test', 60)])
    await first.mark_sent(writer)
    await first.finish(writer, {'http_status': 200, 'usage': {'total_tokens': 20},
        'headers': {'x-ratelimit-remaining-tokens': '80', 'x-ratelimit-reset-tokens': '60s'}})
    assert first._buckets['shared-test'].observed_tokens == 20
    assert await first.release_unused(review)
    assert first._buckets['shared-test'].observed_tokens == 80
