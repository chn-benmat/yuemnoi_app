from dataclasses import dataclass, field
from enum import Enum
from typing import List, Optional, Dict, Any

class IntentType(str, Enum):
    ITEM_INQUIRY = "ITEM_INQUIRY"
    ITEM_SPEC_INQUIRY = "ITEM_SPEC_INQUIRY"
    RENTAL_COMPARISON = "RENTAL_COMPARISON"
    CLARIFICATION_NEEDED = "CLARIFICATION_NEEDED"
    GENERAL_CHAT = "GENERAL_CHAT"

@dataclass
class ExtractedSlots:
    target_items: List[str] = field(default_factory=list)
    categories: List[str] = field(default_factory=list)
    target_attribute: Optional[str] = None
    budget_max: Optional[float] = None
    rental_duration: Optional[str] = None
    intended_use: Optional[str] = None
    missing_slots: List[str] = field(default_factory=list)

@dataclass
class IntentDecision:
    intent: IntentType
    confidence: float
    ambiguity_level: float
    slots: ExtractedSlots
    reasoning: str = ""
    needs_web_search: bool = False
    is_comparison: bool = False
