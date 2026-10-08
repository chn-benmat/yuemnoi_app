"""Internal response assessment; never a human-review certificate."""
from typing import Literal
from pydantic import ConfigDict, Field, model_validator
from app.domain.entities.catalog_guidance import GuidanceModel


class ReviewIssue(GuidanceModel):
    kind: Literal["semantic", "neutral_voice", "grounding", "context", "choice", "contract"]
    field_path: str = Field(min_length=1, description='Exact JSON pointer relative to the restored draft root, for example /response or /questions/0/title. Do not prefix /draft.',json_schema_extra={'x-provider-description':True})
    quoted_text: str = Field(min_length=1, description='Exact unchanged substring of the original string at field_path, without surrounding quotation marks or paraphrase.',json_schema_extra={'x-provider-description':True})
    reason: str = Field(min_length=1)


class ResponseChecks(GuidanceModel):
    relevance: bool
    completeness: bool
    neutral_voice: bool
    choice_equivalence: bool
    grounding: bool
    context: bool
    followups: bool


class ReviewAssessment(GuidanceModel):
    check: Literal['relevance','completeness','neutral_voice','choice_equivalence','grounding','context','followups']
    reason: str = Field(min_length=1, description='Specific assessment against actual user evidence and original draft text; distinguish assistant authorship from quoted speech.',json_schema_extra={'x-provider-description':True})
    field_paths: list[str] = Field(description='Relevant exact JSON pointers relative to restored draft root. Empty only when that check has no applicable draft field.',json_schema_extra={'x-provider-description':True})
    passed: bool


class ResponseReview(GuidanceModel):
    assessments: list[ReviewAssessment] = Field(default_factory=list)
    semantic_pass: bool
    neutral_voice_pass: bool
    issues: list[ReviewIssue]
    checks: ResponseChecks | None = None
    reviewed_surface_groups: list[Literal['response', 'questions', 'clarification', 'items', 'suggested_replies', 'references', 'search_sources']] = Field(default_factory=list)

    @model_validator(mode="after")
    def consistent_verdict(self):
        semantic_issues = any(i.kind != "neutral_voice" for i in self.issues)
        voice_issues = any(i.kind == "neutral_voice" for i in self.issues)
        if self.semantic_pass == semantic_issues or self.neutral_voice_pass == voice_issues:
            raise ValueError("Review verdict must agree with cited issues")
        if self.checks is not None:
            semantic = all(value for key, value in self.checks.model_dump().items() if key != 'neutral_voice')
            if semantic != self.semantic_pass or self.checks.neutral_voice != self.neutral_voice_pass:
                raise ValueError('Review checks must agree with the verdict')
        return self


class NativeResponseReview(GuidanceModel):
    """A single model assessment per check, rather than contradictory verdict copies."""
    model_config = ConfigDict(populate_by_name=True)
    named_assessments: 'NamedReviewAssessments' = Field(alias='assessments',
        description='One assessment for every required named property. Each property identifies its check; do not emit an array or repeated check entries.',
        json_schema_extra={'x-provider-description': True})
    issues: list[ReviewIssue]
    reviewed_surface_groups: list[Literal['response','questions','clarification','items','suggested_replies','references','search_sources']]

    @property
    def assessments(self):
        return [ReviewAssessment(check=name, **assessment.model_dump())
                for name, assessment in self.named_assessments]

    @property
    def checks(self):
        return ResponseChecks(**{assessment.check:assessment.passed for assessment in self.assessments})

    @property
    def semantic_pass(self):
        return all(assessment.passed for assessment in self.assessments if assessment.check!='neutral_voice')

    @property
    def neutral_voice_pass(self):
        return self.checks.neutral_voice

    def as_review(self):
        return ResponseReview(assessments=self.assessments,semantic_pass=self.semantic_pass,
            neutral_voice_pass=self.neutral_voice_pass,issues=self.issues,checks=self.checks,
            reviewed_surface_groups=self.reviewed_surface_groups)

    @model_validator(mode='after')
    def assessments_match_checks(self):
        # Derive the public internal verdict from the one validated source of
        # truth. Issues still must agree; no malformed old output is repaired.
        self.as_review()
        return self


class NamedAssessment(GuidanceModel):
    reason: str = Field(min_length=1,
        description='Specific assessment of this check against actual user evidence and original draft text.',
        json_schema_extra={'x-provider-description': True})
    field_paths: list[str] = Field(
        description='Exact JSON pointers at the restored draft root; empty only when this check has no applicable field.',
        json_schema_extra={'x-provider-description': True})
    passed: bool


class NamedReviewAssessments(GuidanceModel):
    model_config = ConfigDict(populate_by_name=True)
    relevance: 'ApplicableAssessment'
    completeness: 'ApplicableAssessment'
    neutral_voice: 'NeutralVoiceAssessment' = Field(alias='ungendered_speaker')
    choice_equivalence: NamedAssessment
    grounding: NamedAssessment
    context: NamedAssessment
    followups: NamedAssessment


class ApplicableAssessment(NamedAssessment):
    # คำตอบทุกฉบับมีข้อความให้ตรวจ จึงต้องอ้างฟิลด์จริงก่อนอนุมัติ
    field_paths: list[str] = Field(min_length=1,
        description='Cite at least one exact original draft pointer for this always-applicable check.',
        json_schema_extra={'x-provider-description': True})


class NeutralVoiceAssessment(ApplicableAssessment):
    reason: str = Field(min_length=1,
        description='Inspect assistant-authored speaker expressions and politeness markers for grammatical gender. Conventional or courteous gender-marked wording still fails ungendered voice. Distinguish quoted user/catalog text from assistant speech; cite the actual authored wording rather than accepting the declared register.',
        json_schema_extra={'x-provider-description': True})


NamedReviewAssessments.model_rebuild()
NativeResponseReview.model_rebuild()
