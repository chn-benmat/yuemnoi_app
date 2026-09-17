from dataclasses import dataclass, field
from typing import List, Optional, Dict, Any

@dataclass
class ChoiceOption:
    id: str
    label: str
    description: Optional[str] = None
    action_value: str = ""

@dataclass
class QuestionStep:
    id: str
    title: str
    options: List[str] = field(default_factory=list)
    step: int = 1
    total_steps: int = 1
    branch_titles: Optional[Dict[str, str]] = None
    branch_options: Optional[Dict[str, List[str]]] = None

@dataclass
class ClarificationQuestion:
    question: str
    options: List[ChoiceOption] = field(default_factory=list)
    missing_dimension: str = ""
    original_query: str = ""
    suggested_intent: Optional[str] = None
    steps: List[QuestionStep] = field(default_factory=list)

