"""Contract regressions; semantic behavior is evaluated separately with real providers."""
import json

import httpx
import pytest
from pydantic import ValidationError

from app.application.dtos.chat_dto import ChatRequestDTO
from app.application.use_cases.plan_chat_turn_use_case import render_catalog_text
from app.domain.entities.chat_result import SessionContext
from app.domain.entities.clarification import QuestionStep, ChoiceOption
from app.domain.entities.turn_plan import PlannedQuestion
from test_fast_turn import ITEM, equipment_answer, make_fast, turn
from test_request_understanding import understanding
from test_provider_runtime import stack, SmallResult
from app.infrastructure.llm.provider_client import native_schema
from pydantic import BaseModel, Field
from typing import Literal


def context():
    return SessionContext(session_id="session", user_goal="เลือกอุปกรณ์", questions=[
        QuestionStep(id="batch:duration", dimension="rental_duration", title="เช่านานเท่าไร",
            choices=[ChoiceOption(id="week", label="หนึ่งสัปดาห์", action_value="1 week")])])


def test_active_question_is_a_hint_and_does_not_create_an_answer():
    request = ChatRequestDTO(message="เปลี่ยนเรื่อง", session_id="session", context=context(),
                             active_question_id="batch:duration")
    assert request.questionnaire_answers == []
    for changes in ({"active_question_id": "unknown"}, {"context": None}):
        with pytest.raises(ValidationError):
            ChatRequestDTO.model_validate({**request.model_dump(), **changes})


@pytest.mark.asyncio
async def test_raw_turn_and_active_question_reach_semantic_planner():
    decision = understanding(intent="general_greeting", catalog_operation="none", next_action="answer",
                             information_sufficient=True, missing_slots=[], request_scope="specific")
    fast, llm, _, _ = make_fast(turn(understanding=decision, knowledge_ids=[], message="พักคุยกันได้เลย", response_mode="conversation"))
    result = await fast.execute(ChatRequestDTO(message="เล่าเรื่องขำ ๆ", session_id="session",
                                              context=context(), active_question_id="batch:duration"))
    payload = json.loads(llm.generate_structured.call_args.kwargs["prompt"])
    assert payload["active_question_id"] == "batch:duration"
    assert payload["current_message"]["content"] == "เล่าเรื่องขำ ๆ"
    assert not payload["questionnaire_answers"]["data"]
    assert not result.questions and not result.items


@pytest.mark.asyncio
async def test_duration_choices_cannot_collapse_distinct_labels_into_daily():
    q = PlannedQuestion(id="duration", dimension="rental_duration", title="เช่านานเท่าไร", choices=[
        {"id": "one", "label": "1 วัน", "value": "daily", "supporting_item_ids": []},
        {"id": "week", "label": "1 สัปดาห์", "value": "daily", "supporting_item_ids": []}])
    fast, _, _, _ = make_fast(turn(understanding=understanding(missing_slots=["rental_duration"]),
        knowledge_ids=[], questions=[q], message="ขอระยะเวลา", response_mode="clarification"))
    with pytest.raises(ValidationError, match="distinct answer values"):
        await fast.execute(ChatRequestDTO(message="ช่วยเลือกอุปกรณ์"))


def test_catalog_text_uses_authoritative_fields_and_rejects_unknown_reference():
    assert render_catalog_text("{{item:real-1:name}} ราคา {{item:real-1:price}} ต่อ{{item:real-1:type}}", [ITEM]) == "คลังจริง ราคา 100.0 ต่อวัน"
    for value in ("{{item:absent:name}}", "{{item:real-1:invented}}", "{{item:real-1:name"):
        with pytest.raises(ValueError):
            render_catalog_text(value, [ITEM])


@pytest.mark.parametrize("text", [
    "${item:real-1:price}", "{item:real-1:price}", "item:real-1:price",
    "{{item:real-1:name}} ${item:real-1:type}",
])
def test_reserved_catalog_namespace_cannot_leak_as_literal_text(text):
    with pytest.raises(ValueError, match="Malformed catalog text reference"):
        render_catalog_text(text, [ITEM])


@pytest.mark.asyncio
@pytest.mark.parametrize("field", ["answer", "suggested_replies"])
async def test_provider_admission_rejects_malformed_catalog_tokens_in_all_evidence_prose(field):
    decision = understanding(catalog_operation="selection", information_sufficient=True,
                             next_action="answer", missing_slots=[])
    malformed = "${item:real-1:price}"
    value = malformed if field == "answer" else [malformed]
    answer = equipment_answer(mode="no_matches", selected_items=[]).model_copy(update={field: value})
    fast, _, _, _ = make_fast(turn(understanding=decision, knowledge_ids=[], response_mode="equipment"), answer)
    with pytest.raises(ValidationError, match="Malformed catalog text reference"):
        await fast.execute(ChatRequestDTO(message="เลือกตามความต้องการ"))


@pytest.mark.asyncio
async def test_reply_catalog_tokens_render_and_cite_evidence_without_cards():
    decision = understanding(catalog_operation="selection", information_sufficient=True,
                             next_action="answer", missing_slots=[])
    answer = equipment_answer(mode="no_matches", selected_items=[]).model_copy(update={
        "answer": "ไม่มีรายการที่ตรงงาน", "suggested_replies": ["ดู {{item:real-1:name}} ที่ราคา {{item:real-1:price}}"]})
    fast, _, _, _ = make_fast(turn(understanding=decision, knowledge_ids=[], response_mode="equipment"), answer)
    result = await fast.execute(ChatRequestDTO(message="เลือกตามความต้องการ"))
    assert result.suggested_replies == ["ดู คลังจริง ที่ราคา 100.0"]
    assert [(r.kind, r.id) for r in result.references] == [("catalog", ITEM.id)]


@pytest.mark.asyncio
async def test_absent_user_budget_is_null_in_native_evidence_contract():
    decision = understanding(catalog_operation="inspection", information_sufficient=True,
                             next_action="answer", missing_slots=[], target_items=[ITEM.name])
    fast, llm, _, _ = make_fast(turn(understanding=decision, knowledge_ids=[], response_mode="equipment"),
                               equipment_answer(purpose="inspection"))
    await fast.execute(ChatRequestDTO(message="รายละเอียดรายการ"))
    contract = native_schema(llm.generate_structured.call_args_list[1].kwargs["schema"])
    assert contract["$defs"]["ResolvedSelectionPlan"]["properties"]["price_requirement"] == {"type": "null"}


@pytest.mark.asyncio
@pytest.mark.parametrize("mode,fit", [
    ("no_matches", "meets_request"), ("items", "no_supported_match"),
    ("categories", "meets_request"), ("items", "not_assessed"),
])
async def test_request_fit_cannot_contradict_generated_selection_outcome(mode, fit):
    decision = understanding(catalog_operation="selection", information_sufficient=True,
                             next_action="answer", missing_slots=[])
    answer = equipment_answer(mode=mode, selected_items=[] if mode != "items" else [
        {"id": ITEM.id, "reason": "ตรงข้อกำหนด", "evidence_fields": ["description"]}]).model_copy(
            update={"request_fit": fit})
    fast, _, _, _ = make_fast(turn(understanding=decision, knowledge_ids=[], response_mode="equipment"), answer)
    with pytest.raises(ValidationError, match="Request fit disagrees with selection outcome"):
        await fast.execute(ChatRequestDTO(message="เลือกให้ตรงงาน"))


@pytest.mark.asyncio
async def test_selected_item_prose_cannot_omit_authoritative_model_reference():
    decision = understanding(catalog_operation="inspection", information_sufficient=True,
                             next_action="answer", missing_slots=[], target_items=[ITEM.name])
    answer = equipment_answer(purpose="inspection").model_copy(update={"answer": "ชื่อรุ่นที่โมเดลเขียนเอง"})
    fast, _, _, _ = make_fast(turn(understanding=decision, knowledge_ids=[], response_mode="equipment"), answer)
    with pytest.raises(ValidationError, match="authoritative name reference"):
        await fast.execute(ChatRequestDTO(message="ข้อมูลรุ่นนี้"))


@pytest.mark.asyncio
@pytest.mark.parametrize("changes,field", [({"selection": None}, "selection"), ({"search_ids": ["invented"]}, "search_ids")])
async def test_evidence_contract_rejects_missing_selection_or_unsupplied_web(changes, field):
    decision = understanding(catalog_operation="inspection", information_sufficient=True,
                             next_action="answer", missing_slots=[], target_items=[ITEM.name])
    answer = equipment_answer(purpose="inspection").model_copy(update=changes)
    fast, _, _, _ = make_fast(turn(understanding=decision, knowledge_ids=[], response_mode="equipment"), answer)
    with pytest.raises(ValidationError, match=field):
        await fast.execute(ChatRequestDTO(message="ข้อมูลรุ่นนี้"))


@pytest.mark.asyncio
async def test_validation_diagnostics_omit_provider_values_and_unknown_keys():
    secret = "private-user-value"
    def respond(request):
        return httpx.Response(200, json={"choices": [{"message": {"content": json.dumps({"value": [], secret: secret})}}]})
    service, http = stack(respond)
    try:
        with pytest.raises(Exception):
            await service.generate_structured("fixture", SmallResult)
        diagnostics = [t["validation_errors"] for t in service.telemetry if "validation_errors" in t]
        assert diagnostics
        assert secret not in json.dumps(list(service.telemetry))
        assert "unknown_field" in json.dumps(diagnostics)
    finally:
        await http.aclose()


def test_native_single_value_contract_preserves_value_and_description():
    class FixedContract(BaseModel):
        purpose: Literal["recommendation"] = Field(description="Semantic purpose fixed by the resolved operation.", json_schema_extra={"x-provider-description": True})
    field = native_schema(FixedContract)["properties"]["purpose"]
    assert field["enum"] == ["recommendation"]
    assert "description" in field
    assert "x-provider-description" not in field
    with pytest.raises(ValidationError):
        FixedContract(purpose="inspection")


@pytest.mark.asyncio
async def test_evidence_advertises_and_constrains_established_budget():
    decision = understanding(catalog_operation="selection", information_sufficient=True, next_action="answer",
        missing_slots=[], budget_max=100, budget_unit=ITEM.type)
    answer = equipment_answer(price_requirement={"maximum": 100, "user_unit": ITEM.type,
        "catalog_units": [ITEM.type], "interpretation": "same established billing unit"})
    fast, llm, _, _ = make_fast(turn(understanding=decision, knowledge_ids=[], response_mode="equipment"), answer)
    await fast.execute(ChatRequestDTO(message="เลือกตามข้อกำหนดที่ให้ไว้"))
    call = llm.generate_structured.call_args_list[1].kwargs
    payload = json.loads(call["prompt"])
    assert payload["allowed_selection_purposes"] == ["recommendation"]
    assert payload["price_contract"]["permitted_catalog_periods"] == [ITEM.type]
    invalid = answer.model_dump()
    invalid["selection"]["price_requirement"]["catalog_units"] = ["unsupported-period"]
    with pytest.raises(ValidationError):
        call["schema"].model_validate(invalid)


@pytest.mark.asyncio
async def test_filtered_evidence_exposes_actual_stock_scope():
    decision = understanding(catalog_operation="selection", information_sufficient=True, next_action="answer",
        missing_slots=[], categories=[ITEM.category], budget_max=100, budget_unit=ITEM.type)
    answer = equipment_answer(price_requirement={"maximum": 100, "user_unit": ITEM.type,
        "catalog_units": [ITEM.type], "interpretation": "same established billing unit"})
    fast, llm, repo, _ = make_fast(turn(understanding=decision, knowledge_ids=[], response_mode="equipment"), answer)
    repo.get_all_items.return_value = [ITEM,
        ITEM.model_copy(update={"id": "over-budget", "name": "Excluded by budget", "price": 200}),
        ITEM.model_copy(update={"id": "unavailable", "status": "unavailable"}),
        ITEM.model_copy(update={"id": "other-category", "category": "other"})]
    await fast.execute(ChatRequestDTO(message="เลือกตามเงื่อนไข"))
    payload = json.loads(llm.generate_structured.call_args_list[1].kwargs["prompt"])
    scope = payload["catalog_scope"]
    assert scope["inventory_item_count"] == 4
    assert scope["category_item_count"] == 4
    assert scope["available_category_item_count"] == 3
    assert scope["candidate_item_count"] == 2
    assert scope["full_catalog_included"] is True
    assert scope["price_filter_applied"] is True


@pytest.mark.asyncio
async def test_no_match_explanation_cites_items_even_without_cards():
    decision = understanding(catalog_operation="selection", information_sufficient=True,
                             next_action="answer", missing_slots=[])
    answer = equipment_answer(mode="no_matches", selected_items=[]).model_copy(update={
        "answer": "{{item:real-1:name}} ราคา {{item:real-1:price}} ไม่ตรงความต้องการ"})
    fast, _, _, _ = make_fast(turn(understanding=decision, knowledge_ids=[], response_mode="equipment"), answer)
    result = await fast.execute(ChatRequestDTO(message="เลือกสินค้าที่เหมาะกับงาน"))
    assert not result.items
    assert [(r.kind, r.id) for r in result.references] == [("catalog", ITEM.id)]


@pytest.mark.asyncio
async def test_catalog_warming_overlaps_planning_without_replacing_final_freshness_check():
    import asyncio
    from app.domain.exceptions import GuidanceGenerationError
    from test_fast_turn import QUESTION
    warm = asyncio.Event()
    planning_finished = False
    decision = understanding(missing_slots=[QUESTION.dimension])
    plan = turn(understanding=decision, knowledge_ids=[], questions=[QUESTION],
                message="ขอข้อมูลที่ยังจำเป็น", response_mode="clarification")
    fast, llm, repo, _ = make_fast(plan)

    async def items(refresh=False):
        if refresh and not planning_finished:
            warm.set()
        return [ITEM.model_copy(update={"price": 200})] if planning_finished else [ITEM]

    async def planning(**kwargs):
        nonlocal planning_finished
        await warm.wait()
        planning_finished = True
        return plan

    repo.get_all_items.side_effect = items
    llm.generate_structured.side_effect = planning
    with pytest.raises(GuidanceGenerationError, match="catalog_changed"):
        await asyncio.wait_for(fast.execute(ChatRequestDTO(message="ช่วยเลือกตามงาน")), timeout=.5)


@pytest.mark.asyncio
async def test_clarification_stage_preserves_pending_catalog_operation_without_synthesis():
    from test_fast_turn import QUESTION
    decision = understanding(catalog_operation="selection", missing_slots=[QUESTION.dimension])
    fast, llm, _, _ = make_fast(turn(understanding=decision, knowledge_ids=[], questions=[QUESTION],
        message="ขอข้อมูลที่ยังจำเป็น", response_mode="clarification"))
    result = await fast.execute(ChatRequestDTO(message="ถามความต้องการก่อนเลือกสินค้า"))
    assert result.questions and not result.items and result.next_action == "clarify"
    assert llm.generate_structured.await_count == 1
    schema = native_schema(llm.generate_structured.call_args.kwargs["schema"])
    fields = list(schema["properties"])
    assert fields.index("stage") < fields.index("analysis")
    assert schema['$defs']['ClarificationStage']['properties']['response_mode']['enum'] == ['clarification']
    assert schema['$defs']['EvidenceStage']['properties']['text']['enum'] == ['']


@pytest.mark.asyncio
async def test_clarification_stage_cannot_be_used_without_a_question():
    fast, _, _, _ = make_fast(turn(knowledge_ids=[], response_mode="clarification", message="ข้อความ"))
    with pytest.raises(ValidationError):
        await fast.execute(ChatRequestDTO(message="ตอบข้อมูลที่มีครบแล้ว"))
