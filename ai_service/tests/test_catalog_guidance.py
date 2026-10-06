"""Step 4 contracts with synthetic fixtures; semantic accuracy needs live evaluation."""

import json
from dataclasses import replace
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import httpx
import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.application.dtos.chat_dto import ChatRequestDTO
from app.application.services.catalog_guidance import catalog_snapshot
from app.application.services.conversation_context import ContextLimits
from app.application.use_cases.generate_clarification_use_case import GenerateClarificationUseCase
from app.application.use_cases.process_chat_message_use_case import ProcessChatMessageUseCase
from app.application.use_cases.query_items_use_case import QueryItemsUseCase
from app.core.config import Settings
from app.core.exceptions import AllLLMProvidersExhaustedException
from app.domain.entities.catalog_guidance import (
    CatalogSelection, GuidancePolicy, GuidanceReview, QuestionnairePlan, SelectionPlan,
)
from app.domain.entities.intent_decision import KnownFact
from app.domain.entities.item import Item
from app.domain.exceptions import GuidanceGenerationError
from app.infrastructure.llm.cascade_llm_service import CascadeLLMService
from app.infrastructure.llm.gemini_client import GeminiClient
from app.infrastructure.llm.groq_client import GroqClient
from app.infrastructure.supabase.supabase_repository import SupabaseRepository
from app.core.exceptions import DatabaseException
from app.interface.api.v1.endpoints import chat
from tests.test_request_understanding import understanding

POLICY = GuidancePolicy(3, 4, 80, 80, 3, 2, 0.1)


def repository():
    return MagicMock(get_all_items=AsyncMock(return_value=[
        Item(id="camera", name="กล้องแบรนด์ A", category="ภาพ", price=500, type="วัน", description="กล้องน้ำหนักเบา"),
        Item(id="light", name="ไฟแบรนด์ B", category="ภาพ", price=100, type="วัน", description="แสงต่อเนื่อง"),
        Item(id="hourly", name="กล้องแบรนด์ C", category="ภาพ", price=50, type="ชั่วโมง"),
        Item(id="unavailable", name="กล้องแบรนด์ D", category="ภาพ", price=200, status="rented"),
        Item(id="free", name="ขาตั้งแบรนด์ E", category="ขาตั้ง", price=0),
    ]))


def question_plan(dimensions=("budget",)):
    return QuestionnairePlan(introduction="ขอข้อมูลที่จำเป็นเพิ่มค่ะ", questions=[{
        "id": f"q-{index}", "dimension": dimension, "title": "กำหนดรายละเอียดที่ต้องการค่ะ",
        "choices": [{"id": "choice-a", "label": "ตามเงื่อนไขที่ระบุ", "value": "ตามเงื่อนไข",
                     "supporting_item_ids": []}],
    } for index, dimension in enumerate(dimensions)])


def selection_plan(ids=("camera",), *, budget=None, units=("วัน",), purpose="recommendation", mode=None):
    return SelectionPlan(mode=mode or ("items" if ids else "no_matches"), purpose=purpose,
        selected_items=[{"id": item_id, "reason": "ตรงข้อกำหนดใน fixture", "evidence_fields": ["description"]} for item_id in ids],
        price_requirement={"maximum": budget, "user_unit": "วัน", "catalog_units": list(units), "interpretation": "fixture ระบุหน่วยนี้"} if budget is not None else None,
        reasoning="เหตุผลจาก fixture")


def reviewed_llm(candidate, approved=True, issues=None):
    review = GuidanceReview(approved=approved, issues=issues or [], reasoning="ตรวจ fixture")
    async def generate(**kwargs):
        return review if kwargs["schema"] is GuidanceReview else candidate
    return MagicMock(generate_structured=AsyncMock(side_effect=generate))


@pytest.mark.asyncio
@pytest.mark.parametrize("count", [1, 2, 3])
async def test_only_requested_unknown_dimensions_are_asked_together(count):
    dims = [f"missing-{index}" for index in range(count)]
    plan = question_plan(dims)
    llm = reviewed_llm(plan)
    known = KnownFact(dimension="usage", value="ถ่ายภาพกลางแจ้ง", source_message_ids=["current"])
    decision = understanding(known_facts=[known], intended_use=known.value, missing_slots=dims)
    result = await GenerateClarificationUseCase(llm, repository(), POLICY).execute("ความต้องการนี้", decision)
    assert len(result.questions) == count
    assert [question.dimension for question in result.questions] == dims
    assert all(question.total_steps == count and not question.branch_options for question in result.questions)
    assert result.questions[0].choices[0].id == "choice-a"
    assert result.options[0].action_value == "ตามเงื่อนไข"
    payload = json.loads(llm.generate_structured.call_args_list[0].kwargs["prompt"])
    assert payload["understanding"]["intended_use"] == "ถ่ายภาพกลางแจ้ง"
    assert {item["id"] for item in payload["catalog"]["items"]} == {"camera", "light", "hourly", "unavailable", "free"}


@pytest.mark.asyncio
@pytest.mark.parametrize("fault", ["known_dimension", "not_missing", "too_many_questions", "too_many_choices", "unknown_id", "duplicate_question", "duplicate_choice", "duplicate_label", "long_title", "no_questions", "no_choices"])
async def test_invalid_questionnaires_never_receive_canned_questions(fault):
    plan = question_plan().model_dump()
    question = plan["questions"][0]
    decision = understanding(missing_slots=["budget", "usage", "missing-2", "missing-3"])
    if fault == "known_dimension":
        decision.known_facts = [KnownFact(dimension="budget", value="500", source_message_ids=["current"])]
    elif fault == "not_missing":
        question["dimension"] = "unrequested"
    elif fault == "too_many_questions":
        plan = question_plan(["budget", "usage", "missing-2", "missing-3"]).model_dump()
    elif fault == "too_many_choices":
        question["choices"] = [dict(question["choices"][0], id=str(index), label=str(index)) for index in range(5)]
    elif fault == "unknown_id":
        question["choices"][0]["supporting_item_ids"] = ["invented"]
    elif fault == "duplicate_question":
        plan["questions"].append(question.copy())
    elif fault == "duplicate_choice":
        question["choices"].append(dict(question["choices"][0], label="อีกช้อย"))
    elif fault == "duplicate_label":
        question["choices"].append(dict(question["choices"][0], id="another"))
    elif fault == "long_title":
        question["title"] = "x" * 81
    elif fault == "no_questions":
        plan["questions"] = []
    elif fault == "no_choices":
        question["choices"] = []
    llm = reviewed_llm(QuestionnairePlan.model_validate(plan))
    with pytest.raises(GuidanceGenerationError, match="generation_rejected"):
        await GenerateClarificationUseCase(llm, repository(), POLICY).execute("ข้อความ", decision)
    assert llm.generate_structured.await_count == POLICY.generation_attempts


@pytest.mark.asyncio
async def test_equivalent_known_fact_rejected_by_semantic_review_then_regenerated():
    known = KnownFact(dimension="budget_per_day", value="500", source_message_ids=["current"])
    wrong = question_plan(["budget"])
    correct = question_plan(["reference"])
    llm = MagicMock(generate_structured=AsyncMock(side_effect=[
        wrong, GuidanceReview(approved=False, issues=["Already known budget asked under another dimension"], reasoning="ซ้ำ"),
        correct, GuidanceReview(approved=True, issues=[], reasoning="ไม่ซ้ำ"),
    ]))
    result = await GenerateClarificationUseCase(llm, repository(), POLICY).execute("คำขอ", understanding(
        known_facts=[known], budget_max=500, missing_slots=["budget", "reference"]))
    assert [question.dimension for question in result.questions] == ["reference"]
    retry = json.loads(llm.generate_structured.call_args_list[2].kwargs["prompt"])
    assert retry["previous_validation_issues"] == ["Already known budget asked under another dimension"]


@pytest.mark.asyncio
async def test_declined_questionnaire_is_not_generated_or_fetched():
    llm, repo = MagicMock(), repository()
    with pytest.raises(ValueError, match="declined"):
        await GenerateClarificationUseCase(llm, repo, POLICY).execute("ข้าม", understanding(
            clarification_declined=True, next_action="answer"))
    repo.get_all_items.assert_not_awaited()
    llm.generate_structured.assert_not_called()


@pytest.mark.asyncio
@pytest.mark.parametrize("ids", [("camera",), ("camera", "light"), ()])
async def test_no_backfill_and_no_keyword_filter_overrides_semantic_ids(ids):
    llm = reviewed_llm(selection_plan(ids))
    query = QueryItemsUseCase(repository(), llm, POLICY)
    decision = understanding(target_items=["คำที่ไม่อยู่ในชื่อสินค้า"], next_action="answer")
    result = await query.execute(decision)
    assert [item.id for item in result] == list(ids)
    payload = json.loads(llm.generate_structured.call_args_list[0].kwargs["prompt"])
    assert payload["understanding"]["target_items"] == ["คำที่ไม่อยู่ในชื่อสินค้า"]


@pytest.mark.asyncio
@pytest.mark.parametrize("plan,budget", [
    (selection_plan(["invented"]), None),
    (selection_plan(["camera", "camera"]), None),
    (selection_plan(["camera", "light", "hourly", "free"]), None),
    (selection_plan(["unavailable"]), None),
    (selection_plan(["camera"], budget=499), 499),
    (selection_plan(["hourly"], budget=500), 500),
    (selection_plan(["camera"]), 500),
    (selection_plan(["camera"], budget=600), 500),
    (selection_plan(["camera"], budget=500, units=["invented"]), 500),
    (selection_plan(["camera"], budget=0), 0),
    (selection_plan([], mode="items"), None),
    (selection_plan(["camera"], mode="categories"), None),
    (selection_plan([], mode="categories"), None),
])
async def test_invalid_selection_ids_price_units_availability_and_modes_fail_closed(plan, budget):
    llm = reviewed_llm(plan)
    with pytest.raises(GuidanceGenerationError, match="generation_rejected"):
        await QueryItemsUseCase(repository(), llm, POLICY).execute(understanding(budget_max=budget))
    assert llm.generate_structured.await_count == POLICY.generation_attempts


@pytest.mark.asyncio
async def test_zero_budget_accepts_actual_free_item_and_inspection_can_show_unavailable():
    result = await QueryItemsUseCase(repository(), reviewed_llm(selection_plan(["free"], budget=0)), POLICY).execute(
        understanding(budget_max=0))
    assert result[0].price == 0
    result = await QueryItemsUseCase(repository(), reviewed_llm(selection_plan(["unavailable"], purpose="inspection")), POLICY).execute(
        understanding(intent="item_inquiry"))
    assert result[0].status == "rented"


@pytest.mark.asyncio
async def test_category_browse_after_skip_uses_real_categories_without_item_cards():
    decision = understanding(clarification_declined=True, next_action="answer", categories=[])
    query = QueryItemsUseCase(repository(), reviewed_llm(selection_plan([], mode="categories")), POLICY)
    result = await query.execute_selection(decision)
    assert result.items == []
    assert result.available_categories == ["ภาพ", "ขาตั้ง"]
    assert result.mode == "categories"


@pytest.mark.asyncio
async def test_corrections_negations_brand_preferences_and_all_constraints_reach_both_models():
    decision = understanding(budget_max=500, excluded_items=["แบรนด์ B"], user_constraints=[
        KnownFact(dimension="weight", value="ไม่เกิน 1 กก.", source_message_ids=["current"]),
        KnownFact(dimension="brand", value="แบรนด์ A ตามความชอบผู้ใช้", source_message_ids=["current"]),
    ])
    llm = reviewed_llm(selection_plan(["camera"], budget=500))
    await QueryItemsUseCase(repository(), llm, POLICY).execute(decision)
    for call in llm.generate_structured.call_args_list:
        payload = json.loads(call.kwargs["prompt"])
        assert payload["understanding"]["excluded_items"] == ["แบรนด์ B"]
        assert len(payload["understanding"]["user_constraints"]) == 2


@pytest.mark.asyncio
async def test_empty_catalog_and_duplicate_ids_never_trigger_fabricated_items():
    repo = MagicMock(get_all_items=AsyncMock(return_value=[]))
    llm = MagicMock()
    result = await QueryItemsUseCase(repo, llm, POLICY).execute(understanding())
    assert result == []
    llm.generate_structured.assert_not_called()
    items = repository().get_all_items.return_value
    with pytest.raises(GuidanceGenerationError, match="invalid_catalog_ids"):
        catalog_snapshot([items[0], items[0]])


@pytest.mark.asyncio
async def test_semantic_review_rejects_unsuitable_or_unsupported_recommendation():
    llm = reviewed_llm(selection_plan(["light"]), approved=False, issues=["Requested kind and mandatory specification unsupported"])
    with pytest.raises(GuidanceGenerationError):
        await QueryItemsUseCase(repository(), llm, POLICY).execute(understanding(target_items=["กล้อง"] ))
    assert llm.generate_structured.await_count == 2 * POLICY.generation_attempts


@pytest.mark.asyncio
async def test_provider_exhaustion_propagates_without_any_deterministic_selection():
    llm = MagicMock(generate_structured=AsyncMock(side_effect=AllLLMProvidersExhaustedException()))
    with pytest.raises(AllLLMProvidersExhaustedException):
        await QueryItemsUseCase(repository(), llm, POLICY).execute(understanding())
    assert llm.generate_structured.await_count == 1


@pytest.mark.asyncio
async def test_same_semantic_decision_survives_catalog_order_and_brand_changes():
    repo = repository()
    llm = reviewed_llm(selection_plan(["camera", "light"]))
    query = QueryItemsUseCase(repo, llm, POLICY)
    first = await query.execute(understanding())
    repo.get_all_items.return_value = [item.model_copy(update={"name": f"ชื่อสลับ {index}"})
                                      for index, item in enumerate(reversed(repo.get_all_items.return_value))]
    second = await query.execute(understanding())
    assert [item.id for item in first] == [item.id for item in second] == ["camera", "light"]


@pytest.mark.asyncio
async def test_runtime_validator_inside_real_adapter_triggers_backup_provider(monkeypatch):
    requests = []
    good = selection_plan(["camera"])
    bad = selection_plan(["invented"])
    review = GuidanceReview(approved=True, issues=[], reasoning="fixture independent review")
    def respond(request):
        payload = json.loads(request.content)
        requests.append(payload)
        if "contents" in payload:
            schema = payload["generationConfig"]["responseJsonSchema"]
            text = review.model_dump_json() if "approved" in schema["properties"] else bad.model_dump_json()
            return httpx.Response(200, json={"candidates": [{"content": {"parts": [{"text": text}]}}], "usageMetadata": {"totalTokenCount": 100}})
        schema = payload["response_format"]["json_schema"]["schema"]
        text = review.model_dump_json() if "approved" in schema["properties"] else good.model_dump_json()
        return httpx.Response(200, json={"choices": [{"message": {"content": text}}], "usage": {"total_tokens": 100}})
    original = httpx.AsyncClient
    monkeypatch.setattr(httpx, "AsyncClient", lambda *args, **kwargs: original(transport=httpx.MockTransport(respond), **kwargs))
    config = Settings(_env_file=None, GROQ_PRIMARY_MODEL="fixture")
    cascade = CascadeLLMService(GeminiClient(api_key="fixture", configuration=config),
                               GroqClient(api_key="fixture", configuration=config), configuration=config)
    monkeypatch.setattr(cascade, "_get_cascade_tiers", lambda: [("gemini", "fixture"), ("groq", "fixture")])
    result = await QueryItemsUseCase(repository(), cascade, POLICY).execute(understanding())
    assert result[0].id == "camera"
    assert len(requests) == 3
    assert requests[0]["generationConfig"]["maxOutputTokens"] == Settings().STRUCTURED_MAX_OUTPUT_TOKENS
    assert requests[1]["max_completion_tokens"] == Settings().STRUCTURED_MAX_OUTPUT_TOKENS
    await cascade.aclose()




@pytest.mark.asyncio
@pytest.mark.parametrize("error", [GuidanceGenerationError("generation_rejected"), AllLLMProvidersExhaustedException(), DatabaseException("private fixture error")])
async def test_guidance_errors_have_safe_json_and_sse_contracts(monkeypatch, error):
    async def fail_stream(request):
        raise error
        yield "unreachable"
    monkeypatch.setattr(chat.container, "process_chat_message_use_case", SimpleNamespace(
        execute=AsyncMock(side_effect=error), execute_stream=fail_stream))
    monkeypatch.setattr(chat.settings, "INTERNAL_SERVICE_KEY", "")
    with pytest.raises(HTTPException) as failure:
        await chat.chat_endpoint(ChatRequestDTO(message="ข้อความ"))
    assert failure.value.status_code == 503
    assert set(failure.value.detail) == {"error_code"}
    response = await chat.chat_stream_endpoint(ChatRequestDTO(message="ข้อความ"))
    body = b"".join([part async for part in response.body_iterator]).decode()
    data = json.loads(body.split("data: ")[1].strip())
    assert set(data) == {"error_code"}


@pytest.mark.parametrize("value", [-1, float("nan"), float("inf")])
def test_invalid_numeric_catalog_price_is_rejected(value):
    with pytest.raises(ValidationError):
        Item(id="bad", name="bad", category="bad", price=value)


def test_policy_limits_and_model_parameters_are_configurable():
    with pytest.raises(ValidationError):
        Settings(_env_file=None, GUIDANCE_MAX_QUESTIONS=4)
    with pytest.raises(ValidationError):
        Settings(_env_file=None, GUIDANCE_MAX_OPTIONS=5)
    smaller = replace(POLICY, max_questions=1, max_options=2, generation_attempts=1)
    assert smaller.max_questions == 1 and smaller.generation_attempts == 1


@pytest.mark.asyncio
@pytest.mark.parametrize("change", ["price", "status", "description", "missing"])
async def test_changed_catalog_after_model_review_cannot_return_stale_cards(change):
    repo = repository()
    original = repo.get_all_items.return_value
    fresh = list(original)
    if change == "missing":
        fresh = fresh[1:]
    else:
        updates = {"price": 501} if change == "price" else ({"status": "rented"} if change == "status" else {"description": "เปลี่ยนข้อมูล"})
        fresh[0] = fresh[0].model_copy(update=updates)
    repo.get_all_items.side_effect = [original, fresh]
    query = QueryItemsUseCase(repo, reviewed_llm(selection_plan(["camera"])), POLICY)
    with pytest.raises(GuidanceGenerationError, match="catalog_changed"):
        await query.execute(understanding())
    assert repo.get_all_items.call_args_list[1].kwargs == {"refresh": True}


@pytest.mark.parametrize("missing", ["price", "type"])
def test_supabase_mapping_does_not_invent_free_price_or_daily_unit(missing):
    row = {"id": "fixture", "item_name": "fixture", "category": "fixture", "price": 0, "type": "hourly"}
    row.pop(missing)
    with pytest.raises(DatabaseException):
        SupabaseRepository(api_key="fixture", base_url="https://fixture.invalid")._map_row_to_item(row)


def test_missing_catalog_status_does_not_mean_available_and_genuine_zero_is_preserved():
    row = {"id": "fixture", "item_name": "fixture", "category": "fixture", "price": 0, "type": "hourly"}
    item = SupabaseRepository(api_key="fixture", base_url="https://fixture.invalid")._map_row_to_item(row)
    assert item.price == 0 and item.type == "hourly"
    assert item.status == "unknown" and not item.is_available


@pytest.mark.parametrize("price", [-1, float("nan"), float("inf"), True])
def test_malformed_source_price_is_a_safe_catalog_error(price):
    row = {"id": "fixture", "item_name": "fixture", "category": "fixture", "price": price, "type": "hourly"}
    with pytest.raises(DatabaseException, match="Catalog price is invalid"):
        SupabaseRepository(api_key="fixture", base_url="https://fixture.invalid")._map_row_to_item(row)


@pytest.mark.asyncio
async def test_refresh_bypasses_catalog_cache(monkeypatch):
    cached = Item(id="cached", name="cached", category="cached", price=99)
    cache = MagicMock(get=AsyncMock(return_value=[cached]), set=AsyncMock())
    repo = SupabaseRepository(api_key="fixture", base_url="https://fixture.invalid", cache_service=cache)
    requests = []
    def respond(request):
        requests.append(request)
        return httpx.Response(200, json=[{"id": "fresh", "item_name": "fresh", "category": "fresh",
                                        "price": 10, "type": "hourly", "status": "available"}])
    original = httpx.AsyncClient
    monkeypatch.setattr(httpx, "AsyncClient", lambda *args, **kwargs: original(transport=httpx.MockTransport(respond), **kwargs))
    assert (await repo.get_all_items())[0].id == "cached"
    assert (await repo.get_all_items(refresh=True))[0].id == "fresh"
    assert len(requests) == 1


@pytest.mark.asyncio
@pytest.mark.parametrize("budget_unit", [None, "ชั่วโมง"])
async def test_budget_period_cannot_be_guessed_or_replaced(budget_unit):
    query = QueryItemsUseCase(repository(), reviewed_llm(selection_plan(["camera"], budget=500)), POLICY)
    with pytest.raises(GuidanceGenerationError):
        await query.execute(understanding(budget_max=500, budget_unit=budget_unit))


@pytest.mark.asyncio
async def test_unknown_budget_period_can_return_limits_without_items():
    decision = understanding(budget_max=500, budget_unit=None, clarification_declined=True, next_action="answer")
    result = await QueryItemsUseCase(repository(), reviewed_llm(selection_plan([])), POLICY).execute_selection(decision)
    assert result.mode == "no_matches" and result.items == []


@pytest.mark.asyncio
@pytest.mark.parametrize("mode", ["categories", "no_matches"])
async def test_changed_catalog_cannot_support_old_category_or_absence_claim(mode):
    repo = repository()
    first = repo.get_all_items.return_value
    repo.get_all_items.side_effect = [first, [*first, Item(id="new", name="new", category="หมวดใหม่", price=1)]]
    query = QueryItemsUseCase(repo, reviewed_llm(selection_plan([], mode=mode)), POLICY)
    with pytest.raises(GuidanceGenerationError, match="catalog_changed"):
        await query.execute_selection(understanding(clarification_declined=True, next_action="answer"))
