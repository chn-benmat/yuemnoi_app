"""Deployment wiring and the approved Groq model roles."""
import json
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.core.config import Settings, settings
from app.core.container import container
from app.infrastructure.runtime.documents import ValidatedFile
from app.infrastructure.runtime.schema import ProviderProfile, RuntimeDocument


ROOT = Path(__file__).resolve().parents[1]


def test_deployed_stages_use_the_three_approved_models():
    runtime = ValidatedFile(settings.AI_RUNTIME_PATH, RuntimeDocument).read()[0]
    assert settings.groq_models == ("openai/gpt-oss-120b", "openai/gpt-oss-20b", "qwen/qwen3.8-27b")
    assert set(container.llm_service._clients) == {"groq"}
    assert len(runtime.providers) == 3 and all(p.enabled for p in runtime.providers)
    assert {p.protocol for p in runtime.providers} == {"groq_json_schema"}
    for stage in ("planning", "evidence", "repair"):
        assert getattr(runtime.stages, stage).profiles == ("groq-primary", "groq-fallback-2", "groq-fallback-1")
    assert runtime.stages.review.profiles == ("groq-fallback-1", "groq-fallback-2", "groq-primary")
    assert runtime.providers[2].reasoning_effort == "none"
    assert runtime.general.hard_deadline_seconds == runtime.equipment.hard_deadline_seconds == 30
    assert runtime.technical_hard_deadline_seconds == 30


def test_retired_provider_configuration_is_rejected():
    profile = container.llm_service.runtime.providers[0].model_dump(mode="json")
    profile.update(protocol="gemini_json_schema", key_setting="GEMINI_API_KEY", model_setting="GEMINI_PRIMARY_MODEL")
    with pytest.raises(ValidationError):
        ProviderProfile.model_validate(profile)
    assert not any(name.startswith("GEMINI_") for name in Settings.model_fields)


def test_exported_runtime_schema_matches_the_python_contract():
    schema = json.loads((ROOT / "config/schemas/ai_runtime.schema.json").read_text(encoding="utf-8"))
    assert schema == RuntimeDocument.model_json_schema()
