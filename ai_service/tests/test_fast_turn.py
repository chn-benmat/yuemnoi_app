"""Fast-path contracts with simulated outputs, not semantic accuracy certification."""
import json
from dataclasses import replace
from pathlib import Path
from unittest.mock import AsyncMock

import pytest
from pydantic import ValidationError

from app.application.dtos.chat_dto import ChatRequestDTO
from app.application.services.conversation_context import ContextLimits
from app.application.use_cases.plan_chat_turn_use_case import PlanChatTurnUseCase
from app.application.use_cases.process_chat_message_use_case import ProcessChatMessageUseCase
from app.application.use_cases.query_items_use_case import QueryItemsUseCase
from app.core.exceptions import DatabaseException, AllLLMProvidersExhaustedException
from app.domain.entities.catalog_guidance import GuidancePolicy, MissingQuestion, PriceRequirement
from app.domain.entities.chat_result import SessionContext
from app.domain.entities.item import Item
from app.domain.entities.intent_decision import KnownFact
from app.domain.entities.clarification import QuestionStep, ChoiceOption
from app.domain.entities.chat_message import ChatMessage
from app.domain.entities.turn_plan import TurnPlan, EvidenceAnswer, PlannedQuestion
from app.domain.exceptions import GuidanceGenerationError
from app.infrastructure.knowledge.file_knowledge_repository import FileKnowledgeRepository
from app.infrastructure.runtime.documents import ValidatedFile
from app.infrastructure.runtime.execution import RuntimeExecutionGuard, consume_logical_call
from app.infrastructure.runtime.schema import InterpretationPolicy
from test_request_understanding import understanding

ROOT = Path(__file__).resolve().parents[1]
POLICY = GuidancePolicy(3, 4, 80, 80, 3, 2, .1)
LIMITS = ContextLimits(16, 24000)
INTERPRETATION = ValidatedFile(ROOT / "knowledge/interpretation_policy.json", InterpretationPolicy).read()[0].model_dump(
    mode="json", exclude={"approval", "schema_version", "version", "status", "production_enabled"})
ITEM = Item(id="real-1", name="คลังจริง", category="ภาพ", price=100, type="วัน", status="available")
QUESTION = PlannedQuestion(id="q1", dimension="location", title="ใช้ที่ไหน", choices=[
    {"id": "indoor", "label": "ภายในอาคาร", "value": "indoor", "supporting_item_ids": [ITEM.id]}])


def turn(**changes):
    data = dict(understanding=understanding(intent="platform_faq", catalog_operation="none", next_action="answer",
                information_sufficient=True, missing_slots=[]), knowledge_ids=["account.registration"],
                unverified_topic_ids=[], questions=[], message="", response_mode="documents")
    data.update(changes)
    return TurnPlan(**data).model_copy(deep=True)


def equipment_answer(**selection_changes):
    data = dict(mode="items", purpose="recommendation", selected_items=[{
        "id": ITEM.id, "reason": "เหตุผลตามหลักฐาน", "evidence_fields": ["price", "category"]}],
        price_requirement=None, reasoning="ตามความต้องการ")
    data.update(selection_changes)
    fit = "not_assessed" if data["purpose"] == "inspection" or data["mode"] == "categories" else (
        "no_supported_match" if data["mode"] == "no_matches" else "meets_request")
    return EvidenceAnswer(request_fit=fit, selection=data, answer="รายละเอียดจากหลักฐาน {{item:" + ITEM.id + ":name}}", search_ids=[], suggested_replies=[])


def make_fast(plan, answer=None, repository=None):
    llm = AsyncMock()
    llm.generate_structured.side_effect = [plan] + ([answer] if answer else [])
    repo = repository or AsyncMock()
    if repository is None:
        repo.get_all_items.return_value = [ITEM]
    knowledge = FileKnowledgeRepository(ROOT / "knowledge/app_knowledge.json")
    search = AsyncMock()
    search.search.return_value = []
    query = QueryItemsUseCase(repo, llm, POLICY)
    # These tests isolate planning/evidence contracts. Actual review composition
    # is covered separately and is mandatory in the production container.
    review = AsyncMock()
    fast = PlanChatTurnUseCase(llm, repo, knowledge, query, search, LIMITS, POLICY, INTERPRETATION,
                              review_service=review)
    return fast, llm, repo, search


@pytest.mark.asyncio
async def test_faq_one_call_exact_document_without_full_articles_in_prompt():
    fast, llm, _, _ = make_fast(turn())
    result = await fast.execute(ChatRequestDTO(message="สมัครบัญชีทำอย่างไร"))
    snapshot = await fast._knowledge.get_approved_knowledge()
    article = next(a for a in snapshot.articles if a.id == "account.registration")
    assert result.response == article.content
    assert llm.generate_structured.await_count == 1
    payload = json.loads(llm.generate_structured.call_args.kwargs["prompt"])
    assert len(payload["knowledge_index"]) == 22
    assert all("content" not in a for a in payload["knowledge_index"])
    assert payload["catalog_summary"]["prices"]["rows"] == [[ITEM.category, ITEM.type, ITEM.price, ITEM.price]]
    assert article.content not in llm.generate_structured.call_args.kwargs["prompt"]
    assert result.references and result.next_action == "answer" and result.response_flow == "general"


@pytest.mark.asyncio
async def test_unverified_policy_is_notice_only_no_followup_no_web():
    fast, llm, _, search = make_fast(turn(knowledge_ids=[], unverified_topic_ids=["policy.deposit"]))
    result = await fast.execute(ChatRequestDTO(message="มัดจำเท่าไหร่"))
    assert result.response == INTERPRETATION["unavailable_notice"]
    assert not result.items and not result.questions and not result.references
    assert llm.generate_structured.await_count == 1
    search.search.assert_not_awaited()


@pytest.mark.asyncio
async def test_missing_app_topic_cannot_use_factual_social_reply():
    fast, _, _, _ = make_fast(turn(knowledge_ids=[], response_mode="conversation", message="ข้อมูลที่แต่ง"))
    with pytest.raises(ValidationError):
        await fast.execute(ChatRequestDTO(message="ข้อมูลแอปที่ยังไม่รู้"))


@pytest.mark.asyncio
async def test_questionnaire_and_mixed_faq_use_one_call_and_no_cards():
    decision = understanding(intent="inventory_search", catalog_operation="selection", missing_slots=["location"])
    fast, llm, _, _ = make_fast(turn(understanding=decision, questions=[QUESTION], message="ขอข้อมูลเพิ่มเติม", response_mode="clarification"))
    result = await fast.execute(ChatRequestDTO(message="สมัครและหาอุปกรณ์สำหรับงาน"))
    assert result.response.endswith("ขอข้อมูลเพิ่มเติม")
    assert len(result.questions) == 1 and not result.items
    assert result.questions[0].id.endswith(":q1")
    assert llm.generate_structured.await_count == 1


@pytest.mark.asyncio
async def test_equipment_selection_and_explanation_use_exactly_two_calls():
    decision = understanding(catalog_operation="selection", information_sufficient=True, next_action="answer", missing_slots=[])
    fast, llm, repo, _ = make_fast(turn(understanding=decision, knowledge_ids=[], response_mode="equipment"), equipment_answer())
    result = await fast.execute(ChatRequestDTO(message="เลือกตามข้อกำหนดที่ทราบ"))
    assert llm.generate_structured.await_count == 2
    assert result.items[0].id == ITEM.id and result.items[0].price == ITEM.price
    assert result.response_flow == "equipment"
    assert repo.get_all_items.await_count == 3


@pytest.mark.asyncio
async def test_broad_catalog_browsing_needs_no_forced_questionnaire():
    decision = understanding(catalog_operation="selection", request_scope="broad", information_sufficient=True,
                             next_action="answer", missing_slots=[])
    fast, _, _, _ = make_fast(turn(understanding=decision, knowledge_ids=[], response_mode="equipment"),
                             equipment_answer(mode="categories", selected_items=[]))
    result = await fast.execute(ChatRequestDTO(message="มีหมวดไหนให้ดูบ้าง"))
    assert not result.questions and not result.items and ITEM.category in result.response


@pytest.mark.asyncio
async def test_skip_preserves_no_question_loop_and_real_categories():
    decision = understanding(catalog_operation="selection", clarification_declined=True, next_action="answer", missing_slots=[])
    fast, llm, _, _ = make_fast(turn(understanding=decision, knowledge_ids=[], response_mode="equipment"),
                             equipment_answer(mode="categories", selected_items=[]))
    result = await fast.execute(ChatRequestDTO(message="ข้าม", questionnaire_skipped=True))
    assert result.context.clarification_declined and not result.questions
    assert llm.generate_structured.await_count == 2


@pytest.mark.asyncio
@pytest.mark.parametrize("invalid", ["unknown_doc", "unapproved_doc", "unknown_topic", "repeat", "unsupported_choice", "too_many_choices", "too_long", "bad_source", "garbled_fact", "skip", "mode"])
async def test_invalid_turn_contract_rejected_without_an_extra_logical_call(invalid):
    decision = understanding(catalog_operation="selection", missing_slots=["location"])
    plan = turn(understanding=decision, questions=[QUESTION], message="ข้อมูลเพิ่ม", response_mode="clarification")
    request = ChatRequestDTO(message="เลือกอุปกรณ์")
    if invalid == "unknown_doc": plan.knowledge_ids = ["fake"]
    if invalid == "unapproved_doc": plan.knowledge_ids = ["policy.deposit"]
    if invalid == "unknown_topic": plan.unverified_topic_ids = ["fake"]
    if invalid == "repeat": plan.understanding.known_facts = [KnownFact(dimension="location", value="ในอาคาร", source_message_ids=["current"])]
    if invalid == "unsupported_choice": plan.questions[0].choices[0].supporting_item_ids = ["fake"]
    if invalid == "too_many_choices": plan.questions[0].choices *= 5
    if invalid == "too_long": plan.questions[0].title = "x" * 81
    if invalid == "bad_source": plan.understanding.known_facts = [KnownFact(dimension="location", value="ในอาคาร", source_message_ids=["not-supplied"])]
    if invalid == "garbled_fact": plan.understanding.known_facts = [KnownFact(dimension="budget_max", value="}, {", source_message_ids=["current"])]
    if invalid == "skip": request.questionnaire_skipped = True
    if invalid == "mode": plan.response_mode = "equipment"
    fast, llm, _, _ = make_fast(plan)
    with pytest.raises((ValueError, ValidationError, AttributeError)):
        await fast.execute(request)
    assert llm.generate_structured.await_count == 1


@pytest.mark.asyncio
@pytest.mark.parametrize("invalid", ["id", "unavailable", "budget", "period", "purpose", "web", "excluded"])
async def test_evidence_validation_is_grounded_and_never_requests_a_third_call(invalid):
    decision = understanding(catalog_operation="selection", information_sufficient=True, next_action="answer", missing_slots=[])
    answer = equipment_answer()
    repo = AsyncMock()
    repo.get_all_items.return_value = [ITEM]
    if invalid == "id": answer.selection.selected_items[0].id = "fake"
    if invalid == "unavailable": repo.get_all_items.return_value = [ITEM.model_copy(update={"status": "rented"})]
    if invalid == "budget": decision.budget_max = 50; decision.budget_unit = "วัน"
    if invalid == "period": answer.selection.price_requirement = PriceRequirement(maximum=100, user_unit="วัน", catalog_units=["วัน"], interpretation="invented")
    if invalid == "purpose": answer.selection.purpose = "inspection"
    if invalid == "web": answer.search_ids = ["web:fake"]
    if invalid == "excluded": decision.excluded_items = [ITEM.id]
    fast, llm, _, _ = make_fast(turn(understanding=decision, knowledge_ids=[], response_mode="equipment"), answer, repo)
    with pytest.raises((ValueError, ValidationError, AttributeError)):
        await fast.execute(ChatRequestDTO(message="เลือกอุปกรณ์"))
    assert llm.generate_structured.await_count == 2


@pytest.mark.asyncio
async def test_changed_catalog_before_send_is_rejected():
    decision = understanding(catalog_operation="selection", information_sufficient=True, next_action="answer", missing_slots=[])
    repo = AsyncMock()
    repo.get_all_items.side_effect = [[ITEM], [ITEM], [ITEM.model_copy(update={"price": 101})]]
    fast, _, _, _ = make_fast(turn(understanding=decision, knowledge_ids=[], response_mode="equipment"), equipment_answer(), repo)
    with pytest.raises(GuidanceGenerationError, match="catalog_changed"):
        await fast.execute(ChatRequestDTO(message="เลือกอุปกรณ์"))


@pytest.mark.asyncio
async def test_knowledge_revocation_before_send_is_rejected():
    fast, _, _, _ = make_fast(turn())
    snapshot = await fast._knowledge.get_approved_knowledge()
    fast._knowledge = AsyncMock()
    fast._knowledge.get_approved_knowledge.side_effect = [snapshot, replace(snapshot, document_sha256="changed", articles=())]
    with pytest.raises(GuidanceGenerationError, match="knowledge_changed"):
        await fast.execute(ChatRequestDTO(message="สมัคร"))


@pytest.mark.asyncio
async def test_catalog_failure_does_not_block_document_answer():
    repo = AsyncMock()
    repo.get_all_items.side_effect = DatabaseException("unavailable")
    fast, llm, _, _ = make_fast(turn(), repository=repo)
    result = await fast.execute(ChatRequestDTO(message="สมัครบัญชี"))
    assert result.response and llm.generate_structured.await_count == 1


@pytest.mark.asyncio
async def test_json_and_sse_use_fast_result_and_never_execute_legacy_routes():
    fast, llm, _, _ = make_fast(turn())
    llm.generate_structured.side_effect = [turn(), turn()]
    legacy = AsyncMock()
    process = ProcessChatMessageUseCase(legacy, legacy, legacy, llm, legacy, LIMITS,
        fast._knowledge, POLICY, .01, 64, fast_path=fast)
    request = ChatRequestDTO(message="สมัคร", session_id="chat")
    result = await process.execute(request)
    events = [e async for e in process.execute_stream(request)]
    done = next(json.loads(e.splitlines()[1][6:]) for e in events if e.startswith("event: done"))
    assert done["response"] == result.response and done["request_scope"] == result.request_scope
    legacy.execute.assert_not_awaited()
    assert llm.generate_structured.await_count == 2


@pytest.mark.asyncio
async def test_runtime_counts_logical_calls_independently_of_provider_failover():
    guard = RuntimeExecutionGuard(ROOT / "config/ai_runtime.json", ROOT / "knowledge/interpretation_policy.json")
    async with guard.turn():
        guard.select_flow("general")
        consume_logical_call()
        consume_logical_call()
        with pytest.raises(AllLLMProvidersExhaustedException, match="cloud LLM") as error:
            consume_logical_call()
        assert error.value.code == "logical_call_budget_exceeded"
    async with guard.turn():
        consume_logical_call()
        guard.select_flow("equipment")
        consume_logical_call()
        consume_logical_call()
        with pytest.raises(AllLLMProvidersExhaustedException):
            consume_logical_call()


@pytest.mark.asyncio
async def test_catalog_overview_projects_only_current_categories_with_one_call():
    decision = understanding(catalog_operation="inspection", next_action="answer", information_sufficient=True, missing_slots=[])
    fast, llm, _, _ = make_fast(turn(understanding=decision, knowledge_ids=[], response_mode="catalog_overview"))
    result = await fast.execute(ChatRequestDTO(message="ดูหมวดทั้งหมด"))
    assert result.response == ITEM.category and not result.items
    assert result.references[0].id == ITEM.id and llm.generate_structured.await_count == 1


@pytest.mark.asyncio
async def test_empty_available_overview_uses_json_notice():
    repo = AsyncMock()
    repo.get_all_items.return_value = [ITEM.model_copy(update={"status": "rented"})]
    decision = understanding(catalog_operation="inspection", next_action="answer", information_sufficient=True, missing_slots=[])
    fast, _, _, _ = make_fast(turn(understanding=decision, knowledge_ids=[], response_mode="catalog_overview", overview_available_only=True), repository=repo)
    result = await fast.execute(ChatRequestDTO(message="ดูหมวดที่เช่าได้"))
    assert result.response == INTERPRETATION["empty_catalog_notice"] and not result.items


@pytest.mark.asyncio
async def test_overview_respects_semantic_category_ids_and_current_availability():
    unrelated = ITEM.model_copy(update={"id": "unrelated", "category": "เสียง"})
    unavailable = ITEM.model_copy(update={"id": "unavailable", "status": "rented"})
    repo = AsyncMock()
    repo.get_all_items.return_value = [unrelated, unavailable, ITEM]
    decision = understanding(catalog_operation="inspection", categories=[ITEM.category], next_action="answer",
                             information_sufficient=True, missing_slots=[])
    fast, llm, _, _ = make_fast(turn(understanding=decision, knowledge_ids=[],
        response_mode="catalog_overview", overview_available_only=True), repository=repo)
    result = await fast.execute(ChatRequestDTO(message="ขอหมวดตามสิ่งที่เราคุยไว้"))
    assert result.response == ITEM.category
    assert [r.id for r in result.references] == [ITEM.id]
    assert not result.items and llm.generate_structured.await_count == 1


@pytest.mark.asyncio
async def test_question_catalog_reordering_is_not_a_changed_evidence_error():
    other = ITEM.model_copy(update={"id": "second", "category": "เสียง"})
    repo = AsyncMock()
    repo.get_all_items.side_effect = [[ITEM, other], [other, ITEM]]
    decision = understanding(catalog_operation="selection", missing_slots=["location"])
    fast, _, _, _ = make_fast(turn(understanding=decision, knowledge_ids=[], questions=[QUESTION],
        message="ใช้ที่ไหน", response_mode="clarification"), repository=repo)
    result = await fast.execute(ChatRequestDTO(message="ช่วยเลือกอุปกรณ์"))
    assert result.questions and not result.items


@pytest.mark.asyncio
async def test_question_reordering_does_not_hide_changed_catalog_price():
    other = ITEM.model_copy(update={"id": "second", "category": "เสียง"})
    repo = AsyncMock()
    repo.get_all_items.side_effect = [[ITEM, other], [other, ITEM.model_copy(update={"price": 101})]]
    decision = understanding(catalog_operation="selection", missing_slots=["location"])
    fast, _, _, _ = make_fast(turn(understanding=decision, knowledge_ids=[], questions=[QUESTION],
        message="ใช้ที่ไหน", response_mode="clarification"), repository=repo)
    with pytest.raises(GuidanceGenerationError, match="catalog_changed"):
        await fast.execute(ChatRequestDTO(message="ช่วยเลือกอุปกรณ์"))


@pytest.mark.asyncio
async def test_corrected_budget_and_restrictions_are_sent_together():
    decision = understanding(intent="platform_faq", catalog_operation="none", next_action="answer", information_sufficient=True,
        missing_slots=[], budget_max=250, budget_unit="วัน", known_facts=[KnownFact(dimension="budget", value="250", source_message_ids=["current"])],
        user_constraints=[KnownFact(dimension="system", value="Windows", source_message_ids=["context"])])
    fast, llm, _, _ = make_fast(turn(understanding=decision))
    context = SessionContext(session_id="chat", user_goal="งานเอกสาร", budget_max=500, budget_unit="วัน")
    response = await fast.execute(ChatRequestDTO(message="เปลี่ยนงบเป็น 250 ข้อกำหนดอื่นเดิม", session_id="chat", context=context,
        history=[ChatMessage(role="user", content="ใช้ Windows ทำเอกสาร")]))
    payload = json.loads(llm.generate_structured.call_args.kwargs["prompt"])
    assert payload["client_context"]["data"]["budget_max"] == 500
    assert payload["conversation"]["messages"][0]["content"] == "ใช้ Windows ทำเอกสาร"
    assert response.context.budget_max == 250 and response.context.user_constraints[0].value == "Windows"


@pytest.mark.asyncio
async def test_answered_dimension_cannot_repeat_even_if_model_omits_known_fact():
    question = QuestionStep(id="batch:q", dimension="location", title="ใช้ที่ไหน", choices=[ChoiceOption(id="in", label="ในอาคาร", action_value="in")])
    context = SessionContext(session_id="chat", user_goal="เลือกอุปกรณ์", questions=[question])
    decision = understanding(catalog_operation="selection", missing_slots=["location"])
    fast, _, _, _ = make_fast(turn(understanding=decision, questions=[QUESTION], message="ข้อมูลเพิ่ม", response_mode="clarification"))
    with pytest.raises(ValidationError):
        await fast.execute(ChatRequestDTO(message="เลือกแล้ว", session_id="chat", context=context,
            questionnaire_answers=[{"question_id": question.id, "option_id": "in"}]))


@pytest.mark.asyncio
async def test_technical_evidence_uses_two_calls_without_catalog_cards():
    decision = understanding(intent="item_inquiry", catalog_operation="none", next_action="answer", information_sufficient=True,
        missing_slots=[], needs_external_search=True, search_query="technical verification")
    fast, llm, _, search = make_fast(turn(understanding=decision, knowledge_ids=[], response_mode="technical"),
        EvidenceAnswer(request_fit="not_assessed", selection=None, answer="ยังไม่มีหลักฐานภายนอกยืนยัน", search_ids=[], suggested_replies=[]))
    result = await fast.execute(ChatRequestDTO(message="ตรวจคุณสมบัติที่คลังไม่ได้ระบุ"))
    assert result.response_flow == "technical" and not result.items
    assert llm.generate_structured.await_count == 2
    search.search.assert_awaited_once()


@pytest.mark.asyncio
async def test_billing_period_cannot_be_converted_without_evidence():
    decision = understanding(catalog_operation="selection", next_action="answer", information_sufficient=True,
        missing_slots=[], budget_max=100, budget_unit="ชั่วโมง")
    answer = equipment_answer(price_requirement=PriceRequirement(maximum=100, user_unit="ชั่วโมง", catalog_units=["วัน"], interpretation="unsupported conversion"))
    fast, llm, _, _ = make_fast(turn(understanding=decision, knowledge_ids=[], response_mode="equipment"), answer)
    with pytest.raises(ValidationError):
        await fast.execute(ChatRequestDTO(message="งบ 100 ต่อชั่วโมง"))
    assert llm.generate_structured.await_count == 2


@pytest.mark.asyncio
async def test_candidate_scope_comes_from_semantically_selected_ids_not_query_words():
    other = ITEM.model_copy(update={"id": "other-real", "category": "เสียง", "price": 50})
    repo = AsyncMock()
    repo.get_all_items.return_value = [ITEM, other]
    decision = understanding(catalog_operation="selection", categories=[ITEM.category], next_action="answer",
                             information_sufficient=True, missing_slots=[])
    fast, llm, _, _ = make_fast(turn(understanding=decision, knowledge_ids=[], response_mode="equipment"), equipment_answer(), repo)
    result = await fast.execute(ChatRequestDTO(message="นั่นแหละ เลือกตามที่คุยไว้"))
    payload = json.loads(llm.generate_structured.call_args_list[1].kwargs["prompt"])
    assert [row[0] for row in payload["catalog"]["rows"]] == [ITEM.id, other.id]
    assert payload["catalog_scope"]["full_catalog_included"] is True
    assert [i.id for i in result.items] == [ITEM.id]


@pytest.mark.asyncio
async def test_real_id_outside_semantically_selected_category_is_rejected():
    other = ITEM.model_copy(update={"id": "other-real", "category": "เสียง", "price": 50})
    repo = AsyncMock()
    repo.get_all_items.return_value = [ITEM, other]
    decision = understanding(catalog_operation="selection", categories=[ITEM.category], next_action="answer",
                             information_sufficient=True, missing_slots=[])
    answer = equipment_answer()
    answer.selection.selected_items[0].id = other.id
    fast, llm, _, _ = make_fast(turn(understanding=decision, knowledge_ids=[], response_mode="equipment"), answer, repo)
    with pytest.raises(ValidationError):
        await fast.execute(ChatRequestDTO(message="เลือกตามบริบท"))
    assert llm.generate_structured.await_count == 2
