"""Transport and evidence contracts with fixtures, not a semantic accuracy evaluation."""
import asyncio
import json
from dataclasses import replace
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock

import httpx
import pytest
from fastapi import FastAPI
from pydantic import ValidationError

from app.application.dtos.chat_dto import ChatRequestDTO
from app.application.services.conversation_context import ContextLimits
from app.application.use_cases.process_chat_message_use_case import ProcessChatMessageUseCase
from app.application.use_cases.query_items_use_case import QueryItemsUseCase
from app.application.use_cases.route_intent_use_case import RouteIntentUseCase
from app.domain.entities.catalog_guidance import CatalogSelection, GuidancePolicy, GuidanceReview
from app.domain.entities.chat_result import AnswerPlan, QuestionnaireAnswer, SessionContext
from app.domain.entities.clarification import ClarificationQuestion, ChoiceOption, QuestionStep
from app.domain.entities.intent_decision import KnownFact
from app.domain.entities.item import Item
from app.domain.entities.search_source import SearchSource
from app.domain.exceptions import GuidanceGenerationError
from app.infrastructure.knowledge.file_knowledge_repository import FileKnowledgeRepository
from test_request_understanding import understanding

POLICY = GuidancePolicy(3, 4, 80, 80, 3, 2, 0.1)
LIMITS = ContextLimits(16, 24000)
KNOWLEDGE_PATH = Path(__file__).resolve().parents[1] / "knowledge/app_knowledge.json"
QUESTION = QuestionStep(id="batch:q1", title="ใช้ที่ไหน", dimension="location", options=["ในอาคาร", "กลางแจ้ง"],
    choices=[ChoiceOption(id="indoor", label="ในอาคาร", action_value="indoor"),
             ChoiceOption(id="outdoor", label="กลางแจ้ง", action_value="outdoor")])


def context(**changes):
    return SessionContext(session_id="current-chat", user_goal="เลือกอุปกรณ์", questions=[QUESTION], **changes)


def make_process(decision=None, selection=None, plan=None, reviews=None):
    decision = decision or understanding(intent="platform_faq", next_action="answer", information_sufficient=True, missing_slots=[])
    selection = selection or CatalogSelection([], "no_matches", [], "fixture", [])
    route = MagicMock(execute=AsyncMock(return_value=decision))
    query = MagicMock(execute_selection=AsyncMock(return_value=selection), refresh_selection=AsyncMock(return_value=selection))
    clarify = MagicMock(execute=AsyncMock(return_value=ClarificationQuestion(question="ใช้ที่ไหน", questions=[QUESTION])))
    payloads = []
    reviews = iter(reviews or [True] * POLICY.generation_attempts)

    async def generate(**kwargs):
        payload = json.loads(kwargs["prompt"])
        payloads.append(payload)
        if kwargs["schema"] is GuidanceReview:
            approved = next(reviews)
            return GuidanceReview(approved=approved, issues=[] if approved else ["unsupported_policy"], reasoning="fixture review")
        return plan or AnswerPlan(answer="คำตอบจากหลักฐานที่มี", item_ids=[i.id for i in selection.items],
            knowledge_ids=[], search_ids=[], suggested_replies=[])

    llm = MagicMock(generate_structured=AsyncMock(side_effect=generate))
    search = MagicMock(search=AsyncMock(return_value=[]))
    process = ProcessChatMessageUseCase(route, query, clarify, llm, search, LIMITS,
        FileKnowledgeRepository(KNOWLEDGE_PATH), POLICY, .01, 5)
    return process, route, query, clarify, search, payloads


def decode_events(events):
    return [(event.splitlines()[0].split(": ")[1], json.loads(event.splitlines()[1][6:]))
            for event in events if event.startswith("event:")]


@pytest.mark.asyncio
@pytest.mark.parametrize("intent", ["platform_faq", "bot_capabilities", "general_greeting", "inventory_search", "comparison", "item_inquiry"])
async def test_one_structured_result_projects_to_json_and_sse(intent):
    decision = understanding(intent=intent, next_action="answer", information_sufficient=True, missing_slots=[])
    process, route, query, _, _, _ = make_process(decision)
    request = ChatRequestDTO(message="คำถาม", session_id="current-chat")
    response = await process.execute(request)
    events = decode_events([e async for e in process.execute_stream(request)])
    done = next(data for event, data in events if event == "done")
    metadata = next(data for event, data in events if event == "metadata")
    assert done["answer"] == response.response == "".join(d["text"] for e, d in events if e == "delta")
    assert done["recommended_items"] == metadata["recommended_items"] == response.model_dump()["items"]
    for key in ("request_scope", "information_sufficient", "next_action", "response_flow"):
        assert metadata[key] == done[key]
    for key, value in response.model_dump(mode="json").items():
        assert done[key] == value


@pytest.mark.asyncio
async def test_cards_follow_ids_even_without_names_in_answer():
    item = Item(id="actual-17", name="ชื่อคลังจริง", category="ภาพ", price=17, type="hourly", status="available")
    selection = CatalogSelection([item], "items", [], "ตรวจรายการ", [])
    plan = AnswerPlan(answer="รายละเอียดอยู่ในการ์ด", item_ids=[item.id], knowledge_ids=[], search_ids=[], suggested_replies=[])
    process, _, _, _, _, _ = make_process(understanding(next_action="answer", information_sufficient=True, missing_slots=[]), selection, plan)
    response = await process.execute(ChatRequestDTO(message="ดูรายละเอียด"))
    assert [i.id for i in response.items] == [item.id]
    assert response.items[0].price == 17 and response.items[0].type == "hourly"


@pytest.mark.asyncio
async def test_mixed_faq_primary_intent_still_queries_requested_catalog():
    item = Item(id="mixed", name="ชื่อจริง", category="ภาพ", price=17, type="daily")
    selection = CatalogSelection([item], "items", [], "fixture", [])
    process, _, query, _, _, _ = make_process(understanding(intent="platform_faq", catalog_operation="inspection",
        next_action="answer", information_sufficient=True, missing_slots=[], additional_goals=["ดูอุปกรณ์"]), selection)
    response = await process.execute(ChatRequestDTO(message="เรื่องแอปและรายการอุปกรณ์"))
    assert response.items[0].id == "mixed"
    query.execute_selection.assert_awaited_once()


@pytest.mark.asyncio
async def test_user_budget_survives_compact_context_without_history():
    process, *_ = make_process(understanding(next_action="answer", information_sufficient=True, missing_slots=[],
        budget_max=0, budget_unit="ชั่วโมง", intended_use="งานที่ระบุ"))
    response = await process.execute(ChatRequestDTO(message="ข้อกำหนด"))
    assert response.context.budget_max == 0
    assert response.context.budget_unit == "ชั่วโมง"
    assert response.context.intended_use == "งานที่ระบุ"


@pytest.mark.asyncio
async def test_mixed_app_answer_and_questionnaire_has_sources_and_no_cards():
    decision = understanding(intent="inventory_search", ambiguity_level=0, additional_goals=["วิธีเช่าในแอป"], missing_slots=["location"])
    plan = AnswerPlan(answer="ส่งคำขอผ่านแชตกับเจ้าของ แล้วระบุสถานที่ใช้งาน", item_ids=[],
                      knowledge_ids=["rental.request_in_chat"], search_ids=[], suggested_replies=[])
    process, _, query, _, _, payloads = make_process(decision, plan=plan)
    response = await process.execute(ChatRequestDTO(message="เช่ายังไงและช่วยเลือกให้ด้วย"))
    assert response.questions and response.clarification and not response.items
    assert response.context.questions == response.questions
    assert response.references[0].id == "rental.request_in_chat"
    assert response.references[0].content_sha256
    query.execute_selection.assert_not_awaited()
    assert len(payloads[0]["approved_knowledge"]) == 12
    assert not any(a["id"] == "policy.deposit" for a in payloads[0]["approved_knowledge"])
    assert payloads[0]["understanding"]["additional_goals"] == ["วิธีเช่าในแอป"]
    article = next(a for a in payloads[0]["approved_knowledge"] if a["id"] == "rental.request_in_chat")
    assert response.response == article["content"] + "\n\n" + response.clarification.question


@pytest.mark.asyncio
async def test_app_facts_are_projected_from_approved_ids_even_if_review_misses_an_invention():
    plan = AnswerPlan(answer="unsupported invented workflow", item_ids=[],
        knowledge_ids=["rental.request_in_chat"], search_ids=[], suggested_replies=[])
    process, _, _, _, _, payloads = make_process(plan=plan)
    response = await process.execute(ChatRequestDTO(message="วิธีส่งคำขอในแอป"))
    article = next(a for a in payloads[0]["approved_knowledge"] if a["id"] == "rental.request_in_chat")
    assert response.response == article["content"]
    assert "unsupported invented workflow" not in response.response
    assert [a["id"] for a in payloads[1]["approved_knowledge"]] == ["rental.request_in_chat"]


@pytest.mark.asyncio
async def test_question_batches_have_distinct_ids_and_preserve_choices():
    process, *_ = make_process(understanding(missing_slots=["location"]))
    first = await process.execute(ChatRequestDTO(message="เลือกอุปกรณ์"))
    second = await process.execute(ChatRequestDTO(message="เลือกอุปกรณ์"))
    assert first.questions[0].id != second.questions[0].id
    assert first.questions[0].choices == QUESTION.choices
    request = ChatRequestDTO(message="คำตอบ", session_id=first.context.session_id, context=first.context,
        questionnaire_answers=[QuestionnaireAnswer(question_id=first.questions[0].id, option_id="outdoor")])
    assert request.questionnaire_answers[0].option_id == "outdoor"


@pytest.mark.parametrize("updates", [
    {"session_id": "another-chat"},
    {"questionnaire_answers": [{"question_id": "unknown", "text": "อะไรก็ได้"}]},
    {"questionnaire_answers": [{"question_id": QUESTION.id, "option_id": "unknown"}]},
    {"questionnaire_answers": [{"question_id": QUESTION.id, "text": "x", "option_id": "outdoor"}]},
    {"questionnaire_answers": [{"question_id": QUESTION.id}]},
    {"questionnaire_answers": [{"question_id": QUESTION.id, "text": "x"}] * 2},
])
def test_invalid_context_and_answers_rejected_before_provider(updates):
    with pytest.raises(ValidationError):
        ChatRequestDTO.model_validate({"message": "คำตอบ", "session_id": "current-chat", "context": context().model_dump(), **updates})


@pytest.mark.parametrize("field", ["price", "stock", "approved_policy"])
def test_context_cannot_carry_authoritative_business_fields(field):
    with pytest.raises(ValidationError):
        SessionContext.model_validate({**context().model_dump(), field: "client-claim"})


@pytest.mark.asyncio
@pytest.mark.parametrize("typed_answer", [QuestionnaireAnswer(question_id=QUESTION.id, option_id="outdoor"),
    QuestionnaireAnswer(question_id=QUESTION.id, text="ริมน้ำที่ลมแรง")])
async def test_router_combines_id_answer_context_and_new_correction(typed_answer):
    fact = KnownFact(dimension="budget", value="900 ต่อวัน", source_message_ids=["current"])
    decision = understanding(next_action="answer", information_sufficient=True, missing_slots=[], budget_max=900,
        known_facts=[fact], user_constraints=[fact], excluded_items=["ของหนัก"])
    llm = MagicMock(generate_structured=AsyncMock(return_value=decision))
    result = await RouteIntentUseCase(llm, LIMITS, .1).execute("แก้งบเป็น 900 ต่อวัน", session_context=context(), questionnaire_answers=[typed_answer])
    payload = json.loads(llm.generate_structured.call_args.kwargs["prompt"])
    assert payload["client_context"]["data"]["questions"][0]["choices"][1]["id"] == "outdoor"
    assert payload["questionnaire_answers"]["data"] == [typed_answer.model_dump()]
    assert result.budget_max == 900 and result.excluded_items == ["ของหนัก"]


@pytest.mark.asyncio
async def test_explicit_skip_cannot_be_overridden_by_router():
    llm = MagicMock(generate_structured=AsyncMock(return_value=understanding()))
    with pytest.raises(ValueError, match="skip"):
        await RouteIntentUseCase(llm, LIMITS, .1).execute("ช่วยต่อ", questionnaire_skipped=True)


@pytest.mark.asyncio
async def test_skip_browses_real_categories_without_questionnaire():
    decision = understanding(intent="clarification_needed", next_action="answer", clarification_declined=True)
    selection = CatalogSelection([], "categories", ["ภาพ", "ขาตั้ง"], "ชนิดยังไม่ทราบ", [])
    process, _, _, clarify, _, payloads = make_process(decision, selection)
    response = await process.execute(ChatRequestDTO(message="ข้าม", questionnaire_skipped=True))
    assert not response.questions and not response.items
    assert payloads[0]["validated_selection"]["available_categories"] == selection.available_categories
    clarify.execute.assert_not_awaited()


@pytest.mark.asyncio
async def test_changed_topic_replaces_returned_user_context():
    old_fact = KnownFact(dimension="budget", value="500", source_message_ids=["context"])
    decision = understanding(intent="platform_faq", topic_changed=True, next_action="answer", information_sufficient=True,
        missing_slots=[], user_goal="ถามข้อมูลแอป", known_facts=[], user_constraints=[], excluded_items=[])
    process, route, *_ = make_process(decision)
    response = await process.execute(ChatRequestDTO(message="เปลี่ยนเรื่อง", session_id="current-chat", context=context(known_facts=[old_fact])))
    assert not response.context.known_facts and response.context.user_goal == "ถามข้อมูลแอป"
    assert route.execute.call_args.kwargs["session_context"].known_facts == [old_fact]


@pytest.mark.asyncio
@pytest.mark.parametrize("bad_field,bad_ids", [("item_ids", ["invented"]), ("knowledge_ids", ["policy.deposit"]),
    ("search_ids", ["invented"]), ("knowledge_ids", ["platform.overview"] * 2)])
async def test_unknown_or_duplicate_source_ids_never_emitted(bad_field, bad_ids):
    plan = AnswerPlan(answer="คำตอบ", item_ids=[], knowledge_ids=[], search_ids=[], suggested_replies=[])
    plan = plan.model_copy(update={bad_field: bad_ids})
    process, *_ = make_process(plan=plan)
    events = []
    with pytest.raises(GuidanceGenerationError):
        async for event in process.execute_stream(ChatRequestDTO(message="คำถาม")):
            events.append(event)
    assert not any("event: delta" in e or "event: metadata" in e for e in events)


@pytest.mark.asyncio
async def test_semantic_review_rejects_unsupported_policy_without_canned_fallback():
    process, *_ = make_process(reviews=[False, False])
    with pytest.raises(GuidanceGenerationError, match="generation_rejected"):
        await process.execute(ChatRequestDTO(message="ถามนโยบาย"))


@pytest.mark.asyncio
async def test_technical_search_and_sources_shared_by_transports():
    plan = AnswerPlan(answer="ข้อเท็จจริงทางเทคนิค", item_ids=[], knowledge_ids=[], search_ids=["web:0"], suggested_replies=[])
    process, _, _, _, search, _ = make_process(understanding(intent="comparison", next_action="answer", information_sufficient=True,
        missing_slots=[], needs_external_search=True, search_query="technical fixture query"), plan=plan)
    search.search.return_value = [SearchSource(title="เอกสารผู้ผลิต", snippet="ข้อเท็จจริง", url="https://example.test/spec")]
    response = await process.execute(ChatRequestDTO(message="เทียบรุ่น"))
    search.search.assert_awaited_once_with("technical fixture query", max_results=POLICY.max_items)
    assert response.search_sources[0].url == "https://example.test/spec"
    assert response.references[0].id == "web:0"


@pytest.mark.asyncio
async def test_revoked_knowledge_during_synthesis_fails_closed():
    process, *_ = make_process()
    snapshot = await process._knowledge.get_approved_knowledge()
    process._knowledge = MagicMock(get_approved_knowledge=AsyncMock(side_effect=[snapshot, replace(snapshot, document_sha256="changed")]))
    with pytest.raises(GuidanceGenerationError, match="knowledge_changed"):
        await process.execute(ChatRequestDTO(message="ข้อมูลแอป"))


@pytest.mark.asyncio
@pytest.mark.parametrize("update", [{"price": 999}, {"status": "rented"}, {"description": "เปลี่ยน"}])
async def test_catalog_change_after_answer_generation_is_rejected(update):
    item = Item(id="real", name="fixture", category="ภาพ", price=100, type="daily")
    selection = CatalogSelection([item], "items", [], "fixture", [])
    repository = MagicMock(get_all_items=AsyncMock(return_value=[item.model_copy(update=update)]))
    query = QueryItemsUseCase(repository, MagicMock(), POLICY)
    with pytest.raises(GuidanceGenerationError, match="catalog_changed"):
        await query.refresh_selection(selection)
    repository.get_all_items.assert_awaited_once_with(refresh=True)


@pytest.mark.asyncio
async def test_stream_heartbeat_and_cancellation_stop_work():
    process, *_ = make_process()
    cancelled = asyncio.Event()
    async def delayed(request):
        try:
            await asyncio.Event().wait()
        finally:
            cancelled.set()
    process.execute = delayed
    stream = process.execute_stream(ChatRequestDTO(message="รอ"))
    assert "event: status" in await anext(stream)
    assert "keep-alive" in await anext(stream)
    await stream.aclose()
    assert cancelled.is_set()


@pytest.mark.asyncio
@pytest.mark.parametrize("stream", [False, True])
async def test_public_api_accepts_legacy_request_and_exposes_new_optional_fields(monkeypatch, stream):
    from app.interface.api.v1.endpoints import chat
    process, *_ = make_process()
    monkeypatch.setattr(chat.container, "process_chat_message_use_case", process)
    monkeypatch.setattr(chat.settings, "INTERNAL_SERVICE_KEY", "")
    app = FastAPI()
    app.include_router(chat.router)
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app), base_url="http://test") as client:
        response = await client.post("/chat/stream" if stream else "/chat", json={"query": "ข้อมูลแอป", "history": []})
    assert response.status_code == 200
    if stream:
        assert "event: done" in response.text and '"context"' in response.text
    else:
        assert "context" in response.json() and "references" in response.json()
