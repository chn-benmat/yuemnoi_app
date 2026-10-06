"""Contract and transport checks. These do not prove an LLM's semantic accuracy."""

import json
from unittest.mock import AsyncMock, MagicMock

import pytest
from pydantic import ValidationError

from app.application.dtos.chat_dto import ChatRequestDTO
from app.application.services.conversation_context import ContextLimits, conversation_context
from app.application.use_cases.process_chat_message_use_case import ProcessChatMessageUseCase
from app.application.use_cases.route_intent_use_case import RouteIntentUseCase
from app.domain.entities.chat_message import ChatMessage
from app.domain.entities.clarification import ClarificationQuestion, QuestionStep
from app.domain.entities.intent_decision import IntentDecision, RequestUnderstanding
from app.domain.entities.catalog_guidance import CatalogSelection
from evaluation.baseline import score
from evaluation.schema import RunConfig, load_suite
from app.infrastructure.llm.provider_client import native_schema
from pathlib import Path


LIMITS = ContextLimits(16, 24000)


def understanding(**changes):
    values = dict(intent="inventory_search", user_goal="เลือกอุปกรณ์",
                  additional_goals=[], request_scope="broad", information_sufficient=False,
                  next_action="clarify", known_facts=[], user_constraints=[], excluded_items=[],
                  topic_changed=False, clarification_declined=False, reference_resolution="ไม่มีสิ่งอ้างถึง",
                  decision_reason="ขาดข้อกำหนดที่จำเป็น", missing_slots=["required_workload"],
                  ambiguity_level=0.5, confidence=0.8, target_items=[], categories=[],
                  budget_max=None, budget_unit=None, intended_use=None, needs_external_search=False, search_query=None)
    if changes.get("budget_max") is not None:
        values["budget_unit"] = "วัน"  # Explicit unit for the synthetic budget fixture.
    values.update(changes)
    if "catalog_operation" not in values:
        values["catalog_operation"] = {"inventory_search": "selection", "item_inquiry": "inspection", "comparison": "comparison"}.get(values["intent"], "selection" if values["clarification_declined"] else "none")
    return RequestUnderstanding(**values)


@pytest.mark.parametrize("scope,sufficient,action", [
    ("broad", True, "answer"), ("specific", False, "clarify"),
    ("specific", True, "answer"), ("not_applicable", True, "answer"),
])
def test_scope_and_sufficiency_are_independent(scope, sufficient, action):
    result = understanding(request_scope=scope, information_sufficient=sufficient, next_action=action,
                           missing_slots=[] if sufficient else ["required_workload"])
    assert result.requires_clarification == (action == "clarify")


def test_live_contract_rejects_incomplete_and_inconsistent_output():
    with pytest.raises(ValidationError):
        RequestUnderstanding.model_validate(IntentDecision(intent="inventory_search").model_dump())
    with pytest.raises(ValidationError):
        understanding(missing_slots=[])
    with pytest.raises(ValidationError):
        understanding(information_sufficient=True)
    with pytest.raises(ValidationError):
        understanding(clarification_declined=True)
    with pytest.raises(ValidationError):
        understanding(needs_external_search=True)


def test_native_adapter_keeps_nested_contract_and_local_validation():
    schema = native_schema(RequestUnderstanding)
    assert "$defs" in schema
    assert schema["additionalProperties"] is False
    fact_schema = schema["properties"]["known_facts"]["items"]
    fact_schema = schema["$defs"][fact_schema["$ref"].split("/")[-1]]
    assert fact_schema["type"] == "object"
    assert fact_schema["additionalProperties"] is False
    assert "source_message_ids" in fact_schema["required"]
    with pytest.raises(ValidationError):
        understanding(unknown_property="invalid")
    # Property names must not be discarded as schema metadata.
    from pydantic import create_model
    custom = native_schema(create_model("FixturePropertyNames", title=(str, ...), default=(str, ...)))
    assert set(custom["properties"]) == {"title", "default"}


@pytest.mark.asyncio
@pytest.mark.parametrize("updates", [
    dict(topic_changed=True, intent="bot_capabilities", request_scope="not_applicable",
         information_sufficient=True, next_action="answer", missing_slots=[]),
    dict(clarification_declined=True, next_action="answer"),
    dict(additional_goals=["สอบถามขั้นตอนเช่าในแอป"], excluded_items=["รุ่นที่ปฏิเสธ"]),
])
async def test_semantic_topic_decline_and_mixed_goals_survive_routing(updates):
    expected = understanding(**updates)
    llm = MagicMock(generate_structured=AsyncMock(return_value=expected))
    result = await RouteIntentUseCase(llm, LIMITS, 0.1).execute(
        "ข้อความต่อเนื่อง", [ChatMessage(role="user", content="ความต้องการเดิม")])
    assert result == expected


def test_json_questionnaire_is_complete_and_not_reduced_to_answer_text():
    content = {"answer": "ร" * 700, "questions": [{"id": "q-usage", "title": "นำไปใช้กับงานอะไร",
               "options": ["ถ่ายในอาคาร", "ถ่ายกลางแจ้ง"]}],
               "answers": [{"question_id": "q-usage", "option_id": "outdoor", "text": "ถ่ายกลางแจ้ง"}],
               "items": [{"id": "real-id", "name": "ตัวเลือกที่ยังไม่ได้เลือก"}]}
    result = conversation_context([ChatMessage(role="assistant", content=json.dumps(content))], LIMITS)
    assert result["messages"][0]["content"] == content
    assert not result["truncated"]


def test_context_retains_old_constraints_and_new_corrections_in_order():
    history = [ChatMessage(role="user", content="ไม่เอากล้องที่หนัก งบ 500 ต่อวัน")]
    history += [ChatMessage(role="assistant", content="รายละเอียดเพิ่มเติม") for _ in range(6)]
    history += [ChatMessage(role="user", content="แก้งบเป็น 900 ต่อวัน แต่ยังต้องเบา")]
    context = conversation_context(history, LIMITS)
    assert context["messages"][0]["id"] == "h0"
    assert context["messages"][-1]["content"] == history[-1].content
    assert len(context["messages"]) == 8


def test_bounds_never_cut_json_or_silently_hide_truncation():
    history = [ChatMessage(role="assistant", content=json.dumps({"questions": [{"id": "q1", "title": "x" * 300}]})),
               ChatMessage(role="user", content="เลือกข้อสอง")]
    result = conversation_context(history, ContextLimits(4, 100))
    assert result["messages"] == [{"id": "h1", "role": "user", "content": "เลือกข้อสอง"}]
    assert result["truncated"] and result["omitted_messages"] == 1
    assert conversation_context(history, ContextLimits(1, 1))["messages"] == []


@pytest.mark.asyncio
async def test_router_preserves_corrections_and_validates_evidence_without_session_memory():
    llm = MagicMock()
    fact = {"dimension": "budget_per_day", "value": "900", "source_message_ids": ["current"]}
    llm.generate_structured = AsyncMock(return_value=understanding(
        known_facts=[fact], user_constraints=[fact], budget_max=900,
        excluded_items=["อุปกรณ์หนัก"], topic_changed=False))
    router = RouteIntentUseCase(llm, LIMITS, 0.1)
    result = await router.execute("แก้งบเป็น 900", [ChatMessage(role="user", content="งบ 500 ไม่เอาของหนัก")])
    assert result.budget_max == 900
    payload = json.loads(llm.generate_structured.call_args.kwargs["prompt"])
    assert payload["conversation"]["messages"][0]["content"] == "งบ 500 ไม่เอาของหนัก"
    assert payload["current_message"]["content"] == "แก้งบเป็น 900"
    assert issubclass(llm.generate_structured.call_args.kwargs["schema"], RequestUnderstanding)
    await router.execute("เริ่มใหม่")
    assert json.loads(llm.generate_structured.call_args.kwargs["prompt"])["conversation"]["messages"] == []
    llm.generate_structured.return_value = understanding(known_facts=[dict(fact, source_message_ids=["unknown-id"])])
    with pytest.raises(ValueError, match="evidence ID"):
        await router.execute("คำถามใหม่")






def test_semantic_evaluation_scores_scope_and_sufficiency_separately():
    root = Path(__file__).resolve().parents[1]
    config = RunConfig.model_validate_json((root / "evaluation/step3_config.json").read_text(encoding="utf-8"))
    case = load_suite(root / "evaluation/development.json").cases[0]
    decision = understanding(intent=case.expected.accepted_intents[0], request_scope=case.expected.request_scope,
                             information_sufficient=case.expected.information_sufficient, next_action=case.expected.action,
                             missing_slots=[] if case.expected.information_sufficient else ["required_workload"])
    first = score(case, decision, config)
    assert first["request_scope_correct"] and first["information_sufficient_correct"]
    decision.request_scope = "specific" if case.expected.request_scope == "broad" else "broad"
    assert not score(case, decision, config)["all_automated_checks_correct"]
