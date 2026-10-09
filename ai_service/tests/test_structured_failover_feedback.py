import json
from typing import Literal
import httpx
import pytest
from pydantic import BaseModel
from app.core.config import settings
from app.domain.interfaces.generation_stage import generation_stage
from app.infrastructure.llm.cascade_llm_service import CascadeLLMService
from app.infrastructure.llm.groq_client import GroqClient
from app.application.services.review_input import restore_planning_input
from test_provider_runtime import RUNTIME, envelope


class Result(BaseModel):
    value: Literal['valid']


@pytest.mark.asyncio
@pytest.mark.parametrize('failure', ['contract', 'quota'])
async def test_bounded_fallback_receives_only_machine_contract_feedback(tmp_path, monkeypatch, failure):
    runtime = RUNTIME.model_copy(update={'quota_ledger': RUNTIME.quota_ledger.model_copy(
        update={'path': str(tmp_path / 'quota.json')})})
    payloads = []
    def respond(request):
        payloads.append(json.loads(request.content))
        if len(payloads) == 1:
            if failure == 'quota':
                return httpx.Response(429, headers={'retry-after': '1'}, json={'error': {'code': 'rate_limit_exceeded'}})
            return httpx.Response(200, json=envelope('{"value":"invalid"}'))
        return httpx.Response(200, json=envelope('{"value":"valid"}'))
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as http:
        service = CascadeLLMService(runtime=runtime,
            groq_client=GroqClient(api_key='fixture', runtime=runtime, http_client=http))
        monkeypatch.setattr(service, '_get_cascade_tiers', lambda: [
            ('groq', settings.GROQ_PRIMARY_MODEL), ('groq', settings.GROQ_FALLBACK_MODEL_1)])
        try:
            with generation_stage('planning'):
                result = await service.generate_structured(
                    json.dumps({'current_message': {'content': 'คำถามต้นฉบับ'}}, ensure_ascii=False),
                    Result, system_instruction='Keep the supplied evidence.')
            assert result.value == 'valid'
            assert len(payloads) == 2
            for payload in payloads:
                prompt = restore_planning_input(json.loads(payload['messages'][-1]['content']))
                assert prompt['current_message']['content'] == 'คำถามต้นฉบับ'
            instruction = payloads[1]['messages'][0]['content']
            if failure == 'contract':
                assert 'literal_error' in instruction
                assert 'invalid' not in instruction
            else:
                assert 'literal_error' not in instruction
            calls = [row for row in service.telemetry if row.get('http_attempts')]
            assert len({row['logical_call_id'] for row in calls}) == 1
        finally:
            await service.aclose()
