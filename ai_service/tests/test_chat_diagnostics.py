import asyncio
import json
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from pydantic import BaseModel

from app.application.dtos.chat_dto import ChatRequestDTO, ChatResponseDTO
from app.domain.exceptions import GuidanceGenerationError
from app.domain.interfaces.chat_diagnostics import (
    current_diagnostic_trace_id, diagnostic_scope, record_diagnostic,
)
from app.domain.interfaces.generation_stage import GENERATION_RECORDING, generation_stage
from app.interface.cli.capture_chat_diagnostics import capture_chat, redact_configured_credentials


def rejected_review():
    return {"issues": [{"kind": "context", "field_path": "/response",
                        "reason": "private review reason", "quoted_text": "private draft text"}],
            "assessments": [{"check": "context", "passed": False,
                             "field_paths": ["/response"], "reason": "private assessment reason"}]}


@pytest.mark.asyncio
async def test_child_tasks_share_request_trace_and_concurrent_requests_are_isolated():
    async def request(label):
        with diagnostic_scope() as trace:
            async def child():
                await asyncio.sleep(0)
                record_diagnostic("outcome", error_code=label)
                return current_diagnostic_trace_id()
            assert await asyncio.create_task(child()) == trace.trace_id
            with diagnostic_scope() as nested:
                assert nested is trace
            return trace.summary()
    first, second = await asyncio.gather(request("first"), request("second"))
    assert first["trace_id"] != second["trace_id"]
    assert first["events"] == [{"event": "outcome", "error_code": "first"}]
    assert second["events"] == [{"event": "outcome", "error_code": "second"}]
    assert current_diagnostic_trace_id() is None


def test_ordinary_diagnostics_are_bounded_and_exclude_content_and_raw_headers():
    with diagnostic_scope() as trace, generation_stage("review"):
        record_diagnostic("provider_attempt", provider="groq", model="configured/model", review=rejected_review(),
                          observation={"http_status": 400, "error_code": "json_validate_failed", "headers": {"Authorization": "private key",
                                       "x-ratelimit-remaining-tokens": "4999"},
                                       "validation_errors": [{"path": ["response", "private field value"],
                                                              "type": "string_type", "input": "private raw text"}]})
        for _ in range(1000):
            record_diagnostic("outcome")
        summary = trace.summary()
    encoded = json.dumps(summary)
    assert len(summary["events"]) <= 128 and summary["omitted_events"] > 0
    assert "private" not in encoded and "4999" not in encoded
    assert summary["events"][0]["stage"] == "review"
    assert summary["events"][0]["provider_error_code"] == "json_validate_failed"
    assert summary["events"][0]["issues"] == [{"kind": "context", "field_path": "/response"}]
    assert summary["events"][0]["validation_errors"][0]["path"] == ["response", "unknown_field"]
    assert GENERATION_RECORDING.get() is None


def test_opt_in_capture_keeps_original_rate_headers_without_auth_or_envelopes():
    records = []
    token = GENERATION_RECORDING.set(records)
    try:
        with diagnostic_scope():
            record_diagnostic("provider_attempt", observation={
                "http_status": 200, "headers": {"x-ratelimit-reset-tokens": "1m0.002s",
                "Authorization": "private credential"}, "usage": {"total_tokens": 5839},
                "raw_provider_envelope": "private response envelope"})
    finally:
        GENERATION_RECORDING.reset(token)
    details = records[0]["events"][0]
    assert details["rate_limit_headers"] == {"x-ratelimit-reset-tokens": "1m0.002s"}
    assert details["usage"] == {"total_tokens": 5839}
    assert "private" not in json.dumps(records)


@pytest.mark.asyncio
@pytest.mark.parametrize("stream", [False, True])
async def test_failure_endpoint_logs_safe_trace_without_adding_content_to_public_contract(monkeypatch, stream):
    from app.interface.api.v1.endpoints import chat
    logs = []
    logger = SimpleNamespace(info=lambda *args: logs.append(args), warning=lambda *args: logs.append(args))
    async def fail(request):
        assert GENERATION_RECORDING.get() is None
        record_diagnostic("review", review=rejected_review())
        error = GuidanceGenerationError("response_quality_rejected")
        error.draft = {"response": "private draft text"}
        error.review = rejected_review()
        raise error
    async def failing_stream(request):
        await asyncio.create_task(fail(request))
        yield "unreachable"
    monkeypatch.setattr(chat, "logger", logger)
    monkeypatch.setattr(chat.settings, "INTERNAL_SERVICE_KEY", "")
    monkeypatch.setattr(chat.container, "process_chat_message_use_case", SimpleNamespace(execute=fail, execute_stream=failing_stream))
    request = ChatRequestDTO(message="private user message")
    if stream:
        response = await chat.chat_stream_endpoint(request)
        body = b"".join([chunk async for chunk in response.body_iterator]).decode()
        assert body == 'event: error\ndata: {"error_code": "response_quality_rejected"}\n\n'
    else:
        with pytest.raises(HTTPException) as failure:
            await chat.chat_endpoint(request)
        assert failure.value.detail == {"error_code": "response_quality_rejected"}
    text = str(logs)
    assert "private" not in text and "trace=" in text and "response_quality_rejected" in text
    assert current_diagnostic_trace_id() is None


@pytest.mark.asyncio
async def test_local_capture_preserves_rejection_evidence_and_closes_container():
    closed = []
    async def start():
        pass
    async def close():
        closed.append(True)
    async def execute(request):
        assert GENERATION_RECORDING.get() is not None
        error = GuidanceGenerationError("response_quality_rejected")
        error.draft = {"response": "local draft"}
        error.review = rejected_review()
        raise error
    service = SimpleNamespace(start=start, aclose=close, process_chat_message_use_case=SimpleNamespace(execute=execute))
    artifact = await capture_chat(ChatRequestDTO(message="local request"), service)
    assert artifact["error"]["draft"] == {"response": "local draft"}
    assert artifact["error"]["review"] == rejected_review()
    assert artifact["trace_id"] == artifact["diagnostics"]["trace_id"]
    assert closed == [True] and GENERATION_RECORDING.get() is None


def test_capture_redacts_configured_secrets_even_if_echoed_in_generated_content():
    class Configuration(BaseModel):
        GROQ_API_KEY: str = "private-provider-key"
        INTERNAL_SERVICE_KEY: str = "private-internal-key"
        GROQ_QUOTA_ACCOUNT_ID: str = "private-account-id"
    value = {"output": "echo private-provider-key", "records": ["private-internal-key", "private-account-id"]}
    assert "private" not in json.dumps(redact_configured_credentials(value, Configuration()))
