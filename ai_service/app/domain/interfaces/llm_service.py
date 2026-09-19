from typing import AsyncGenerator, Optional, Protocol, Type, TypeVar
from pydantic import BaseModel

T = TypeVar("T", bound=BaseModel)


class LLMServiceInterface(Protocol):
    """Abstract port for interacting with LLM providers with automatic fallback."""

    async def generate_text(
        self,
        prompt: str,
        system_instruction: Optional[str] = None,
        max_tokens: int = 1000,
        temperature: float = 0.7,
    ) -> str:
        """Generate unstructured text completion."""
        ...

    async def generate_structured(
        self,
        prompt: str,
        schema: Type[T],
        system_instruction: Optional[str] = None,
        temperature: float = 0.2,
    ) -> T:
        """Generate typed structured output conforming to a Pydantic schema."""
        ...

    async def generate_stream(
        self,
        prompt: str,
        system_instruction: Optional[str] = None,
        max_tokens: int = 1500,
        temperature: float = 0.7,
    ) -> AsyncGenerator[str, None]:
        """Stream generated text chunks asynchronously."""
        ...
