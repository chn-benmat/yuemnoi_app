from typing import Dict, List, Optional
from pydantic import BaseModel, Field


class ChoiceOption(BaseModel):
    """Domain model representing a clickable choice chip."""
    id: str
    label: str
    description: str = ""
    action_value: str = ""


class QuestionStep(BaseModel):
    """Domain model representing an adaptive multi-step question."""
    id: str
    title: str
    options: List[str] = Field(default_factory=list)
    step: int = 1
    total_steps: int = 1
    branch_titles: Dict[str, str] = Field(default_factory=dict)
    branch_options: Dict[str, List[str]] = Field(default_factory=dict)


class ClarificationQuestion(BaseModel):
    """Domain model representing clarification details for underspecified requests."""
    question: str
    missing_dimension: str = ""
    options: List[ChoiceOption] = Field(default_factory=list)
    questions: List[QuestionStep] = Field(default_factory=list)
