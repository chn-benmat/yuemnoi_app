import json
from unittest.mock import AsyncMock
import pytest
from app.application.dtos.chat_dto import ChatRequestDTO, ChatResponseDTO
from app.application.services.response_review import ResponseReviewService, visible_text_fields
from app.domain.entities.response_review import ResponseReview
from app.domain.interfaces.generation_stage import CURRENT_GENERATION, Provenance
from app.domain.exceptions import GuidanceGenerationError


def stack(result, reviewer=Provenance("fixture", "reviewer"), assessments=True):
    llm = AsyncMock()
    async def generate(**kwargs):
        capture = CURRENT_GENERATION.get()
        assert capture.name == "review" and Provenance("fixture", "writer") in capture.excluded_models
        capture.provenance = reviewer
        from review_fixture import assessed
        return kwargs["schema"].model_validate(assessed(result) if assessments else result)
    llm.generate_structured.side_effect = generate
    return ResponseReviewService(llm, "fixture semantic policy", .1), llm


@pytest.mark.asyncio
async def test_rejection_with_actual_span_withholds_gendered_draft():
    review, llm = stack(dict(semantic_pass=True, neutral_voice_pass=False, issues=[
        dict(kind="neutral_voice", field_path="/response", quoted_text="ครับ", reason="Speaker honorific")]))
    with pytest.raises(GuidanceGenerationError, match="response_quality_rejected") as failure:
        await review.execute(ChatRequestDTO(message="fixture"), ChatResponseDTO(response="ราคา 650 ครับ"),
            [Provenance("fixture", "writer")], [], [], [])
    assert failure.value.review["neutral_voice_pass"] is False
    assert llm.generate_structured.await_count == 1


@pytest.mark.asyncio
async def test_success_still_requires_different_actual_model():
    review, _ = stack(dict(semantic_pass=True, neutral_voice_pass=True, issues=[],
        checks={key: True for key in ('relevance', 'completeness', 'neutral_voice', 'choice_equivalence', 'grounding', 'context', 'followups')},
        reviewed_surface_groups=['response']), Provenance("fixture", "writer"))
    with pytest.raises(GuidanceGenerationError, match="review_model_not_independent"):
        await review.execute(ChatRequestDTO(message="fixture"), ChatResponseDTO(response="ข้อความจริง"),
            [Provenance("fixture", "writer")], [], [], [])


@pytest.mark.asyncio
async def test_fabricated_issue_span_is_not_a_valid_rejection():
    review, _ = stack(dict(semantic_pass=True, neutral_voice_pass=False, issues=[
        dict(kind="neutral_voice", field_path="/response", quoted_text="not in draft", reason="fixture")]))
    from pydantic import ValidationError
    with pytest.raises(ValidationError):
        await review.execute(ChatRequestDTO(message="fixture"), ChatResponseDTO(response="ข้อความจริง"),
            [Provenance("fixture", "writer")], [], [], [])


def test_question_values_and_cards_are_in_review_surface():
    fields = visible_text_fields({"response":"intro", "questions":[{"title":"question", "choices":[
        {"label":"label", "action_value":"value"}]}], "items":[{"description":"card"}],
        "references":[{"title":"citation"}], "suggested_replies":["reply"]})
    assert fields["/questions/0/choices/0/action_value"] == "value"
    assert fields["/items/0/description"] == "card"
    assert fields["/suggested_replies/0"] == "reply"


@pytest.mark.asyncio
async def test_pipeline_never_sends_rejected_final_reply_or_repairs_it():
    from test_fast_turn import make_fast, turn
    from test_request_understanding import understanding
    from app.domain.interfaces.generation_stage import CURRENT_GENERATION
    plan = turn(understanding=understanding(intent="general_greeting", catalog_operation="none",
        information_sufficient=True, missing_slots=[], next_action="answer", request_scope="not_applicable"),
        knowledge_ids=[], response_mode="conversation", message="คุยกันได้ครับ")
    fast, llm, _, _ = make_fast(plan)
    async def generate(**kwargs):
        capture = CURRENT_GENERATION.get()
        capture.provenance = Provenance("fixture", "writer" if capture.name == "planning" else "reviewer")
        if capture.name == "planning":
            return plan
        payload = json.loads(kwargs["prompt"])
        assert payload["draft"]["response"] == "คุยกันได้ครับ"
        from review_fixture import assessed
        return kwargs['schema'].model_validate(assessed(dict(semantic_pass=True, neutral_voice_pass=False, issues=[
            dict(kind="neutral_voice", field_path="/response", quoted_text="ครับ", reason="Actual assistant voice")])) )
    llm.generate_structured.side_effect = generate
    fast._review = ResponseReviewService(llm, "fixture policy", .1)
    with pytest.raises(GuidanceGenerationError, match="response_quality_rejected"):
        await fast.execute(ChatRequestDTO(message="fixture conversation"))
    assert llm.generate_structured.await_count == 2
