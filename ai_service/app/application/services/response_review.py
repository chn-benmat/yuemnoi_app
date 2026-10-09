"""One independent model assessment of the exact final draft. No repair loop."""
import json
from pydantic_core import PydanticCustomError
from app.application.services.catalog_guidance import validated_schema
from app.domain.entities.response_review import NativeResponseReview
from app.domain.interfaces.generation_stage import generation_stage
from app.domain.exceptions import GuidanceGenerationError
from app.application.services.review_input import compact_review_draft, restore_review_draft, compact_planning_input
from app.domain.interfaces.chat_diagnostics import record_diagnostic
from app.application.services.recovery_evidence import request_evidence,catalog_evidence

VISIBLE_TEXT_SURFACES = frozenset(('response', 'questions', 'clarification', 'items',
                                 'suggested_replies', 'references', 'search_sources'))

def visible_text_fields(draft):
    """Stable JSON paths for every user-visible string, including duplicated UI fields."""
    result = {}
    def visit(value, path):
        if isinstance(value, str):
            result[path] = value
        elif isinstance(value, dict):
            for key, child in value.items():
                visit(child, path + "/" + str(key).replace("~", "~0").replace("/", "~1"))
        elif isinstance(value, list):
            for index, child in enumerate(value):
                visit(child, path + "/" + str(index))
    for key in sorted(VISIBLE_TEXT_SURFACES):
        visit(draft.get(key), "/" + key)
    return result


class ResponseReviewService:
    def __init__(self, llm, instruction, temperature, context_limits=None):
        self.llm, self.instruction, self.temperature = llm, instruction, temperature
        self.context_limits = context_limits

    async def execute(self, request, draft, writers, catalog, articles, web, *, recovery_request=None, catalog_summary=None):
        if not writers or any(writer is None for writer in writers):
            raise GuidanceGenerationError("review_provenance_unavailable")
        data = draft.model_dump(mode="json")
        fields = visible_text_fields(data)
        draft_paths=set()
        def collect_paths(value,path):
            draft_paths.add(path)
            if isinstance(value,dict):
                for key,child in value.items():
                    collect_paths(child,path+'/'+str(key).replace('~','~0').replace('/','~1'))
            elif isinstance(value,list):
                for index,child in enumerate(value):collect_paths(child,path+'/'+str(index))
        collect_paths(data,'')
        groups = sorted({path.split('/')[1] for path in fields})
        # ให้คำถามหลักอ่านได้ตรง ๆ ก่อน alias สำเนาที่ UI/context ใช้ร่วมกัน
        review_data = {'questions': data['questions'], **data}
        projected, draft_references = compact_review_draft(review_data, literal_paths=('/questions',))
        if restore_review_draft(projected, draft_references) != data:
            raise GuidanceGenerationError("review_input_projection_invalid")
        request_data = request_evidence(request,self.context_limits)
        def validate(review):
            for assessment in review.assessments:
                if any(path not in draft_paths for path in assessment.field_paths):
                    raise PydanticCustomError('review_unknown_assessment_path','Assessment must reference an existing original draft field or collection')
            for issue in review.issues:
                if issue.field_path not in fields or issue.quoted_text not in fields[issue.field_path]:
                    raise PydanticCustomError("review_unknown_text_span", "Review issue must cite an exact draft span")
            if review.semantic_pass and review.neutral_voice_pass:
                if review.checks is None or not all(review.checks.model_dump().values()):
                    raise PydanticCustomError('review_positive_requires_all_checks', 'An approval must assess all quality checks')
                if sorted(review.reviewed_surface_groups) != groups:
                    raise PydanticCustomError('review_surface_coverage_incomplete', 'An approval must cover every visible surface group')
        # ตรวจ pointer ทุกตำแหน่งกับ draft จริงหลัง decode แทน enum ขนาดใหญ่
        # เพื่อให้อ้างฟิลด์ย่อยได้โดยไม่ทำให้ schema กินงบทั้ง request
        schema = validated_schema(NativeResponseReview, validate)
        with generation_stage("review", excluded_models=writers, recovery_request=recovery_request) as capture:
            review = await self.llm.generate_structured(prompt=json.dumps(compact_planning_input({
                "request": request_data, "draft": projected, "draft_references": draft_references, 'surface_groups': groups,
                "assessment_field_paths": sorted('/' + name for name in VISIBLE_TEXT_SURFACES if name in data),
                "issue_path_format": "Assess only the current restored draft. Request history is evidence, never part of the current assistant answer. Assessment field_paths select applicable surfaces from assessment_field_paths. Issue field_path names the exact original string within a surface. Paths start at the restored draft root, never /draft. An issue cites an exact original substring, not a paraphrase or text from history. draft.questions is displayed separately from the introduction; assess both and their aliased duplicates. Inspect every string in every surface group against actual user purpose with specific reasons before deciding verdicts.",
                **({'catalog_summary': catalog_summary} if catalog_summary is not None
                   else {'catalog': catalog_evidence(catalog,draft)}),
                "approved_articles": articles, "search_evidence": web,
            }, literal_paths=('/draft', '/draft_references')), ensure_ascii=False, separators=(",", ":")), schema=schema,
                system_instruction=self.instruction, temperature=self.temperature)
            review = schema.model_validate(review.model_dump())
            record_diagnostic("review", provider=capture.provenance.provider if capture.provenance else None,
                model=capture.provenance.model if capture.provenance else None, review=review.as_review().model_dump(mode="json"))
            if capture.provenance is None or capture.provenance in writers:
                raise GuidanceGenerationError("review_model_not_independent")
        review=review.as_review()
        if not review.semantic_pass or not review.neutral_voice_pass:
            error = GuidanceGenerationError("response_quality_rejected")
            error.review = review.model_dump(mode="json")
            error.draft = data
            error.writers = [{"provider":writer.provider,"model":writer.model} for writer in writers]
            raise error
        return review
