"""Request-local, content-free diagnostics shared across clean architecture layers."""

from contextlib import contextmanager
from contextvars import ContextVar
from dataclasses import dataclass, field
from typing import Literal
from uuid import uuid4

from app.domain.interfaces.generation_stage import CURRENT_GENERATION, GENERATION_RECORDING


DiagnosticEvent = Literal["provider_attempt", "admission", "reservation", "review", "repair", "outcome"]
_CURRENT_TRACE = ContextVar("chat_diagnostic_trace", default=None)
_SAFE_RATE_HEADERS = frozenset({
    "retry-after", "x-ratelimit-limit-requests", "x-ratelimit-limit-tokens",
    "x-ratelimit-remaining-requests", "x-ratelimit-remaining-tokens",
    "x-ratelimit-reset-requests", "x-ratelimit-reset-tokens",
})
_CHECKS = frozenset({"relevance", "completeness", "neutral_voice", "choice_equivalence",
                     "grounding", "context", "followups"})
_ISSUE_KINDS = frozenset({"semantic", "neutral_voice", "grounding", "context", "choice", "contract"})
# ขอบเขตข้อมูลวินิจฉัยเป็นข้อจำกัดด้านความปลอดภัย ไม่ใช่การกำหนดพฤติกรรมบทสนทนา
_MAX_EVENTS = 128
_MAX_DETAILS = 16


def _identifier(value, *, limit=128):
    if not isinstance(value, str) or not value or len(value) > limit:
        return None
    return value if all(c.isascii() and (c.isalnum() or c in "_./-") for c in value) else None


def _pointer(value):
    if not isinstance(value, str) or not value.startswith("/") or len(value) > 256:
        return None
    return value if all(_identifier(part) is not None for part in value.split("/")[1:]) else None


def _validation_details(errors):
    rows = []
    for error in errors or []:
        if not isinstance(error, dict):
            continue
        path = error.get("path", error.get("loc", []))
        if not isinstance(path, (list, tuple)):
            continue
        rows.append({"path": [part if isinstance(part, int) else (_identifier(part) or "unknown_field")
                              for part in path[:_MAX_DETAILS]],
                     "type": _identifier(error.get("type")) or "validation_failed"})
        if len(rows) == _MAX_DETAILS:
            break
    return rows


def _review_details(review):
    if not isinstance(review, dict):
        return {}
    issues = []
    for issue in review.get("issues", [])[:_MAX_DETAILS]:
        if not isinstance(issue, dict) or issue.get("kind") not in _ISSUE_KINDS:
            continue
        pointer = _pointer(issue.get("field_path"))
        if pointer is not None:
            issues.append({"kind": issue["kind"], "field_path": pointer})
    assessments = []
    for assessment in review.get("assessments", [])[:_MAX_DETAILS]:
        if not isinstance(assessment, dict) or assessment.get("check") not in _CHECKS:
            continue
        if not isinstance(assessment.get("passed"), bool):
            continue
        paths = [pointer for value in assessment.get("field_paths", [])[:_MAX_DETAILS]
                 if (pointer := _pointer(value)) is not None]
        assessments.append({"check": assessment["check"], "passed": assessment["passed"],
                            "field_paths": paths})
    return {"issues": issues, "assessments": assessments}


@dataclass
class DiagnosticTrace:
    trace_id: str
    events: list[dict] = field(default_factory=list)
    omitted_events: int = 0

    def summary(self):
        return {"trace_id": self.trace_id, "events": self.events, "omitted_events": self.omitted_events}


@contextmanager
def diagnostic_scope(trace_id=None):
    """Nested scopes and child tasks share one trace; unrelated requests do not."""
    current = _CURRENT_TRACE.get()
    if current is not None:
        yield current
        return
    trace = DiagnosticTrace(_identifier(trace_id) or uuid4().hex)
    token = _CURRENT_TRACE.set(trace)
    try:
        yield trace
    finally:
        _CURRENT_TRACE.reset(token)


def current_diagnostic_trace_id():
    current = _CURRENT_TRACE.get()
    return current.trace_id if current is not None else None


def record_diagnostic(event: DiagnosticEvent, *, stage=None, provider=None, model=None,
                      http_status=None, error_code=None, validation_errors=None,
                      review=None, observation=None):
    """Allowlist operational metadata; never retain exception text or draft content."""
    current = _CURRENT_TRACE.get()
    if current is None:
        return
    capture = CURRENT_GENERATION.get()
    stage = stage or (capture.name if capture is not None else None)
    row = {"event": _identifier(event) or "outcome"}
    for name, value in (("stage", stage), ("provider", provider), ("model", model),
                        ("error_code", error_code)):
        safe = _identifier(value)
        if safe is not None:
            row[name] = safe
    observation = observation if isinstance(observation, dict) else {}
    provider_code = _identifier(observation.get('error_code'))
    if provider_code is not None:
        row['provider_error_code'] = provider_code
    status = http_status if http_status is not None else observation.get("http_status")
    if isinstance(status, int) and not isinstance(status, bool) and 100 <= status <= 599:
        row["http_status"] = status
    errors = _validation_details(validation_errors or observation.get("validation_errors"))
    if errors:
        row["validation_errors"] = errors
    row.update(_review_details(review))
    if len(current.events) < _MAX_EVENTS:
        current.events.append(row)
    else:
        current.omitted_events += 1

    # Header ต้นฉบับและ usage เก็บเฉพาะ artifact ที่ผู้ใช้เปิดใช้อย่างชัดเจน
    recording = GENERATION_RECORDING.get()
    if recording is not None:
        entry = next((item for item in reversed(recording) if item.get("phase") == "diagnostics"), None)
        if entry is None:
            entry = {"phase": "diagnostics", "trace_id": current.trace_id, "events": []}
            recording.append(entry)
        if len(entry["events"]) < _MAX_EVENTS:
            details = dict(row)
            headers = observation.get("headers", {})
            if isinstance(headers, dict):
                details["rate_limit_headers"] = {
                    key: value for key, value in headers.items()
                    if key in _SAFE_RATE_HEADERS and isinstance(value, str) and len(value) <= 256
                }
            usage = observation.get("usage", {})
            if isinstance(usage, dict):
                details["usage"] = {key: value for key, value in usage.items()
                                    if key in ("input_tokens", "output_tokens", "prompt_tokens", "completion_tokens", "total_tokens", "cached_tokens")
                                    and isinstance(value, int) and not isinstance(value, bool) and value >= 0}
            entry["events"].append(details)
