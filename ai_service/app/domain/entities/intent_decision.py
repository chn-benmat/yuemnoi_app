from typing import List, Literal, Optional
from pydantic import BaseModel, ConfigDict, Field, model_validator


class IntentDecision(BaseModel):
    """Semantic intent classification and entity extraction decision."""
    intent: str = Field(
        description="Communicative purpose of the user input: "
                    "'bot_capabilities' for assistant or app capability questions; "
                    "'item_inquiry' for details of equipment actually referenced; "
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
        description="Names or model identifiers of equipment the user actually refers to, resolved semantically."
    )
    categories: List[str] = Field(
        default_factory=list,
        description="Conceptual categories of equipment identified from the user query."
    )
    budget_max: Optional[float] = Field(
        default=None,
        description="Maximum budget constraint mentioned by the user."
    )
    budget_unit: Optional[str] = Field(default=None, description="User-stated budget billing period, without guessing a period.")
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
    next_action: Optional[Literal["answer", "clarify"]] = None

    @property
    def requires_clarification(self) -> bool:
        # Compatibility for older internal callers; live routing requires an action.
        if self.next_action is not None:
            return self.next_action == "clarify"
        return self.intent == "clarification_needed"


class KnownFact(BaseModel):
    model_config = ConfigDict(extra="forbid")
    dimension: str = Field(min_length=1)
    value: str = Field(min_length=1)
    source_message_ids: List[str] = Field(min_length=1)


class RequestUnderstanding(IntentDecision):
    """Required semantic contract for live routing, independent of legacy scores."""
    model_config = ConfigDict(extra="forbid")
    intent: Literal[
        "bot_capabilities", "item_inquiry", "inventory_search", "comparison",
        "clarification_needed", "platform_faq", "general_greeting", "general_information",
    ] = Field(description="Communicative purpose, separate from whether clarification is needed.")
    ambiguity_level: float = Field(ge=0, le=1, description="Unresolved meaning; not an action threshold.")
    confidence: float = Field(ge=0, le=1, description="Uncalibrated model self-assessment.")
    target_items: List[str] = Field(description="Equipment actually requested or referred to; resolve only supported references.")
    categories: List[str] = Field(description="Conceptual equipment categories, without a fixed catalog taxonomy.")
    budget_max: Optional[float] = Field(description="Explicit maximum budget; null when absent or units cannot be interpreted.")
    budget_unit: Optional[str] = Field(description="Budget billing period explicitly established by the user; null when unknown, do not infer it from shop units.")
    intended_use: Optional[str] = Field(description="Relevant user-stated workload, after corrections; null if unknown.")
    missing_slots: List[str] = Field(description="Only material unknown requirements for the requested operation, not optional preferences.")
    needs_external_search: bool = Field(description="Whether technical facts need external verification; shop prices, stock and policies need their authoritative source.")
    search_query: Optional[str] = Field(description="Focused technical verification query, or null when unnecessary.")
    user_goal: str = Field(min_length=1)
    catalog_operation: Literal["none", "selection", "inspection", "comparison"] = Field(
        description="Required catalog operation across all user goals, independent of the primary intent; none when no catalog evidence is needed.")
    additional_goals: List[str]
    request_scope: Literal["broad", "specific", "not_applicable"]
    information_sufficient: bool
    next_action: Literal["answer", "clarify"]
    known_facts: List[KnownFact]
    user_constraints: List[KnownFact]
    excluded_items: List[str]
    topic_changed: bool
    clarification_declined: bool
    reference_resolution: str = Field(min_length=1)
    decision_reason: str = Field(min_length=1)

    @model_validator(mode="after")
    def check_action_contract(self):
        if self.next_action == "clarify" and not self.missing_slots:
            raise ValueError("Clarification requires a material missing requirement")
        if self.next_action == "clarify" and self.information_sufficient:
            raise ValueError("Sufficient information cannot require clarification")
        if self.information_sufficient and self.missing_slots:
            raise ValueError("Material missing requirements contradict sufficiency")
        if self.clarification_declined and self.next_action == "clarify":
            raise ValueError("Declined clarification cannot be required again")
        if self.needs_external_search and not (self.search_query or "").strip():
            raise ValueError("External verification requires a search query")
        return self
