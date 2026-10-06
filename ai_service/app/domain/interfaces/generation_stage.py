"""Request-local generation metadata, independent of infrastructure/frameworks."""
from contextlib import contextmanager
from contextvars import ContextVar
from dataclasses import dataclass, field
from typing import Literal

Stage = Literal["planning", "evidence", "review"]


@dataclass(frozen=True)
class Provenance:
    provider: str
    model: str


@dataclass
class GenerationStage:
    name: Stage
    downstream: tuple[Stage, ...] = ()
    excluded_models: frozenset[Provenance] = frozenset()
    provenance: Provenance | None = None
    assessment: dict | None = None


CURRENT_GENERATION = ContextVar("current_generation_stage", default=None)
# Diagnostic-only profile rotations. Production requests leave this unset.
DIAGNOSTIC_PROFILE_ORDER = ContextVar("diagnostic_profile_order", default=None)
# Opt-in evaluation artifact capture. Never set by a production endpoint/logger.
GENERATION_RECORDING = ContextVar("evaluation_generation_records", default=None)


@contextmanager
def generation_stage(name, *, downstream=(), excluded_models=()):
    capture = GenerationStage(name, tuple(downstream), frozenset(excluded_models))
    token = CURRENT_GENERATION.set(capture)
    try:
        yield capture
    finally:
        CURRENT_GENERATION.reset(token)
