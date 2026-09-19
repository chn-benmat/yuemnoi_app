from typing import Dict, List, Optional
from pydantic import BaseModel, Field


class ComparisonMatrix(BaseModel):
    """Domain model representing verified comparison between equipment items."""
    target_items: List[str] = Field(default_factory=list)
    specifications: Dict[str, Dict[str, str]] = Field(
        default_factory=dict,
        description="Key technical specifications per model (e.g., {'Sony A7 IV': {'sensor': '33MP Full-Frame', 'video': '4K 60p'}})"
    )
    pros_and_cons: Dict[str, Dict[str, List[str]]] = Field(
        default_factory=dict,
        description="Objective pros and cons per model grounded in technical specs"
    )
    verdict: str = Field(
        default="",
        description="Balanced, unbiased situational verdict explaining which workflow suits each device."
    )
