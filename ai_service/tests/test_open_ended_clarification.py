import pytest
from app.domain.entities.intent import IntentType
from app.application.dtos.chat_dto import ChatRequestDTO
from app.core.config import get_settings
from app.core.container import Container

@pytest.mark.asyncio
async def test_route_intent_open_ended_recommendation_device():
    """ทดสอบว่าคำถามกว้างระดับร้าน 'แนะนำอุปกรณ์เช่าหน่อย' ต้องได้ CLARIFICATION_NEEDED และเปิดแบบสอบถามระดับร้าน"""
    settings = get_settings()
    container = Container(settings=settings)
    router = container.route_intent_use_case
    
    decision = await router.execute(user_message="แนะนำอุปกรณ์เช่าหน่อย", history_context=None)
    assert decision.intent == IntentType.CLARIFICATION_NEEDED
    assert decision.ambiguity_level >= 0.8
    assert len(decision.slots.target_items) == 0

@pytest.mark.asyncio
async def test_route_intent_open_ended_recommendation_mobile():
    """ทดสอบว่าคำถามกว้างระดับหมวด 'แนะนำมือถือ' ต้องได้ CLARIFICATION_NEEDED พร้อมหมวดโทรศัพท์และอุปกรณ์สื่อสาร"""
    settings = get_settings()
    container = Container(settings=settings)
    router = container.route_intent_use_case
    
    decision = await router.execute(user_message="แนะนำมือถือ", history_context=None)
    assert decision.intent == IntentType.CLARIFICATION_NEEDED
    assert decision.ambiguity_level >= 0.8
    assert len(decision.slots.target_items) == 0
    assert "โทรศัพท์และอุปกรณ์สื่อสาร" in decision.slots.categories

@pytest.mark.asyncio
async def test_route_intent_specific_model_not_clarification():
    """ทดสอบว่าคำถามระบุชื่อรุ่นเฉพาะเจาะจง 'แนะนำ iPhone 15 Pro หน่อย' ต้องได้ ITEM_INQUIRY ทันที ไม่เข้าแบบสอบถาม"""
    settings = get_settings()
    container = Container(settings=settings)
    router = container.route_intent_use_case
    
    decision = await router.execute(user_message="แนะนำ iPhone 15 Pro หน่อย", history_context=None)
    assert decision.intent == IntentType.ITEM_INQUIRY
    assert "iPhone 15 Pro" in decision.slots.target_items

@pytest.mark.asyncio
async def test_e2e_process_chat_message_clarification_cards():
    """ทดสอบ Full Flow ผ่าน ProcessChatMessageUseCase ว่าส่งคืน Clarification DTO พร้อม 3 Step Questions ครบถ้วน"""
    settings = get_settings()
    container = Container(settings=settings)
    chat_processor = container.process_chat_message_use_case
    
    # 1. แนะนำอุปกรณ์เช่าหน่อย -> ต้องได้ 3-step General Store Questionnaire
    res_general = await chat_processor.execute(ChatRequestDTO(message="แนะนำอุปกรณ์เช่าหน่อย"))
    assert res_general.intent == "CLARIFICATION_NEEDED"
    assert res_general.clarification is not None
    assert len(res_general.clarification.questions) == 3
    assert res_general.clarification.questions[0].step == 1
    assert len(res_general.clarification.questions[0].options) > 0
    
    # 2. แนะนำมือถือ -> ต้องได้ 3-step Phone Questionnaire
    res_phone = await chat_processor.execute(ChatRequestDTO(message="แนะนำมือถือ"))
    assert res_phone.intent == "CLARIFICATION_NEEDED"
    assert res_phone.clarification is not None
    assert len(res_phone.clarification.questions) == 3
    assert "โทรศัพท์" in res_phone.clarification.questions[0].title or "สมาร์ตโฟน" in res_phone.clarification.questions[0].title
