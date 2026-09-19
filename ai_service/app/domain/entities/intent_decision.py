from typing import List, Optional
from pydantic import BaseModel, Field


class IntentDecision(BaseModel):
    """Semantic intent classification and entity extraction decision."""
    intent: str = Field(
        description="Communicative purpose of the user input: "
                    "'bot_capabilities' when user asks what the assistant or app can do (strictly when no equipment is in active discussion in recent context); "
                    "'item_inquiry' when user asks about features, capabilities, specs, or what specific or previously discussed item(s) can do (including elliptical questions regarding capabilities when items were just introduced in context); "
                    "'inventory_search' for requests to find, rent, or check equipment; "
                    "'comparison' for comparing specifications or features of multiple models, or requesting decision advice/recommendation between 2+ previously recommended equipment items; "
                    "'clarification_needed' when request lacks necessary specificity to act; "
                    "'platform_faq' for inquiries on rental rules, fees, app identity, or policies; "
                    "'general_greeting' for conversational greetings without specific rental requests."
    )
    ambiguity_level: float = Field(
        default=0.0,
        ge=0.0,
        le=1.0,
        description="Degree of underspecification in the request: 0.0 means completely specific, 1.0 means highly ambiguous."
    )
    confidence: float = Field(
        default=1.0,
        ge=0.0,
        le=1.0,
        description="Model confidence in this classification decision."
    )
    target_items: List[str] = Field(
        default_factory=list,
        description="Names or model identifiers of specific equipment referenced by the user or discussed in recent context (if multiple items are in context, list all of them)."
    )
    categories: List[str] = Field(
        default_factory=list,
        description="Conceptual categories of equipment identified from the user query."
    )
    budget_max: Optional[float] = Field(
        default=None,
        description="Maximum budget constraint mentioned by the user."
    )
    intended_use: Optional[str] = Field(
        default=None,
        description="Use case, workload, or scenario described by the user."
    )
    missing_slots: List[str] = Field(
        default_factory=list,
        description="Essential dimensions missing from user query necessary to make a definitive recommendation."
    )
    needs_external_search: bool = Field(
        default=False,
        description="True if request requires technical verification, release specs, or external comparisons beyond catalog data."
    )
    search_query: Optional[str] = Field(
        default=None,
        description="Targeted technical search query if external web search is needed."
    )
