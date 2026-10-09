"""Rejected model fields are opt-in local evidence, absent from ordinary logs."""
import httpx
import pytest
from pydantic import BaseModel
from app.core.config import settings
from app.core.exceptions import LLMProviderException
from app.domain.interfaces.generation_stage import GENERATION_RECORDING,generation_stage
from app.infrastructure.llm.groq_client import GroqClient


class Result(BaseModel):value:str


@pytest.mark.asyncio
@pytest.mark.parametrize('opt_in',[False,True])
async def test_invalid_native_value_is_preserved_only_in_evaluation(opt_in):
    async def respond(request):
        return httpx.Response(200,json={'choices':[{'finish_reason':'stop','message':{'content':'{"value":27}'}}]})
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond))as http:
        client=GroqClient(api_key='fixture-private-header',http_client=http)
        records=[{'phase':'review','logical_call_id':'fixture'}]
        token=GENERATION_RECORDING.set(records if opt_in else None)
        try:
            with generation_stage('review'),pytest.raises(LLMProviderException):
                await client.generate_structured(settings.GROQ_PRIMARY_MODEL,'fixture',Result)
        finally:GENERATION_RECORDING.reset(token)
        observation=client.observation()
        assert 'native_output' not in observation and 'typed_outputs' not in observation
        assert 'fixture-private-header' not in str(records) and 'fixture-private-header' not in str(observation)
        if opt_in:
            assert records[0]['typed_outputs']==[{'provider':'groq','model':settings.GROQ_PRIMARY_MODEL,'native_output':{'value':27},'validated':False}]
        else:assert 'typed_outputs' not in records[0]
