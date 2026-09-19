from typing import Dict, List, Optional
from pydantic import BaseModel, Field

from app.domain.entities.chat_message import ChatMessage
from app.domain.entities.clarification import ChoiceOption, QuestionStep, ClarificationQuestion
from app.domain.entities.item import Item
from app.domain.entities.search_source import SearchSource


class ChatRequestDTO(BaseModel):
    """Incoming chat request matching Go backend's aiChatRequestDTO."""
    message: Optional[str] = None
    query: Optional[str] = None
    session_id: Optional[str] = None
    history: List[ChatMessage] = Field(default_factory=list)

    @property
    def effective_message(self) -> str:
        if self.query and self.query.strip():
            return self.query.strip()
        if self.message and self.message.strip():
            return self.message.strip()
        return ""


class ClarificationDTO(BaseModel):
    """Clarification details matching Go backend's aiClarificationDTO."""
    question: str = ""
    missing_dimension: str = ""
    options: List[ChoiceOption] = Field(default_factory=list)
    questions: List[QuestionStep] = Field(default_factory=list)


class ItemDTO(BaseModel):
    """Item representation matching Go backend and Flutter client."""
    id: str
    name: str
    item_name: str = ""
    category: str
    price: float
    type: str = "วัน"
    unit: str = "วัน"
    price_unit: str = "วัน"
    status: str = "available"
    image_urls: List[str] = Field(default_factory=list)
    image_url: str = ""
    description: str = ""

    @classmethod
    def from_entity(cls, entity: Item) -> "ItemDTO":
        first_img = entity.image_urls[0] if entity.image_urls else ""
        return cls(
            id=entity.id,
            name=entity.name,
            item_name=entity.name,
            category=entity.category,
            price=entity.price,
            type=entity.type,
            unit=entity.type,
            price_unit=entity.type,
            status=entity.status,
            image_urls=entity.image_urls,
            image_url=first_img,
            description=entity.description,
        )


class SearchSourceDTO(BaseModel):
    """Web source matching Go backend's aiSearchSourceDTO."""
    title: str = ""
    link: str = ""
    url: str = ""
    domain: str = ""
    snippet: str = ""

    @classmethod
    def from_entity(cls, entity: SearchSource) -> "SearchSourceDTO":
        target_url = entity.url or entity.link
        return cls(
            title=entity.title,
            link=target_url,
            url=target_url,
            domain=entity.domain,
            snippet=entity.snippet,
        )


class ChatResponseDTO(BaseModel):
    """Complete response payload matching Go backend's aiChatResponseDTO."""
    response: str
    intent: str = "inventory_search"
    confidence: float = 1.0
    ambiguity_level: float = 0.0
    clarification: Optional[ClarificationDTO] = None
    questions: List[QuestionStep] = Field(default_factory=list)
    items: List[ItemDTO] = Field(default_factory=list)
    search_query: str = ""
    search_sources: List[SearchSourceDTO] = Field(default_factory=list)
