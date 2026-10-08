import asyncio
from contextlib import asynccontextmanager
from contextvars import ContextVar
from dataclasses import dataclass
from uuid import uuid4

from app.core.exceptions import AllLLMProvidersExhaustedException, RuntimeConfigurationException
from app.infrastructure.runtime.documents import ValidatedFile
from app.infrastructure.runtime.schema import InterpretationPolicy, RuntimeDocument
from app.domain.interfaces.chat_diagnostics import current_diagnostic_trace_id

REQUEST_DEADLINE = ContextVar("ai_request_deadline", default=None)
LOGICAL_CALL_BUDGET = ContextVar("ai_logical_call_budget", default=None)
TURN_TRACE_ID = ContextVar("ai_turn_trace_id", default=None)
TURN_RESOURCES = ContextVar("ai_turn_resources", default=None)


@dataclass
class LogicalCallBudget:
    maximum: int
    used: int = 0


def consume_logical_call():
    budget = LOGICAL_CALL_BUDGET.get()
    if budget is not None:
        if budget.used >= budget.maximum:
            raise AllLLMProvidersExhaustedException(code="logical_call_budget_exceeded")
        budget.used += 1


@dataclass
class TurnClock:
    started: float
    timeout: asyncio.Timeout


class RuntimeExecutionGuard:
    def __init__(self, runtime_path, policy_path):
        self.runtime_file = ValidatedFile(runtime_path, RuntimeDocument)
        self.policy_file = ValidatedFile(policy_path, InterpretationPolicy)
        self.runtime, self.runtime_hash = self.runtime_file.read()
        self.policy, self.policy_hash = self.policy_file.read()
        self._clock = ContextVar("ai_turn_clock", default=None)

    async def _check_files(self):
        runtime, policy = await asyncio.gather(self.runtime_file.snapshot(), self.policy_file.snapshot())
        if runtime[1] != self.runtime_hash or policy[1] != self.policy_hash:
            raise RuntimeConfigurationException("runtime_changed_restart_required")

    @asynccontextmanager
    async def turn(self):
        start = asyncio.get_running_loop().time()
        deadline_token = REQUEST_DEADLINE.set(start + self.runtime.technical_hard_deadline_seconds)
        timeout = asyncio.timeout_at(REQUEST_DEADLINE.get())
        clock_token = self._clock.set(TurnClock(start, timeout))
        budget_token = LOGICAL_CALL_BUDGET.set(LogicalCallBudget(self.runtime.equipment.logical_calls))
        trace_token = TURN_TRACE_ID.set(current_diagnostic_trace_id() or uuid4().hex)
        resources = {'cleanup': []}
        resources_token = TURN_RESOURCES.set(resources)
        try:
            async with timeout:
                await self._check_files()
                yield
                await self._check_files()
        except TimeoutError:
            raise AllLLMProvidersExhaustedException(code="deadline_exceeded") from None
        finally:
            try:
                for cleanup in resources['cleanup']:
                    await asyncio.shield(cleanup())
            finally:
                TURN_RESOURCES.reset(resources_token)
                REQUEST_DEADLINE.reset(deadline_token)
                self._clock.reset(clock_token)
                LOGICAL_CALL_BUDGET.reset(budget_token)
                TURN_TRACE_ID.reset(trace_token)

    def select_flow(self, flow):
        clock = self._clock.get()
        if clock is None:
            return
        seconds = self.runtime.technical_hard_deadline_seconds if flow == "technical" else getattr(self.runtime, flow).hard_deadline_seconds
        deadline = clock.started + seconds
        budget = LOGICAL_CALL_BUDGET.get()
        budget.maximum = self.runtime.equipment.logical_calls if flow == "technical" else getattr(self.runtime, flow).logical_calls
        if budget.used > budget.maximum:
            raise AllLLMProvidersExhaustedException(code="logical_call_budget_exceeded")
        REQUEST_DEADLINE.set(deadline)
        clock.timeout.reschedule(deadline)
