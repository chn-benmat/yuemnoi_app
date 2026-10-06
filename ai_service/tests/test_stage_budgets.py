import asyncio
import json
import httpx
import pytest
from app.domain.interfaces.generation_stage import generation_stage, Provenance
from app.infrastructure.runtime.execution import REQUEST_DEADLINE, LOGICAL_CALL_BUDGET, LogicalCallBudget
from app.core.exceptions import AllLLMProvidersExhaustedException
from test_provider_runtime import SmallResult, stack, runtime, envelope


@pytest.mark.asyncio
async def test_slow_primary_is_canceled_while_backup_still_has_time():
    models, canceled = [], []
    async def respond(request):
        model = json.loads(request.content)["model"]
        models.append(model)
        if len(models) == 1:
            try:
                await asyncio.sleep(1)
            except asyncio.CancelledError:
                canceled.append(model)
                raise
        return httpx.Response(200, json=envelope())
    service, http = stack(respond, runtime(logical_call_deadline_seconds=.16))
    async with http:
        result = await service.generate_structured("fixture", SmallResult)
    assert result.value == "valid" and len(models) == 2 and canceled == models[:1]
    assert service.telemetry[0]["status"] == "attempt_deadline_exceeded"


@pytest.mark.asyncio
async def test_stage_reserves_remaining_review_and_excludes_actual_writer():
    called = []
    def respond(request):
        called.append(json.loads(request.content)["model"])
        return httpx.Response(200, json=envelope())
    service, http = stack(respond)
    token = REQUEST_DEADLINE.set(asyncio.get_running_loop().time()+.6)
    budget_token = LOGICAL_CALL_BUDGET.set(LogicalCallBudget(2))
    try:
        async with http:
            with generation_stage("planning", downstream=("review",)) as writer:
                await service.generate_structured("fixture", SmallResult)
                assert writer.provenance is not None
            with generation_stage("review", excluded_models=[writer.provenance]) as reviewer:
                await service.generate_structured("fixture", SmallResult)
                assert reviewer.provenance != writer.provenance
            with pytest.raises(AllLLMProvidersExhaustedException) as failure:
                await service.generate_structured("extra repair", SmallResult)
            assert failure.value.code == "logical_call_budget_exceeded"
        assert called[0] != called[1]
        assert service.telemetry[0]["remaining_stage_seconds"] < .3
        assert [t["phase"] for t in service.telemetry] == ["planning", "review"]
    finally:
        REQUEST_DEADLINE.reset(token)
        LOGICAL_CALL_BUDGET.reset(budget_token)
