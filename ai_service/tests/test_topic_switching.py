import pytest
import sys
import os

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from app.core.config import get_settings
from app.infrastructure.llm.ollama_client import OllamaClient
from app.application.use_cases.route_intent import RouteIntentUseCase
from app.domain.entities.intent import IntentType

@pytest.mark.asyncio
async def test_topic_switch_from_gaming_to_phone():
    settings = get_settings()
    llm = OllamaClient(settings)
    router = RouteIntentUseCase(llm)

    history = (
        'assistant: เพื่อช่วยค้นหาอุปกรณ์ที่ตรงใจคุณที่สุด รบกวนเลือกข้อมูลด้านล่างได้เลยนะคะ '
        '(คำตอบช้อยส์ที่เลือก: ต้องการเช่าอุปกรณ์ประเภทใดคะ: เกมและความบันเทิง, '
        'นำไปใช้งานด้านใดเป็นหลักคะ: ปาร์ตี้เกม / งานเลี้ยง, '
        'งบประมาณค่าเช่าที่ตั้งไว้ประมาณเท่าไรคะ: ประหยัด (ไม่เกิน 350 บ./วัน))\n'
        'user: เกมและความบันเทิง, ปาร์ตี้เกม / งานเลี้ยง, ประหยัด (ไม่เกิน 350 บ./วัน)\n'
        'assistant: คุณลูกค้าสามารถเช่าเครื่องเล่นเกมพกพาได้เลยนะคะ\n'
        '### 🎮 Nintendo Switch OLED\n'
        '- ค่าเช่า: 400 บาท/วัน\n'
        '- จุดเด่น: เครื่องเล่นเกมพกพาหน้าจอ OLED 7 นิ้ว\n'
        '- เหมาะสำหรับ: เล่นเกมปาร์ตี้'
    )

    decision = await router.execute('อยากเช่ามือถือ', history_context=history)

    assert decision.intent == IntentType.CLARIFICATION_NEEDED, f'Expected CLARIFICATION_NEEDED, got {decision.intent}'
    assert 'โทรศัพท์และอุปกรณ์สื่อสาร' in decision.slots.categories, f'Categories should include phone, got {decision.slots.categories}'
    for item in decision.slots.target_items:
        assert 'Switch' not in item and 'Nintendo' not in item, f'Old item leaked: {item}'
    assert len(decision.slots.target_items) == 0, f'Expected empty target_items, got {decision.slots.target_items}'

@pytest.mark.asyncio
async def test_topic_switch_with_specific_item():
    settings = get_settings()
    llm = OllamaClient(settings)
    router = RouteIntentUseCase(llm)

    history = (
        'user: เกมและความบันเทิง, ปาร์ตี้เกม / งานเลี้ยง, ประหยัด (ไม่เกิน 350 บ./วัน)\n'
        'assistant: คุณลูกค้าสามารถเช่าเครื่องเล่นเกมพกพาได้เลยนะคะ Nintendo Switch OLED'
    )

    decision = await router.execute('งั้นเปลี่ยนเป็นอยากเช่า iPhone 15 Pro', history_context=history)

    assert decision.intent == IntentType.ITEM_INQUIRY, f'Expected ITEM_INQUIRY, got {decision.intent}'
    assert any('iPhone' in it for it in decision.slots.target_items), f'Expected iPhone in target_items, got {decision.slots.target_items}'
    for item in decision.slots.target_items:
        assert 'Switch' not in item, f'Old item leaked: {item}'
