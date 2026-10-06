"""Structured generation contracts; identifiers are not language classifiers."""

from dataclasses import dataclass
from typing import List, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field

from app.domain.entities.item import Item


class GuidanceModel(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False, str_strip_whitespace=True)


class QuestionChoice(GuidanceModel):
    id: str = Field(min_length=1)
    label: str = Field(min_length=1)
    value: str = Field(min_length=1)
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
    evidence_fields: List[Literal["name", "category", "description", "price", "type", "status"]] = Field(min_length=1)


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


@dataclass(frozen=True)
class GuidancePolicy:
    max_questions: int
    max_options: int
    title_max_characters: int
    option_max_characters: int
    max_items: int
    generation_attempts: int
    temperature: float

    def __post_init__(self):
        if not (1 <= self.max_questions <= 3 and 1 <= self.max_options <= 4):
            raise ValueError("Questionnaire limits exceed the supported UI contract")
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
