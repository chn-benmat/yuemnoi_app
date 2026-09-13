"""Unit tests for text_sanitizer utility."""
import pytest
from app.infrastructure.utils.text_sanitizer import (
    is_cjk_char,
    sanitize_thai_output,
    normalize_rental_unit,
)

def test_is_cjk_char():
    # Chinese characters
    assert is_cjk_char("卡") is True
    assert is_cjk_char("片") is True
    assert is_cjk_char("按") is True
    assert is_cjk_char("钮") is True
    
    # Thai characters
    assert is_cjk_char("ก") is False
    assert is_cjk_char("า") is False
    assert is_cjk_char("ร") is False
    assert is_cjk_char("์") is False
    assert is_cjk_char("ด") is False
    
    # English characters and symbols
    assert is_cjk_char("A") is False
    assert is_cjk_char("z") is False
    assert is_cjk_char("1") is False
    assert is_cjk_char("!") is False

def test_sanitize_thai_output():
    # Test case from real user error: "ดูรายละเอียดและกดเช่าได้จาก卡片下方按钮~!"
    raw_text = "ดูรายละเอียดและกดเช่าได้จาก卡片下方按钮~!"
    cleaned = sanitize_thai_output(raw_text)
    assert "卡" not in cleaned
    assert "片" not in cleaned
    assert "按" not in cleaned
    assert "钮" not in cleaned
    assert "~!" not in cleaned
    assert "ดูรายละเอียดและกดเช่าได้จากรายการสินค้าด้านล่าง!" in cleaned

    # Test case with mixed English brand and Chinese slip
    raw_mixed = "แนะนำ Yamaha F310 เหมาะมากครับ 点击查看"
    cleaned_mixed = sanitize_thai_output(raw_mixed)
    assert "Yamaha F310" in cleaned_mixed
    assert "เหมาะมากครับ" in cleaned_mixed
    assert "点击查看" not in cleaned_mixed

def test_normalize_rental_unit():
    assert normalize_rental_unit("daily") == "วัน"
    assert normalize_rental_unit("day") == "วัน"
    assert normalize_rental_unit("hourly") == "ชั่วโมง"
    assert normalize_rental_unit("hour") == "ชั่วโมง"
    assert normalize_rental_unit("monthly") == "เดือน"
    assert normalize_rental_unit("month") == "เดือน"
    assert normalize_rental_unit("วัน") == "วัน"
    assert normalize_rental_unit("") == "วัน"

def test_normalize_thai_english_spacing():
    from app.infrastructure.utils.text_sanitizer import normalize_thai_english_spacing
    
    # Test Thai and English stuck together
    assert normalize_thai_english_spacing("ลู่วิ่งKingSmithเหมาะ") == "ลู่วิ่ง KingSmith เหมาะ"
    # Test Thai and number stuck together
    assert normalize_thai_english_spacing("ราคา350บาท") == "ราคา 350 บาท"
    # Test Markdown bold
    assert normalize_thai_english_spacing("แนะนำรุ่น**Sony A7**ครับ") == "แนะนำรุ่น **Sony A7** ครับ"
    assert normalize_thai_english_spacing("- **ค้นหาและแนะนำอุปกรณ์**: บอกสเปก") == "- **ค้นหาและแนะนำอุปกรณ์**: บอกสเปก"
    assert normalize_thai_english_spacing("- ** ค้นหาและแนะนำอุปกรณ์ **: บอกสเปก") == "- **ค้นหาและแนะนำอุปกรณ์**: บอกสเปก"
    assert normalize_thai_english_spacing("แนะนำรุ่น**กล้อง**ครับ") == "แนะนำรุ่น **กล้อง** ครับ"

def test_sanitize_streaming_token():
    from app.infrastructure.utils.text_sanitizer import sanitize_streaming_token
    
    # Must preserve spaces!
    assert sanitize_streaming_token(" ") == " "
    assert sanitize_streaming_token("  ") == "  "
    # Must preserve newlines!
    assert sanitize_streaming_token("\n") == "\n"
    assert sanitize_streaming_token("\n\n- ") == "\n\n- "
    # Must preserve leading spaces in words
    assert sanitize_streaming_token(" Canon") == " Canon"
    assert sanitize_streaming_token(" EOS") == " EOS"
    # Must filter CJK characters
    assert sanitize_streaming_token("卡片 Canon") == "การ์ดสินค้า Canon"
    assert sanitize_streaming_token("点击") == ""

def test_strip_selection_guide():
    from app.infrastructure.utils.text_sanitizer import strip_selection_guide, strip_selection_guide_if_single

    # Case 1: Multiple items with selection guide and closing sentence
    text_multi = (
        "สำหรับอุปกรณ์ที่ตอบโจทย์การใช้งานของคุณลูกค้า ขอแนะนำรุ่นยอดนิยมดังนี้ค่ะ:\n\n"
        "- **PlayStation 5**\n"
        "  • **ค่าเช่า**: 300 บาท/วัน\n"
        "  • **จุดเด่น**: ภาพระดับ 4K\n"
        "  • **เหมาะสำหรับ**: คอเกม\n\n"
        "- **Nintendo Switch OLED**\n"
        "  • **ค่าเช่า**: 200 บาท/วัน\n"
        "  • **จุดเด่น**: พกพาสะดวก\n"
        "  • **เหมาะสำหรับ**: สายพกพา\n\n"
        "💡 **คำแนะนำในการเลือก**:\n"
        "- **PlayStation 5**: เหมาะสำหรับสายกราฟิก\n"
        "- **Nintendo Switch OLED**: เหมาะสำหรับสายพกพา\n\n"
        "คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติมและกดเช่าจากรายการสินค้าด้านล่างได้เลยนะคะ 😊"
    )
    cleaned_multi = strip_selection_guide(text_multi)
    assert "คำแนะนำในการเลือก" not in cleaned_multi
    assert "PlayStation 5" in cleaned_multi
    assert "Nintendo Switch OLED" in cleaned_multi
    assert "คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติม" in cleaned_multi

    # Case 2: Backward-compatibility alias
    cleaned_alias = strip_selection_guide_if_single(text_multi)
    assert cleaned_alias == cleaned_multi

    # Case 3: Already clean text without selection guide
    text_clean = "- **Canon EOS R50**\n  • **ค่าเช่า**: 450 บาท/วัน"
    assert strip_selection_guide(text_clean) == text_clean

def test_normalize_bullet_properties():
    from app.infrastructure.utils.text_sanitizer import normalize_bullet_properties

    # Unbolded variants
    raw = (
        "• ค่าเช่า: 900 บาท/วัน\n"
        "• จุดเด่น: เร็วและแรง\n"
        "• เหมาะสำหรับ: คนทำงานออฟฟิศ"
    )
    result = normalize_bullet_properties(raw)
    assert "• **ค่าเช่า**: 900 บาท/วัน" in result
    assert "• **จุดเด่น**: เร็วและแรง" in result
    assert "• **เหมาะสำหรับ**: คนทำงานออฟฟิศ" in result

    # Colon inside asterisks or with extra spaces
    raw_mixed = (
        "- **ค่าเช่า:** 900 บาท/วัน\n"
        "• **จุดเด่น :** ชิปประมวลผล M2\n"
        "- **เหมาะสำหรับ **: นักเรียนนักศึกษา"
    )
    result_mixed = normalize_bullet_properties(raw_mixed)
    assert "• **ค่าเช่า**: 900 บาท/วัน" in result_mixed
    assert "• **จุดเด่น**: ชิปประมวลผล M2" in result_mixed
    assert "• **เหมาะสำหรับ**: นักเรียนนักศึกษา" in result_mixed

def test_normalize_product_headings():
    from app.infrastructure.utils.text_sanitizer import normalize_product_headings

    raw = (
        "ขอแนะนำอุปกรณ์ดังนี้ค่ะ\n\n"
        "• 💻 MacBook Air M2 13 นิ้ว\n"
        "• **ค่าเช่า**: 900 บาท/วัน\n"
        "• **จุดเด่น**: ชิปประมวลผล M2\n"
        "• **เหมาะสำหรับ**: คนทำงาน\n"
    )
    result = normalize_product_headings(raw)
    assert "### 💻 MacBook Air M2 13 นิ้ว" in result
    assert "• 💻 MacBook Air M2 13 นิ้ว" not in result

    # Check that it also handles bullet with **
    raw_bullet_bold = (
        "- **MacBook Air M2**\n"
        "• **ค่าเช่า**: 900 บาท/วัน\n"
    )
    result_bullet_bold = normalize_product_headings(raw_bullet_bold)
    assert "### MacBook Air M2" in result_bullet_bold

    # Check that capability bullets mentioning 'จุดเด่น' in the sentence are NOT converted to ### headings
    raw_capabilities = (
        "ฉันคือน้องยืมหน่อย AI ผู้ช่วยที่ปรึกษาการเช่าอุปกรณ์ประจำร้านยืมหน่อยค่ะ\n"
        "- ช่วยแนะนำอุปกรณ์เช่าตามความต้องการ เช่น เกมคอนโซล กล้องวิดีโอ หรือเครื่องใช้ไฟฟ้าต่างๆ\n"
        "- ช่วยวางแผนการใช้งานให้เหมาะสม เช่น การเล่นเกม การตัดต่อวิดีโอ หรืองานสร้างสรรค์\n"
        "- อธิบายข้อจำกัดของอุปกรณ์ เช่น ระบบปฏิบัติการไม่รองรับเกม หรือไม่มีพัดลมระบายความร้อน\n"
        "- เปรียบเทียบอุปกรณ์ให้ชัดเจนระหว่างรุ่นต่างๆ โดยเน้นจุดเด่นและข้อแตกต่างสำคัญ\n\n"
        "คุณลูกค้าสามารถพิมพ์บอกสิ่งที่กำลังมองหา หรือสอบถามข้อมูลเพิ่มเติมได้เลยนะคะ"
    )
    result_cap = normalize_product_headings(raw_capabilities)
    assert "### " not in result_cap
    assert "- ช่วยวางแผนการใช้งานให้เหมาะสม" in result_cap
    assert "- อธิบายข้อจำกัดของอุปกรณ์" in result_cap
    assert "- เปรียบเทียบอุปกรณ์ให้ชัดเจน" in result_cap

def test_normalize_thai_greetings():
    from app.infrastructure.utils.text_sanitizer import normalize_thai_greetings, sanitize_thai_output

    # Case 1: Truncated 'คุณลูก' with double newline before welcome
    raw_broken_newline = (
        "สวัสดีค่ะคุณลูก\n\n"
        "ยินดีต้อนรับสู่ร้านยืมหน่อยนะคะ วันนี้กำลังมองหาอุปกรณ์อะไร หรืออยากให้ช่วยแนะนำชิ้นไหน สอบถามน้องยืมหน่อยได้เลยนะคะ 😊"
    )
    result1 = normalize_thai_greetings(raw_broken_newline)
    assert "คุณลูก " not in result1
    assert "คุณลูก\n" not in result1
    assert "สวัสดีค่ะคุณลูกค้า ยินดีต้อนรับสู่ร้านยืมหน่อยนะคะ" in result1

    # Case 2: Hallucinated suffixes like 'คุณลูกน้อย' or 'คุณลูกinois'
    assert normalize_thai_greetings("สวัสดีค่ะคุณลูกน้อย ยินดีต้อนรับนะคะ") == "สวัสดีค่ะคุณลูกค้า ยินดีต้อนรับนะคะ"
    assert normalize_thai_greetings("สวัสดีค่ะคุณลูกinois ยินดีต้อนรับนะคะ") == "สวัสดีค่ะคุณลูกค้า ยินดีต้อนรับนะคะ"
    assert normalize_thai_greetings("สวัสดีค่ะคุณลูก") == "สวัสดีค่ะคุณลูกค้า"

    # Case 3: Through full sanitize_thai_output
    raw_full = "สวัสดีค่ะคุณลูก\n\nยินดีต้อนรับสู่ร้านยืมหน่อยนะคะ\nวันนี้กำลังมองหาอะไรคะ"
    cleaned_full = sanitize_thai_output(raw_full)
    assert "คุณลูก\n" not in cleaned_full
    assert "สวัสดีค่ะคุณลูกค้า ยินดีต้อนรับสู่ร้านยืมหน่อยนะคะ วันนี้กำลังมองหาอะไรคะ" in cleaned_full

def test_strip_card_cta_if_no_items():
    from app.infrastructure.utils.text_sanitizer import strip_card_cta_if_no_items

    sample = (
        "ปัจจุบันทางร้านยืมหน่อยมี **Sony Alpha A7 IV** ในระบบของร้าน แต่ขณะนี้สินค้ายังไม่พร้อมให้บริการเช่า (อาจอยู่ระหว่างการเช่าหรือรอคิวส่งมอบ) ค่ะ\n\n"
        "คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติมและราคาเช่าของอุปกรณ์ได้ที่การ์ดด้านล่างได้เลยนะคะ"
    )
    cleaned = strip_card_cta_if_no_items(sample)
    assert "การ์ดด้านล่าง" not in cleaned
    assert "คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติม" not in cleaned
    assert "ปัจจุบันทางร้านยืมหน่อยมี **Sony Alpha A7 IV** ในระบบของร้าน แต่ขณะนี้สินค้ายังไม่พร้อมให้บริการเช่า" in cleaned


def test_sanitize_instruction_leakage():
    from app.infrastructure.utils.text_sanitizer import sanitize_instruction_leakage

    # Case 1: Image 2 - Rule leakage at bottom of recommendation
    raw_img2 = (
        "💻 **MacBook Air M2 13 นิ้ว**\n"
        "• **ค่าเช่า**: 900 บาท/วัน\n"
        "• **จุดเด่น**: ชิป Apple M2 แบตเตอรี่อึด 18 ชั่วโมง\n"
        "• **เหมาะสำหรับ**: ผู้ที่ทำงานหรือเรียนออนไลน์\n\n"
        "4. กฎเหล็กเรื่องเพศและสรรพนาม: ใช้ 'ค่ะ' หรือ 'นะคะ' เสมอ และเรียกผู้ใช้ว่า 'คุณลูกค้า'"
    )
    cleaned2 = sanitize_instruction_leakage(raw_img2)
    assert "กฎเหล็กเรื่องเพศและสรรพนาม" not in cleaned2
    assert "MacBook Air M2 13 นิ้ว" in cleaned2

    # Case 2: Image 3/4 - Out-of-catalog prompt echoing 1-6
    raw_img3_4 = (
        "1. แจ้งขออภัยอย่างสุภาพและเป็นมิตรว่า ทางร้านยืมหน่อยยังไม่มีบริการให้เช่าสินค้าหรือหมวดหมู่ประเภทที่ผู้ใช้ต้องการในขณะนี้ค่ะ\n\n"
        "2. สรุปหมวดหมู่หลักที่ทางร้านมีให้บริการพร้อมเช่าในปัจจุบันให้อ่านง่ายและสบายตา เพื่อให้ผู้ใช้ทราบขอบเขตบริการของร้าน:\n"
        "- กล้องและอุปกรณ์ถ่ายภาพ\n"
        "- โทรศัพท์และอุปกรณ์สื่อสาร\n\n"
        "3. เชิญชวนอย่างสุภาพให้ผู้ใช้สอบถามหรือค้นหาอุปกรณ์ในหมวดหมู่อื่น ๆ ที่มีให้บริการในร้านยืมหน่อย กรุณาแจ้งน้องยืมหน่อยได้เลยนะคะ\n\n"
        "4. กฎเหล็ก: ห้ามแนะนำสินค้าที่ไม่เกี่ยวข้องโดยเด็ดขาด\n"
        "5. กฎเหล็กเรื่องเพศและสรรพนาม: แชตบอตเป็นผู้หญิง 100% ต้องลงท้ายด้วย 'ค่ะ' หรือ 'นะคะ' เสมอ\n"
        "6. เว้นวรรคระหว่างภาษาไทยและชื่อภาษาอังกฤษเสมอ และห้ามมีตัวอักษรภาษาจีนเด็ดขาด"
    )
    cleaned3_4 = sanitize_instruction_leakage(raw_img3_4)
    assert "กฎเหล็ก" not in cleaned3_4
    assert "1. แจ้งขออภัย" not in cleaned3_4
    assert "ทางร้านยืมหน่อยยังไม่มีบริการให้เช่าสินค้าหรือหมวดหมู่ประเภทที่ผู้ใช้ต้องการในขณะนี้ค่ะ" in cleaned3_4
    assert "หมวดหมู่สินค้าที่ทางร้านยืมหน่อยมีให้บริการพร้อมเช่าในปัจจุบันค่ะ:" in cleaned3_4
    assert "กล้องและอุปกรณ์ถ่ายภาพ" in cleaned3_4

    # Case 3: Image 5 - Template outline numbers
    raw_img5 = (
        "1. ประโยคเปิดการสนทนา: \"ยินดีต้อนรับคุณลูกค้าสู่ร้านยืมหน่อย! หากคุณกำลังมองหากีตาร์โปร่ง Yamaha F310 คือตัวเลือกที่ดีที่สุดค่ะ\"\n\n"
        "2. สรุปรายละเอียดของรุ่น:\n\n"
        "🎸 **กีตาร์โปร่ง Yamaha F310**\n"
        "• **ค่าเช่า**: 250 บาท/วัน\n"
        "• **จุดเด่น**: เสียงกังวานใส\n"
        "• **เหมาะสำหรับ**: ผู้เริ่มต้น\n\n"
        "3. ย่อหน้าสรุปปิดท้าย: \"คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติมและกดเช่าจากรายการสินค้าด้านล่างได้เลยนะคะ\""
    )
    cleaned5 = sanitize_instruction_leakage(raw_img5)
    assert "1. ประโยคเปิดการสนทนา:" not in cleaned5
    assert "2. สรุปรายละเอียดของรุ่น:" not in cleaned5
    assert "3. ย่อหน้าสรุปปิดท้าย:" not in cleaned5
    assert "ยินดีต้อนรับคุณลูกค้าสู่ร้านยืมหน่อย!" in cleaned5
    assert "กีตาร์โปร่ง Yamaha F310" in cleaned5
    assert "คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติมและกดเช่าจากรายการสินค้าด้านล่างได้เลยนะคะ" in cleaned5


def test_streaming_line_sanitizer_suppresses_header_leakage():
    """ทดสอบ StreamingLineSanitizer ในการดักตัดหัวข้อคำสั่งแบบเรียลไทม์ระหว่างสตรีม (เคสจากภาพที่ 1)."""
    from app.infrastructure.utils.text_sanitizer import StreamingLineSanitizer

    sanitizer = StreamingLineSanitizer()
    stream_chunks = [
        "1",
        ". ",
        "ประโยคเปิดการสนทนา: ",
        '"ยินดีต้อนรับคุณลูกค้า 🎸 สู่โลกแห่งเสียงดนตรีกับกีตาร์โปร่ง Yamaha F310 นะคะ"',
        "\n",
        "2",
        ". ",
        "สรุปรายละเอียดของรุ่น:",
        "\n",
        "### 🎸 กีตาร์โปร่ง Yamaha F310\n",
        "• **ค่าเช่า**: 250 บาท/วัน\n",
        "• **จุดเด่น**: มีเสียงกังวานใส\n",
    ]

    emitted_chunks = []
    for chunk in stream_chunks:
        emitted_chunks.extend(sanitizer.process_token(chunk))
    emitted_chunks.extend(sanitizer.flush())

    full_streamed = "".join(emitted_chunks)

    # ต้องไม่ปรากฏหัวข้อคำสั่งหลุดในสตรีมแม้แต่คำเดียว
    assert "1. ประโยคเปิดการสนทนา:" not in full_streamed
    assert "ประโยคเปิดการสนทนา:" not in full_streamed
    assert "2. สรุปรายละเอียดของรุ่น:" not in full_streamed
    assert "สรุปรายละเอียดของรุ่น:" not in full_streamed
    # ต้องมีเนื้อความจริง
    assert "ยินดีต้อนรับคุณลูกค้า 🎸 สู่โลกแห่งเสียงดนตรีกับกีตาร์โปร่ง Yamaha F310 นะคะ" in full_streamed
    assert "### 🎸 กีตาร์โปร่ง Yamaha F310" in full_streamed
    assert "• **ค่าเช่า**: 250 บาท/วัน" in full_streamed
    # ต้องไม่มีเครื่องหมายคำพูดเปิด-ปิดครอบเนื้อความ
    assert not full_streamed.startswith('"')
    assert not full_streamed.startswith('“')


def test_separate_trailing_card_cta():
    """ทดสอบการแยกประโยคเชิญชวนดูการ์ดที่ติดกับหัวข้อย่อย 'เหมาะสำหรับ' ให้อยู่ในย่อหน้าใหม่ (เคสจากภาพที่ 2)."""
    from app.infrastructure.utils.text_sanitizer import separate_trailing_card_cta

    raw_bullet = (
        "• **เหมาะสำหรับ**: นักดนตรีและผู้ที่ต้องการเรียนรู้การเล่นกีตาร์โปร่ง "
        "\"คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติมและกดเช่าจากรายการสินค้าด้านล่างได้เลยนะคะ หรือหากต้องการคำแนะนำเรื่องอุปกรณ์เสริม สอบถามฉันได้เสมอนะคะ 😊\""
    )
    separated = separate_trailing_card_cta(raw_bullet)

    # ต้องแยกเป็น 2 ส่วนโดยมีบรรทัดว่างคั่น
    parts = separated.split("\n\n")
    assert len(parts) == 2
    assert parts[0].strip() == "• **เหมาะสำหรับ**: นักดนตรีและผู้ที่ต้องการเรียนรู้การเล่นกีตาร์โปร่ง"
    assert "คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติมและกดเช่าจากรายการสินค้าด้านล่างได้เลยนะคะ" in parts[1]
    # ต้องไม่มีเครื่องหมายคำพูดครอบประโยค CTA
    assert not parts[1].startswith('"')
    assert not parts[1].endswith('"')


def test_sanitize_instruction_leakage_unquotes_opening_dialogue():
    """ทดสอบการถอดเครื่องหมายคำพูดครอบประโยคเปิดที่หลงเหลือจากการตัดหัวข้อคำสั่ง."""
    from app.infrastructure.utils.text_sanitizer import sanitize_instruction_leakage

    raw = (
        "1. ประโยคเปิดการสนทนา: \"ยินดีต้อนรับคุณลูกค้า 🎸 สู่โลกแห่งเสียงดนตรีนะคะ\"\n\n"
        "### 🎸 กีตาร์โปร่ง Yamaha F310\n"
        "• **ค่าเช่า**: 250 บาท/วัน"
    )
    cleaned = sanitize_instruction_leakage(raw)

    assert "1. ประโยคเปิดการสนทนา:" not in cleaned
    assert "ยินดีต้อนรับคุณลูกค้า 🎸 สู่โลกแห่งเสียงดนตรีนะคะ" in cleaned
    # ต้องไม่มี " นำหน้าหรือปิดท้ายประโยคเปิด
    first_line = cleaned.split("\n")[0].strip()
    assert not first_line.startswith('"')
    assert not first_line.endswith('"')


def test_trim_verbose_recommendation_intro():
    """ทดสอบการตัดคำต้อนรับเวิ่นเว้อออกจากประโยคเปิดแนะนำสินค้า."""
    from app.infrastructure.utils.text_sanitizer import trim_verbose_recommendation_intro

    raw = (
        "สวัสดีค่ะคุณลูกค้า! ยินดีต้อนรับสู่ร้านยืมหน่อยนะคะ วันนี้เราขอแนะนำ Canon EOS R50 ที่ตอบโจทย์ค่ะ\n\n"
        "### 📸 Canon EOS R50\n"
        "• **ค่าเช่า**: 650 บาท/วัน\n"
        "• **จุดเด่น**: ขนาดกะทัดรัด\n"
        "• **เหมาะสำหรับ**: ถ่ายภาพท่องเที่ยว"
    )
    cleaned = trim_verbose_recommendation_intro(raw)
    assert "ยินดีต้อนรับสู่ร้านยืมหน่อยนะคะ" not in cleaned
    assert "สวัสดีค่ะคุณลูกค้า! วันนี้เราขอแนะนำ Canon EOS R50 ที่ตอบโจทย์ค่ะ" in cleaned


def test_strip_example_clauses():
    """ทดสอบการตัดข้อความยกตัวอย่าง เช่น 'เช่น Sony A7 IV กับ iPhone 15 Pro' ออกจากประโยค."""
    from app.infrastructure.utils.text_sanitizer import strip_example_clauses

    raw_1 = "เพื่อการเปรียบเทียบสเปกที่แม่นยำ รบกวนแจ้งชื่อรุ่นของ Sony และ iPhone ที่สนใจ เช่น Sony A7 IV กับ iPhone 15 Pro ได้เลยนะคะ"
    cleaned_1 = strip_example_clauses(raw_1)
    assert "เช่น" not in cleaned_1
    assert "Sony A7 IV" not in cleaned_1
    assert "iPhone 15 Pro" not in cleaned_1
    assert cleaned_1 == "เพื่อการเปรียบเทียบสเปกที่แม่นยำ รบกวนแจ้งชื่อรุ่นของ Sony และ iPhone ที่สนใจ ได้เลยนะคะ"

    raw_2 = "รบกวนระบุชื่อรุ่นที่ต้องการเปรียบเทียบ (เช่น Sony A7 IV และ iPhone 15 Pro) ได้เลยนะคะ"
    cleaned_2 = strip_example_clauses(raw_2)
    assert "เช่น" not in cleaned_2
    assert cleaned_2 == "รบกวนระบุชื่อรุ่นที่ต้องการเปรียบเทียบ ได้เลยนะคะ"

    raw_3 = "รบกวนระบุชื่อรุ่นที่ต้องการเปรียบเทียบ ตัวอย่างเช่น Canon R50 กับ Sony A6700 ค่ะ"
    cleaned_3 = strip_example_clauses(raw_3)
    assert "ตัวอย่างเช่น" not in cleaned_3
    assert "Canon R50" not in cleaned_3
    assert cleaned_3 == "รบกวนระบุชื่อรุ่นที่ต้องการเปรียบเทียบ ได้เลยค่ะ"

    # ประโยคที่ไม่มีคำว่าเช่น ต้องไม่ถูกตัดทอน
    raw_clean = "ขอทราบชื่อรุ่นเฉพาะของ Sony Alpha และ iPhone ล่าสุดที่ต้องการเปรียบเทียบด้วยนะคะ"
    assert strip_example_clauses(raw_clean) == raw_clean


def test_sanitize_bracketed_prompt_placeholder():
    """ทดสอบว่าข้อความคำสั่งในวงเล็บก้ามปู เช่น [เขียนประโยคสรุปปิดท้าย...] จะถูกแปลงเป็นประโยค CTA ที่ถูกต้อง."""
    from app.infrastructure.utils.text_sanitizer import sanitize_instruction_leakage

    raw = (
        "ขอแนะนำ MacBook Air M2 13 นิ้ว ดังนี้ค่ะ\n\n"
        "### 💻 MacBook Air M2 13 นิ้ว\n"
        "• **ค่าเช่า**: 900 บาท/วัน\n"
        "• **จุดเด่น**: ชิปประมวลผล M2\n"
        "• **เหมาะสำหรับ**: ทำงานทั่วไป\n\n"
        "[เขียนประโยคสรุปปิดท้าย 1 บรรทัด เชิญชวนแตะดูรายละเอียดเพิ่มเติมและกดเช่าจากรายการสินค้าด้านล่าง หรือสอบถามเรื่องอุปกรณ์เสริม]"
    )
    cleaned = sanitize_instruction_leakage(raw)
    assert "[เขียน" not in cleaned
    assert "คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติมและกดเช่าจากรายการสินค้าด้านล่าง หรือสอบถามเรื่องอุปกรณ์เสริมได้เลยนะคะ" in cleaned


def test_streaming_sanitizer_bracketed_closing_leak_recovery():
    """ทดสอบว่า StreamingLineSanitizer ดักจับ [เขียนประโยคสรุปปิดท้าย...] ขณะสตรีมและปล่อยประโยค CTA ที่ถูกต้อง."""
    from app.infrastructure.utils.text_sanitizer import StreamingLineSanitizer

    sanitizer = StreamingLineSanitizer()
    chunks = [
        "ขอแนะนำกล้อง Canon EOS R50 ค่ะ\n\n",
        "### 📸 Canon EOS R50\n",
        "• **ค่าเช่า**: 650 บาท/วัน\n",
        "[เขียนประโยคสรุปปิดท้าย 1 บรรทัด เชิญชวนแตะดูรายละเอียดเพิ่มเติมและกดเช่าจากรายการสินค้าด้านล่าง หรือสอบถามเรื่องอุปกรณ์เสริม]"
    ]
    output = []
    for chunk in chunks:
        for clean in sanitizer.process_token(chunk):
            output.append(clean)
    for flush_clean in sanitizer.flush():
        output.append(flush_clean)

    full_output = "".join(output)
    assert "[เขียน" not in full_output
    assert "คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติมและกดเช่าจากรายการสินค้าด้านล่าง หรือสอบถามเรื่องอุปกรณ์เสริมได้เลยนะคะ" in full_output
