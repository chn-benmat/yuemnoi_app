"""Replay real planning failures through transport, validation and failover."""
from copy import deepcopy
import json
from pathlib import Path
from types import SimpleNamespace

import httpx
import pytest
from pydantic import BaseModel, ValidationError, model_validator

from app.application.dtos.chat_dto import ChatRequestDTO
from app.application.services.catalog_guidance import validated_schema
from app.application.use_cases.plan_chat_turn_use_case import PlanChatTurnUseCase
from app.domain.entities.turn_plan import NativeTurnPlan
from app.domain.interfaces.generation_stage import generation_stage
from test_provider_runtime import envelope, stack


def recorded_failures():
    return json.loads((Path(__file__).parent / 'fixtures/native_computer_rental_failures.json')
                      .read_text(encoding='utf-8'))


def replay_schema():
    case = PlanChatTurnUseCase.__new__(PlanChatTurnUseCase)
    case._policy = SimpleNamespace(max_questions=3)
    request = ChatRequestDTO(message='อยากเช่าคอม')
    knowledge = SimpleNamespace(topics=[], articles=[])
    catalog = {'categories': recorded_failures()[1]['analysis']['categories'], 'items': []}
    return validated_schema(NativeTurnPlan, lambda plan: case._validate_plan(
        plan.to_plan(), {'@ref24'}, request, knowledge, catalog))


@pytest.mark.asyncio
@pytest.mark.parametrize('failure_index', [0, 1], ids=['unrestricted_only', 'filtered_overview'])
async def test_failed_planning_sends_the_violated_requirement_to_bounded_failover(failure_index):
    rejected = recorded_failures()[failure_index]
    corrected = deepcopy(rejected)
    if failure_index == 0:
        corrected['stage']['questions'][0]['choices'][0].update(
            label='รายวัน', value='รายวัน', value_kind='specified')
        # ทดสอบรูปแบบคำถามจริงโดยไม่พึ่งข้อมูลคลังและการตรวจความหมายภายนอก
        schema = NativeTurnPlan
        requirement_fragment = 'at least one specified'
    else:
        corrected['stage']['response_mode'] = 'equipment'
        schema = replay_schema()
        requirement_fragment = 'Unfiltered category browsing only'
    with pytest.raises(ValidationError):
        schema.model_validate(rejected)
    schema.model_validate(corrected)
    calls = []

    def respond(request):
        payload = json.loads(request.content)
        calls.append(payload)
        instruction = payload['messages'][0]['content']
        feedback = instruction.split('Field requirements for this retry: ', 1)
        has_requirement = (len(feedback) == 2 and requirement_fragment in feedback[1])
        output = corrected if len(calls) == 2 and has_requirement else rejected
        return httpx.Response(200, json=envelope(json.dumps(output, ensure_ascii=False)))

    service, transport = stack(respond)
    try:
        with generation_stage('planning'):
            result = await service.generate_structured('fixture', schema,
                                                       system_instruction='Preserve validated requirements.')
        assert result.stage.response_mode == corrected['stage']['response_mode']
        assert len(calls) == 2
        assert calls[0]['model'] != calls[1]['model']
        assert service.telemetry[0]['status'] == 'structured_output_invalid'
        assert service.telemetry[1]['status'] == 'success'
        assert rejected['analysis']['user_goal'] not in json.dumps(list(service.telemetry), ensure_ascii=False)
    finally:
        await service.aclose()
        await transport.aclose()


@pytest.mark.asyncio
async def test_validation_exception_context_is_never_sent_to_failover_or_telemetry():
    private_input = 'private-generated-value'
    private_message = 'private-validation-exception'

    class Result(BaseModel):
        value: str

        @model_validator(mode='after')
        def valid_result(self):
            if self.value != 'valid':
                raise ValueError(private_message)
            return self

    calls = []

    def respond(request):
        calls.append(json.loads(request.content))
        output = {'value': private_input if len(calls) == 1 else 'valid'}
        return httpx.Response(200, json=envelope(json.dumps(output)))

    service, transport = stack(respond)
    try:
        result = await service.generate_structured('fixture', Result)
        assert result.value == 'valid'
        assert len(calls) == 2
        recorded = json.dumps([calls[1], list(service.telemetry)])
        assert private_input not in recorded
        assert private_message not in recorded
        assert 'Field requirements for this retry:' not in calls[1]['messages'][0]['content']
    finally:
        await service.aclose()
        await transport.aclose()
