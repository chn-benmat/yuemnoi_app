import asyncio
import math
import json
import time
from uuid import uuid4
from collections import deque
from contextlib import asynccontextmanager
from contextvars import ContextVar

from app.core.config import settings
from app.core.exceptions import AllLLMProvidersExhaustedException, LLMProviderException
from app.domain.interfaces.llm_service import LLMServiceInterface
from app.infrastructure.llm.gemini_client import GeminiClient
from app.infrastructure.llm.groq_client import GroqClient
from app.infrastructure.llm.provider_client import ProviderClient
from app.infrastructure.llm.quota import PersistentQuotaGovernor
from app.domain.interfaces.generation_stage import CURRENT_GENERATION, DIAGNOSTIC_PROFILE_ORDER, GENERATION_RECORDING, Provenance
from app.domain.entities.response_review import ResponseReview,NativeResponseReview
from app.infrastructure.runtime.documents import ValidatedFile
from app.infrastructure.runtime.execution import REQUEST_DEADLINE, consume_logical_call, TURN_TRACE_ID, TURN_RESOURCES
from app.infrastructure.runtime.schema import RuntimeDocument

REQUEST_PHASE = ContextVar("llm_request_phase", default="chat")


class CascadeLLMService(LLMServiceInterface):
    """A bounded cascade with shared permission, quota and circuit state."""

    def __init__(self, gemini_client=None, groq_client=None, runtime=None, configuration=None):
        self.configuration = configuration or settings
        self.runtime = runtime or ValidatedFile(self.configuration.AI_RUNTIME_PATH, RuntimeDocument).read()[0]
        self._gemini = gemini_client or GeminiClient(runtime=self.runtime, configuration=self.configuration)
        self._groq = groq_client or GroqClient(runtime=self.runtime, configuration=self.configuration)
        self._clients = {"gemini": self._gemini, "groq": self._groq}
        self._semaphore = asyncio.Semaphore(self.runtime.load.concurrent_requests)
        self._permission_locks = {name: asyncio.Lock() for name in self._clients}
        self._permission_confirmed = set()
        self._auth_blocked = set()
        self._model_open_until = {}
        quotas = []
        for profile in self.runtime.providers:
            provider = profile.protocol.removesuffix("_json_schema")
            model = getattr(self.configuration, profile.model_setting)
            quotas.append(profile.quota.model_copy(update={"bucket": self._quota_bucket(profile, provider, model)}))
        path = self.configuration.AI_QUOTA_LEDGER_PATH or self.configuration.AI_RUNTIME_PATH.parent.parent / self.runtime.quota_ledger.path
        self.governor = PersistentQuotaGovernor(quotas, path,
            lock_timeout_seconds=self.runtime.quota_ledger.lock_timeout_seconds,
            poll_seconds=self.runtime.quota_ledger.poll_seconds)
        self.telemetry = deque(maxlen=self.runtime.http.telemetry_history)

    def _get_cascade_tiers(self):
        capture = CURRENT_GENERATION.get()
        profiles = [p for p in self.runtime.providers if p.enabled]
        if capture is not None:
            rotation = DIAGNOSTIC_PROFILE_ORDER.get()
            order = rotation if rotation is not None else getattr(self.runtime.stages, capture.name).profiles
            ranks = {key: index for index, key in enumerate(order)}
            profiles = [p for p in profiles if p.id in ranks]
            profiles.sort(key=lambda p: ranks.get(p.id, len(ranks)))
        tiers = [(p.protocol.removesuffix("_json_schema"), getattr(self.configuration, p.model_setting)) for p in profiles]
        if capture is not None:
            tiers = [tier for tier in tiers if Provenance(*tier) not in capture.excluded_models]
        return list(dict.fromkeys(tiers))

    def _weight(self, stage, provider, model):
        route = getattr(self.runtime.stages, stage)
        return route.p95_seconds.get(self._profile(provider, model).id)

    def _stage_deadline(self, started, turn_deadline):
        capture = CURRENT_GENERATION.get()
        deadline = started + self.runtime.http.logical_call_deadline_seconds
        if turn_deadline is None:
            return deadline
        deadline = min(deadline, turn_deadline)
        if capture is None:
            return deadline
        available = max(0, turn_deadline - started - self.runtime.stages.finalization_reserve_seconds)
        weights = []
        for name in (capture.name, *capture.downstream):
            route = getattr(self.runtime.stages, name)
            measured = [seconds for key, seconds in route.p95_seconds.items()
                        if key in route.profiles and next(p for p in self.runtime.providers if p.id == key).enabled]
            weights.append(min(measured) if measured else self.runtime.http.logical_call_deadline_seconds)
        # Before measurements exist the same absolute budget is divided evenly.
        stage_share = available * weights[0] / sum(weights)
        return min(deadline, started + stage_share)

    def _profile(self, provider, model):
        protocol = provider + "_json_schema"
        profiles = [p for p in self.runtime.providers if p.protocol == protocol]
        return next((p for p in profiles if getattr(self.configuration, p.model_setting) == model), profiles[0])

    @staticmethod
    def _quota_bucket(profile, provider, model):
        # ใช้ model ที่ตั้งค่าจริง เพื่อไม่แยกโควตาซ้ำเมื่อสอง profile ชี้โมเดลเดียวกัน
        identity = (["model", provider, model] if profile.quota.scope == "model"
                    else ["provider", profile.quota.bucket])
        return json.dumps(identity, separators=(",", ":"))

    def _review_candidates(self, writer):
        profiles = {p.id: p for p in self.runtime.providers if p.enabled}
        candidates = []
        for key in self.runtime.stages.review.profiles:
            profile = profiles.get(key)
            if profile is None:
                continue
            provider = profile.protocol.removesuffix('_json_schema')
            model = getattr(self.configuration, profile.model_setting)
            client = self._clients[provider]
            if ((provider, model) == writer or provider in self._auth_blocked
                    or time.monotonic() < self._model_open_until.get((provider, model), 0)
                    or isinstance(client, ProviderClient) and not client.configured):
                continue
            candidates.append((provider, model, profile))
        return candidates

    async def _turn_permit(self, phase, provider, model, bucket, cost, deadline):
        resources = TURN_RESOURCES.get()
        if resources is None or phase not in ('planning', 'evidence', 'review'):
            return await self.governor.wait_reserve(bucket, cost, deadline=deadline)
        key = ('review_hold', id(self))
        hold = resources.get(key)
        if phase == 'review':
            if hold is None:
                return None
            if hold['permit'].sent:
                permit = await self.governor.wait_reserve(bucket, cost, deadline=deadline)
            else:
                permit = await self.governor.replace_unused(hold['permit'], bucket, cost)
            if permit is not None:
                hold.update(permit=permit, identity=(provider, model))
            return permit
        if hold is not None:
            if hold['identity'] == (provider, model):
                return None  # Reserve an actual different model for the final review.
            return await self.governor.wait_reserve(bucket, cost, deadline=deadline)
        for review_provider, review_model, profile in self._review_candidates((provider, model)):
            review_bucket = self._quota_bucket(profile, review_provider, review_model)
            # The final rendered input is not known yet. Hold only the existing
            # bucket's maximum admissible request; shrink to its measured request
            # cost atomically when the review stage has the complete draft.
            capacity = min(profile.quota.tokens_per_window, profile.quota.tokens_per_day)
            permits = await self.governor.reserve_many([(bucket, cost), (review_bucket, capacity)])
            if permits is not None:
                hold = {'permit': permits[1], 'identity': (review_provider, review_model)}
                resources[key] = hold
                async def release():
                    if not hold['permit'].sent:
                        await self.governor.release_unused(hold['permit'])
                resources['cleanup'].append(release)
                return permits[0]
        return None

    def _quota_retry_delay(self, phase, provider, model, bucket, cost):
        resources = TURN_RESOURCES.get()
        if resources is not None and phase in ('planning','evidence') and resources.get(('review_hold',id(self))) is None:
            delays=[]
            for review_provider, review_model, profile in self._review_candidates((provider,model)):
                review_bucket=self._quota_bucket(profile,review_provider,review_model)
                capacity=min(profile.quota.tokens_per_window,profile.quota.tokens_per_day)
                delays.append(self.governor.retry_after_many([(bucket,cost),(review_bucket,capacity)]))
            return min(delays,default=self.runtime.quota_backoff_seconds)
        return self.governor.retry_after(bucket,cost)

    def _request_cost(self, client, method, model, kwargs):
        if isinstance(client, ProviderClient):
            return client.request_cost(method, model, kwargs)
        return (math.ceil((len(kwargs['prompt']) + len(kwargs.get('system_instruction') or '')) /
                          self.runtime.http.token_estimation_characters_per_token) +
                kwargs.get('max_tokens', self.configuration.STRUCTURED_MAX_OUTPUT_TOKENS))

    async def _release_review_hold(self, resources):
        # คืนเฉพาะโควตาผู้ตรวจที่ยังไม่ได้ส่ง ไม่คืนค่าใช้จ่ายของโมเดลที่เรียกไปแล้ว
        if resources is None:
            return
        key = ('review_hold', id(self))
        hold = resources.get(key)
        if hold is not None and not hold['permit'].sent:
            await self.governor.release_unused(hold['permit'])
            resources.pop(key, None)

    async def _turn_retry_delay(self, resources):
        # คำนวณใหม่หลังปล่อยการจองและบันทึก usage เพื่อไม่แจ้งเวลารอจากสถานะเก่า
        delays = []
        for (provider, model), cost in resources.get(('planning_costs', id(self)), {}).items():
            if provider in self._auth_blocked or time.monotonic() < self._model_open_until.get((provider, model), 0):
                continue
            bucket = self._quota_bucket(self._profile(provider, model), provider, model)
            for review_provider, review_model, profile in self._review_candidates((provider, model)):
                review_bucket = self._quota_bucket(profile, review_provider, review_model)
                capacity = min(profile.quota.tokens_per_window, profile.quota.tokens_per_day)
                delay = await self.governor.next_admission_delay([(bucket, cost), (review_bucket, capacity)])
                if math.isfinite(delay):
                    delays.append(delay)
        return min(delays) if delays else None

    async def start(self):
        for client in self._clients.values():
            if isinstance(client, ProviderClient):
                await client.start()
        # ตรวจสิทธิ์ด้วยคำขอเล็กก่อนรับแชต โดยนับโควตาและ HTTP attempts ตามจริง
        async def probe(provider, tiers):
            if provider in self._permission_confirmed or provider in self._auth_blocked:
                return
            marker = REQUEST_PHASE.set("startup_permission_probe")
            try:
                await self._run("generate_text", dict(prompt=self.runtime.http.permission_probe_prompt,
                    system_instruction=None, max_tokens=self.runtime.http.permission_probe_output_tokens,
                    temperature=self.configuration.GUIDANCE_TEMPERATURE), tiers=tiers)
            except AllLLMProvidersExhaustedException:
                pass
            finally:
                REQUEST_PHASE.reset(marker)
        grouped = {}
        for provider, model in self._get_cascade_tiers():
            client = self._clients[provider]
            if isinstance(client, ProviderClient) and client.configured:
                grouped.setdefault(provider, []).append((provider, model))
        await asyncio.gather(*(probe(provider, tiers) for provider, tiers in grouped.items()))

    async def aclose(self):
        await self.governor.aclose()
        for client in self._clients.values():
            if isinstance(client, ProviderClient):
                await client.aclose()

    @asynccontextmanager
    async def _permission_gate(self, provider):
        if provider in self._permission_confirmed:
            yield
        else:
            lock = self._permission_locks[provider]
            await lock.acquire()
            if provider in self._permission_confirmed:
                lock.release()
                yield
            else:
                try:
                    yield
                finally:
                    lock.release()

    def _failure(self, provider, model, error):
        # คำตอบของหนึ่งคำขอไม่ผ่าน contract ไม่ได้แปลว่าโมเดลล่มสำหรับทุกแชต
        if error.error_code == "structured_output_invalid":
            return
        if error.status_code in (401, 403):
            self._auth_blocked.add(provider)
        else:
            permanent = error.status_code in (400, 404) and error.error_code != "structured_output_invalid"
            self._model_open_until[(provider, model)] = math.inf if permanent else time.monotonic() + self.runtime.circuit_open_seconds

    async def _run(self, method, kwargs, tiers=None):
        consume_logical_call()
        loop = asyncio.get_running_loop()
        started = loop.time()
        deadline = self._stage_deadline(started, REQUEST_DEADLINE.get())
        capture = CURRENT_GENERATION.get()
        phase = capture.name if capture else REQUEST_PHASE.get()
        call_id = uuid4().hex
        recording = GENERATION_RECORDING.get()
        record = None
        if recording is not None and capture is not None:
            record = {'phase': phase, 'logical_call_id': call_id,
                'prompt': kwargs['prompt'], 'system_instruction': kwargs.get('system_instruction'),
                'schema': kwargs['schema'].model_json_schema() if method == 'generate_structured' else None}
            recording.append(record)
        ordered = self._get_cascade_tiers() if tiers is None else list(tiers)
        resources = TURN_RESOURCES.get()
        hold = resources.get(('review_hold', id(self))) if resources is not None else None
        if resources is not None and phase == 'planning':
            costs = {}
            for provider, model in ordered:
                client = self._clients[provider]
                if isinstance(client, ProviderClient) and not client.configured:
                    continue
                try:
                    costs[(provider, model)] = self._request_cost(client, method, model, kwargs)
                except ValueError:
                    continue
            resources[('planning_costs', id(self))] = costs
        if hold is not None:
            if phase == 'review':
                ordered.sort(key=lambda identity: identity != hold['identity'])
            else:
                ordered = [identity for identity in ordered if identity != hold['identity']]
        attempts, quota_denied, oversized, waits = 0, False, False, []
        deadline_limited = False
        try:
            async with asyncio.timeout_at(deadline):
                async with self._semaphore:
                    queue_seconds = loop.time() - started
                    for index, (provider, model) in enumerate(ordered):
                        if deadline-loop.time() < self.runtime.stages.minimum_attempt_seconds:
                            deadline_limited = True
                            break
                        if attempts >= 1 + self.runtime.max_failovers_per_logical_call:
                            break
                        profile, client = self._profile(provider, model), self._clients[provider]
                        quota_bucket = self._quota_bucket(profile, provider, model)
                        if provider in self._auth_blocked or time.monotonic() < self._model_open_until.get((provider, model), 0):
                            continue
                        if isinstance(client, ProviderClient) and not client.configured:
                            self._auth_blocked.add(provider)
                            continue
                        async with self._permission_gate(provider):
                            if provider in self._auth_blocked or time.monotonic() < self._model_open_until.get((provider, model), 0):
                                continue
                            try:
                                cost = self._request_cost(client, method, model, kwargs)
                            except ValueError:
                                self._model_open_until[(provider, model)] = math.inf
                                continue
                            # จำกัดเวลารอโควตาของแต่ละโมเดล เพื่อเหลือเวลาให้โมเดลสำรอง
                            admission_deadline = min(deadline, loop.time() + self.runtime.http.quota_admission_wait_seconds)
                            # Quota polling is bounded by admission_deadline. The
                            # atomic disk transaction is instead bounded by the
                            # existing stage/turn timeout; canceling it at the
                            # polling boundary can discard an already committed permit.
                            permit = await self._turn_permit(phase, provider, model, quota_bucket, cost, admission_deadline)
                            if permit is None:
                                too_large = self.governor.cost_exceeds_capacity(quota_bucket, cost)
                                oversized |= too_large
                                quota_denied |= not too_large
                                retry_delay = None if too_large else self._quota_retry_delay(phase,provider,model,quota_bucket,cost)
                                if retry_delay is not None and math.isfinite(retry_delay):
                                    waits.append(retry_delay)
                                self.telemetry.append({'trace_id': TURN_TRACE_ID.get(), 'phase': phase, 'logical_call_id': call_id, 'provider': provider, 'model': model,
                                                       'status': 'request_budget_exceeded' if too_large else 'quota_admission_denied',
                                                       'admission_scope': 'turn_writer_and_review' if resources is not None and phase == 'planning' else 'logical_call',
                                                       'http_attempts': 0, 'estimated_tokens': cost,
                                                       'retry_after_seconds': retry_delay if retry_delay is not None and math.isfinite(retry_delay) else None,
                                                       'queue_seconds': loop.time() - started})
                                continue
                            if isinstance(client, ProviderClient):
                                client.reset_observation()
                            attempts += 1
                            attempt_start = loop.time()
                            row = {'trace_id': TURN_TRACE_ID.get(), 'phase': phase, 'logical_call_id': call_id,
                                   'attempt_index': attempts, 'provider': provider, 'model': model, 'status': 'started', 'http_attempts': 0,
                                   'queue_seconds': loop.time() - started, 'semaphore_queue_seconds': queue_seconds,
                                   'reserved_tokens': cost, 'remaining_stage_seconds': max(0, deadline-loop.time()),
                                   'remaining_turn_seconds': max(0, REQUEST_DEADLINE.get()-loop.time()) if REQUEST_DEADLINE.get() else None}
                            backups = [(p, m) for p, m in ordered[index+1:] if p not in self._auth_blocked
                                and time.monotonic() >= self._model_open_until.get((p, m), 0)]
                            remaining = max(0, deadline-loop.time())
                            reserve_backup = bool(backups) and attempts < 1 + self.runtime.max_failovers_per_logical_call
                            fraction = 1.0
                            if reserve_backup:
                                first_weight = self._weight(capture.name, provider, model) if capture else None
                                backup_weight = self._weight(capture.name, *backups[0]) if capture else None
                                fraction = first_weight / (first_weight+backup_weight) if first_weight and backup_weight else 1 / (1+self.runtime.max_failovers_per_logical_call)
                            attempt_deadline = loop.time() + remaining*fraction
                            try:
                                await self.governor.mark_sent(permit)
                                async with asyncio.timeout_at(attempt_deadline):
                                    result = await getattr(client, method)(model=model, **kwargs)
                                self._permission_confirmed.add(provider)
                                row['status'] = 'success'
                                if record is not None:
                                    record.update(provider=provider, model=model,
                                        result=result.model_dump(mode='json') if method == 'generate_structured' else result)
                                if capture is not None:
                                    capture.provenance = Provenance(provider, model)
                                    if capture.name == 'review' and isinstance(result, (ResponseReview,NativeResponseReview)):
                                        row['assessment'] = {'semantic_pass': result.semantic_pass,
                                            'neutral_voice_pass': result.neutral_voice_pass,
                                            'issues': [{'kind':issue.kind, 'field_path':issue.field_path} for issue in result.issues]}
                                return result
                            except TimeoutError:
                                row['status'] = 'attempt_deadline_exceeded'
                                deadline_limited = True
                            except LLMProviderException as error:
                                row.update(status=error.error_code, http_status=error.status_code)
                                if error.status_code == 429:
                                    quota_denied = True
                                    seconds = error.retry_after if error.retry_after is not None else self.runtime.quota_backoff_seconds
                                    await self.governor.cooldown(quota_bucket, seconds)
                                    waits.append(seconds)
                                else:
                                    self._failure(provider, model, error)
                            except asyncio.CancelledError:
                                row['status'] = 'canceled'
                                raise
                            except Exception:
                                row['status'] = 'provider_unexpected_failure'
                                self._model_open_until[(provider, model)] = time.monotonic() + self.runtime.circuit_open_seconds
                            finally:
                                observation = client.observation() if isinstance(client, ProviderClient) else None
                                if observation:
                                    if observation['http_status'] == 200:
                                        self._permission_confirmed.add(provider)
                                    row.update(http_attempts=1, http_status=observation['http_status'],
                                               usage=observation['usage'], rate_limit_headers=observation['headers'])
                                    row.update({k: observation[k] for k in ("error_code", "error_type") if k in observation})
                                    if "validation_errors" in observation:
                                        row["validation_errors"] = observation["validation_errors"]
                                elif not isinstance(client, ProviderClient):
                                    row['http_attempts'] = 1
                                row['elapsed_seconds'] = loop.time() - attempt_start
                                row['remaining_stage_seconds_after'] = max(0, deadline-loop.time())
                                self.telemetry.append(row)
                                await asyncio.shield(self.governor.finish(permit, observation))
                                if phase == 'planning' and hold is None and row['status'] != 'success':
                                    await asyncio.shield(self._release_review_hold(resources))
        except TimeoutError:
            raise AllLLMProvidersExhaustedException(code='deadline_exceeded') from None
        retry = min((w for w in waits if w > 0 and math.isfinite(w)), default=self.runtime.quota_backoff_seconds) if quota_denied else None
        if resources is not None:
            await self._release_review_hold(resources)
            if quota_denied:
                refreshed = await self._turn_retry_delay(resources)
                if refreshed is not None:
                    retry = refreshed
                    # ถ้ายังมีคู่โมเดลที่รับคำขอได้ ความล้มเหลวนี้ไม่ใช่ทุกระบบติดโควตา
                    if refreshed <= 0:
                        quota_denied = False
                        retry = None
        code = 'providers_rate_limited' if quota_denied else 'request_budget_exceeded' if oversized else 'deadline_exceeded' if deadline_limited else 'providers_exhausted'
        raise AllLLMProvidersExhaustedException(code=code, retry_after=retry)

    async def generate_text(self, prompt, system_instruction=None, max_tokens=None, temperature=None):
        max_tokens = self.configuration.STRUCTURED_MAX_OUTPUT_TOKENS if max_tokens is None else max_tokens
        temperature = self.configuration.GUIDANCE_TEMPERATURE if temperature is None else temperature
        return await self._run('generate_text', dict(prompt=prompt, system_instruction=system_instruction,
                                                   max_tokens=max_tokens, temperature=temperature))

    async def generate_structured(self, prompt, schema, system_instruction=None, temperature=None):
        temperature = self.configuration.GUIDANCE_TEMPERATURE if temperature is None else temperature
        return await self._run('generate_structured', dict(prompt=prompt, schema=schema,
                                                         system_instruction=system_instruction, temperature=temperature))

    async def generate_stream(self, prompt, system_instruction=None, max_tokens=None, temperature=None):
        yield await self.generate_text(prompt, system_instruction, max_tokens, temperature)
