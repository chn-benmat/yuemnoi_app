from pydantic import BaseModel, Field
from typing import List, Optional, Dict

class ChoiceOptionDTO(BaseModel):
    id: str
    label: str
    description: Optional[str] = None
    action_value: str = ""

class QuestionStepDTO(BaseModel):
    id: str
    title: str
    options: List[str] = Field(default_factory=list)
    step: int = 1
    total_steps: int = 1
    branch_titles: Optional[Dict[str, str]] = None
    branch_options: Optional[Dict[str, List[str]]] = None

class ClarificationDTO(BaseModel):
    question: str
    missing_dimension: str
    options: List[ChoiceOptionDTO] = []
    questions: List[QuestionStepDTO] = []

