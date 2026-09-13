from dataclasses import dataclass, field
from typing import List, Optional, Dict, Any

@dataclass
class VerifiedSource:
    title: str
    link: str
    snippet: str
    relevance_score: float = 1.0
    is_credible: bool = True

@dataclass
class ComparisonSpec:
    feature_name: str
    item_a_value: str
    item_b_value: str
    notes: Optional[str] = None

@dataclass
class ComparisonMatrix:
    item_a_name: str
    item_b_name: str
    item_a_price: Optional[float] = None
    item_b_price: Optional[float] = None
    item_a_status: Optional[str] = None
    item_b_status: Optional[str] = None
    specs: List[ComparisonSpec] = field(default_factory=list)
    key_differences: List[str] = field(default_factory=list)
    recommendation: str = ""
    sources: List[VerifiedSource] = field(default_factory=list)
    search_query: Optional[str] = None
