from app.application.services.conversation_context import ContextLimits
import json
import pytest
from unittest.mock import AsyncMock, MagicMock
from app.application.dtos.chat_dto import ChatRequestDTO
from app.application.services.fact_verification_service import FactVerificationService
from app.application.use_cases.compare_items_use_case import CompareItemsUseCase
from app.application.use_cases.generate_clarification_use_case import GenerateClarificationUseCase
from app.application.use_cases.process_chat_message_use_case import ProcessChatMessageUseCase
from app.application.use_cases.query_items_use_case import QueryItemsUseCase
from app.application.use_cases.route_intent_use_case import RouteIntentUseCase
from app.domain.entities.chat_message import ChatMessage
from app.domain.entities.clarification import ClarificationQuestion, ChoiceOption, QuestionStep
from app.domain.entities.comparison import ComparisonMatrix
from app.domain.entities.intent_decision import IntentDecision, RequestUnderstanding
from app.domain.entities.item import Item
from app.domain.entities.search_source import SearchSource
from app.domain.entities.catalog_guidance import GuidancePolicy, GuidanceReview, SelectionPlan, CatalogSelection

@pytest.mark.asyncio
async def test_route_intent_passes_history_and_active_items_context():
    """Verifies that RouteIntentUseCase extracts active items from history and formats them in prompt."""
    import json
    from app.domain.entities.chat_message import ChatMessage

    mock_llm = MagicMock()
    mock_llm.generate_structured = AsyncMock(return_value=RequestUnderstanding(catalog_operation="inspection",
        user_goal="สอบถามอุปกรณ์ที่อ้างถึง", additional_goals=[],
        request_scope="specific", information_sufficient=True, next_action="answer",
        known_facts=[], user_constraints=[], excluded_items=[], topic_changed=False,
        clarification_declined=False, reference_resolution="อ้างถึงอุปกรณ์เดียว", decision_reason="มีสิ่งที่อ้างถึง",
        intent="item_inquiry",
        confidence=0.8, categories=[], budget_max=None, intended_use=None,
        budget_unit=None,
        missing_slots=[], needs_external_search=False, search_query=None,
        target_items=["กล้อง Sony Alpha A7 IV"],
        ambiguity_level=0.0,
    ))

    uc = RouteIntentUseCase(llm_service=mock_llm, context_limits=ContextLimits(16, 24000), temperature=0.1)
    history = [
        ChatMessage(role="user", content="อยากเช่ากล้องถ่ายภาพมืออาชีพ"),
        ChatMessage(
            role="assistant",
            content=json.dumps({
                "answer": "ยืมหน่อย AI ขอแนะนำกล้อง Sony Alpha A7 IV นะคะ",
                "items": [{"id": "1", "name": "กล้อง Sony Alpha A7 IV"}],
            }),
        ),
    ]

    result = await uc.execute("ทำไรได้", history=history)

    assert result.intent == "item_inquiry"
    assert "กล้อง Sony Alpha A7 IV" in result.target_items

    # Verify prompt sent to LLM contains active item context
    call_args = mock_llm.generate_structured.call_args
    prompt_sent = call_args.kwargs.get("prompt") or call_args.args[0]
    assert "กล้อง Sony Alpha A7 IV" in prompt_sent
    assert json.loads(prompt_sent)["conversation"]["messages"][1]["content"]["items"][0]["id"] == "1"


@pytest.mark.asyncio
async def test_compare_items_creates_fallback_query_and_includes_closing_guidelines():
    """Verifies that CompareItemsUseCase generates a fallback search query if none provided,
    and prompts for 'ยังไม่มีให้บริการในระบบค่ะ' and 'หากสนใจสินค้าที่มีให้เช่าในระบบตอนนี้ สามารถแตะดูรายละเอียดเพิ่มเติมที่การ์ดด้านล่างนี้ได้เลยนะคะ'."""
    mock_llm = MagicMock()
    mock_search = MagicMock()
    mock_fact = MagicMock()

    mock_search.search = AsyncMock(return_value=[
        SearchSource(title="iPhone 16 Pro Review", snippet="A18 Pro chip, 6.3 inch", domain="tech.com", url="https://tech.com")
    ])
    mock_fact.verify_and_synthesize = AsyncMock(return_value=ComparisonMatrix(
        target_items=["iPhone 15 Pro", "iPhone 16 Pro"],
        specifications={"iPhone 16 Pro": {"chip": "A18 Pro"}, "iPhone 15 Pro": {"chip": "A17 Pro"}},
        pros_and_cons={},
        verdict="iPhone 16 Pro แรงกว่า"
    ))
    mock_llm.generate_text = AsyncMock(return_value=(
        "ทั้งสองรุ่นมีจุดเด่นแตกต่างกันดังนี้นะคะ\n\n"
        "**iPhone 15 Pro**\n- **จุดเด่น/การใช้งาน:** ชิป A17 Pro จอ 6.1 นิ้ว\n- **ราคาเช่า:** 380 บาท ต่อ วัน\n\n"
        "**iPhone 16 Pro**\n- **จุดเด่น/การใช้งาน:** ชิป A18 Pro จอ 6.3 นิ้ว\n- **ราคาเช่า:** ยังไม่มีให้บริการในระบบค่ะ\n\n"
        "หากสนใจสินค้าที่มีให้เช่าในระบบตอนนี้ สามารถแตะดูรายละเอียดเพิ่มเติมที่การ์ดด้านล่างนี้ได้เลยนะคะ"
    ))

    uc = CompareItemsUseCase(
        llm_service=mock_llm,
        search_service=mock_search,
        fact_service=mock_fact,
    )

    decision = IntentDecision(
        intent="comparison",
        target_items=["iPhone 15 Pro", "iPhone 16 Pro"],
        categories=["โทรศัพท์และอุปกรณ์สื่อสาร"],
        ambiguity_level=0.0,
        search_query=None,
    )
    candidate_items = [
        Item(id="15", name="iPhone 15 Pro 128GB", category="โทรศัพท์และอุปกรณ์สื่อสาร", price=380.0, type="day")
    ]

    answer, sources = await uc.execute(decision, candidate_items)

    assert mock_search.search.called
    assert decision.search_query == "compare iPhone 15 Pro vs iPhone 16 Pro specs"
    assert len(sources) == 1
    assert "ยังไม่มีให้บริการในระบบค่ะ" in answer
    assert "หากสนใจสินค้าที่มีให้เช่าในระบบตอนนี้ สามารถแตะดูรายละเอียดเพิ่มเติมที่การ์ดด้านล่างนี้ได้เลยนะคะ" in answer

    # Verify prompt guidelines sent to LLM
    prompt_sent = mock_llm.generate_text.call_args[1]["prompt"]
    assert "ยังไม่มีให้บริการในระบบค่ะ" in prompt_sent
    assert "หากสนใจสินค้าที่มีให้เช่าในระบบตอนนี้ สามารถแตะดูรายละเอียดเพิ่มเติมที่การ์ดด้านล่างนี้ได้เลยนะคะ" in prompt_sent


