import pytest
import sys
import os

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.core.config import get_settings
from app.infrastructure.llm.ollama_client import OllamaClient
from app.infrastructure.db.supabase_repository import SupabaseRepository
from app.infrastructure.cache.memory_cache import MemoryCacheService
from app.application.use_cases.route_intent import RouteIntentUseCase
from app.application.use_cases.generate_clarification import GenerateClarificationUseCase
from app.domain.entities.intent import IntentType

@pytest.mark.asyncio
async def test_route_intent_item_inquiry():
    settings = get_settings()
    llm = OllamaClient(settings)
    router = RouteIntentUseCase(llm)

    query = "กล้อง Canon EOS R50 มีให้เช่าไหมครับ ราคาเช่าวันละเท่าไหร่"
    decision = await router.execute(query)

    assert decision.intent == IntentType.ITEM_INQUIRY
    assert decision.confidence >= 0.5

@pytest.mark.asyncio
async def test_route_intent_comparison():
    settings = get_settings()
    llm = OllamaClient(settings)
    router = RouteIntentUseCase(llm)

    query = "ช่วยเปรียบเทียบสเปกระหว่าง Sony A7 IV กับ Canon R50 ให้หน่อย ตัวไหนคุ้มค่ากว่ากัน"
    decision = await router.execute(query)

    assert decision.intent == IntentType.RENTAL_COMPARISON

@pytest.mark.asyncio
async def test_route_intent_clarification_needed():
    settings = get_settings()
    llm = OllamaClient(settings)
    router = RouteIntentUseCase(llm)

    query = "อยากได้คอมทำงานสักเครื่อง"
    decision = await router.execute(query)

    assert decision.intent == IntentType.CLARIFICATION_NEEDED or decision.ambiguity_level >= 0.5

@pytest.mark.asyncio
async def test_route_intent_capabilities_with_history():
    settings = get_settings()
    llm = OllamaClient(settings)
    router = RouteIntentUseCase(llm)

    history = (
        "assistant: สวัสดีค่ะ ฉันคือ Yuemnoi ผู้ช่วยแนะนำอุปกรณ์เช่า มีอะไรให้ช่วยวันนี้คะ\n"
        "user: กล้องและอุปกรณ์ถ่ายภาพ\n"
        "assistant: เพื่อช่วยคัดสรรอุปกรณ์ที่เหมาะกับคุณที่สุด ต้องการกล้องสำหรับงานประเภทใดคะ"
    )
    decision = await router.execute("ทำไรได้", history_context=history)

    assert decision.intent == IntentType.GENERAL_CHAT

@pytest.mark.asyncio
async def test_route_intent_item_spec_inquiry():
    settings = get_settings()
    llm = OllamaClient(settings)
    router = RouteIntentUseCase(llm)

    query = "กล้อง canon สามารถขนาดเท่าไร"
    decision = await router.execute(query)

    assert decision.intent == IntentType.ITEM_SPEC_INQUIRY
    assert decision.slots.target_items is not None
    assert len(decision.slots.target_items) > 0

@pytest.mark.asyncio
async def test_route_intent_topic_transition_to_gaming():
    settings = get_settings()
    llm = OllamaClient(settings)
    router = RouteIntentUseCase(llm)

    history = (
        "user: แล้วถ้าอยากเช่าคอมไปทำงานเอกสารทั่วไปมีแนะนำไรบ้าง\n"
        "assistant: MacBook Air M2 13 นิ้ว: แล็ปท็อปบางเบา เหมาะสำหรับทำงานเอกสาร...\n"
        "user: แล้วถ้าเอา mackbook ari ไปเล่นเกมได้ไหม\n"
        "assistant: MacBook Air M2 13 นิ้ว ไม่เหมาะสมสำหรับการเล่นเกม...\n"
    )
    decision = await router.execute("งั้นแนะนำอุปกรณ์เล่นเกมหน่อย", history_context=history)

    assert decision.intent == IntentType.ITEM_INQUIRY
    # target_items should NOT contain MacBook
    for target in decision.slots.target_items:
        assert "macbook" not in target.lower()
    # categories should include gaming
    assert any("เกม" in cat for cat in decision.slots.categories)

@pytest.mark.asyncio
async def test_route_intent_clarification_with_greeting_history_computer():
    settings = get_settings()
    llm = OllamaClient(settings)
    router = RouteIntentUseCase(llm)

    history = (
        "user: สวัสดี\n"
        "assistant: สวัสดีค่ะคุณลูกค้า ยินดีต้อนรับสู่ร้านยืมหน่อยนะคะ วันนี้กำลังมองหาอุปกรณ์อะไร หรืออยากให้ช่วยแนะนำชิ้นไหน สอบถามน้องยืมหน่อยได้เลยนะคะ 😊"
    )
    decision = await router.execute("อยากเช่าคอม", history_context=history)

    assert decision.intent == IntentType.CLARIFICATION_NEEDED
    assert decision.ambiguity_level >= 0.5
    assert len(decision.slots.target_items) == 0

@pytest.mark.asyncio
async def test_route_intent_clarification_with_greeting_history_mobile():
    settings = get_settings()
    llm = OllamaClient(settings)
    router = RouteIntentUseCase(llm)

    history = (
        "user: สวัสดีค่ะ\n"
        "assistant: สวัสดีค่ะคุณลูกค้า มีอะไรให้ช่วยสอบถามได้เลยนะคะ"
    )
    decision = await router.execute("อยากเช่ามือถือ", history_context=history)

    assert decision.intent == IntentType.CLARIFICATION_NEEDED
    assert decision.ambiguity_level >= 0.5
    assert len(decision.slots.target_items) == 0

@pytest.mark.asyncio
async def test_route_intent_latest_iphone_resolves_to_clarification_needed():
    """คำถามเปรียบเทียบปลายเปิดที่ระบุ 'iphon รุ่นล่าสุด' หรือ 'sony alpha' ต้องถามความชัดเจน (CLARIFICATION_NEEDED) ก่อนค้นหา"""
    settings = get_settings()
    llm = OllamaClient(settings)
    router = RouteIntentUseCase(llm)

    # Even with history recommending iPhone 15 Pro
    history = (
        "user: อยากได้มือถือไปถ่ายคอนเสิร์ต\n"
        "assistant: ขอแนะนำ iPhone 15 Pro สำหรับการถ่ายวิดีโอและซูมภาพในคอนเสิร์ตค่ะ"
    )
    decision = await router.execute(
        "อยากทราบว่า vivo v30 กับ iphon รุ่นล่าสุด อันไหนเหมาะสำหรับเอามาใช้ถ่ายภาพงานออกแบบ",
        history_context=history
    )

    assert decision.intent == IntentType.CLARIFICATION_NEEDED
    assert decision.ambiguity_level >= 0.7
    assert decision.is_comparison is True

@pytest.mark.asyncio
async def test_route_intent_sony_alpha_vs_iphone_latest_clarification():
    """กรณีคำถามจากผู้ใช้จริง 'แล้ว sony alpha กับ iphon ล่าสุดอันไหนถ่ายรูปได้ดีกว่า' ต้องได้ CLARIFICATION_NEEDED"""
    settings = get_settings()
    llm = OllamaClient(settings)
    router = RouteIntentUseCase(llm)

    decision = await router.execute("แล้ว sony alpha กับ iphon ล่าสุดอันไหนถ่ายรูปได้ดีกว่า")
    assert decision.intent == IntentType.CLARIFICATION_NEEDED
    assert decision.ambiguity_level >= 0.7
    assert decision.is_comparison is True

@pytest.mark.asyncio
async def test_route_intent_broad_recommendation():
    """คำถามขอคำแนะนำทั่วไป/ทักทายระดับร้าน ต้องได้ CLARIFICATION_NEEDED โดยที่ is_comparison ต้องเป็น False"""
    settings = get_settings()
    llm = OllamaClient(settings)
    router = RouteIntentUseCase(llm)

    decision = await router.execute("สวัสดีครับมีอะไรแนะนำในการเช่าไหม")
    assert decision.intent == IntentType.CLARIFICATION_NEEDED
    assert decision.is_comparison is False
    assert len(decision.slots.target_items) == 0

@pytest.mark.asyncio
async def test_generate_clarification_for_broad_recommendation():
    """คำถามขอคำแนะนำกว้างระดับร้าน ต้องได้แบบสอบถาม General Store Taxonomy ไม่ใช่แบบสอบถามเปรียบเทียบ"""
    settings = get_settings()
    llm = OllamaClient(settings)
    router = RouteIntentUseCase(llm)
    repo = SupabaseRepository(settings)
    cache = MemoryCacheService()
    clarification_uc = GenerateClarificationUseCase(llm, repo, cache)

    query = "สวัสดีครับมีอะไรแนะนำในการเช่าไหม"
    decision = await router.execute(query)
    assert decision.is_comparison is False

    questionnaire = await clarification_uc.execute(query, decision)
    # ต้องได้ 3 ขั้นตอน
    assert len(questionnaire.steps) == 3
    # สเต็ปแรกต้องเป็นการเลือกหมวดหมู่อุปกรณ์ ไม่ใช่การเลือกรุ่นเปรียบเทียบ
    assert questionnaire.steps[0].title == "ต้องการเช่าอุปกรณ์ประเภทใดคะ"
    # ต้องไม่มีคำว่า "อุปกรณ์แรก" ในหัวข้อคำถาม
    for st in questionnaire.steps:
        assert "อุปกรณ์แรก" not in st.title
        assert "อุปกรณ์ที่สอง" not in st.title

@pytest.mark.asyncio
async def test_route_intent_cheaper_alternative_category_isolation():
    """ทดสอบคำถามขอราคาถูกกว่า 'มีที่ถูกกว่านี้ไหม' ต่อเนื่องจากประวัติการสนทนาข้ามหมวดหมู่
    ต้องได้ ITEM_INQUIRY, is_comparison = False, categories = ['คอมพิวเตอร์และอุปกรณ์ไอที'],
    target_items = [] และไม่ดึงกล้องจากประวัติเก่ามาปน
    """
    settings = get_settings()
    llm = OllamaClient(settings)
    router = RouteIntentUseCase(llm)

    history = (
        "user: แนะนำกล้องหน่อย\n"
        "assistant: ขอแนะนำ Sony Alpha A7 IV สำหรับการถ่ายภาพระดับมืออาชีพค่ะ ราคาเช่า 1,200 บาท/วัน\n"
        "user: แล้วเราต้องการเช่าคอม\n"
        "assistant: ขอแนะนำ MacBook Air M2 13 นิ้ว สำหรับการทำงานทั่วไปและพกพาสะดวกค่ะ ราคาเช่า 900 บาท/วัน"
    )

    decision = await router.execute("มีที่ถูกกว่านี้ไหม", history_context=history)

    assert decision.intent == IntentType.ITEM_INQUIRY
    assert decision.is_comparison is False
    assert decision.confidence >= 0.8
    assert decision.ambiguity_level == 0.0
    # ต้องไม่ดึง Sony กล้องจากรอบแรกมาปะปน และไม่ล็อก MacBook Air
    assert len(decision.slots.target_items) == 0
    assert "คอมพิวเตอร์และอุปกรณ์ไอที" in decision.slots.categories
    # เพดานงบประมาณต้องถูกสกัดจากราคาเดิม 900 บาท
    assert decision.slots.budget_max == 900.0



