"""Request-local generation metadata, independent of infrastructure/frameworks."""
from contextlib import contextmanager
from contextvars import ContextVar
from dataclasses import dataclass, field
from typing import Callable, Literal
from pydantic import BaseModel

Stage = Literal["planning", "evidence", "review", "repair"]


@dataclass(frozen=True)
class Provenance:
    provider: str
    model: str


@dataclass
class GenerationRequest:
    prompt: str
    schema: type[BaseModel]
    system_instruction: str | None
    temperature: float


@dataclass
class GenerationStage:
    name: Stage
    downstream: tuple[Stage, ...] = ()
    excluded_models: frozenset[Provenance] = frozenset()
    provenance: Provenance | None = None
    assessment: dict | None = None
    recovery_request: GenerationRequest | None = None


CURRENT_GENERATION = ContextVar("current_generation_stage", default=None)
# ผู้รับสถานะผูกกับคำขอ เพื่อไม่ให้ขั้นตอนของแชตที่ทำพร้อมกันปะปนกัน
GENERATION_PROGRESS: ContextVar[Callable[[Stage], None] | None] = ContextVar("generation_progress", default=None)
# Diagnostic-only profile rotations. Production requests leave this unset.
DIAGNOSTIC_PROFILE_ORDER = ContextVar("diagnostic_profile_order", default=None)
# Opt-in evaluation artifact capture. Never set by a production endpoint/logger.
GENERATION_RECORDING = ContextVar("evaluation_generation_records", default=None)


@contextmanager
def generation_progress(listener: Callable[[Stage], None]):
    token = GENERATION_PROGRESS.set(listener)
    try:
        yield
    finally:
        GENERATION_PROGRESS.reset(token)


@contextmanager
def generation_stage(name, *, downstream=(), excluded_models=(), recovery_request=None):
    capture = GenerationStage(name, tuple(downstream), frozenset(excluded_models))
    capture.recovery_request = recovery_request
    token = CURRENT_GENERATION.set(capture)
    try:
        listener = GENERATION_PROGRESS.get()
        if listener is not None:
            listener(name)
        yield capture
    finally:
        CURRENT_GENERATION.reset(token)
