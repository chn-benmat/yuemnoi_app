from pydantic import BaseModel
from typing import List, Optional

class VerifiedSourceDTO(BaseModel):
    title: str
    link: str
    snippet: str
    relevance_score: float = 1.0
    is_credible: bool = True

class ComparisonSpecDTO(BaseModel):
    feature_name: str
    item_a_value: str
    item_b_value: str
    notes: Optional[str] = None

class ComparisonDTO(BaseModel):
    item_a_name: str
    item_b_name: str
    item_a_price: Optional[float] = None
    item_b_price: Optional[float] = None
    item_a_status: Optional[str] = None
    item_b_status: Optional[str] = None
    specs: List[ComparisonSpecDTO] = []
    key_differences: List[str] = []
    recommendation: str = ""
    sources: List[VerifiedSourceDTO] = []
    search_query: Optional[str] = None
