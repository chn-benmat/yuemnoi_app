from typing import List, Optional
from pydantic import BaseModel, Field


class SemanticItemFilterDecision(BaseModel):
    """Structured decision for AI-Native semantic catalog item selection."""
    matched_item_ids: List[str] = Field(
        default_factory=list,
        description="List of item IDs from the catalog that directly and strictly match the user's requested equipment or intended use. Only include items that genuinely match. Do NOT backfill with unrelated items."
    )
    reasoning: Optional[str] = Field(
        default=None,
        description="Brief concise rationale for why these items were selected and others excluded."
    )
