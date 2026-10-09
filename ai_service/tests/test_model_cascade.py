import json

import httpx
import pytest

from app.core.config import settings
from app.core.exceptions import AllLLMProvidersExhaustedException
from app.infrastructure.llm.cascade_llm_service import CascadeLLMService
from app.infrastructure.llm.groq_client import GroqClient
from test_provider_runtime import RUNTIME, envelope


@pytest.mark.asyncio
async def test_cascade_falls_back_to_other_model_when_primary_rate_limited():
    calls = []
    def respond(request):
        model = json.loads(request.content)['model']
        calls.append(model)
        if model == settings.GROQ_PRIMARY_MODEL:
            return httpx.Response(429, headers={'retry-after': '45'}, json={'error': {'code': 'rate_limit_exceeded'}})
        return httpx.Response(200, json=envelope('คำตอบจาก Groq สำรอง'))
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as http:
        cascade = CascadeLLMService(runtime=RUNTIME,
            groq_client=GroqClient(api_key='fixture', runtime=RUNTIME, http_client=http))
        try:
            assert await cascade.generate_text(prompt='สวัสดี') == 'คำตอบจาก Groq สำรอง'
            assert calls == list(settings.groq_models[:2])
        finally:
            await cascade.aclose()


@pytest.mark.asyncio
async def test_cascade_raises_exhausted_after_bounded_failed_attempts():
    calls = []
    def respond(request):
        calls.append(json.loads(request.content)['model'])
        return httpx.Response(503, json={'error': {'code': 'unavailable'}})
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as http:
        cascade = CascadeLLMService(runtime=RUNTIME,
            groq_client=GroqClient(api_key='fixture', runtime=RUNTIME, http_client=http))
        try:
            with pytest.raises(AllLLMProvidersExhaustedException):
                await cascade.generate_text(prompt='ทดสอบ')
            assert calls == list(settings.groq_models[:2])
            assert len(calls) == 1 + cascade.runtime.max_failovers_per_logical_call
        finally:
            await cascade.aclose()
