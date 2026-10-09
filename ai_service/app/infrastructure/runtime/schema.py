"""Production JSON contracts. No phrases, product data or language routing rules."""

import hashlib
import hmac
import json
from typing import Literal

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, HttpUrl, model_validator
from app.domain.entities.catalog_guidance import QuestionnaireChoicePolicy


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, allow_inf_nan=False)


def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON property")
        result[key] = value
    return result


class Approval(Strict):
    approved_by: str = Field(min_length=1)
    approved_at: AwareDatetime
    authorization: str = Field(min_length=1)
    content_sha256: str = Field(min_length=1)


class ApprovedDocument(Strict):
    schema_version: Literal["2"]
    version: str = Field(min_length=1)
    status: Literal["approved"]
    production_enabled: Literal[True]
    approval: Approval

    def approval_digest(self):
        material = self.model_dump(mode="json", exclude={"approval"})
        return hashlib.sha256(json.dumps(material, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()

    @model_validator(mode="after")
    def valid_approval(self):
        if not hmac.compare_digest(self.approval.content_sha256.encode("utf-8"), self.approval_digest().encode("ascii")):
            raise ValueError("Configuration changed since approval")
        return self


class ScopeDefinitions(Strict):
    broad: str = Field(min_length=1)
    specific: str = Field(min_length=1)
    not_applicable: str = Field(min_length=1)
    independence: str = Field(min_length=1)


class CatalogPresentation(Strict):
    currency: str = Field(min_length=1)
    amount_format: str = Field(min_length=1)
    price_template: str = Field(min_length=1)
    unit_labels: dict[str, str]
    status_labels: dict[str, str]


class QuestionnaireFlowPolicy(Strict):
    single_batch_per_goal: bool


class InterpretationPolicy(ApprovedDocument):
    questionnaire_flow: QuestionnaireFlowPolicy
    questionnaire_choices: QuestionnaireChoicePolicy | None = None
    catalog_presentation: CatalogPresentation
    turn_instruction: str = Field(min_length=1)
    evidence_instruction: str = Field(min_length=1)
    review_instruction: str = Field(min_length=1)
    repair_instruction: str = Field(min_length=1)
    unavailable_notice: str = Field(min_length=1)
    empty_catalog_notice: str = Field(min_length=1)
    scope: ScopeDefinitions
    information_sufficiency: tuple[str, ...] = Field(min_length=1)
    action: tuple[str, ...] = Field(min_length=1)
    context: tuple[str, ...] = Field(min_length=1)
    evidence: tuple[str, ...] = Field(min_length=1)
    neutrality: tuple[str, ...] = Field(min_length=1)


class FlowBudget(Strict):
    target_seconds: float = Field(gt=0)
    hard_deadline_seconds: float = Field(gt=0)
    logical_calls: int = Field(ge=1, le=5)

    @model_validator(mode="after")
    def deadlines(self):
        if self.target_seconds > self.hard_deadline_seconds:
            raise ValueError("Target exceeds deadline")
        return self


class QuotaPolicy(Strict):
    bucket: str = Field(min_length=1)
    scope: Literal["provider", "model"] = "provider"
    authority: Literal["configured", "provider"] = "configured"
    requests_per_window: int = Field(gt=0)
    tokens_per_window: int = Field(gt=0)
    window_seconds: float = Field(gt=0)
    requests_per_day: int = Field(gt=0)
    tokens_per_day: int = Field(gt=0)
    day_seconds: float = Field(gt=0)


class ProviderProfile(Strict):
    id: str = Field(min_length=1)
    protocol: Literal["groq_json_schema"]
    endpoint: HttpUrl
    key_setting: Literal["GROQ_API_KEY"]
    model_setting: Literal["GROQ_PRIMARY_MODEL", "GROQ_FALLBACK_MODEL_1", "GROQ_FALLBACK_MODEL_2"]
    proposed_model: str = Field(min_length=1)
    reasoning_effort: Literal["none", "low", "medium", "high"] | None
    enabled: bool
    disabled_reason: str | None
    quota: QuotaPolicy

    @model_validator(mode="after")
    def valid_endpoint(self):
        u = self.endpoint
        if u.scheme != "https" or u.username or u.password or u.query or u.fragment:
            raise ValueError("Unsafe provider endpoint")
        if not self.model_setting.startswith("GROQ_"):
            raise ValueError("Provider setting mismatch")
        if not self.enabled and not self.disabled_reason:
            raise ValueError("Disabled provider needs an operational reason")
        return self


class Limits(Strict):
    messages: int = Field(gt=0)
    characters: int = Field(gt=0)
    questions: int = Field(ge=1, le=3)
    choices_per_question: int = Field(ge=1, le=5)
    items: int = Field(gt=0)
    output_tokens: int = Field(gt=0)
    temperature: float = Field(ge=0, le=2)
    question_title_characters: int = Field(gt=0)
    choice_label_characters: int = Field(gt=0)
    generation_attempts: int = Field(gt=0)


class StreamPolicy(Strict):
    heartbeat_seconds: float = Field(gt=0, le=30)
    chunk_characters: int = Field(gt=0)


class LoadProfile(Strict):
    concurrent_requests: Literal[5]
    batch_interval_seconds: Literal[60]
    certification_batches_per_flow_per_round: Literal[20]
    certification_rounds: Literal[3]
    ui_requests_per_batch: Literal[1]
    transport_requests_per_batch: Literal[4]


class HTTPPolicy(Strict):
    timeout_seconds: float = Field(gt=0)
    logical_call_deadline_seconds: float = Field(gt=0)
    quota_admission_wait_seconds: float = Field(gt=0)
    permission_probe_prompt: str = Field(min_length=1)
    permission_probe_output_tokens: int = Field(gt=0)
    max_connections: int = Field(gt=0)
    max_keepalive_connections: int = Field(ge=0)
    keepalive_expiry_seconds: float = Field(gt=0)
    token_estimation_characters_per_token: float = Field(gt=0)
    token_estimation_safety_factor: float = Field(ge=1)
    telemetry_history: int = Field(gt=0)


class QuotaLedgerPolicy(Strict):
    path: str = Field(min_length=1)
    lock_timeout_seconds: float = Field(gt=0)
    poll_seconds: float = Field(gt=0)


class StageRoute(Strict):
    profiles: tuple[str, ...] = Field(min_length=1)
    p95_seconds: dict[str, float] = Field(default_factory=dict)

    @model_validator(mode="after")
    def valid_timings(self):
        if len(set(self.profiles)) != len(self.profiles) or not set(self.p95_seconds) <= set(self.profiles):
            raise ValueError("Duplicate or unknown measured profile")
        if any(not 0 < seconds for seconds in self.p95_seconds.values()):
            raise ValueError("Stage timings must be positive")
        return self


class StageRouting(Strict):
    planning: StageRoute
    evidence: StageRoute
    review: StageRoute
    repair: StageRoute
    finalization_reserve_seconds: float = Field(gt=0)
    minimum_attempt_seconds: float = Field(gt=0)
    measurement_artifact: str | None
    initial_review_reserve_tokens: int = Field(gt=0)


class RuntimeDocument(ApprovedDocument):
    knowledge_path: str = Field(min_length=1)
    interpretation_policy_path: str = Field(min_length=1)
    settings_precedence: Literal["explicit_environment_then_dotenv_then_json"]
    model_order_status: Literal["pending_development_measurement", "measured_development"]
    providers: tuple[ProviderProfile, ...] = Field(min_length=1)
    general: FlowBudget
    equipment: FlowBudget
    technical_hard_deadline_seconds: float = Field(gt=0)
    max_failovers_per_logical_call: Literal[1]
    load: LoadProfile
    limits: Limits
    circuit_open_seconds: float = Field(gt=0)
    quota_backoff_seconds: float = Field(gt=0)
    http: HTTPPolicy
    stream: StreamPolicy
    quota_ledger: QuotaLedgerPolicy
    stages: StageRouting

    @model_validator(mode="after")
    def consistent_providers(self):
        if len({p.id for p in self.providers}) != len(self.providers):
            raise ValueError("Duplicate provider profile ID")
        quotas = {}
        for profile in self.providers:
            if profile.quota.scope == "model":
                # ตรวจโมเดลที่ตั้งค่าจริงอีกครั้งใน cascade หลังใช้ environment overrides
                continue
            previous = quotas.setdefault(profile.quota.bucket, profile.quota)
            if previous != profile.quota:
                raise ValueError("Shared quota bucket must have one policy")
        if self.http.max_keepalive_connections > self.http.max_connections:
            raise ValueError("Keepalive connections exceed pool")
        enabled = {p.id for p in self.providers if p.enabled}
        for route in (self.stages.planning, self.stages.evidence, self.stages.review, self.stages.repair):
            if not set(route.profiles) <= {p.id for p in self.providers}:
                raise ValueError("Stage route refers to unknown provider profile")
        if self.model_order_status == "measured_development" and not self.stages.measurement_artifact:
            raise ValueError("Measured routing requires its evidence artifact")
        return self
