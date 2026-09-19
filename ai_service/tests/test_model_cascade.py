import pytest
from unittest.mock import AsyncMock, MagicMock
from app.core.config import settings
from app.core.exceptions import AllLLMProvidersExhaustedException, LLMProviderException
from app.infrastructure.llm.cascade_llm_service import CascadeLLMService


@pytest.mark.asyncio
async def test_cascade_falls_back_when_primary_gemini_fails():
    """Verifies that when Gemini primary fails (e.g. 429 quota), it falls back down the cascade."""
    mock_gemini = MagicMock()
    mock_groq = MagicMock()

    # Make all Gemini calls fail with 429 Quota Exceeded
    mock_gemini.generate_text = AsyncMock(
        side_effect=LLMProviderException("Gemini", "gemini-3.5-flash-lite", "Quota exceeded", status_code=429)
    )

    # Make Groq succeed on primary model
    mock_groq.generate_text = AsyncMock(return_value="คำตอบจาก Groq สำรองค่ะ")

    cascade = CascadeLLMService(gemini_client=mock_gemini, groq_client=mock_groq)
    result = await cascade.generate_text(prompt="สวัสดีค่ะ")

    assert result == "คำตอบจาก Groq สำรองค่ะ"
    # Verify Gemini was attempted 3 times (for 3 gemini models) before switching to Groq
    assert mock_gemini.generate_text.call_count == len(settings.gemini_models)
    assert mock_groq.generate_text.call_count == 1


@pytest.mark.asyncio
async def test_cascade_raises_exhausted_when_all_fail():
    """Verifies that when all 6 models fail, AllLLMProvidersExhaustedException is raised."""
    mock_gemini = MagicMock()
    mock_groq = MagicMock()

    mock_gemini.generate_text = AsyncMock(
        side_effect=LLMProviderException("Gemini", "gemini", "Service down", status_code=503)
    )
    mock_groq.generate_text = AsyncMock(
        side_effect=LLMProviderException("Groq", "groq", "Rate limited", status_code=429)
    )

    cascade = CascadeLLMService(gemini_client=mock_gemini, groq_client=mock_groq)

    with pytest.raises(AllLLMProvidersExhaustedException):
        await cascade.generate_text(prompt="ทดสอบ")

    total_models = len(settings.gemini_models) + len(settings.groq_models)
    assert mock_gemini.generate_text.call_count == len(settings.gemini_models)
    assert mock_groq.generate_text.call_count == len(settings.groq_models)
