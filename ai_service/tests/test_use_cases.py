import pytest
import sys
import os

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.core.container import get_container
from app.application.dtos.chat_dto import ChatRequestDTO

@pytest.mark.asyncio
async def test_process_chat_clarification_flow():
    container = get_container()
    use_case = container.process_chat_message_use_case

    req = ChatRequestDTO(message="อยากเช่าของไปเที่ยวสักหน่อย")
    res = await use_case.execute(req)

    assert res.response != ""
    assert res.intent in ["CLARIFICATION_NEEDED", "ITEM_INQUIRY"]

@pytest.mark.asyncio
async def test_process_chat_item_inquiry():
    container = get_container()
    use_case = container.process_chat_message_use_case

    req = ChatRequestDTO(message="ตอนนี้มีกล้อง Sony ให้เช่าไหมครับ")
    res = await use_case.execute(req)

    assert res.intent == "ITEM_INQUIRY"
    assert len(res.items) > 0

@pytest.mark.asyncio
async def test_process_chat_capabilities_query():
    container = get_container()
    use_case = container.process_chat_message_use_case

    from app.application.dtos.chat_dto import ChatMessageDTO
    req = ChatRequestDTO(
        message="ทำไรได้",
        history=[
            ChatMessageDTO(role="assistant", content="สวัสดีค่ะ ฉันคือ Yuemnoi ผู้ช่วยแนะนำอุปกรณ์เช่า มีอะไรให้ช่วยวันนี้คะ"),
            ChatMessageDTO(role="user", content="กล้องและอุปกรณ์ถ่ายภาพ"),
            ChatMessageDTO(role="assistant", content="เพื่อช่วยคัดสรรอุปกรณ์ที่เหมาะกับคุณที่สุด ต้องการกล้องสำหรับงานประเภทใดคะ")
        ]
    )
    res = await use_case.execute(req)

    assert res.intent == "GENERAL_CHAT"
    assert len(res.items) == 0
    assert "Yuemnoi" in res.response or "ยืมหน่อย" in res.response
    assert "สวัสดีค่ะ ฉันคือ Yuemnoi ผู้ช่วยแนะนำอุปกรณ์เช่า มีอะไรให้ช่วยวันนี้คะ" not in res.response

@pytest.mark.asyncio
async def test_process_chat_item_spec_inquiry():
    container = get_container()
    use_case = container.process_chat_message_use_case

    req = ChatRequestDTO(message="กล้อง canon สามารถขนาดเท่าไร")
    res = await use_case.execute(req)

    assert res.intent == "ITEM_SPEC_INQUIRY"
    assert res.response != ""
    assert any(k in res.response for k in ["มม", "mm", "ขนาด", "มิติ", "กรัม", "g", "น้ำหนัก"])

@pytest.mark.asyncio
async def test_process_chat_gaming_feasibility_inquiry():
    container = get_container()
    use_case = container.process_chat_message_use_case

    from app.application.dtos.chat_dto import ChatMessageDTO
    req = ChatRequestDTO(
        message="mackbook air เหมาะเอามาเล่นเกมจริงดิ",
        history=[
            ChatMessageDTO(role="user", content="อยากเช่าคอมเอาไว้เล่นเกมที่บ้าน"),
            ChatMessageDTO(role="assistant", content="คัดสรรแล็ปท็อปประสิทธิภาพสูงมาให้เหมาะกับการเล่นเกมและใช้งานบนโต๊ะบ้านค่ะ - MacBook Air M2 13 นิ้ว")
        ]
    )
    res = await use_case.execute(req)

    assert res.intent == "ITEM_SPEC_INQUIRY"
    assert res.response != ""
    # Must NOT recite dimensions or weight when asked about gaming suitability
    assert "กว้าง × สูง" not in res.response
    assert "กว้าง x สูง" not in res.response
    # Should address gaming, macOS, or games
    assert any(k in res.response.lower() for k in ["เกม", "game", "macos", "พัดลม", "apple"])

@pytest.mark.asyncio
async def test_process_chat_battery_inquiry():
    container = get_container()
    use_case = container.process_chat_message_use_case

    req = ChatRequestDTO(message="MacBook Air M2 แบตเตอรี่ใช้งานได้กี่ชั่วโมง")
    res = await use_case.execute(req)

    assert res.intent == "ITEM_SPEC_INQUIRY"
    assert res.response != ""
    # Should answer hours / battery
    assert any(k in res.response for k in ["ชั่วโมง", "ชม.", "18", "15", "แบต"])
    # Must NOT recite width x height x depth dimensions
    assert "กว้าง × สูง" not in res.response
    assert "กว้าง x สูง" not in res.response

@pytest.mark.asyncio
async def test_process_chat_item_not_in_catalog():
    container = get_container()
    use_case = container.process_chat_message_use_case

    req = ChatRequestDTO(message="อยากเช่าเสื้อ")
    res = await use_case.execute(req)

    assert res.intent == "ITEM_INQUIRY"
    assert res.response != ""
    # Must NOT return any items (empty list)
    assert len(res.items) == 0
    # Must NOT recommend drill, projector, or tent
    assert "สว่าน" not in res.response
    assert "เต็นท์" not in res.response
    assert "Bosch" not in res.response
    # Should politely inform that the shop has no clothes/apparel, or apologize
    assert any(k in res.response for k in ["ขออภัย", "ยังไม่มี", "ไม่มีบริการ", "เสื้อ"])

@pytest.mark.asyncio
async def test_process_chat_gaming_pivot_after_macbook():
    container = get_container()
    use_case = container.process_chat_message_use_case
    from app.application.dtos.chat_dto import ChatMessageDTO

    history = [
        ChatMessageDTO(role="user", content="แล้วถ้าอยากเช่าคอมไปทำงานเอกสารทั่วไปมีแนะนำไรบ้าง"),
        ChatMessageDTO(role="assistant", content="MacBook Air M2 13 นิ้ว: แล็ปท็อปบางเบา เหมาะสำหรับทำงานเอกสารทั่วไป พกพาสะดวก แบตเตอรี่อึดตลอดวัน"),
        ChatMessageDTO(role="user", content="แล้วถ้าเอา mackbook ari ไปเล่นเกมได้ไหม"),
        ChatMessageDTO(role="assistant", content="MacBook Air M2 13 นิ้ว เป็นแล็ปท็อปที่เน้นความบางเบาและไม่มีพัดลมระบายความร้อน จึงอาจไม่เหมาะสมสำหรับผู้ใช้งานที่ต้องการเล่นเกมอย่างต่อเนื่องค่ะ")
    ]
    req = ChatRequestDTO(
        message="งั้นแนะนำอุปกรณ์เล่นเกมหน่อย",
        history=history
    )
    res = await use_case.execute(req)

    assert res.intent == "ITEM_INQUIRY"
    assert len(res.items) > 0
    item_names = [it.name for it in res.items]
    # Must recommend gaming console (PS5 or Nintendo Switch)
    assert any("PlayStation" in name or "Nintendo" in name for name in item_names)
    # Must NOT recommend MacBook Air or Guitar
    assert not any("MacBook" in name for name in item_names)
    assert not any("กีตาร์" in name for name in item_names)

@pytest.mark.asyncio
async def test_process_chat_comparison_with_history_inheritance():
    container = get_container()
    use_case = container.process_chat_message_use_case
    from app.application.dtos.chat_dto import ChatMessageDTO

    history = [
        ChatMessageDTO(role="user", content="อยากได้มือถือไปถ่ายคอนเสิร์ต"),
        ChatMessageDTO(role="assistant", content="ขอแนะนำ iPhone 15 Pro สำหรับการถ่ายวิดีโอและซูมภาพในคอนเสิร์ตค่ะ")
    ]
    req = ChatRequestDTO(
        message="แล้ว iPhone 15 Pro ที่แนะนำ กับ Canon EOS R50 ต่างกันยังไง",
        history=history
    )
    res = await use_case.execute(req)

    assert res.intent == "RENTAL_COMPARISON"
    assert res.comparison is not None
    assert res.comparison.search_query is not None
    assert "iPhone 15 Pro" in res.comparison.search_query
    assert len(res.comparison.sources) > 0
    assert len(res.items) > 0

@pytest.mark.asyncio
async def test_process_chat_comparison_out_of_catalog_approach_1():
    container = get_container()
    use_case = container.process_chat_message_use_case

    req = ChatRequestDTO(message="Nikon Z30 กับ Canon R50 ต่างกันไง")
    res = await use_case.execute(req)

    assert res.intent == "RENTAL_COMPARISON"
    assert res.comparison is not None
    assert len(res.comparison.sources) > 0
    # Canon EOS R50 in store should be attached
    assert len(res.items) > 0
    assert any("Canon" in item.name for item in res.items)
    assert res.response != ""

@pytest.mark.asyncio
async def test_process_chat_open_ended_comparison_triggers_clarification():
    """คำถามเปรียบเทียบปลายเปิด เช่น 'แล้ว sony alpha กับ iphon ล่าสุดอันไหนถ่ายรูปได้ดีกว่า' ต้องได้ CLARIFICATION_NEEDED พร้อมข้อความขอให้ผู้ใช้ระบุรุ่น (ไม่มีคำถามหรือช้อยส์บังคับเลือก)"""
    container = get_container()
    use_case = container.process_chat_message_use_case

    req = ChatRequestDTO(message="แล้ว sony alpha กับ iphon ล่าสุดอันไหนถ่ายรูปได้ดีกว่า")
    res = await use_case.execute(req)

    assert res.intent == "CLARIFICATION_NEEDED"
    assert res.clarification is not None
    assert len(res.clarification.questions) == 0
    assert len(res.clarification.options) == 0
    assert res.response != ""
    assert "เช่น" not in res.response

@pytest.mark.asyncio
async def test_process_chat_comparison_out_of_catalog_no_alternatives():
    """เปรียบเทียบอุปกรณ์ที่ไม่มีในร้านทั้งคู่ ต้องไม่นำสินค้าทางเลือกในหมวดเดียวกันมาแนะนำเด็ดขาด (No Alternatives)"""
    container = get_container()
    use_case = container.process_chat_message_use_case

    req = ChatRequestDTO(message="Fujifilm X-T5 กับ Nikon Zfc ต่างกันยังไง")
    res = await use_case.execute(req)

    assert res.intent == "RENTAL_COMPARISON"
    assert res.comparison is not None
    # ทั้งสองรุ่นไม่มีในร้านยืมหน่อย -> matched_items ต้องเป็นลิสต์ว่าง 100%
    assert len(res.items) == 0
    assert res.response != ""
    # ต้องระบุว่าไม่มีให้บริการเช่าในร้านยืมหน่อย
    assert any(k in res.response for k in ["ไม่มีให้บริการ", "ยังไม่มี", "ขออภัย", "ไม่มี"])

@pytest.mark.asyncio
async def test_process_chat_spec_inquiry_unavailable_item():
    """สอบถามสเปกอุปกรณ์ที่มีในระบบของร้านแต่สถานะเป็น unavailable (เช่น Sony Alpha A7 IV)
    ต้องแจ้งว่ามีในระบบ แต่ยังไม่พร้อมให้บริการเช่า (ห้ามบอกว่าร้านไม่มีสินค้านี้เด็ดขาด)
    และต้องไม่แสดงการ์ดเช่าสินค้า (items = []) พร้อมตัดประโยคเชิญชวนดูการ์ดออก
    """
    container = get_container()
    use_case = container.process_chat_message_use_case

    req = ChatRequestDTO(message="กล้อง sony a7 iv ถ่ายตอนกลางคืนดีไหม")
    res = await use_case.execute(req)

    assert res.intent == "ITEM_SPEC_INQUIRY"
    assert res.response != ""
    # ต้องแจ้งว่ามีในระบบ แต่ยังไม่พร้อมเช่า
    assert "ยังไม่พร้อมให้บริการเช่า" in res.response or "ไม่พร้อม" in res.response
    # ต้องไม่บอกว่าทางร้านไม่มีรุ่นนี้
    assert "ยังไม่มีกล้อง Sony" not in res.response
    # ต้องไม่แนบการ์ดสินค้าเพราะยังไม่พร้อมเช่า
    assert len(res.items) == 0
    # ต้องไม่ชวนแตะดูการ์ดด้านล่าง
    assert "การ์ดด้านล่าง" not in res.response

@pytest.mark.asyncio
async def test_process_chat_questionnaire_smartphone_recommendation():
    """ทดสอบกรณีผู้ใช้ตอบแบบสอบถาม (Questionnaire Follow-up) เช่น
    'สมาร์ตโฟนจอใหญ่สำหรับทำงาน, ประชุมออนไลน์ / สตรีม, ตามความเหมาะสม / ไม่จำกัด'
    ต้องไม่ตกเป็น Out-of-Catalog (ห้ามบอกว่าร้านไม่มีบริการสมาร์ตโฟนจอใหญ่)
    แต่ต้องแมตช์เข้าหมวดโทรศัพท์และแนะนำสมาร์ตโฟนในร้าน เช่น Samsung Galaxy S24 Ultra หรือ iPhone 15 Pro
    """
    container = get_container()
    use_case = container.process_chat_message_use_case
    from app.application.dtos.chat_dto import ChatMessageDTO

    req = ChatRequestDTO(
        message="สมาร์ตโฟนจอใหญ่สำหรับทำงาน, ประชุมออนไลน์ / สตรีม, ตามความเหมาะสม / ไม่จำกัด",
        history=[
            ChatMessageDTO(role="user", content="อยากได้มือถือ"),
            ChatMessageDTO(role="assistant", content="ยินดีแนะนำค่ะ เพื่อให้อุปกรณ์ตอบโจทย์ที่สุด ขอสอบถามรูปแบบการใช้งานเพิ่มเติมดังนี้ค่ะ...")
        ]
    )
    res = await use_case.execute(req)

    assert res.intent == "ITEM_INQUIRY"
    # ต้องมีสินค้าแนะนำในร้าน เช่น Samsung Galaxy S24 Ultra หรือ iPhone
    assert len(res.items) > 0
    item_names = [it.name for it in res.items]
    assert any("Samsung" in t or "iPhone" in t or "Galaxy" in t for t in item_names)
    # ต้องไม่บอกว่าทางร้านไม่มีให้บริการ
    assert "ไม่มีบริการ" not in res.response
    assert "ไม่มีในระบบ" not in res.response
    assert "ไม่มีหมวดหมู่นี้" not in res.response

@pytest.mark.asyncio
async def test_process_chat_guitar_recommendation_no_instruction_leakage():
    """ทดสอบกรณีผู้ใช้สอบถามเช่ากีตาร์ (เช่น กีตาร์โปร่งสำหรับฝึกเล่น หรือมีกีตาร์ให้เช่าไหม)
    และข้อความตอบกลับต้องไม่มีหัวข้อคำสั่งรั่วไหล (เช่น 1. ประโยคเปิดการสนทนา หรือ 2. สรุปรายละเอียดของรุ่น)
    ประโยคเปิดต้องไม่มีเครื่องหมายคำพูดครอบ และประโยคปิดท้ายชวนดูการ์ดต้องเว้นวรรคบรรทัดใหม่อย่างเรียบร้อย
    """
    container = get_container()
    use_case = container.process_chat_message_use_case
    from app.application.dtos.chat_dto import ChatMessageDTO

    req = ChatRequestDTO(
        message="กีตาร์โปร่งสำหรับฝึกซ้อม, เล่นทั่วไป, ตามความเหมาะสม",
        history=[
            ChatMessageDTO(role="user", content="อยากเช่ากีต้าร์"),
            ChatMessageDTO(role="assistant", content="ยินดีแนะนำค่ะ เพื่อให้อุปกรณ์ตอบโจทย์ที่สุด ขอสอบถามรูปแบบการใช้งานเพิ่มเติมดังนี้ค่ะ...")
        ]
    )
    res = await use_case.execute(req)

    assert res.intent == "ITEM_INQUIRY"
    assert len(res.items) > 0
    assert any("Yamaha" in it.name or "F310" in it.name for it in res.items)

    # ตรวจสอบว่าไม่มีหัวข้อคำสั่งรั่วไหลออกมาในคำตอบ
    assert "ประโยคเปิดการสนทนา" not in res.response
    assert "สรุปรายละเอียดของรุ่น" not in res.response
    assert "1. " not in res.response
    assert "2. " not in res.response

    # ประโยคเปิดต้องไม่มีเครื่องหมายคำพูด " หรือ “ ครอบ
    first_line = res.response.strip().split("\n")[0].strip()
    assert not (first_line.startswith('"') and first_line.endswith('"'))
    assert not (first_line.startswith('“') and first_line.endswith('”'))

    # ตรวจสอบว่าประโยคชวนดูการ์ด (ถ้ามี) ต้องไม่ติดกับ bullet point ในบรรทัดเดียวกัน
    for line in res.response.splitlines():
        if line.strip().startswith("•") or line.strip().startswith("-"):
            assert "คุณลูกค้าสามารถแตะดูรายละเอียด" not in line
            assert "แตะดูการ์ด" not in line


@pytest.mark.asyncio
async def test_process_chat_camera_recommendation_concise_intro():
    """ทดสอบกรณีแนะนำกล้อง (เช่น Canon EOS R50) ประโยคเปิดต้องสั้นกระชับ ไม่เกริ่นยาว
    ห้ามทักทายเวิ่นเว้อ เช่น 'ยินดีต้อนรับสู่ร้านยืมหน่อย' หรือ 'ใช่ไหมคะ?'
    และห้ามใส่สเปกยาว เช่น เซนเซอร์ APS-C หรือความละเอียด ในประโยคเปิด
    """
    container = get_container()
    use_case = container.process_chat_message_use_case
    from app.application.dtos.chat_dto import ChatMessageDTO

    req = ChatRequestDTO(
        message="กล้องมิเรอร์เลสพร้อมใช้งานสำหรับฝึกหัดถ่ายภาพ, ถ่ายภาพท่องเที่ยว, ตามความเหมาะสม",
        history=[
            ChatMessageDTO(role="user", content="อยากเช่ากล้อง"),
            ChatMessageDTO(
                role="assistant",
                content="ยินดีแนะนำค่ะ เพื่อให้อุปกรณ์ตอบโจทย์ที่สุด ขอสอบถามรูปแบบการใช้งานเพิ่มเติมดังนี้ค่ะ..."
            )
        ]
    )
    res = await use_case.execute(req)

    assert res.intent == "ITEM_INQUIRY"
    assert len(res.items) > 0
    assert any("Canon" in it.name or "R50" in it.name for it in res.items)

    # ตรวจสอบประโยคเปิดก่อนเริ่มรายการสินค้า
    intro_paragraph = res.response.strip().split("\n\n")[0].strip()

    # ต้องไม่ยาวเกินไป (สั้นกระชับ 1 ประโยค)
    assert len(intro_paragraph) <= 250, f"Intro is too long ({len(intro_paragraph)} chars): {intro_paragraph}"

    # ต้องไม่กล่าวต้อนรับเวิ่นเว้อซ้ำซ้อน หรือถามย้อนความต้องการ
    assert "ยินดีต้อนรับสู่ร้านยืมหน่อย" not in intro_paragraph
    assert "ใช่ไหมคะ" not in intro_paragraph

    # ต้องไม่สปอยล์สเปกละเอียดล่วงหน้าในประโยคเปิด
    assert "24.2" not in intro_paragraph
    assert "APS-C" not in intro_paragraph


@pytest.mark.asyncio
async def test_process_chat_comparison_broad_brands_resolves_to_specific_models():
    """ทดสอบกรณีผู้ใช้ถามเปรียบเทียบโดยใช้ชื่อแบรนด์กว้างๆ (เช่น iphon กับ cannon)
    ระบบต้องจับคู่กับสินค้าในร้าน (iPhone 15 Pro และ Canon EOS R50)
    และสร้างคำค้นหา Google ที่ระบุชื่อรุ่นเฉพาะเจาะจง ห้ามเป็นเพียง 'iPhone vs Canon'
    และคำตอบต้องไม่มีข้อมูลของ Canon EOS R5 (รุ่นเรือธงนอกร้าน)
    """
    container = get_container()
    use_case = container.process_chat_message_use_case
    from app.application.dtos.chat_dto import ChatMessageDTO

    history = [
        ChatMessageDTO(role="user", content="แนะนำกล้องหน่อย"),
        ChatMessageDTO(role="assistant", content="ทางร้านขอแนะนำ Canon EOS R50 กล้อง Mirrorless ขนาดกะทัดรัด พร้อมเลนส์คิท 18-45mm ค่าเช่า 650 บาท/วัน ค่ะ"),
        ChatMessageDTO(role="user", content="แนะนำโทรศัพท์หน่อย"),
        ChatMessageDTO(role="assistant", content="ทางร้านขอแนะนำ iPhone 15 Pro 128GB สมาร์ตโฟนระดับเรือธง ชิป A17 Pro ค่าเช่า 800 บาท/วัน ค่ะ")
    ]
    req = ChatRequestDTO(
        message="แล้ว iphon กับ cannon อันไหนเหมาะไปถ่ายรูปตัวเองลงใน ไอจีมากกว่ากัน",
        history=history
    )
    res = await use_case.execute(req)

    assert res.intent == "RENTAL_COMPARISON"
    assert res.comparison is not None
    assert res.comparison.search_query is not None

    # ตรวจสอบว่าคำค้นหาต้องเจาะจงรุ่น ไม่ใช่คำกว้างๆ
    query = res.comparison.search_query.lower()
    assert "canon eos r50" in query or "r50" in query, f"Expected R50 in query, got: {res.comparison.search_query}"
    assert "iphone 15 pro" in query or "15 pro" in query, f"Expected iPhone 15 Pro in query, got: {res.comparison.search_query}"
    assert query.strip() != "iphone vs canon specs comparison รีวิว"

    # ต้องมีสินค้าที่จับคู่ได้ทั้ง 2 รุ่นแนบไปในการ์ด
    assert len(res.items) == 2
    item_names = [it.name for it in res.items]
    assert any("iPhone 15 Pro" in n for n in item_names)
    assert any("Canon EOS R50" in n for n in item_names)

    # คำตอบต้องไม่มีการ hallucinate รุ่น Canon EOS R5 นอกร้าน
    assert "canon eos r5 " not in res.response.lower()
    assert "canon r5 " not in res.response.lower()
    assert "45mp" not in res.response.lower()

@pytest.mark.asyncio
async def test_process_chat_cheaper_alternative_isolated_category():
    """ทดสอบกรณีผู้ใช้ถาม 'มีที่ถูกกว่านี้ไหม' หลังจากแนะนำ MacBook Air (900 บ./วัน)
    แม้จะมีประวัติคุยเรื่องกล้อง Sony Alpha A7 IV ในรอบแรก
    ระบบต้องจัดเป็น ITEM_INQUIRY ไม่ใช่ RENTAL_COMPARISON หรือ CLARIFICATION_NEEDED
    และต้องแนะนำอุปกรณ์ในหมวดคอมพิวเตอร์ที่ราคาถูกกว่า 900 บาท เช่น Dell UltraSharp หรือ iPad Pro
    โดยไม่มีการนำกล้อง Sony มาปะปน
    """
    container = get_container()
    use_case = container.process_chat_message_use_case
    from app.application.dtos.chat_dto import ChatMessageDTO, ChatRequestDTO

    # Pre-cache models to ensure fast run
    await container.cache_service.set(f"{container.query_items_use_case.CACHE_KEY}:models", {})

    history = [
        ChatMessageDTO(role="user", content="แนะนำกล้องหน่อย"),
        ChatMessageDTO(role="assistant", content="ขอแนะนำ Sony Alpha A7 IV สำหรับการถ่ายภาพระดับมืออาชีพค่ะ ราคาเช่า 1,200 บาท/วัน"),
        ChatMessageDTO(role="user", content="แล้วเราต้องการเช่าคอม"),
        ChatMessageDTO(role="assistant", content="ขอแนะนำ MacBook Air M2 13 นิ้ว สำหรับการทำงานทั่วไปและพกพาสะดวกค่ะ ราคาเช่า 900 บาท/วัน")
    ]

    req = ChatRequestDTO(
        message="มีที่ถูกกว่านี้ไหม",
        history=history
    )
    res = await use_case.execute(req)

    assert res.intent == "ITEM_INQUIRY"
    assert res.clarification is None
    assert len(res.items) > 0
    # ทุกสินค้าต้องอยู่ในหมวดคอมพิวเตอร์และอุปกรณ์ไอที
    for item in res.items:
        assert "คอมพิวเตอร์" in item.category or "ไอที" in item.category
        assert "sony" not in item.name.lower()
        assert "กล้อง" not in item.category
    # สรุปตอบสั้นกระชับแบบ B
    assert "ขอแนะนำ" in res.response
    assert "Sony" not in res.response



