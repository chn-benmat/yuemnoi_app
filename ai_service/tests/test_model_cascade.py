import pytest
from unittest.mock import AsyncMock, MagicMock
from app.core.config import settings
from app.core.exceptions import AllLLMProvidersExhaustedException, LLMProviderException
from app.infrastructure.llm.cascade_llm_service import CascadeLLMService


@pytest.mark.asyncio
async def test_cascade_falls_back_to_other_provider_when_primary_rate_limited(monkeypatch):
    """One failed attempt uses one eligible fallback, without repeating the quota bucket."""
    mock_gemini = MagicMock()
    mock_groq = MagicMock()

    # Make all Gemini calls fail with 429 Quota Exceeded
    mock_gemini.generate_text = AsyncMock(
        side_effect=LLMProviderException("Gemini", "gemini-3.5-flash-lite", "Quota exceeded", status_code=429)
    )

    # Make Groq succeed on primary model
    mock_groq.generate_text = AsyncMock(return_value="คำตอบจาก Groq สำรองค่ะ")

    config = settings.model_copy(update={"GROQ_PRIMARY_MODEL": "fixture-backup"})
    cascade = CascadeLLMService(gemini_client=mock_gemini, groq_client=mock_groq, configuration=config)
    monkeypatch.setattr(cascade, "_get_cascade_tiers", lambda: [("gemini", "fixture-primary"), ("groq", "fixture-backup")])
    result = await cascade.generate_text(prompt="สวัสดีค่ะ")

    assert result == "คำตอบจาก Groq สำรองค่ะ"
    assert mock_gemini.generate_text.call_count == 1
    assert mock_groq.generate_text.call_count == 1


@pytest.mark.asyncio
async def test_cascade_raises_exhausted_after_bounded_failed_attempts(monkeypatch):
    """The failover bound does not expand to every configured model."""
    mock_gemini = MagicMock()
    mock_groq = MagicMock()

    mock_gemini.generate_text = AsyncMock(
        side_effect=LLMProviderException("Gemini", "gemini", "Service down", status_code=503)
    )
    mock_groq.generate_text = AsyncMock(
        side_effect=LLMProviderException("Groq", "groq", "Rate limited", status_code=429)
    )

    config = settings.model_copy(update={"GROQ_PRIMARY_MODEL": "fixture-backup", "GROQ_FALLBACK_MODEL_1": "fixture-extra"})
    cascade = CascadeLLMService(gemini_client=mock_gemini, groq_client=mock_groq, configuration=config)
    monkeypatch.setattr(cascade, "_get_cascade_tiers", lambda: [("gemini", "fixture-primary"), ("groq", "fixture-backup"), ("groq", "fixture-extra")])

    with pytest.raises(AllLLMProvidersExhaustedException):
        await cascade.generate_text(prompt="ทดสอบ")

    assert mock_gemini.generate_text.call_count == 1
    assert mock_groq.generate_text.call_count == 1
