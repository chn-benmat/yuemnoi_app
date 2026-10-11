from typing import Dict, List, Optional, Literal
from pydantic import BaseModel, Field, model_validator
from app.domain.entities.chat_result import SessionContext, QuestionnaireAnswer, EvidenceReference

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
    context: Optional[SessionContext] = None
    questionnaire_answers: List[QuestionnaireAnswer] = Field(default_factory=list, max_length=3)
    questionnaire_skipped: bool = False
    active_question_id: Optional[str] = Field(default=None, min_length=1)

    @model_validator(mode="after")
    def check_session_and_answers(self):
        if not self.effective_message:
            raise ValueError("A message is required")
        if self.context is not None and self.context.session_id != self.session_id:
            raise ValueError("Context must belong to this session")
        if self.active_question_id is not None:
            if self.context is None or self.active_question_id not in {q.id for q in self.context.questions}:
                raise ValueError("Active question must belong to the supplied context")
        if self.questionnaire_answers:
            if self.context is None:
                raise ValueError("Questionnaire answers require context")
            questions = {q.id: q for q in self.context.questions}
            ids = [a.question_id for a in self.questionnaire_answers]
            answers = {a.question_id: a for a in self.questionnaire_answers}
            if len(ids) != len(set(ids)):
                raise ValueError("Duplicate question answer")
            for answer in self.questionnaire_answers:
                question = questions.get(answer.question_id)
                if question is None:
                    raise ValueError("Unknown question ID")
                if answer.option_id is not None and answer.option_id not in {c.id for c in question.choices}:
                    raise ValueError("Unknown choice ID")
                if answer.option_id is not None and question.branch_question_id:
                    source = answers.get(question.branch_question_id)
                    choices = question.branch_choices.get(source.option_id) if source else None
                    if choices is not None and answer.option_id not in {c.id for c in choices}:
                        raise ValueError("Choice does not belong to the selected question branch")
        return self

    @property
    def questionnaire_complete(self) -> bool:
        """ครบเมื่อมีคำตอบจริงของทุก ID ในชุดปัจจุบัน ไม่อนุมานจากข้อความ"""
        return bool(self.context and self.context.questions) and {
            answer.question_id for answer in self.questionnaire_answers
        } == {question.id for question in self.context.questions}

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
    price_display: str | None = None
    unit_display: str | None = None
    status_display: str | None = None
    image_urls: List[str] = Field(default_factory=list)
    image_url: str = ""
    description: str = ""

    @classmethod
    def from_entity(cls, entity: Item, presentation=None) -> "ItemDTO":
        from app.application.services.catalog_guidance import presented_record
        display = presented_record(entity, presentation)
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
            price_display=display.get('price_display'),
            unit_display=display.get('unit_display'),
            status_display=display.get('status_display'),
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
    suggested_replies: List[str] = Field(default_factory=list)
    context: Optional[SessionContext] = None
    references: List[EvidenceReference] = Field(default_factory=list)
    request_scope: Optional[Literal["broad", "specific", "not_applicable"]] = None
    information_sufficient: Optional[bool] = None
    next_action: Optional[Literal["answer", "clarify"]] = None
    response_flow: Optional[Literal["general", "equipment", "technical"]] = None
    response_kind: Optional[Literal["clarification", "conversation", "information", "overview", "recommendation", "item_details", "comparison", "technical", "app_information"]] = None

