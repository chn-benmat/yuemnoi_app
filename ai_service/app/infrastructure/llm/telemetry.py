"""One allowlist shared by both evaluation surfaces; never provider response bodies."""
SAFE_TELEMETRY_FIELDS = frozenset({"provider", "model", "status", "http_status", "http_attempts", "usage",
    "error_code", "error_type", "elapsed_seconds", "trace_id", "phase", "logical_call_id", "attempt_index",
    "validation_errors", "queue_seconds", "semaphore_queue_seconds", "reserved_tokens", "estimated_tokens",
    "remaining_stage_seconds", "remaining_turn_seconds", "remaining_stage_seconds_after", "assessment", "admission_scope", "retry_after_seconds"})


def safe_telemetry(rows):
    return [{key:value for key,value in row.items() if key in SAFE_TELEMETRY_FIELDS} for row in rows]
