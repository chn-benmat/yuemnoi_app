from contextlib import AbstractAsyncContextManager
from typing import Literal, Protocol


class ExecutionGuard(Protocol):
    def turn(self) -> AbstractAsyncContextManager[None]: ...
    def select_flow(self, flow: Literal["general", "equipment", "technical"]) -> None: ...
