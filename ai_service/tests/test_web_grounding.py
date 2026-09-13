import pytest
from app.core.container import get_container
from app.application.dtos.chat_dto import ChatRequestDTO, ChatMessageDTO
from app.domain.entities.intent import IntentType

@pytest.mark.asyncio
async def test_route_intent_needs_web_search_flag():
    container = get_container()
    router = container.route_intent_use_case

    # 1. Spec inquiry should require web search
    decision_spec = await router.execute("กล้อง canon ขนาดเท่าไร")
    assert decision_spec.intent == IntentType.ITEM_SPEC_INQUIRY
    assert decision_spec.needs_web_search is True

    # 2. Specific comparison should require web search
    decision_comp = await router.execute("vivo v30 กับ iPhone 15 Pro ต่างกันยังไง")
    assert decision_comp.intent == IntentType.RENTAL_COMPARISON
    assert decision_comp.needs_web_search is True

    # 2.1 Open-ended comparison without specific models should trigger clarification
    decision_open_comp = await router.execute("vivo v30 กับ iphon รุ่นล่าสุด ต่างกันยังไง")
    assert decision_open_comp.intent == IntentType.CLARIFICATION_NEEDED
    assert decision_open_comp.needs_web_search is False

    # 3. General chat should not require web search
    decision_chat = await router.execute("ทำไรได้บ้าง")
    assert decision_chat.intent == IntentType.GENERAL_CHAT
    assert decision_chat.needs_web_search is False

    # 4. Broad fresh inquiry should not require web search
    decision_clar = await router.execute("อยากเช่ากล้อง")
    assert decision_clar.intent == IntentType.CLARIFICATION_NEEDED
    assert decision_clar.needs_web_search is False

@pytest.mark.asyncio
async def test_web_grounding_service_query_formulation():
    container = get_container()
    grounding = container.web_grounding_service

    # Spec query formulation
    q1 = grounding.formulate_spec_query("Canon EOS R50", "ขนาดและน้ำหนัก")
    assert "Canon EOS R50" in q1
    assert "ขนาดและน้ำหนัก" in q1
    assert "สเปก" in q1
    assert "specs" in q1

    # Comparison query formulation (general without attribute)
    q2 = grounding.formulate_comparison_query("vivo v30", "iPhone 17")
    assert "vivo v30 vs iPhone 17" in q2
    assert "specs comparison รีวิว" in q2
    assert "ข้อดี ข้อเสีย" not in q2

    # Comparison query formulation (attribute-focused)
    q3 = grounding.formulate_comparison_query("Sony A7 IV", "Canon R50", "ถ่ายที่แสงน้อย")
    assert "Sony A7 IV vs Canon R50" in q3
    assert "ถ่ายที่แสงน้อย" in q3
    assert "specs comparison" in q3
    assert "ข้อดี ข้อเสีย" not in q3

@pytest.mark.asyncio
async def test_spec_inquiry_web_grounding_and_no_citation_tags():
    container = get_container()
    use_case = container.process_chat_message_use_case

    req = ChatRequestDTO(message="กล้อง canon EOS R50 ขนาดและน้ำหนักเท่าไร")
    res = await use_case.execute(req)

    assert res.intent == "ITEM_SPEC_INQUIRY"
    assert res.response != ""
    # Verify search metadata is populated for AISummaryBottomSheet
    assert res.search_query is not None and len(res.search_query) > 0
    assert len(res.search_sources) > 0
    for src in res.search_sources:
        assert src.title != ""
        assert src.link != ""

    # Strict Clean Text Policy: No citation badges [1], [2], (1) in chat text
    assert "[1]" not in res.response
    assert "[2]" not in res.response
    assert "[3]" not in res.response
    assert "(1)" not in res.response
    assert "(2)" not in res.response

@pytest.mark.asyncio
async def test_comparison_no_citation_tags_in_response():
    container = get_container()
    use_case = container.process_chat_message_use_case

    req = ChatRequestDTO(message="ช่วยเปรียบเทียบ Sony A7 IV กับ Canon EOS R50 หน่อย")
    res = await use_case.execute(req)

    assert res.intent == "RENTAL_COMPARISON"
    assert res.response != ""
    assert res.search_query is not None
    assert len(res.search_sources) > 0

    # Strict Clean Text Policy: No citation badges [1], [2], (1) in chat text
    assert "[1]" not in res.response
    assert "[2]" not in res.response
    assert "[3]" not in res.response
    assert "(1)" not in res.response
    assert "(2)" not in res.response
