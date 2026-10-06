"""One semantic planning call, followed only by evidence synthesis when needed."""
from typing import Literal
from pydantic import Field
from app.domain.entities.catalog_guidance import GuidanceModel, MissingQuestion, QuestionChoice, SelectionPlan
from app.domain.entities.intent_decision import RequestUnderstanding


class PlannedQuestion(MissingQuestion):
    choices: list[QuestionChoice] = Field(min_length=1, max_length=4)


class TurnPlan(GuidanceModel):
    speaker_register: Literal["informal_ungendered"] = Field(default="informal_ungendered", description="Use direct, conversational Thai with no gender attribution to the speaker. Express warmth through responsive wording rather than gender-associated pronouns or sentence-final honorifics. Apply this register to every generated text field.", json_schema_extra={"x-provider-description": True})
    response_mode: Literal["clarification", "documents", "conversation", "information", "catalog_overview", "equipment", "technical"] = Field(description="Select the CURRENT response stage, independent of the eventual catalog operation: clarification whenever any material question is pending; conversation only for a nonfactual social reply with no questions; documents for approved app answers without questions; catalog_overview for unfiltered category browsing; equipment for a ready catalog answer; technical for ready external verification. Clarification includes a brief introduction and stops evidence synthesis, even when a selection/inspection/comparison operation remains requested.", json_schema_extra={"x-provider-description": True})
    overview_available_only: bool = False
    understanding: RequestUnderstanding
    knowledge_ids: list[str]
    unverified_topic_ids: list[str]
    questions: list[PlannedQuestion] = Field(max_length=3)
    message: str = Field(description="Only a brief questionnaire introduction or nonfactual social reply, otherwise empty. Friendly natural Thai in a nongendered speaker voice: omit gender-associated first-person pronouns and sentence-final honorifics; express courtesy through helpful wording.", json_schema_extra={"x-provider-description": True})


class ClarificationStage(GuidanceModel):
    response_mode: Literal['clarification']
    message: str = Field(min_length=1)
    questions: list[PlannedQuestion] = Field(min_length=1, max_length=3)


class EvidenceStage(GuidanceModel):
    response_mode: Literal['equipment', 'technical', 'catalog_overview', 'documents']
    message: Literal['']
    questions: list[PlannedQuestion] = Field(max_length=0)


class ConversationStage(GuidanceModel):
    response_mode: Literal['conversation', 'information']
    message: str = Field(min_length=1)
    questions: list[PlannedQuestion] = Field(max_length=0)


class NativeTurnPlan(GuidanceModel):
    """Provider contract separates current-stage prose from evidence synthesis."""
    speaker_register: Literal['informal_ungendered']
    stage: ClarificationStage | EvidenceStage | ConversationStage
    overview_available_only: bool
    understanding: RequestUnderstanding
    knowledge_ids: list[str]
    unverified_topic_ids: list[str]

    def to_plan(self):
        fields = self.model_dump(exclude={'stage'})
        return TurnPlan.model_validate({**fields, **self.stage.model_dump()})


class EvidenceAnswer(GuidanceModel):
    speaker_register: Literal["informal_ungendered"] = Field(default="informal_ungendered", description="Use direct conversational Thai without speaker-gender attribution, gender-associated pronouns or sentence-final honorifics. This register governs the answer and every suggested reply.", json_schema_extra={"x-provider-description": True})
    request_fit: Literal["meets_request", "no_supported_match", "not_assessed"] = Field(description="Resolve suitability before prose: meets_request only when selected equipment satisfies the user's requested kind, function and every established constraint; no_supported_match when no candidate does so; not_assessed for inspection, technical information or category browsing without a justified item selection. Category membership or an eligible price alone never establishes suitability; complementary equipment does not replace the requested device. This conclusion guides writing and is not an independent review.", json_schema_extra={"x-provider-description": True})
    selection: SelectionPlan | None
    answer: str = Field(min_length=1, description="Lead with the request-fit conclusion in friendly nongendered Thai. For no_supported_match explicitly explain that the requested kind/function has no supported match within the preserved constraints; describe complementary or differently constrained options only as alternatives, never as satisfying the unmet request. Do not infer incompatibility from absent evidence. Render catalog names, prices, units and status through {{item:ID:FIELD}} references to supplied rows, never rewritten literal values.", json_schema_extra={"x-provider-description": True})
    search_ids: list[str]
    suggested_replies: list[str]
