"""Structured generation contracts; identifiers are not language classifiers."""

from dataclasses import dataclass
from typing import List, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.domain.entities.item import Item


class GuidanceModel(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False, str_strip_whitespace=True)


class QuestionChoice(GuidanceModel):
    id: str = Field(min_length=1)
    label: str = Field(min_length=1, description="Complete answer. Spending maximum: ceiling with billing period or explicitly unlimited, never a lower bound.", json_schema_extra={'x-provider-description': True})
    value: str = Field(min_length=1, description="Same full meaning as label: ceiling/absence and billing period. Keep choices distinct.", json_schema_extra={'x-provider-description': True})
    supporting_item_ids: List[str]


class MissingQuestion(GuidanceModel):
    id: str = Field(min_length=1)
    dimension: str = Field(min_length=1)
    title: str = Field(min_length=1)
    choices: List[QuestionChoice]


class QuestionnairePlan(GuidanceModel):
    introduction: str = Field(min_length=1)
    questions: List[MissingQuestion]


class PriceRequirement(GuidanceModel):
    maximum: float = Field(ge=0)
    user_unit: str = Field(min_length=1)
    catalog_units: List[str] = Field(min_length=1)
    interpretation: str = Field(min_length=1)


class SelectedItem(GuidanceModel):
    id: str = Field(min_length=1)
    reason: str = Field(min_length=1)
    evidence_fields: List[Literal["name", "category", "description", "price", "type", "status"]] = Field(
        min_length=1, description="An array of individual catalog field names used as evidence for this item. Put the field names directly in the array.",
        json_schema_extra={"x-provider-description": True})


class SelectionPlan(GuidanceModel):
    mode: Literal["items", "categories", "no_matches"]
    purpose: Literal["recommendation", "inspection"]
    selected_items: List[SelectedItem]
    price_requirement: Optional[PriceRequirement]
    reasoning: str = Field(min_length=1)


class GuidanceReview(GuidanceModel):
    approved: bool
    issues: List[str]
    reasoning: str = Field(min_length=1)


class QuestionnaireChoicePolicy(GuidanceModel):
    regular_min: int = Field(ge=1)
    regular_max: int = Field(ge=1)
    budget_choices_per_period: int = Field(ge=1)
    budget_period_labels: list[str] = Field(min_length=1)

    @property
    def budget_total(self):
        return self.budget_choices_per_period * len(self.budget_period_labels) + 1

    @model_validator(mode='after')
    def consistent_counts(self):
        if self.regular_min > self.regular_max:
            raise ValueError('Minimum choices exceed maximum choices')
        if (any(not label.strip() for label in self.budget_period_labels)
                or len(set(self.budget_period_labels)) != len(self.budget_period_labels)):
            raise ValueError('Budget periods must be nonempty and distinct')
        return self


@dataclass(frozen=True)
class GuidancePolicy:
    max_questions: int
    max_options: int
    title_max_characters: int
    option_max_characters: int
    max_items: int
    generation_attempts: int
    temperature: float
    choice_policy: QuestionnaireChoicePolicy | None = None

    def __post_init__(self):
        if not (1 <= self.max_questions <= 3 and 1 <= self.max_options <= 5):
            raise ValueError("Questionnaire limits exceed the supported UI contract")
        if self.choice_policy is not None and max(self.choice_policy.regular_max,
                                                  self.choice_policy.budget_total) > self.max_options:
            raise ValueError('Choice policy exceeds the configured display limit')
        if min(self.title_max_characters, self.option_max_characters,
               self.max_items, self.generation_attempts) < 1:
            raise ValueError("Guidance limits must be positive")


@dataclass(frozen=True)
class CatalogSelection:
    items: List[Item]
    mode: str
    available_categories: List[str]
    reasoning: str
    selected_items: List[SelectedItem]
    catalog_evidence: Optional[dict] = None
