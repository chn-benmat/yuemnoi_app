from abc import ABC, abstractmethod
from typing import List, Optional, Type, TypeVar, AsyncIterator, Any
from app.domain.entities.chat import ChatMessage

T = TypeVar("T")

class LLMServiceInterface(ABC):
    @abstractmethod
    async def generate_text(
        self,
        prompt: str,
        system_instruction: Optional[str] = None,
        temperature: float = 0.7
    ) -> str:
        """Generate plain text from a prompt."""
        pass

    @abstractmethod
    async def generate_structured(
        self,
        prompt: str,
        response_model: Type[T],
        system_instruction: Optional[str] = None,
        temperature: float = 0.2
    ) -> T:
        """Generate a guaranteed structured output adhering to a Pydantic model schema."""
        pass

    @abstractmethod
    async def generate_chat(
        self,
        messages: List[ChatMessage],
        system_instruction: Optional[str] = None,
        temperature: float = 0.7
    ) -> str:
        """Generate a chat response from a list of ChatMessage objects."""
        pass

    @abstractmethod
    async def generate_chat_stream(
        self,
        messages: List[ChatMessage],
        system_instruction: Optional[str] = None,
        temperature: float = 0.7
    ) -> AsyncIterator[str]:
        """Stream chat completion tokens."""
        pass
