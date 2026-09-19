from typing import AsyncGenerator, List, Optional, Tuple, Type, TypeVar
from pydantic import BaseModel

from app.core.config import settings
from app.core.exceptions import (
    AllLLMProvidersExhaustedException,
    LLMProviderException,
)
from app.core.logging import logger
from app.domain.interfaces.llm_service import LLMServiceInterface
from app.infrastructure.llm.gemini_client import GeminiClient
from app.infrastructure.llm.groq_client import GroqClient

T = TypeVar("T", bound=BaseModel)


class CascadeLLMService(LLMServiceInterface):
    """Orchestrates dual-cloud LLM cascade across 6 priority tiers:
    1. Gemini Primary: gemini-3.5-flash-lite
    2. Gemini Fallback 1: gemini-3.1-flash-lite
    3. Gemini Fallback 2: gemini-2.5-flash-lite
    4. Groq Primary: qwen/qwen3.8-27b
    5. Groq Fallback 1: openai/gpt-oss-120b
    6. Groq Fallback 2: openai/gpt-oss-20b
    """

    def __init__(
        self,
        gemini_client: Optional[GeminiClient] = None,
        groq_client: Optional[GroqClient] = None,
    ):
        self._gemini = gemini_client or GeminiClient()
        self._groq = groq_client or GroqClient()

    def _get_cascade_tiers(self) -> List[Tuple[str, str]]:
        tiers: List[Tuple[str, str]] = []
        for model in settings.gemini_models:
            tiers.append(("gemini", model))
        for model in settings.groq_models:
            tiers.append(("groq", model))
        return tiers

    async def generate_text(
        self,
        prompt: str,
        system_instruction: Optional[str] = None,
        max_tokens: int = 1000,
        temperature: float = 0.7,
    ) -> str:
        last_error = None
        for provider, model in self._get_cascade_tiers():
            try:
                if provider == "gemini":
                    return await self._gemini.generate_text(
                        model=model,
                        prompt=prompt,
                        system_instruction=system_instruction,
                        max_tokens=max_tokens,
                        temperature=temperature,
                    )
                else:
                    return await self._groq.generate_text(
                        model=model,
                        prompt=prompt,
                        system_instruction=system_instruction,
                        max_tokens=max_tokens,
                        temperature=temperature,
                    )
            except Exception as exc:
                last_error = exc
                logger.warning(
                    f"Tier [{provider}:{model}] failed: {exc}. Cascading to next candidate..."
                )
                continue

        logger.critical(f"All 6 LLM cascade tiers exhausted. Last error: {last_error}")
        raise AllLLMProvidersExhaustedException(f"All models failed: {last_error}")

    async def generate_structured(
        self,
        prompt: str,
        schema: Type[T],
        system_instruction: Optional[str] = None,
        temperature: float = 0.2,
    ) -> T:
        last_error = None
        for provider, model in self._get_cascade_tiers():
            try:
                if provider == "gemini":
                    return await self._gemini.generate_structured(
                        model=model,
                        prompt=prompt,
                        schema=schema,
                        system_instruction=system_instruction,
                        temperature=temperature,
                    )
                else:
                    return await self._groq.generate_structured(
                        model=model,
                        prompt=prompt,
                        schema=schema,
                        system_instruction=system_instruction,
                        temperature=temperature,
                    )
            except Exception as exc:
                last_error = exc
                logger.warning(
                    f"Tier [{provider}:{model}] failed for structured output: {exc}. Cascading to next candidate..."
                )
                continue

        logger.critical(f"All 6 LLM cascade tiers exhausted for structured generation. Last error: {last_error}")
        raise AllLLMProvidersExhaustedException(f"All models failed: {last_error}")

    async def generate_stream(
        self,
        prompt: str,
        system_instruction: Optional[str] = None,
        max_tokens: int = 1500,
        temperature: float = 0.7,
    ) -> AsyncGenerator[str, None]:
        last_error = None
        for provider, model in self._get_cascade_tiers():
            yielded_any = False
            try:
                generator = (
                    self._gemini.generate_stream(
                        model=model,
                        prompt=prompt,
                        system_instruction=system_instruction,
                        max_tokens=max_tokens,
                        temperature=temperature,
                    )
                    if provider == "gemini"
                    else self._groq.generate_stream(
                        model=model,
                        prompt=prompt,
                        system_instruction=system_instruction,
                        max_tokens=max_tokens,
                        temperature=temperature,
                    )
                )
                async for chunk in generator:
                    yielded_any = True
                    yield chunk

                # Successfully completed stream
                return
            except Exception as exc:
                last_error = exc
                if yielded_any:
                    # If stream already started outputting to user, we cannot seamlessly restart
                    logger.error(f"Stream interrupted mid-generation on [{provider}:{model}]: {exc}")
                    raise
                logger.warning(
                    f"Tier [{provider}:{model}] failed to start stream: {exc}. Cascading to next candidate..."
                )
                continue

        logger.critical(f"All 6 LLM cascade tiers exhausted for streaming. Last error: {last_error}")
        raise AllLLMProvidersExhaustedException(f"All models failed streaming: {last_error}")
