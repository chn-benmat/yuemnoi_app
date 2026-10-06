from typing import List, Literal, Optional
from pydantic import BaseModel, ConfigDict, Field, model_validator
from app.domain.entities.clarification import QuestionStep
from app.domain.entities.intent_decision import KnownFact, RequestUnderstanding


class SessionContext(BaseModel):
    """Untrusted current-chat user context, never catalog or policy evidence."""
    model_config = ConfigDict(extra="forbid")
    session_id: str = Field(min_length=1)
    user_goal: str
    budget_max: Optional[float] = Field(default=None, ge=0)
    budget_unit: Optional[str] = None
    intended_use: Optional[str] = None
    categories: List[str] = Field(default_factory=list)
    target_items: List[str] = Field(default_factory=list)
    known_facts: List[KnownFact] = Field(default_factory=list)
    user_constraints: List[KnownFact] = Field(default_factory=list)
    excluded_items: List[str] = Field(default_factory=list)
    referenced_item_ids: List[str] = Field(default_factory=list)
    clarification_declined: bool = False
    questions: List[QuestionStep] = Field(default_factory=list, max_length=3)

    @classmethod
    def from_decision(cls, session_id: str, decision: RequestUnderstanding, questions, item_ids):
        return cls(session_id=session_id, user_goal=decision.user_goal,
                   budget_max=decision.budget_max, budget_unit=decision.budget_unit,
                   intended_use=decision.intended_use, categories=decision.categories, target_items=decision.target_items,
                   known_facts=decision.known_facts, user_constraints=decision.user_constraints,
                   excluded_items=decision.excluded_items, referenced_item_ids=item_ids,
                   clarification_declined=decision.clarification_declined, questions=questions)


class QuestionnaireAnswer(BaseModel):
    model_config = ConfigDict(extra="forbid")
    question_id: str = Field(min_length=1)
    option_id: Optional[str] = Field(default=None, min_length=1)
    text: Optional[str] = Field(default=None, min_length=1)

    @model_validator(mode="after")
    def one_answer(self):
        if (self.option_id is None) == (self.text is None):
            raise ValueError("Supply either option_id or text")
        return self


class AnswerPlan(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    answer: str = Field(min_length=1)
    item_ids: List[str]
    knowledge_ids: List[str]
    search_ids: List[str]
    suggested_replies: List[str]


class EvidenceReference(BaseModel):
    id: str
    kind: Literal["app_knowledge", "web", "catalog"]
    title: str
    reference: str
    reviewed_at: Optional[str] = None
    content_sha256: Optional[str] = None
