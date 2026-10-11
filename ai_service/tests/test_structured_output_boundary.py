"""Reject invalid wire output without adding retries or publishing a partial answer."""
import json
from types import SimpleNamespace

import httpx
import pytest
from pydantic import BaseModel, Field, ValidationError

from app.application.dtos.chat_dto import ChatRequestDTO
from app.core.config import settings
from app.core.exceptions import AllLLMProvidersExhaustedException, LLMProviderException
from app.infrastructure.llm.groq_client import GroqClient
from app.infrastructure.llm.provider_client import decode_structured
from test_provider_runtime import RUNTIME, SmallResult, envelope, stack


class NumericResult(BaseModel):
    value: float


class NumberChoice(BaseModel):
    value: int = 0


class TextChoice(BaseModel):
    label: str = "default fixture label"


class UnionResult(BaseModel):
    choice: NumberChoice | TextChoice


class TreeResult(BaseModel):
    value: str = Field(alias="text")
    children: list["TreeResult"] = Field(default_factory=list)


@pytest.mark.parametrize("raw", ['{"choice":{}}', '{"choice":{"value":"incorrect"}}'])
def test_domain_defaults_and_union_branch_selection_cannot_hide_wire_violations(raw):
    with pytest.raises(ValidationError):
        decode_structured(raw, UnionResult)


@pytest.mark.parametrize("value", [{"value": 1}, {"label": "valid fixture label"}])
def test_complete_union_branch_remains_accepted(value):
    result = decode_structured(json.dumps({"choice": value}), UnionResult)
    assert result.choice.model_dump() == value


def test_recursive_references_keep_aliases_and_require_nested_defaulted_fields():
    child = {"text": "nested fixture", "children": []}
    result = decode_structured(json.dumps({"text": "root fixture", "children": [child]}), TreeResult)
    assert result.children[0].value == child["text"]
    with pytest.raises(ValidationError):
        decode_structured('{"text":"root fixture","children":[{"text":"nested fixture"}]}', TreeResult)


@pytest.mark.asyncio
async def test_provider_cannot_accept_an_invalid_union_by_filling_another_branch_defaults():
    payloads = []

    def respond(request):
        payloads.append(json.loads(request.content))
        text = '{"choice":{"value":"private invalid value"}}' if len(payloads) == 1 else '{"choice":{"value":1}}'
        return httpx.Response(200, json=envelope(text))

    service, http = stack(respond)
    try:
        result = await service.generate_structured("fixture", UnionResult)
        assert result.choice.value == 1
        assert len(payloads) == 2
        assert service.telemetry[0]["validation_errors"] == [
            {"path": ["choice"], "type": "json_schema_anyOf"}]
        assert "private invalid value" not in json.dumps(payloads[1])
        assert "private invalid value" not in json.dumps(list(service.telemetry))
    finally:
        await service.aclose()
        await http.aclose()


@pytest.mark.asyncio
@pytest.mark.parametrize("number", ["NaN", "Infinity", "-Infinity", "1e400", "-1e400"])
async def test_provider_rejects_non_finite_json_numbers(number):
    def respond(request):
        return httpx.Response(200, json=envelope('{"value":' + number + '}'))

    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as http:
        client = GroqClient(api_key="fixture", runtime=RUNTIME, http_client=http)
        with pytest.raises(LLMProviderException) as failure:
            await client.generate_structured(settings.GROQ_PRIMARY_MODEL, "fixture", NumericResult)
        assert failure.value.error_code == "structured_output_invalid"
        assert client.observation()["validation_errors"] == [
            {"path": [], "type": "structured_decode_failed"}]


@pytest.mark.parametrize("number", [0, 1.25, 1e300])
def test_finite_json_numbers_remain_accepted(number):
    assert decode_structured(json.dumps({"value": number}), NumericResult).value == number


@pytest.mark.asyncio
async def test_reference_handles_are_restored_before_checking_authoritative_enums():
    from typing import Literal

    identifier = "authoritative-fixture-item-identifier"

    class ReferenceResult(BaseModel):
        id: Literal[identifier]

    def respond(request):
        payload = json.loads(request.content)
        handles = payload["response_format"]["json_schema"]["schema"]["properties"]["id"]["enum"]
        assert handles == ["@ref0"]
        return httpx.Response(200, json=envelope(json.dumps({"id": handles[0]})))

    service, http = stack(respond)
    try:
        result = await service.generate_structured(json.dumps({"id": identifier}), ReferenceResult)
        assert result.id == identifier
    finally:
        await service.aclose()
        await http.aclose()


@pytest.mark.asyncio
@pytest.mark.parametrize("metadata,code", [
    ({"finish_reason": "length"}, "structured_output_truncated"),
    ({"finish_reason": "content_filter"}, "structured_output_incomplete"),
    ({"finish_reason": "tool_calls"}, "structured_output_incomplete"),
    ({"finish_reason": None}, "structured_output_incomplete"),
    ({"refusal": "private refusal reason"}, "structured_output_refused"),
    ({"tool_calls": [{"id": "fixture tool"}]}, "structured_output_incomplete"),
    ({"function_call": {"name": "fixture function"}}, "structured_output_incomplete"),
])
async def test_incomplete_or_refused_completion_uses_only_existing_bounded_failover(metadata, code):
    payloads = []

    def respond(request):
        payloads.append(json.loads(request.content))
        response = envelope()
        if len(payloads) == 1:
            choice = response["choices"][0]
            for key, value in metadata.items():
                target = choice if key == "finish_reason" else choice["message"]
                target[key] = value
        return httpx.Response(200, json=response)

    service, http = stack(respond)
    try:
        result = await service.generate_structured("original request", SmallResult)
        assert result.value == "valid"
        assert len(payloads) == 1 + RUNTIME.max_failovers_per_logical_call == 2
        assert payloads[0]["model"] != payloads[1]["model"]
        assert service.telemetry[0]["status"] == "structured_output_invalid"
        assert service.telemetry[0]["validation_errors"] == [{"path": [], "type": code}]
        assert code in payloads[1]["messages"][0]["content"]
        assert "private refusal reason" not in json.dumps(list(service.telemetry))
        assert "private refusal reason" not in json.dumps(payloads[1])
        assert service.telemetry[0]["usage"]["total_tokens"] == 50
        assert ("groq", payloads[0]["model"]) not in service._model_open_until
    finally:
        await service.aclose()
        await http.aclose()


@pytest.mark.asyncio
async def test_completion_metadata_checks_do_not_reject_bounded_text_permission_probes():
    response = envelope("probe text")
    response["choices"][0]["finish_reason"] = "length"
    async with httpx.AsyncClient(transport=httpx.MockTransport(
            lambda request: httpx.Response(200, json=response))) as http:
        client = GroqClient(api_key="fixture", runtime=RUNTIME, http_client=http)
        assert await client.generate_text(settings.GROQ_PRIMARY_MODEL, "fixture") == "probe text"


@pytest.mark.asyncio
async def test_exhausted_wire_validation_returns_safe_json_and_sse_errors(monkeypatch):
    from fastapi import HTTPException
    from app.interface.api.v1.endpoints import chat

    requests = []

    def respond(request):
        requests.append(request)
        return httpx.Response(200, json=envelope('{"value":"partial private draft"'))

    service, http = stack(respond)

    async def execute(request):
        return await service.generate_structured(request.message, SmallResult)

    async def execute_stream(request):
        await execute(request)
        yield "unreachable"

    monkeypatch.setattr(chat.settings, "INTERNAL_SERVICE_KEY", "")
    monkeypatch.setattr(chat.container, "process_chat_message_use_case", SimpleNamespace(
        execute=execute, execute_stream=execute_stream))
    try:
        with pytest.raises(HTTPException) as failure:
            await chat.chat_endpoint(ChatRequestDTO(message="fixture"))
        assert failure.value.status_code == 503
        assert failure.value.detail == {"error_code": "structured_output_invalid"}
        assert len(requests) == 2

        response = await chat.chat_stream_endpoint(ChatRequestDTO(message="fixture"))
        body = b"".join([part async for part in response.body_iterator]).decode()
        assert body == 'event: error\ndata: {"error_code": "structured_output_invalid"}\n\n'
        assert len(requests) == 4
    finally:
        await service.aclose()
        await http.aclose()


@pytest.mark.asyncio
async def test_valid_json_with_a_domain_constraint_failure_is_still_rejected():
    from app.application.services.catalog_guidance import validated_schema
    from pydantic_core import PydanticCustomError

    def reject(result):
        raise PydanticCustomError("fixture_domain_constraint", "Fixture domain constraint")

    service, http = stack(lambda request: httpx.Response(200, json=envelope()))
    try:
        with pytest.raises(AllLLMProvidersExhaustedException) as failure:
            await service.generate_structured("fixture", validated_schema(SmallResult, reject))
        assert failure.value.code == "structured_output_invalid"
        assert all(row["validation_errors"][0]["type"] == "fixture_domain_constraint"
                   for row in service.telemetry if row.get("http_attempts"))
    finally:
        await service.aclose()
        await http.aclose()
