"""Shared admission and server cooldowns. HTTP controls, not language rules."""

import asyncio
import math
import time
import json
import os
from pathlib import Path
from contextlib import contextmanager
from uuid import uuid4
from collections import deque
from copy import deepcopy
from app.core.exceptions import RuntimeConfigurationException
from dataclasses import dataclass, field
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

from app.infrastructure.runtime.schema import QuotaPolicy


def duration_seconds(value: str | None) -> float | None:
    if not value or len(value) > 64:
        return None
    number, total = "", 0.0
    units = {"s": 1, "m": 60, "h": 3600, "d": 86400}
    index = 0
    while index < len(value):
        character = value[index]
        if character.isdigit() or character == ".":
            number += character
        elif character in units and number:
            try:
                milliseconds = character == "m" and index + 1 < len(value) and value[index+1] == "s"
                total += float(number) * (.001 if milliseconds else units[character])
                if milliseconds:
                    index += 1
            except ValueError:
                return None
            number = ""
        else:
            return None
        index += 1
    if number:
        return None
    return total if math.isfinite(total) and total >= 0 else None


def retry_after_seconds(value: str | None, fallback: float | None) -> float | None:
    if value:
        try:
            seconds = float(value)
            if math.isfinite(seconds) and seconds >= 0:
                return seconds
        except ValueError:
            try:
                deadline = parsedate_to_datetime(value)
                if deadline.tzinfo is not None:
                    return max(0, (deadline - datetime.now(timezone.utc)).total_seconds())
            except (ValueError, TypeError, OverflowError):
                pass
    return fallback


@dataclass
class Permit:
    bucket: str
    started: float
    tokens: int
    pending: bool = True
    reservation_id: str = field(default_factory=lambda: uuid4().hex)
    sent: bool = False


@dataclass
class Bucket:
    policy: QuotaPolicy
    records: deque[Permit] = field(default_factory=deque)
    cooldown_until: float = 0
    observed_tokens: int | None = None
    observed_requests: int | None = None
    tokens_reset: float = 0
    requests_reset: float = 0
    token_limit: int | None = None
    request_limit: int | None = None
    cooldown_reported: bool = True
    changed: asyncio.Event = field(default_factory=asyncio.Event)


class QuotaGovernor:
    def __init__(self, policies: list[QuotaPolicy], clock=time.monotonic, *, reservation_seconds=None):
        self._buckets = {}
        for policy in policies:
            previous = self._buckets.get(policy.bucket)
            if previous is not None and previous.policy != policy:
                raise ValueError("A resolved quota bucket cannot have conflicting limits")
            self._buckets.setdefault(policy.bucket, Bucket(policy))
        self._clock = clock
        self._reservation_seconds = reservation_seconds
        self._lock = asyncio.Lock()

    async def aclose(self):
        """In-memory test adapters have no background disk cleanup."""

    async def reserve(self, bucket: str, tokens: int) -> Permit | None:
        async with self._lock:
            return self._reserve_locked(bucket, tokens)

    def _reserve_many_locked(self, requests):
        saved = {key: (deque(state.records), state.observed_tokens, state.observed_requests)
                 for key, state in self._buckets.items()}
        permits = []
        for bucket, tokens in requests:
            permit = self._reserve_locked(bucket, tokens)
            if permit is None:
                for key, (records, tokens_left, requests_left) in saved.items():
                    state = self._buckets[key]
                    state.records, state.observed_tokens, state.observed_requests = records, tokens_left, requests_left
                return None
            permits.append(permit)
        return permits

    async def reserve_many(self, requests):
        async with self._lock:
            return self._reserve_many_locked(requests)

    def _stored_permit(self, permit):
        return next((r for r in self._buckets[permit.bucket].records if r.reservation_id == permit.reservation_id), None)

    def _release_unused_locked(self, permit):
        stored = self._stored_permit(permit)
        if stored is None or not stored.pending or stored.sent:
            return False
        state = self._buckets[permit.bucket]
        active = state.policy.authority != 'provider' or stored in self._active_holds(state)
        state.records.remove(stored)
        if active and state.observed_tokens is not None:
            state.observed_tokens += stored.tokens
        if active and state.observed_requests is not None:
            state.observed_requests += 1
        state.changed.set()
        state.changed = asyncio.Event()
        return True

    async def release_unused(self, permit):
        async with self._lock:
            return self._release_unused_locked(permit)

    def _replace_unused_locked(self, permit, bucket, tokens):
        saved = {key: (deque(state.records), state.observed_tokens, state.observed_requests)
                 for key, state in self._buckets.items()}
        if not self._release_unused_locked(permit):
            return None
        replacement = self._reserve_locked(bucket, tokens)
        if replacement is None:
            for key, (records, token_balance, request_balance) in saved.items():
                state = self._buckets[key]
                state.records, state.observed_tokens, state.observed_requests = records, token_balance, request_balance
        return replacement

    async def replace_unused(self, permit, bucket, tokens):
        async with self._lock:
            return self._replace_unused_locked(permit, bucket, tokens)

    def _replace_unused_many_locked(self, old_permits, requests, *, status_only=False):
        saved = {key: (deque(state.records), state.observed_tokens, state.observed_requests)
                 for key, state in self._buckets.items()}
        try:
            for permit in old_permits:
                if not self._release_unused_locked(permit):
                    raise RuntimeConfigurationException('quota_reservation_missing')
        except RuntimeConfigurationException:
            for key, (records,tokens,count) in saved.items():
                state=self._buckets[key]
                state.records,state.observed_tokens,state.observed_requests=records,tokens,count
            raise
        result = (self._admission_status_many_locked(requests) if status_only
                  else self._reserve_many_locked(requests))
        if status_only or result is None:
            for key, (records, tokens, count) in saved.items():
                state = self._buckets[key]
                state.records, state.observed_tokens, state.observed_requests = records, tokens, count
        return result

    async def replace_unused_many(self, old_permits, requests):
        async with self._lock:
            return self._replace_unused_many_locked(old_permits, requests)

    async def replacement_status(self, old_permits, requests):
        async with self._lock:
            return self._replace_unused_many_locked(old_permits, requests, status_only=True)

    async def mark_sent(self, permit):
        async with self._lock:
            stored = self._stored_permit(permit)
            if stored is None or not stored.pending:
                raise RuntimeConfigurationException('quota_reservation_missing')
            stored.sent = permit.sent = True

    def _provider_status(self, state, tokens, requests=1):
        """Only provider balances/caps and active holds decide API admission.

        Historical local usage is retained for statistics. It cannot establish
        an unreported daily limit, balance or provider reset time.
        """
        now = self._clock()
        token_balance = state.observed_tokens
        request_balance = state.observed_requests
        if state.tokens_reset <= now:
            token_balance = None
        if state.requests_reset <= now:
            request_balance = None
        pending = self._active_holds(state)
        if token_balance is None and state.token_limit is not None:
            token_balance = max(0, state.token_limit - sum(r.tokens for r in pending))
        if request_balance is None and state.request_limit is not None:
            request_balance = max(0, state.request_limit - len(pending))
        if (state.token_limit is not None and tokens > state.token_limit
                or state.request_limit is not None and requests > state.request_limit):
            return 'request_budget_exceeded', math.inf
        delays, daily = [], False
        if now < state.cooldown_until:
            delays.append(state.cooldown_until - now if state.cooldown_reported else math.inf)
        if token_balance is not None and token_balance < tokens:
            delays.append(state.tokens_reset - now if state.tokens_reset > now else math.inf)
        if request_balance is not None and request_balance < requests:
            daily = state.observed_requests is not None and state.requests_reset > now
            delays.append(state.requests_reset - now if state.requests_reset > now else math.inf)
        return ('quota_exhausted' if daily else 'quota_temporarily_unavailable' if delays else None,
                max(delays, default=0))

    def _active_holds(self, state):
        # A crashed process cannot hold future API capacity indefinitely. The
        # application turn deadline bounds live reservations, independently of
        # quota windows; retain expired records as usage/statistical evidence.
        now = self._clock()
        return [r for r in state.records if r.pending and (self._reservation_seconds is None
                or now - r.started < self._reservation_seconds)]

    def _reserve_locked(self, bucket, tokens):
        state = self._buckets[bucket]
        now, policy = self._clock(), state.policy
        while state.records and now - state.records[0].started >= policy.day_seconds:
            state.records.popleft()
        if (policy.authority == 'provider' or state.tokens_reset > 0) and now >= state.tokens_reset:
            state.observed_tokens = None
        if (policy.authority == 'provider' or state.requests_reset > 0) and now >= state.requests_reset:
            state.observed_requests = None
        recent = [r for r in state.records if now - r.started < policy.window_seconds]
        limit = min(policy.tokens_per_window, state.token_limit or policy.tokens_per_window)
        if policy.authority == 'provider':
            if self._provider_status(state, tokens)[0] is not None:
                return None
        elif (now < state.cooldown_until or len(recent) >= policy.requests_per_window
                or len(state.records) >= policy.requests_per_day
                or sum(r.tokens for r in recent) + tokens > limit
                or sum(r.tokens for r in state.records) + tokens > policy.tokens_per_day
                or state.observed_tokens is not None and state.observed_tokens < tokens
                or state.observed_requests is not None and state.observed_requests <= 0):
            return None
        permit = Permit(bucket, now, tokens)
        state.records.append(permit)
        if state.observed_tokens is not None:
            state.observed_tokens -= tokens
        if state.observed_requests is not None:
            state.observed_requests -= 1
        return permit

    async def wait_reserve(self, bucket: str, tokens: int, deadline=None) -> Permit | None:
        while True:
            async with self._lock:
                permit = self._reserve_locked(bucket, tokens)
                if permit is not None:
                    return permit
                state = self._buckets[bucket]
                if state.policy.authority == 'provider':
                    code, delay = self._provider_status(state, tokens)
                    if code == 'request_budget_exceeded':
                        return None
                    now = self._clock()
                    if any(r.pending for r in state.records) and now >= state.cooldown_until:
                        changed, delay = state.changed, None
                    elif deadline is None or not math.isfinite(delay) or delay <= 0 or now + delay >= deadline:
                        return None
                    else:
                        changed = None
                else:
                    changed, delay = self._configured_wait(state, tokens, deadline)
                    if changed is None and delay is None:
                        return None
            if changed is not None:
                if deadline is None:
                    await changed.wait()
                else:
                    try:
                        async with asyncio.timeout(max(0, deadline - self._clock())):
                            await changed.wait()
                    except TimeoutError:
                        return None
            else:
                await asyncio.sleep(delay)

    def _configured_wait(self, state, tokens, deadline):
        """Compatibility for explicitly configured limits, used by older deployments."""
        limit = min(state.policy.tokens_per_window, state.token_limit or state.policy.tokens_per_window)
        if tokens > limit:
            return None, None
        now = self._clock()
        if any(r.pending for r in state.records) and now >= state.cooldown_until:
            changed, delay = state.changed, None
        else:
            ready = max(now, state.cooldown_until)
            recent = [r for r in state.records if now-r.started < state.policy.window_seconds]
            remaining = sum(r.tokens for r in recent)
            count = len(recent)
            for record in recent:
                if remaining + tokens <= limit and count < state.policy.requests_per_window:
                    break
                remaining -= record.tokens
                count -= 1
                ready = max(ready, record.started + state.policy.window_seconds)
            if state.observed_tokens is not None and state.observed_tokens < tokens:
                ready = max(ready, state.tokens_reset)
            if state.observed_requests is not None and state.observed_requests <= 0:
                ready = max(ready, state.requests_reset)
            if (deadline is None or ready <= now or ready >= deadline or
                    len(state.records) >= state.policy.requests_per_day or
                    sum(r.tokens for r in state.records) + tokens > state.policy.tokens_per_day):
                return None, None
            changed, delay = None, ready - now
        return changed, delay

    async def finish(self, permit: Permit, observation: dict | None):
        async with self._lock:
            self._finish_locked(permit, observation)

    def _finish_locked(self, permit, observation):
        state = self._buckets[permit.bucket]
        now = self._clock()
        if not permit.pending:
            return
        permit.pending = False
        state.changed.set()
        state.changed = asyncio.Event()
        if observation is None:
            return  # Canceled connections may still have reached the server.
        reserved = permit.tokens
        usage = observation.get("usage", {})
        if isinstance(usage.get("total_tokens"), int):
            permit.tokens = max(0, usage["total_tokens"] - usage.get("cached_tokens", 0))
        if state.observed_tokens is not None:
            state.observed_tokens = max(0, state.observed_tokens + reserved - permit.tokens)
        headers = observation.get("headers", {})
        provider_authority = state.policy.authority == 'provider'
        for name, attr, reset_header, reset_attr in (
            ("x-ratelimit-remaining-tokens", "observed_tokens", "x-ratelimit-reset-tokens", "tokens_reset"),
            ("x-ratelimit-remaining-requests", "observed_requests", "x-ratelimit-reset-requests", "requests_reset"),
        ):
            try:
                number = int(headers[name])
            except (KeyError, ValueError, TypeError):
                continue
            if number < 0:
                continue
            # Recovery holds and other in-flight HTTP can be absent from this
            # response's snapshot. Keep their capacity deducted until finished.
            holds = (self._active_holds(state) if provider_authority else
                     [r for r in state.records if r.pending and not r.sent])
            number = max(0, number - (sum(r.tokens for r in holds) if attr == 'observed_tokens' else len(holds)))
            previous = getattr(state, attr)
            setattr(state, attr, number if provider_authority or previous is None else min(previous, number))
            reset = duration_seconds(headers.get(reset_header))
            period = state.policy.window_seconds if attr == "observed_tokens" else state.policy.day_seconds
            if provider_authority:
                setattr(state, reset_attr, now + reset if reset is not None else 0)
            else:
                setattr(state, reset_attr, max(getattr(state, reset_attr), now + (reset if reset is not None else period)))
        try:
            token_limit = int(headers["x-ratelimit-limit-tokens"])
            if token_limit > 0:
                state.token_limit = token_limit if provider_authority else min(state.policy.tokens_per_window, token_limit)
        except (KeyError, ValueError, TypeError):
            pass
        if provider_authority:
            try:
                request_limit = int(headers['x-ratelimit-limit-requests'])
                if request_limit > 0:
                    state.request_limit = request_limit
            except (KeyError, ValueError, TypeError):
                pass

    async def cooldown(self, bucket: str, seconds: float, *, reported=True):
        async with self._lock:
            state = self._buckets[bucket]
            self._cooldown_locked(state, seconds, reported)

    def _cooldown_locked(self, state, seconds, reported):
        until = self._clock() + seconds
        if until >= state.cooldown_until:
            state.cooldown_until, state.cooldown_reported = until, reported

    def retry_after(self, bucket: str, tokens: int = 0, requests: int = 1) -> float:
        """Conservative next admission time for this cost, without spending quota.

        Rolling daily tokens can block a small request even after the minute
        window clears. Sent usage of unknown size remains charged until expiry.
        """
        state = self._buckets[bucket]
        if state.policy.authority == 'provider':
            return self._provider_status(state, tokens, requests)[1]
        now = self._clock()
        policy = state.policy
        window_limit = min(policy.tokens_per_window, state.token_limit or policy.tokens_per_window)
        if tokens > min(window_limit, policy.tokens_per_day) or requests > min(policy.requests_per_window, policy.requests_per_day):
            return math.inf
        ready = max(now, state.cooldown_until)
        for seconds, token_limit, request_limit in (
            (policy.window_seconds, window_limit, policy.requests_per_window),
            (policy.day_seconds, policy.tokens_per_day, policy.requests_per_day),
        ):
            records = sorted((r for r in state.records if now-r.started < seconds), key=lambda r:r.started)
            remaining, count = sum(r.tokens for r in records), len(records)
            for record in records:
                if remaining + tokens <= token_limit and count + requests <= request_limit:
                    break
                remaining -= record.tokens
                count -= 1
                ready = max(ready, record.started + seconds)
        if state.observed_tokens is not None and state.observed_tokens < tokens and state.tokens_reset > now:
            ready = max(ready, state.tokens_reset)
        if state.observed_requests is not None and state.observed_requests < requests and state.requests_reset > now:
            ready = max(ready, state.requests_reset)
        return ready - now

    def retry_after_many(self, reservations) -> float:
        """An atomic writer/reviewer pair needs capacity in every shared bucket."""
        costs = {}
        for bucket, tokens in reservations:
            previous_tokens, previous_requests = costs.get(bucket, (0, 0))
            costs[bucket] = (previous_tokens+tokens, previous_requests+1)
        return max((self.retry_after(bucket, tokens, requests) for bucket,(tokens,requests) in costs.items()), default=0)

    async def next_admission_delay(self, reservations) -> float:
        async with self._lock:
            return self.retry_after_many(reservations)

    def _admission_status_many_locked(self, reservations):
        costs = {}
        for bucket, tokens in reservations:
            previous_tokens, previous_requests = costs.get(bucket, (0, 0))
            costs[bucket] = (previous_tokens + tokens, previous_requests + 1)
        codes = set()
        now = self._clock()
        for bucket, (tokens, requests) in costs.items():
            state = self._buckets[bucket]
            policy = state.policy
            if policy.authority == 'provider':
                code, _ = self._provider_status(state, tokens, requests)
                if code is not None:
                    codes.add(code)
                continue
            limit = min(policy.tokens_per_window, state.token_limit or policy.tokens_per_window)
            if tokens > min(limit, policy.tokens_per_day) or requests > min(policy.requests_per_window, policy.requests_per_day):
                codes.add('request_budget_exceeded')
                continue
            daily = [r for r in state.records if now - r.started < policy.day_seconds]
            recent = [r for r in daily if now - r.started < policy.window_seconds]
            if sum(r.tokens for r in daily) + tokens > policy.tokens_per_day or len(daily) + requests > policy.requests_per_day:
                codes.add('quota_exhausted')
            elif (now < state.cooldown_until
                    or sum(r.tokens for r in recent) + tokens > limit
                    or len(recent) + requests > policy.requests_per_window
                    or state.tokens_reset > now and state.observed_tokens is not None and state.observed_tokens < tokens
                    or state.requests_reset > now and state.observed_requests is not None and state.observed_requests < requests):
                codes.add('quota_temporarily_unavailable')
        code = ('request_budget_exceeded' if 'request_budget_exceeded' in codes else
                'quota_exhausted' if 'quota_exhausted' in codes else
                'quota_temporarily_unavailable' if codes else None)
        return code, self.retry_after_many(reservations)

    async def next_admission_status(self, reservations):
        """Classify a known usage limit without reserving tokens or guessing queue state."""
        async with self._lock:
            return self._admission_status_many_locked(reservations)

    def cost_exceeds_capacity(self, bucket: str, tokens: int) -> bool:
        state = self._buckets[bucket]
        if state.policy.authority == 'provider':
            return state.token_limit is not None and tokens > state.token_limit
        return tokens > min(state.policy.tokens_per_window, state.token_limit or state.policy.tokens_per_window,
                            state.policy.tokens_per_day)


from pydantic import BaseModel, ConfigDict, Field
from typing import Literal

class StoredPermit(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, allow_inf_nan=False)
    bucket: str
    sent: bool = True  # Legacy unfinished records may already have reached HTTP.
    started: float = Field(ge=0)
    tokens: int = Field(ge=0)
    pending: bool
    reservation_id: str = Field(min_length=1)

class StoredBucket(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, allow_inf_nan=False)
    policy: dict
    records: list[StoredPermit]
    cooldown_until: float = Field(ge=0)
    observed_tokens: int | None = Field(ge=0)
    observed_requests: int | None = Field(ge=0)
    tokens_reset: float = Field(ge=0)
    requests_reset: float = Field(ge=0)
    token_limit: int | None = Field(gt=0)
    request_limit: int | None = Field(default=None, gt=0)
    cooldown_reported: bool = True

class StoredLedger(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, allow_inf_nan=False)
    version: Literal[1]
    buckets: dict[str, StoredBucket]



class PersistentQuotaGovernor(QuotaGovernor):
    """Same limits with UTC reservations shared by every process on this host.

    OS locks are released on process death. Unfinished reservations are deliberately
    retained until their quota window expires; a canceled HTTP request can be billed.
    Disk operations and lock acquisition run outside the event loop.
    """

    def __init__(self, policies, path, *, lock_timeout_seconds, poll_seconds, reservation_seconds=None):
        super().__init__(policies, clock=time.time, reservation_seconds=reservation_seconds)
        self.path = Path(path)
        self.lock_timeout_seconds = lock_timeout_seconds
        self.poll_seconds = poll_seconds
        self._cleanup_tasks = set()
        self._cleanup_errors = []

    @contextmanager
    def _file_lock(self):
        from app.core.exceptions import RuntimeConfigurationException
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.path.with_suffix(self.path.suffix + ".lock").open("a+b") as handle:
            if handle.tell() == 0:
                handle.write(b"\0")
                handle.flush()
            deadline = time.monotonic() + self.lock_timeout_seconds
            while True:
                try:
                    handle.seek(0)
                    if os.name == "nt":
                        import msvcrt
                        msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
                    else:
                        import fcntl
                        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except OSError:
                    if time.monotonic() >= deadline:
                        raise RuntimeConfigurationException("quota_ledger_lock_timeout") from None
                    time.sleep(self.poll_seconds)
            try:
                yield
            finally:
                handle.seek(0)
                if os.name == "nt":
                    import msvcrt
                    msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(handle.fileno(), fcntl.LOCK_UN)

    def _load(self):
        from app.core.exceptions import RuntimeConfigurationException
        if not self.path.exists():
            return {}
        try:
            raw = json.loads(self.path.read_bytes())
            data = StoredLedger.model_validate(raw).model_dump()
            # Validate all rows, but preserve unowned account rows byte-for-byte
            # as JSON values, including older rows without newly added fields.
            saved = raw['buckets']
            for key, state in self._buckets.items():
                if key not in saved:
                    continue
                row = data['buckets'][key]
                old_policy = QuotaPolicy.model_validate(row['policy'])
                if old_policy.model_dump(exclude={'authority'}) != state.policy.model_dump(exclude={'authority'}):
                    raise ValueError("Conflicting persistent quota policy")
                records = [Permit(**r) for r in row["records"]]
                if any(r.bucket != key for r in records) or len({r.reservation_id for r in records}) != len(records):
                    raise ValueError("Invalid reservation identity")
                state.records = deque(sorted((r for r in records if self._clock()-r.started < state.policy.day_seconds),
                                             key=lambda r: r.started))
                for attr in ("cooldown_until", "observed_tokens", "observed_requests", "tokens_reset", "requests_reset", "token_limit", "request_limit", "cooldown_reported"):
                    setattr(state, attr, row[attr])
                if old_policy.authority != state.policy.authority:
                    # The old algorithm clamped caps/balances and invented reset
                    # times. Refresh those caches; preserve every usage/hold ID
                    # and actual cooldown. No ledger or account is reset.
                    state.observed_tokens = state.observed_requests = None
                    state.token_limit = state.request_limit = None
                    state.tokens_reset = state.requests_reset = 0
            return saved
        except (ValueError, KeyError, TypeError, OSError):
            raise RuntimeConfigurationException("quota_ledger_invalid") from None

    def _transaction(self, action):
        from dataclasses import asdict
        with self._file_lock():
            saved = self._load()
            previous = deepcopy(saved)
            result = action()
            for key, state in self._buckets.items():
                saved[key] = {"policy": state.policy.model_dump(mode="json"),
                    "records": [asdict(r) for r in state.records],
                    **{attr: getattr(state, attr) for attr in ("cooldown_until", "observed_tokens", "observed_requests",
                         "tokens_reset", "requests_reset", "token_limit", "request_limit", "cooldown_reported")}}
            if self.path.exists() and previous == saved:
                return result
            temporary = self.path.with_name(self.path.name + "." + uuid4().hex + ".tmp")
            try:
                with temporary.open("x", encoding="utf-8") as handle:
                    json.dump({"version": 1, "buckets": saved}, handle, allow_nan=False, separators=(",", ":"))
                    handle.flush()
                    os.fsync(handle.fileno())
                temporary.replace(self.path)
            finally:
                temporary.unlink(missing_ok=True)
            return result

    async def reserve(self, bucket, tokens):
        return await self._admit(lambda: self._reserve_locked(bucket, tokens))

    async def reserve_many(self, requests):
        return await self._admit(lambda: self._reserve_many_locked(requests))

    async def next_admission_delay(self, reservations):
        # Read the shared ledger under the same OS lock, including another
        # process's recent reservations. This never makes a new reservation.
        async with self._lock:
            return await asyncio.to_thread(self._transaction,lambda:self.retry_after_many(reservations))

    async def next_admission_status(self, reservations):
        async with self._lock:
            return await asyncio.to_thread(self._transaction,
                lambda: self._admission_status_many_locked(reservations))

    async def replace_unused(self, permit, bucket, tokens):
        return await self._admit(lambda: self._replace_unused_locked(permit, bucket, tokens))

    async def replace_unused_many(self, old_permits, requests):
        return await self._admit(lambda: self._replace_unused_many_locked(old_permits, requests))

    async def replacement_status(self, old_permits, requests):
        # A status result is not a Permit and must never enter admission's
        # cancellation cleanup, which releases newly allocated permits.
        async with self._lock:
            return await asyncio.to_thread(self._transaction,
                lambda: self._replace_unused_many_locked(old_permits, requests, status_only=True))

    async def release_unused(self, permit):
        async with self._lock:
            return await asyncio.to_thread(self._transaction, lambda: self._release_unused_locked(permit))

    async def mark_sent(self, permit):
        async with self._lock:
            def update():
                stored = self._stored_permit(permit)
                if stored is None or not stored.pending:
                    raise RuntimeConfigurationException('quota_reservation_missing')
                stored.sent = permit.sent = True
            await asyncio.to_thread(self._transaction, update)

    async def _admit(self, action):
        async with self._lock:
            operation = asyncio.create_task(asyncio.to_thread(self._transaction, action))
            try:
                return await asyncio.shield(operation)
            except asyncio.CancelledError:
                # The permit was never returned to the HTTP caller. A disk write
                # may finish after cancellation, so clean it up by its exact ID.
                async def cleanup():
                    result = await operation
                    if result is not None:
                        permits = result if isinstance(result, list) else [result]
                        async with self._lock:
                            def release():
                                for permit in permits:
                                    self._release_unused_locked(permit)
                            await asyncio.to_thread(self._transaction, release)
                task = asyncio.create_task(cleanup())
                self._cleanup_tasks.add(task)
                def completed(done):
                    self._cleanup_tasks.discard(done)
                    if not done.cancelled() and done.exception() is not None:
                        self._cleanup_errors.append(done.exception())
                task.add_done_callback(completed)
                raise

    async def aclose(self):
        if self._cleanup_tasks:
            await asyncio.gather(*tuple(self._cleanup_tasks), return_exceptions=True)
        if self._cleanup_errors:
            raise self._cleanup_errors[0]

    async def wait_reserve(self, bucket, tokens, deadline=None):
        loop = asyncio.get_running_loop()
        while True:
            permit = await self.reserve(bucket, tokens)
            if permit is not None or deadline is None or self.cost_exceeds_capacity(bucket, tokens):
                return permit
            remaining = deadline - loop.time()
            if remaining <= 0:
                return None
            await asyncio.sleep(min(self.poll_seconds, remaining))

    async def finish(self, permit, observation):
        # Reuse observation parsing on the persisted reservation, not a stale object.
        async with self._lock:
            def update():
                stored = next((r for r in self._buckets[permit.bucket].records
                               if r.reservation_id == permit.reservation_id), None)
                if stored is None or not stored.pending:
                    return
                self._finish_locked(stored, observation)
                permit.tokens, permit.pending = stored.tokens, stored.pending
            await asyncio.to_thread(self._transaction, update)

    async def cooldown(self, bucket, seconds, *, reported=True):
        async with self._lock:
            def update():
                state = self._buckets[bucket]
                self._cooldown_locked(state, seconds, reported)
            await asyncio.to_thread(self._transaction, update)
