"""One semantic planning call, followed only by evidence synthesis when needed."""
from typing import Literal
from pydantic import Field, ConfigDict, model_validator
from app.domain.entities.catalog_guidance import GuidanceModel, MissingQuestion, QuestionChoice, SelectionPlan
from app.domain.entities.intent_decision import RequestUnderstanding, NativePlanningUnderstanding


class QuestionBranch(GuidanceModel):
    source_question_id: str = Field(min_length=1)
    source_option_id: str = Field(min_length=1)
    title: str = Field(min_length=1)
    choices: list[QuestionChoice] = Field(min_length=1, max_length=4)
    unrestricted_choice: QuestionChoice | None = Field(default=None,
        description='For a budget question, a separate explicit no-ceiling choice; otherwise null. Included in the displayed choices.',
        json_schema_extra={'x-provider-description': True})


class PlannedQuestion(MissingQuestion):
    choices: list[QuestionChoice] = Field(min_length=1, max_length=4)
    unrestricted_choice: QuestionChoice | None = Field(default=None,
        description=QuestionBranch.model_fields['unrestricted_choice'].description,
        json_schema_extra={'x-provider-description': True})
    branches: list[QuestionBranch] = Field(default_factory=list, max_length=4,
        description='Adapt to one earlier question: cover each source choice ID with relevant title/choices. Empty if independent or for unknown typed answers.',
        json_schema_extra={'x-provider-description': True})


class NativeQuestionChoice(QuestionChoice):
    choice_kind: Literal['specified', 'unrestricted'] = Field(
        description='specified establishes a preference or finite ceiling; unrestricted leaves that preference unconstrained. A maximum-budget question includes one unrestricted option explicitly removing the ceiling.',
        json_schema_extra={'x-provider-description': True})


class NativeChoiceSet(GuidanceModel):
    choices: list[NativeQuestionChoice] = Field(min_length=1, max_length=4,
        description='All displayed options in one array, including the unrestricted option when applicable. At most four total.',
        json_schema_extra={'x-provider-description': True})

    @model_validator(mode='after')
    def valid_choice_kinds(self):
        unrestricted = sum(choice.choice_kind == 'unrestricted' for choice in self.choices)
        if unrestricted > 1 or unrestricted == len(self.choices):
            raise ValueError('At most one unrestricted option and at least one specified option are required')
        return self

    def domain_choices(self):
        specified, unrestricted = [], None
        for choice in self.choices:
            value = choice.model_dump(exclude={'choice_kind'})
            if choice.choice_kind == 'unrestricted':
                unrestricted = value
            else:
                specified.append(value)
        return {'choices': specified, 'unrestricted_choice': unrestricted}


class NativeQuestionBranch(NativeChoiceSet):
    source_question_id: str = Field(min_length=1)
    source_option_id: str = Field(min_length=1)
    title: str = Field(min_length=1)


class NativePlannedQuestion(MissingQuestion, NativeChoiceSet):
    choices: list[NativeQuestionChoice] = NativeChoiceSet.model_fields['choices']
    branches: list[NativeQuestionBranch] = Field(default_factory=list, max_length=4,
        description=PlannedQuestion.model_fields['branches'].description,
        json_schema_extra={'x-provider-description': True})

    def to_question(self):
        value = self.model_dump(exclude={'choices', 'branches'})
        branches = [{**branch.model_dump(exclude={'choices'}), **branch.domain_choices()} for branch in self.branches]
        return PlannedQuestion.model_validate({**value, **self.domain_choices(), 'branches': branches})


class TurnPlan(GuidanceModel):
    speaker_register: Literal["informal_ungendered"] = Field(default="informal_ungendered", description="Exact machine label. Use natural ungendered Thai in all assistant text.", json_schema_extra={"x-provider-description": True})
    response_mode: Literal["clarification", "documents", "conversation", "information", "catalog_overview", "equipment", "technical"] = Field(description="Select the CURRENT response stage, independent of the eventual catalog operation: clarification whenever any material question is pending; conversation only for a nonfactual social reply with no questions; documents for approved app answers without questions; catalog_overview for unfiltered category browsing; equipment for a ready catalog answer; technical for ready external verification. Clarification includes a brief introduction and stops evidence synthesis, even when a selection/inspection/comparison operation remains requested.", json_schema_extra={"x-provider-description": True})
    overview_available_only: bool = False
    understanding: RequestUnderstanding
    knowledge_ids: list[str]
    unverified_topic_ids: list[str]
    questions: list[PlannedQuestion] = Field(max_length=3)
    message: str = Field(description="Only a brief questionnaire introduction or nonfactual social reply, otherwise empty. Friendly natural Thai in a nongendered speaker voice: omit gender-associated first-person pronouns and sentence-final honorifics; express courtesy through helpful wording.", json_schema_extra={"x-provider-description": True})


class CatalogOperation(GuidanceModel):
    kind: Literal['none', 'selection', 'inspection', 'comparison']


class EvidenceCatalogOperation(CatalogOperation):
    kind: Literal['selection', 'inspection', 'comparison']


class NoCatalogOperation(CatalogOperation):
    kind: Literal['none']


class ClarificationStage(GuidanceModel):
    model_config = ConfigDict(extra='forbid',populate_by_name=True)
    response_mode: Literal['clarification']
    catalog_operation: CatalogOperation
    message: str = Field(alias='text', min_length=1, description="Original assistant invitation to pending questions; never echo the user. Natural ungendered Thai.", json_schema_extra={'x-provider-description': True})
    questions: list[NativePlannedQuestion] = Field(min_length=1, max_length=3)


class EvidenceStage(GuidanceModel):
    model_config = ConfigDict(extra='forbid',populate_by_name=True)
    response_mode: Literal['equipment', 'catalog_overview'] = Field(
        description='equipment: ready named-item, comparison or filtered requests. catalog_overview: unfiltered category browsing only, without targets, spending ceiling, user constraints, exclusions or external verification.',
        json_schema_extra={'x-provider-description': True})
    catalog_operation: EvidenceCatalogOperation
    message: Literal[''] = Field(alias='text')
    questions: list[None] = Field(max_length=0)


class TechnicalStage(EvidenceStage):
    response_mode: Literal['technical'] = Field(description='Ready technical facts need focused external verification.',
        json_schema_extra={'x-provider-description': True})
    catalog_operation: CatalogOperation


class DocumentStage(EvidenceStage):
    response_mode: Literal['documents'] = Field(description='Ready app information uses supplied approved articles.',
        json_schema_extra={'x-provider-description': True})
    catalog_operation: NoCatalogOperation


class ConversationStage(GuidanceModel):
    model_config = ConfigDict(extra='forbid',populate_by_name=True)
    response_mode: Literal['conversation', 'information'] = Field(
        description='conversation pairs with analysis.intent=general_greeting for allowed social acts/humor. Explanations and scope refusals use information with analysis.intent=general_information. Catalog facts require equipment; unverifiable facts are evidence gaps, never preferences.',
        json_schema_extra={'x-provider-description': True})
    catalog_operation: NoCatalogOperation
    message: str = Field(alias='text',min_length=1)
    questions: list[None] = Field(max_length=0)


class NativeTurnPlan(GuidanceModel):
    """Provider contract separates current-stage prose from evidence synthesis."""
    model_config = ConfigDict(extra='forbid',populate_by_name=True)
    speaker_register: Literal['informal_ungendered'] = Field(description=TurnPlan.model_fields['speaker_register'].description,
        json_schema_extra={'x-provider-description': True})
    stage: ClarificationStage | EvidenceStage | TechnicalStage | DocumentStage | ConversationStage = Field(
        description='Select the current stage using its response_mode semantics, not the eventual rental operation alone.',
        json_schema_extra={'x-provider-description': True})
    overview_available_only: bool
    # Groq จัดลำดับ keys ตามตัวอักษร ให้ reasoning ออกก่อน stage และข้อความ
    understanding: NativePlanningUnderstanding = Field(alias='analysis')
    knowledge_ids: list[str]
    unverified_topic_ids: list[str]

    def to_plan(self):
        fields = self.model_dump(exclude={'stage'})
        fields['understanding']=self.understanding.to_understanding(
            self.stage.catalog_operation.kind, [question.dimension for question in self.stage.questions]).model_dump()
        stage = self.stage.model_dump(exclude={'catalog_operation'})
        # แปลงชนิดช้อยที่โมเดลระบุเข้าสัญญาภายใน โดยไม่ตีความข้อความ label/value
        stage['questions'] = [question.to_question().model_dump() for question in self.stage.questions]
        return TurnPlan.model_validate({**fields, **stage})


class EvidenceAnswer(GuidanceModel):
    model_config = ConfigDict(extra='forbid',populate_by_name=True)
    speaker_register: Literal["informal_ungendered"] = Field(default="informal_ungendered", description="Return the exact machine label informal_ungendered, never a description or translation. Answer and suggested replies use natural Thai without gendered speaker pronouns or honorifics.", json_schema_extra={"x-provider-description": True})
    request_fit: Literal["meets_request", "no_supported_match", "not_assessed"] = Field(description="Resolve suitability before prose: meets_request only when selected equipment satisfies the user's requested kind, function and every established constraint; no_supported_match when no candidate does so; not_assessed for inspection, technical information or category browsing without a justified item selection. Category membership or an eligible price alone never establishes suitability; complementary equipment does not replace the requested device. This conclusion guides writing and is not an independent review.", json_schema_extra={"x-provider-description": True})
    selection: SelectionPlan | None
    answer: str = Field(alias='text',min_length=1, description="Lead with the request-fit conclusion in friendly nongendered Thai. For no_supported_match explicitly explain that the requested kind/function has no supported match within the preserved constraints; describe complementary or differently constrained options only as alternatives, never as satisfying the unmet request. Do not infer incompatibility from absent evidence. Render catalog names, prices, units and status through {{item:ID:FIELD}} references to supplied rows, never rewritten literal values. For product recommendations, follow the system's presentation instructions: each product has a standalone bold name followed by a Markdown field list. Keep the name and fields on separate lines, never combine them into an inline paragraph.", json_schema_extra={"x-provider-description": True})
    search_ids: list[str]
    suggested_replies: list[str]


class ReplyRepair(EvidenceAnswer):
    """One replacement of generated surfaces; authoritative facts are projected separately."""
    questions: list[PlannedQuestion] = Field(max_length=3)
