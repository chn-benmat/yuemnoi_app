"""Pooled transport with native schemas and safe per-task observations."""

import json
import math
import time
from collections import Counter
from copy import deepcopy
from contextvars import ContextVar

import httpx
from pydantic import BaseModel, ValidationError

from app.core.config import settings
from app.core.exceptions import LLMProviderException
from app.infrastructure.llm.quota import retry_after_seconds
from app.infrastructure.runtime.documents import ValidatedFile
from app.infrastructure.runtime.schema import RuntimeDocument, unique_pairs
from app.domain.interfaces.generation_stage import GENERATION_RECORDING,CURRENT_GENERATION

SAFE_HEADERS = ("retry-after", "x-ratelimit-limit-requests", "x-ratelimit-limit-tokens",
                "x-ratelimit-remaining-requests", "x-ratelimit-remaining-tokens",
                "x-ratelimit-reset-requests", "x-ratelimit-reset-tokens")


def native_schema(schema: type[BaseModel]) -> dict:
    def convert(value):
        if isinstance(value, list):
            return [convert(v) for v in value]
        if not isinstance(value, dict):
            return value
        result = {}
        for key, child in value.items():
            if key in ("default", "title"):
                continue
            if key == "x-provider-description" or (key == "description" and not value.get("x-provider-description")):
                continue
            if key == "const":
                # enum ค่าเดียวคงข้อจำกัดเดิม และใช้รูปแบบร่วมของ provider
                result["enum"] = [child]
                continue
            result[key] = {name: convert(spec) for name, spec in child.items()} if key in ("properties", "$defs") else convert(child)
        if result.get("type") == "object":
            if isinstance(result.get("additionalProperties"), dict):
                raise ValueError("Open-ended objects cannot use strict native output")
            result["additionalProperties"] = False
            result["required"] = list(result.get("properties", {}))
        return result
    return convert(schema.model_json_schema())


def compact_schema_definitions(document):
    """Share repeated enum schemas and shorten refs without changing constraints."""
    document = deepcopy(document)
    counts, enums = Counter(), {}
    def collect(value):
        if isinstance(value, list):
            for child in value: collect(child)
        elif isinstance(value, dict):
            if 'enum' in value and value.get('type') == 'string':
                key = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
                counts[key] += 1
                enums[key] = value
            for child in value.values(): collect(child)
    collect(document)
    definitions = document.get('$defs', {})
    shared = {}
    for key, count in counts.items():
        name = 'shared_enum_' + str(len(shared))
        while name in definitions:
            name += '_'
        reference = {'$ref': '#/$defs/' + name}
        # Factor only when its added definition and all refs use fewer bytes.
        if count * len(key) > len(key) + len(json.dumps({name: enums[key]})) + count * len(json.dumps(reference)):
            shared[key] = name
    def factor(value):
        if isinstance(value, list): return [factor(child) for child in value]
        if not isinstance(value, dict): return value
        if 'enum' in value and value.get('type') == 'string':
            key = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
            if key in shared: return {'$ref': '#/$defs/' + shared[key]}
        return {key: factor(child) for key, child in value.items()}
    document = factor(document)
    if shared:
        document.setdefault('$defs', {}).update({name: enums[key] for key, name in shared.items()})
    names = {name: 'd' + str(index) for index, name in enumerate(document.get('$defs', {}))}
    def visit(value):
        if isinstance(value, list):
            return [visit(child) for child in value]
        if not isinstance(value, dict):
            return value
        result = {}
        for key, child in value.items():
            if key == '$defs':
                result[key] = {names[name]: visit(spec) for name, spec in child.items()}
            elif key == '$ref' and child.startswith('#/$defs/'):
                result[key] = '#/$defs/' + names[child.removeprefix('#/$defs/')]
            else:
                result[key] = visit(child)
        return result
    return visit(document)


def decode_structured(raw, schema):
    return schema.model_validate(json.loads(raw, object_pairs_hook=unique_pairs))


def validate_native_keys(candidate, schema):
    """Enforce wire-required keys before domain defaults or aliases can fill them.

    Pydantic handles types, bounds and semantic validators afterwards. This
    guard keeps the stricter provider schema's object shape at every depth.
    """
    document = native_schema(schema)
    definitions = document.get('$defs', {})

    def resolve(spec):
        return definitions.get(spec.get('$ref', '').removeprefix('#/$defs/'), spec)

    def compatible(value, spec):
        spec = resolve(spec)
        kind = spec.get('type')
        if kind == 'null':
            return value is None
        if kind == 'array':
            return isinstance(value, list)
        if kind == 'string':
            return isinstance(value, str)
        if kind == 'boolean':
            return type(value) is bool
        if kind in ('number', 'integer'):
            return type(value) in ((int, float) if kind == 'number' else (int,))
        if kind == 'object':
            if not isinstance(value, dict):
                return False
            # Choose discriminated object unions using their actual literals.
            return all(name not in value or 'enum' not in child or value[name] in child['enum']
                       for name, child in spec.get('properties', {}).items())
        return True

    def inspect(value, spec, path):
        spec = resolve(spec)
        if 'anyOf' in spec:
            branches = [inspect(value, branch, path) for branch in spec['anyOf'] if compatible(value, branch)]
            return min(branches, key=len) if branches else []
        errors = []
        if isinstance(value, dict) and spec.get('type') == 'object':
            properties = spec.get('properties', {})
            errors.extend({'type': 'missing', 'loc': (*path, name), 'input': value}
                          for name in spec.get('required', []) if name not in value)
            if spec.get('additionalProperties') is False:
                errors.extend({'type': 'extra_forbidden', 'loc': (*path, name), 'input': value[name]}
                              for name in value if name not in properties)
            for name, child in properties.items():
                if name in value:
                    errors.extend(inspect(value[name], child, (*path, name)))
        elif isinstance(value, list) and spec.get('type') == 'array':
            for index, child in enumerate(value):
                errors.extend(inspect(child, spec.get('items', {}), (*path, index)))
        return errors

    errors = inspect(candidate, document, ())
    if errors:
        raise ValidationError.from_exception_data(schema.__name__, errors)


class ProviderClient:
    protocol: str
    provider: str
    key_setting: str

    def __init__(self, api_key=None, timeout=None, http_client=None, runtime=None, configuration=None):
        self.configuration = configuration or settings
        self.runtime = runtime or ValidatedFile(self.configuration.AI_RUNTIME_PATH, RuntimeDocument).read()[0]
        self._api_key = getattr(self.configuration, self.key_setting) if api_key is None else api_key
        self._timeout = self.runtime.http.timeout_seconds if timeout is None else timeout
        self._http = http_client
        self._owns_http = http_client is None
        self._observation = ContextVar(f"{self.provider}_observation", default=None)

    @property
    def configured(self):
        return bool(self._api_key)

    def profile(self, model):
        profiles = [p for p in self.runtime.providers if p.protocol == self.protocol]
        return next((p for p in profiles if getattr(self.configuration, p.model_setting) == model), profiles[0])

    async def start(self):
        if self._http is None:
            cfg = self.runtime.http
            self._http = httpx.AsyncClient(timeout=self._timeout, limits=httpx.Limits(
                max_connections=cfg.max_connections, max_keepalive_connections=cfg.max_keepalive_connections,
                keepalive_expiry=cfg.keepalive_expiry_seconds))

    async def aclose(self):
        if self._http is not None and self._owns_http:
            await self._http.aclose()
            self._http = None

    def reset_observation(self):
        self._observation.set(None)

    def decode_candidate(self, candidate, prompt, schema):
        return candidate

    def observation(self):
        return self._observation.get()

    def request_cost(self, method, model, kwargs):
        payload = self.build_payload(model=model, **kwargs)
        encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
        cfg = self.runtime.http
        maximum = kwargs.get("max_tokens", self.configuration.STRUCTURED_MAX_OUTPUT_TOKENS)
        if maximum is None:
            maximum = self.configuration.STRUCTURED_MAX_OUTPUT_TOKENS
        return math.ceil(len(encoded) / cfg.token_estimation_characters_per_token * cfg.token_estimation_safety_factor) + maximum

    async def post(self, model, payload):
        if not self.configured:
            raise LLMProviderException(self.provider, model, "Provider credential is unconfigured", 401, error_code="unconfigured")
        await self.start()
        started = time.perf_counter()
        self._observation.set({"http_status": None, "elapsed_seconds": 0, "headers": {}, "usage": {}})
        try:
            response = await self._http.post(self.url(model), json=payload, headers=self.headers(), timeout=self._timeout)
        except httpx.TimeoutException:
            raise LLMProviderException(self.provider, model, "Provider transport timed out", 504, error_code="provider_timeout") from None
        except httpx.HTTPError:
            raise LLMProviderException(self.provider, model, "Provider transport failed", 502, error_code="provider_transport") from None
        observation = {"http_status": response.status_code, "elapsed_seconds": time.perf_counter() - started,
                       "headers": {k: response.headers[k] for k in SAFE_HEADERS if k in response.headers}, "usage": {}}
        self._observation.set(observation)
        if response.status_code != 200:
            error = {}
            try:
                error = response.json().get("error", {})
                for name in ("code", "type"):
                    value = error.get(name)
                    if isinstance(value, str) and len(value) <= 80 and all(c.isalnum() or c in "_.-" for c in value):
                        observation["error_" + name] = value
                if (self.provider == "groq" and response.status_code == 400
                        and observation.get("error_code") == "json_validate_failed"):
                    self._record_failed_native_generation(model, error)
            except (ValueError, AttributeError):
                pass
            retry = self.rate_limit_retry(response.headers, error) if response.status_code == 429 else None
            raise LLMProviderException(self.provider, model, "Provider rejected request", response.status_code,
                                       retry_after=retry, error_code="provider_rate_limited" if response.status_code == 429 else (
                                           "structured_output_invalid" if observation.get("error_code") == "json_validate_failed" else "provider_http_error"))
        try:
            data = response.json()
            observation["usage"] = self.usage(data)
            return self.content(data)
        except (ValueError, KeyError, IndexError, TypeError, AttributeError):
            raise LLMProviderException(self.provider, model, "Invalid provider envelope", 502, error_code="provider_envelope_invalid") from None

    def rate_limit_retry(self, headers, error):
        # Unknown provider wait stays unknown; the cascade may still back off
        # locally, but must not advertise its configured backoff as API data.
        return retry_after_seconds(headers.get('retry-after'), None)

    def _record_failed_native_generation(self, model, error):
        """Explicit local evidence only; never attach provider text to observations."""
        recording, stage = GENERATION_RECORDING.get(), CURRENT_GENERATION.get()
        if recording is None or stage is None:
            return
        record = next((row for row in reversed(recording) if row.get("phase") == stage.name), None)
        if record is None:
            return
        failures = record.setdefault("failed_generations", [])
        if len(failures) >= 1 + self.runtime.max_failovers_per_logical_call:
            return
        details = {"provider": self.provider, "model": model, "error_code": "json_validate_failed"}
        truncated = []
        # ใช้ขอบเขตอักขระจาก runtime เดิม ไม่เก็บ envelope หรือ request headers
        limit = self.runtime.limits.characters
        for source, target in (("failed_generation", "failed_generation"), ("message", "provider_message")):
            value = error.get(source)
            if isinstance(value, str):
                details[target] = value[:limit]
                if len(value) > limit:
                    truncated.append(target)
        if truncated:
            details["truncated_fields"] = truncated
        failures.append(details)

    async def generate_text(self, model, prompt, system_instruction=None, max_tokens=None, temperature=None):
        return await self.post(model, self.build_payload(model, prompt, system_instruction, temperature, max_tokens=max_tokens))

    async def generate_structured(self, model, prompt, schema, system_instruction=None, temperature=None):
        try:
            payload = self.build_payload(model, prompt, system_instruction, temperature, schema=schema)
        except ValueError:
            raise LLMProviderException(self.provider, model, "Unsupported structured schema", 400, error_code="schema_unsupported") from None
        raw = await self.post(model, payload)
        typed_event=None
        try:
            candidate=json.loads(raw,object_pairs_hook=unique_pairs)
            recording=GENERATION_RECORDING.get();stage=CURRENT_GENERATION.get()
            if recording is not None and stage is not None:
                current=next((r for r in reversed(recording) if r.get('phase')==stage.name),None)
                if current is not None:
                    # Explicit local evaluation artifacts only, never normal
                    # telemetry/logger/provider envelopes or request headers.
                    typed_event={'provider':self.provider,'model':model,'native_output':candidate,'validated':False}
                    current.setdefault('typed_outputs',[]).append(typed_event)
            candidate = self.decode_candidate(candidate,prompt,schema)
            validate_native_keys(candidate, schema)
            result=schema.model_validate(candidate,strict=True,by_alias=True,by_name=False)
            if typed_event is not None:typed_event['validated']=True
            return result
        except ValidationError as error:
            observation = self.observation()
            if observation is not None:
                document = schema.model_json_schema()
                fields = set(document.get("properties", {}))
                for definition in document.get("$defs", {}).values():
                    fields.update(definition.get("properties", {}))
                observation["validation_errors"] = [
                    {"path": [part if isinstance(part, int) or part in fields else "unknown_field"
                              for part in entry["loc"]], "type": entry["type"]}
                    for entry in error.errors(include_url=False, include_context=False, include_input=False)
                ]
            raise LLMProviderException(self.provider, model, "Structured output failed validation", 502, error_code="structured_output_invalid") from None
        except (ValueError, TypeError):
            observation = self.observation()
            if observation is not None:
                observation["validation_errors"] = [{"path": [], "type": "structured_decode_failed"}]
            raise LLMProviderException(self.provider, model, "Structured output failed validation", 502, error_code="structured_output_invalid") from None

    async def generate_stream(self, model, prompt, system_instruction=None, max_tokens=None, temperature=None):
        # Buffer completion; a failed stream cannot mix partial answers from two providers.
        yield await self.generate_text(model, prompt, system_instruction, max_tokens, temperature)
