"""โมดูลยูทิลิตี้สำหรับทำความสะอาดข้อความและรับประกันภาษาไทย 100% (Text Sanitizer)."""

def is_cjk_char(char: str) -> bool:
    """ตรวจสอบว่าเป็นอักขระภาษาจีน (CJK) หรือไม่โดยใช้ช่วงรหัส Unicode (Zero-Regex)."""
    code = ord(char)
    return (
        0x4E00 <= code <= 0x9FFF      # CJK Unified Ideographs
        or 0x3400 <= code <= 0x4DBF  # CJK Extension A
        or 0xF900 <= code <= 0xFAFF  # CJK Compatibility Ideographs
        or 0x2E80 <= code <= 0x2EFF  # CJK Radicals
        or 0x3000 <= code <= 0x303F  # CJK Symbols and Punctuation
    )

def is_thai_char(char: str) -> bool:
    """ตรวจสอบว่าเป็นตัวอักษรภาษาไทยหรือไม่ (Unicode Code Point 0x0E01 - 0x0E5B)."""
    return 0x0E01 <= ord(char) <= 0x0E5B

def is_latin_or_digit(char: str) -> bool:
    """ตรวจสอบว่าเป็นตัวอักษรละติน (A-Z, a-z) หรือตัวเลข (0-9) หรือไม่."""
    code = ord(char)
    return (
        0x0041 <= code <= 0x005A
        or 0x0061 <= code <= 0x007A
        or 0x0030 <= code <= 0x0039
    )

def normalize_thai_english_spacing(text: str) -> str:
    """เว้นวรรคระหว่างภาษาไทยและภาษาอังกฤษ/ตัวเลข เพื่อให้อ่านง่ายและไม่ติดเป็นพืด (Zero-Regex)."""
    if not text:
        return text

    # ขั้นตอนที่ 1: ลบช่องว่างส่วนเกินที่อยู่ด้านในของ Markdown Bold delimiter: '** ข้อความ **' -> '**ข้อความ**'
    # เพื่อให้ Markdown Parser (เช่น flutter_markdown) สามารถเรนเดอร์เป็นตัวหนา (Bold) ได้อย่างถูกต้องตามมาตรฐาน CommonMark
    parts = text.split("**")
    if len(parts) > 2:
        for idx in range(1, len(parts) - 1, 2):
            parts[idx] = parts[idx].strip()
        text = "**".join(parts)

    # ขั้นตอนที่ 2: วนลูปตรวจสอบอักขระและเว้นวรรคระหว่างภาษาไทยกับภาษาอังกฤษ/ตัวเลข หรือนอกเครื่องหมาย Bold
    result = []
    n = len(text)
    in_bold = False
    i = 0
    while i < n:
        # ตรวจสอบ Markdown Bold (**)
        if i < n - 1 and text[i] == "*" and text[i + 1] == "*":
            if not in_bold:
                # เปิด Bold: ถ้าอักขระก่อนหน้าเป็นอักษรไทยหรือละติน/ตัวเลข ให้เว้นวรรคด้านนอกก่อนเปิด Bold
                if result and result[-1] not in (" ", "\n", "\t", "-", ">", "[", "("):
                    result.append(" ")
                result.append("**")
                in_bold = True
            else:
                # ปิด Bold: ใส่ ** ปิด แล้วตรวจสอบว่าถ้าอักขระถัดไปเป็นข้อความ ให้เว้นวรรคด้านนอก
                result.append("**")
                in_bold = False
                if i + 2 < n:
                    next_c = text[i + 2]
                    if (is_thai_char(next_c) or is_latin_or_digit(next_c)) and next_c not in " :.,!?)]}\n\t":
                        result.append(" ")
            i += 2
            continue

        c1 = text[i]
        result.append(c1)
        if i < n - 1:
            c2 = text[i + 1]
            # อักษรไทย ชิด อักษรละติน/ตัวเลข หรือกลับกัน
            if (is_thai_char(c1) and is_latin_or_digit(c2)) or (is_latin_or_digit(c1) and is_thai_char(c2)):
                result.append(" ")
        i += 1

    return "".join(result)


def sanitize_thai_output(text: str) -> str:
    """ทำความสะอาดข้อความที่ส่งออกจาก LLM เพื่อรับประกันว่าไม่มีภาษาจีนหรือสัญลักษณ์หลุดรอด.
    
    1. แทนที่คำศัพท์ UI ภาษาจีนที่พบบ่อยให้เป็นคำไทยที่สละสลวย
    2. กรองอักขระ CJK ทุกตัวออก (Zero-Regex)
    3. ปรับปรุงการเว้นวรรคระหว่างภาษาไทยและภาษาอังกฤษให้อ่านง่าย
    4. ปรับแต่งเครื่องหมายวรรคตอน เช่น '~!' ให้เป็น '!'
    """
    if not text:
        return text

    # แทนที่กลุ่มคำภาษาจีนที่เกี่ยวข้องกับ UI ก่อน
    cleaned = text.replace("卡片下方按钮", "รายการสินค้าด้านล่าง")
    cleaned = cleaned.replace("卡片", "การ์ดสินค้า")
    cleaned = cleaned.replace("按钮", "ปุ่ม")

    # กรองอักขระภาษาจีนที่อาจหลงเหลือออกทั้งหมดด้วย Unicode Code Point
    result_chars = [c for c in cleaned if not is_cjk_char(c)]
    cleaned = "".join(result_chars)

    # กรองคำสั่ง Prompt ที่อาจหลุดออกมาจากโมเดล
    instruction_leaks = [
        "1. ประโยคเปิดการสนทนา: ",
        "1. ประโยคเปิดการสนทนา:",
        "ประโยคเปิดการสนทนา: ",
        "ประโยคเปิดการสนทนา:",
        "2. สรุปรายละเอียดของรุ่น: ",
        "2. สรุปรายละเอียดของรุ่น:",
        "สรุปรายละเอียดของรุ่น: ",
        "สรุปรายละเอียดของรุ่น:",
        "2. สรุปรายละเอียดของแต่ละรุ่น: ",
        "2. สรุปรายละเอียดของแต่ละรุ่น:",
        "สรุปรายละเอียดของแต่ละรุ่น: ",
        "สรุปรายละเอียดของแต่ละรุ่น:",
        "3. ข้อห้ามเด็ดขาดเรื่องคำแนะนำในการเลือก: ",
        "3. ข้อห้ามเด็ดขาดเรื่องคำแนะนำในการเลือก:",
        "ข้อห้ามเด็ดขาดเรื่องคำแนะนำในการเลือก:",
        "3. ย่อหน้าสรุปปิดท้าย: ",
        "3. ย่อหน้าสรุปปิดท้าย:",
        "4. ย่อหน้าสรุปปิดท้าย: ",
        "4. ย่อหน้าสรุปปิดท้าย:",
        "ย่อหน้าสรุปปิดท้าย: ",
        "ย่อหน้าสรุปปิดท้าย:",
        "เว้น 1 บรรทัดว่าง",
        "เว้น 1 บรรทัด",
        "🎯 เกริ่นนำสั้นกระชับ\n",
        "🎯 เกริ่นนำสั้นกระชับ",
        "เกริ่นนำสั้นกระชับ\n",
        "เกริ่นนำสั้นกระชับ",
        "หากกำลังตัดสินใจเลือกระหว่างสองรุ่นนี้ ขอสรุปข้อแตกต่างที่สำคัญดังนี้ค่ะ:\n",
        "หากกำลังตัดสินใจเลือกระหว่างสองรุ่นนี้ ขอสรุปข้อแตกต่างที่สำคัญดังนี้ค่ะ:",
    ]
    for leak in instruction_leaks:
        cleaned = cleaned.replace(leak, "")

    # กรองเส้นคั่นแนวนอนที่อาจทำให้หน้าจอรกรุงรัง
    cleaned = cleaned.replace("---\n\n", "")
    cleaned = cleaned.replace("---\n", "")
    cleaned = cleaned.replace("---", "")

    # ปรับปรุงเครื่องหมายวรรคตอนท้ายประโยค
    cleaned = cleaned.replace("~!", "!")
    cleaned = cleaned.replace("~~", "~")

    # เว้นวรรคระหว่างภาษาไทยและอังกฤษ/ตัวเลขให้อ่านง่าย
    cleaned = normalize_thai_english_spacing(cleaned)

    # ทำความสะอาดคำทักทายและสรรพนามลูกค้าให้อ่านเป็นธรรมชาติ
    cleaned = normalize_thai_greetings(cleaned)

    # ปรับปรุงหัวข้อสเปก (ค่าเช่า, จุดเด่น, เหมาะสำหรับ) ให้เป็นตัวหนาสม่ำเสมอ 100%
    cleaned = normalize_bullet_properties(cleaned)

    # ปรับปรุงบรรทัดชื่อสินค้าให้เป็น Heading 3 (###) โดยไม่มี bullet
    cleaned = normalize_product_headings(cleaned)

    # ทำความสะอาดช่องว่างซ้ำซ้อน
    while "  " in cleaned:
        cleaned = cleaned.replace("  ", " ")

    return cleaned.strip()

def normalize_thai_greetings(text: str) -> str:
    """ทำความสะอาดคำทักทายและสรรพนามลูกค้าภาษาไทย ป้องกันคำขาดหรือขึ้นบรรทัดใหม่ผิดที่ (Zero-Regex)."""
    if not text:
        return text

    # ซ่อมแซมคำเรียกผู้ใช้ที่โมเดลอาจตัดทอนหรือหลอนเป็นคำอื่น
    bad_patterns = [
        ("คุณลูกที่มาเยือน", "คุณลูกค้า"),
        ("คุณลูกน้อย", "คุณลูกค้า"),
        ("คุณลูกinois", "คุณลูกค้า"),
        ("คุณลูก\n\n", "คุณลูกค้า "),
        ("คุณลูก\n", "คุณลูกค้า "),
        ("คุณลูก ", "คุณลูกค้า "),
        ("คุณลูก,", "คุณลูกค้า,"),
        ("คุณลูก!", "คุณลูกค้า!"),
        ("คุณลูก.", "คุณลูกค้า."),
        ("คุณลูก?", "คุณลูกค้า?"),
        ("คุณลูก:", "คุณลูกค้า:"),
    ]
    for bad, good in bad_patterns:
        text = text.replace(bad, good)

    # กรณีจบด้วย "คุณลูก"
    suffix = "คุณลูก"
    if text.endswith(suffix):
        text = text[:-len(suffix)] + "คุณลูกค้า"

    # จัดการการขึ้นบรรทัดใหม่ที่ไม่เหมาะสมในประโยคทักทายเปิดหัว เพื่อให้อ่านเป็นย่อหน้าเดียวที่สละสลวย
    greeting_linebreaks = [
        ("สวัสดีค่ะคุณลูกค้า\n\n", "สวัสดีค่ะคุณลูกค้า "),
        ("สวัสดีค่ะคุณลูกค้า\n", "สวัสดีค่ะคุณลูกค้า "),
        ("สวัสดีค่ะ คุณลูกค้า\n\n", "สวัสดีค่ะ คุณลูกค้า "),
        ("สวัสดีค่ะ คุณลูกค้า\n", "สวัสดีค่ะ คุณลูกค้า "),
        ("ยินดีต้อนรับสู่ร้านยืมหน่อยนะคะ\n\n", "ยินดีต้อนรับสู่ร้านยืมหน่อยนะคะ "),
        ("ยินดีต้อนรับสู่ร้านยืมหน่อยนะคะ\n", "ยินดีต้อนรับสู่ร้านยืมหน่อยนะคะ "),
        ("ยินดีต้อนรับสู่ร้านยืมหน่อยนะคะ  \n", "ยินดีต้อนรับสู่ร้านยืมหน่อยนะคะ "),
        ("ยินดีต้อนรับสู่ร้านยืมหน่อยค่ะ\n\n", "ยินดีต้อนรับสู่ร้านยืมหน่อยค่ะ "),
        ("ยินดีต้อนรับสู่ร้านยืมหน่อยค่ะ\n", "ยินดีต้อนรับสู่ร้านยืมหน่อยค่ะ "),
    ]
    for lb, norm in greeting_linebreaks:
        text = text.replace(lb, norm)

    return text

def normalize_bullet_properties(text: str) -> str:
    """ปรับแต่งเครื่องหมายหัวข้อย่อยและรับประกันความสม่ำเสมอของตัวหนา (Zero-Regex).
    
    รับประกันว่า:
    1. '• **ค่าเช่า**:'
    2. '• **จุดเด่น**:'
    3. '• **เหมาะสำหรับ**:'
    เป็นตัวหนาและมีรูปแบบเดียวกัน 100%
    """
    if not text:
        return text

    # รายการชุดคำรูปแบบต่างๆ ของ 'เหมาะสำหรับ' เพื่อแปลงเป็นรูปแบบมาตรฐาน '• **เหมาะสำหรับ**:'
    suitability_variants = [
        "• **เหมาะสำหรับ:**",
        "• **เหมาะสำหรับ :**",
        "• **เหมาะสำหรับ **:",
        "• ** เหมาะสำหรับ **:",
        "• ** เหมาะสำหรับ**:",
        "• เหมาะสำหรับ:",
        "• เหมาะสำหรับ :",
        "- **เหมาะสำหรับ:**",
        "- **เหมาะสำหรับ :**",
        "- **เหมาะสำหรับ **:",
        "- ** เหมาะสำหรับ **:",
        "- ** เหมาะสำหรับ**:",
        "- เหมาะสำหรับ:",
        "- เหมาะสำหรับ :",
        "* **เหมาะสำหรับ:**",
        "* **เหมาะสำหรับ :**",
        "* **เหมาะสำหรับ **:",
        "* เหมาะสำหรับ:",
        "* เหมาะสำหรับ :",
    ]
    for v in suitability_variants:
        text = text.replace(v, "• **เหมาะสำหรับ**:")

    # รายการชุดคำรูปแบบต่างๆ ของ 'จุดเด่น' เพื่อแปลงเป็นรูปแบบมาตรฐาน '• **จุดเด่น**:'
    highlight_variants = [
        "• **จุดเด่น:**",
        "• **จุดเด่น :**",
        "• **จุดเด่น **:",
        "• ** จุดเด่น **:",
        "• ** จุดเด่น**:",
        "• จุดเด่น:",
        "• จุดเด่น :",
        "- **จุดเด่น:**",
        "- **จุดเด่น :**",
        "- **จุดเด่น **:",
        "- ** จุดเด่น **:",
        "- ** จุดเด่น**:",
        "- จุดเด่น:",
        "- จุดเด่น :",
        "* **จุดเด่น:**",
        "* **จุดเด่น :**",
        "* **จุดเด่น **:",
        "* จุดเด่น:",
        "* จุดเด่น :",
    ]
    for v in highlight_variants:
        text = text.replace(v, "• **จุดเด่น**:")

    # รายการชุดคำรูปแบบต่างๆ ของ 'ค่าเช่า' เพื่อแปลงเป็นรูปแบบมาตรฐาน '• **ค่าเช่า**:'
    rent_price_variants = [
        "• **ค่าเช่า:**",
        "• **ค่าเช่า :**",
        "• **ค่าเช่า **:",
        "• ** ค่าเช่า **:",
        "• ** ค่าเช่า**:",
        "• ค่าเช่า:",
        "• ค่าเช่า :",
        "- **ค่าเช่า:**",
        "- **ค่าเช่า :**",
        "- **ค่าเช่า **:",
        "- ** ค่าเช่า **:",
        "- ** ค่าเช่า**:",
        "- ค่าเช่า:",
        "- ค่าเช่า :",
        "* **ค่าเช่า:**",
        "* **ค่าเช่า :**",
        "* **ค่าเช่า **:",
        "* ค่าเช่า:",
        "* ค่าเช่า :",
    ]
    for v in rent_price_variants:
        text = text.replace(v, "• **ค่าเช่า**:")

    return text

def _is_spec_property_line(line: str) -> bool:
    """ตรวจสอบว่าบรรทัดนี้คือบรรทัดหัวข้อคุณสมบัติสินค้าหรือไม่ (เช่น ค่าเช่า, จุดเด่น, เหมาะสำหรับ) (Zero-Regex)."""
    clean = line.strip()
    for prefix in ("- ", "• ", "* ", " - ", " • "):
        if clean.startswith(prefix):
            clean = clean[len(prefix):].strip()
    return (
        clean.startswith("**ค่าเช่า**:")
        or clean.startswith("**จุดเด่น**:")
        or clean.startswith("**เหมาะสำหรับ**:")
        or clean.startswith("ค่าเช่า:")
        or clean.startswith("จุดเด่น:")
        or clean.startswith("เหมาะสำหรับ:")
    )

def normalize_product_headings(text: str) -> str:
    """แปลงบรรทัดชื่อสินค้าที่อาจมีเครื่องหมาย bullet นำหน้าให้เป็น Markdown Heading (###) โดยไม่มี bullet (Zero-Regex)."""
    if not text:
        return text

    lines = text.split("\n")
    n = len(lines)
    for i in range(n):
        line = lines[i].strip()
        if not line:
            continue
        # ตรวจสอบว่าบรรทัดถัดไป (1-2 บรรทัด) เป็นบรรทัดสเปกของสินค้าจริงหรือไม่
        has_spec_next = False
        for offset in (1, 2):
            if i + offset < n:
                next_line = lines[i + offset].strip()
                if _is_spec_property_line(next_line):
                    has_spec_next = True
                    break

        if has_spec_next:
            # ตรวจสอบว่าไม่ใช่บรรทัดสเปกเอง
            if not _is_spec_property_line(line):
                clean_line = line
                # ถอดเครื่องหมาย bullet นำหน้า (-, •, *) ออก
                for prefix in ("- ", "• ", "* ", " - ", " • "):
                    if clean_line.startswith(prefix):
                        clean_line = clean_line[len(prefix):].strip()

                # หากยังไม่ได้ขึ้นต้นด้วย ### ให้ใส่ ### นำหน้า
                if not clean_line.startswith("###"):
                    if clean_line.startswith("##"):
                        clean_line = "#" + clean_line
                    else:
                        clean_line = f"### {clean_line}"

                # ถอด ** ภายนอกออกถ้ามี เช่น ### **MacBook** -> ### MacBook
                if clean_line.startswith("### **") and clean_line.endswith("**"):
                    clean_line = "### " + clean_line[6:-2].strip()

                lines[i] = clean_line

    return "\n".join(lines)

def strip_selection_guide(text: str) -> str:
    """ตัดบล็อก 'คำแนะนำในการเลือก' ออกจากการตอบกลับแนะนำสินค้าทั้งหมด 100% (Zero-Regex)."""
    if not text:
        return text

    triggers = [
        "💡 **คำแนะนำในการเลือก**:",
        "**คำแนะนำในการเลือก**:",
        "💡 คำแนะนำในการเลือก:",
        "คำแนะนำในการเลือก:",
        "💡 **คำแนะนำการเลือก**:",
        "**คำแนะนำการเลือก**:",
        "💡 คำแนะนำการเลือก:",
        "คำแนะนำการเลือก:",
        "💡 **คำแนะนำในการเลือก**",
        "**คำแนะนำในการเลือก**",
        "💡 คำแนะนำในการเลือก",
        "คำแนะนำในการเลือก",
    ]
    for trigger in triggers:
        if trigger in text:
            parts = text.split(trigger, 1)
            prefix = parts[0]
            suffix = parts[1]
            
            # ค้นหาประโยคสรุปปิดท้ายที่อาจอยู่ถัดจากบล็อกคำแนะนำในการเลือก
            closing_triggers = [
                "คุณลูกค้าสามารถ",
                "สามารถแตะดู",
                "สามารถกดดู",
                "สามารถคลิกดู",
                "สามารถดูรายละเอียด",
                "หากคุณลูกค้าต้องการ",
                "หากต้องการคำแนะนำ",
                "หากมีข้อสงสัย",
            ]
            closing_part = ""
            for close_trig in closing_triggers:
                if close_trig in suffix:
                    closing_part = close_trig + suffix.split(close_trig, 1)[1]
                    break

            if closing_part:
                return (prefix.strip() + "\n\n" + closing_part.strip()).strip()
            return prefix.strip()

    return text.strip()

# Alias เพื่อความเข้ากันได้ย้อนหลัง
strip_selection_guide_if_single = strip_selection_guide

def strip_card_cta_if_no_items(text: str) -> str:
    """ตัดประโยคเชิญชวนดูการ์ดสินค้าด้านล่างออกเมื่อไม่มีสินค้าพร้อมเช่า (Zero-Regex)."""
    if not text:
        return text

    triggers = [
        "คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติมและราคาเช่าของอุปกรณ์ได้ที่การ์ดด้านล่างได้เลยนะคะ",
        "คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติมและราคาเช่าได้ที่การ์ดด้านล่างได้เลยนะคะ",
        "คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติมได้ที่การ์ดด้านล่างได้เลยนะคะ",
        "สามารถแตะดูรายละเอียดเพิ่มเติมและราคาเช่าของอุปกรณ์ได้ที่การ์ดด้านล่างได้เลยนะคะ",
        "สามารถแตะดูรายละเอียดเพิ่มเติมและราคาเช่าได้ที่การ์ดด้านล่างได้เลยนะคะ",
        "สามารถแตะดูรายละเอียดเพิ่มเติมได้ที่การ์ดด้านล่างได้เลยนะคะ",
        "สามารถแตะดูรายละเอียดได้ที่การ์ดด้านล่างได้เลยนะคะ",
        "สามารถแตะดูรายละเอียดและราคาที่การ์ดด้านล่างได้เลยค่ะ",
        "แตะดูรายละเอียดเพิ่มเติมและราคาเช่าของอุปกรณ์ได้ที่การ์ดด้านล่างได้เลยนะคะ",
        "แตะดูรายละเอียดเพิ่มเติมได้ที่การ์ดด้านล่างได้เลยนะคะ",
        "สามารถแตะดูรายละเอียดที่การ์ดด้านล่างได้เลยค่ะ",
        "สามารถแตะดูรายละเอียดเพิ่มเติมที่การ์ดด้านล่างได้เลยค่ะ",
    ]
    cleaned = text
    for trig in triggers:
        if trig in cleaned:
            cleaned = cleaned.replace(trig, "")

    lines = [line.strip() for line in cleaned.split("\n")]
    result_lines = []
    for line in lines:
        if line:
            result_lines.append(line)
        elif result_lines and result_lines[-1] != "":
            result_lines.append("")

    return "\n".join(result_lines).strip()


def sanitize_streaming_token(token: str) -> str:
    """ทำความสะอาดโทเค็นสตรีมมิ่ง โดยกรองเฉพาะอักขระ CJK ออก และรักษาช่องว่างกับการขึ้นบรรทัดใหม่อย่างสมบูรณ์ 100% (Zero-Regex)."""
    if not token:
        return ""

    cleaned = token.replace("卡片下方按钮", "รายการสินค้าด้านล่าง")
    cleaned = cleaned.replace("卡片", "การ์ดสินค้า")
    cleaned = cleaned.replace("按钮", "ปุ่ม")
    cleaned = cleaned.replace("~!", "!")

    # กรองเฉพาะอักขระ CJK ออก โดยเด็ดขาดไม่เรียก .strip() เพื่อรักษาช่องว่างและบรรทัดใหม่อย่างสมบูรณ์
    result_chars = [c for c in cleaned if not is_cjk_char(c)]
    return "".join(result_chars)

def normalize_rental_unit(unit: str) -> str:
    """แปลงหน่วยการเช่าภาษาอังกฤษเป็นภาษาไทย (เช่น daily -> วัน, hourly -> ชั่วโมง)."""
    if not unit:
        return "วัน"
    
    clean = unit.strip().lower()
    unit_map = {
        "daily": "วัน",
        "day": "วัน",
        "hourly": "ชั่วโมง",
        "hour": "ชั่วโมง",
        "monthly": "เดือน",
        "month": "เดือน",
        "weekly": "สัปดาห์",
        "week": "สัปดาห์",
    }
    return unit_map.get(clean, unit)


def strip_citation_badges(text: str) -> str:
    """Zero-regex removal of numeric citation badges like [1], [2], [3], (1), (2)."""
    if not text:
        return text
    cleaned = text
    for i in range(1, 20):
        cleaned = cleaned.replace(f"[{i}]", "")
        cleaned = cleaned.replace(f"({i})", "")
    return cleaned

def sanitize_instruction_leakage(text: str) -> str:
    """ตัดหัวข้อคำสั่ง, หมายเลขขั้นตอน และบรรทัดกฎเกณฑ์ (Prompt Leakage) ออกจากข้อความ 100% (Zero-Regex)."""
    if not text:
        return text

    # ลบป้ายตัวเลขอ้างอิงก่อน
    text = strip_citation_badges(text)

    # รายการข้อความบ่งชี้กฎเกณฑ์ที่ไม่ควรแสดงให้ผู้ใช้เห็นเลยแม้แต่บรรทัดเดียว
    forbidden_substrings = [
        "กฎเหล็ก",
        "กฎเรื่องชื่อรุ่นสินค้า",
        "ตอบตรงประเด็นทันที",
        "เปรียบเทียบความแตกต่างสำคัญแบบหมวดหมู่ชนหมวดหมู่",
        "แชตบอตเป็นผู้หญิง 100%",
        "เว้นวรรคระหว่างภาษาไทยและชื่อภาษาอังกฤษ",
        "ห้ามมีตัวอักษรภาษาจีน",
        "ห้ามแนะนำสินค้าที่ไม่เกี่ยวข้องโดยเด็ดขาด",
        "ไม่ต้องแนะนำสินค้าทดแทนที่ขัดแย้งกับความต้องการ",
        "ห้ามนำบริบทถ่ายภาพไปใส่ให้คอมพิวเตอร์",
        "ห้ามใส่คำนำหน้าหัวข้อว่า 'เกริ่นนำ'",
        "ห้ามพิมพ์หัวข้อคำสั่ง",
        "ห้ามใส่หัวข้อ 'คำแนะนำในการเลือก'",
    ]

    # หัวข้อคำสั่งที่ต้องตัดทั้งบรรทัดทิ้ง
    lines_to_remove = [
        "2. สรุปรายละเอียดของรุ่น:",
        "สรุปรายละเอียดของรุ่น:",
        "2. สรุปรายละเอียดของแต่ละรุ่น:",
        "สรุปรายละเอียดของแต่ละรุ่น:",
        "คำสั่งในการตอบ:",
        "คำสั่ง: ตอบตามรูปแบบ Markdown",
        "ข้อห้ามเด็ดขาดเรื่องคำแนะนำในการเลือก:",
    ]

    # คำนำหน้าหัวข้อโครงสร้างที่ต้องสกัดเอาเฉพาะเนื้อความ
    header_prefixes_to_strip = [
        "1. ประโยคเปิดการสนทนา (1 บรรทัด):",
        "1. ประโยคเปิดการสนทนา:",
        "ประโยคเปิดการสนทนา:",
        "3. ย่อหน้าสรุปปิดท้าย:",
        "ย่อหน้าสรุปปิดท้าย:",
        "4. ย่อหน้าสรุปปิดท้าย:",
        "1. แจ้งขออภัยอย่างสุภาพและเป็นมิตรว่า",
        "แจ้งขออภัยอย่างสุภาพและเป็นมิตรว่า",
        "3. เชิญชวนอย่างสุภาพให้ผู้ใช้สอบถามหรือค้นหาอุปกรณ์ในหมวดหมู่อื่น ๆ ที่มีให้บริการในร้านยืมหน่อย กรุณาแจ้งน้องยืมหน่อยได้เลยนะคะ",
        "3. เชิญชวนอย่างสุภาพให้ผู้ใช้สอบถามหรือค้นหาอุปกรณ์ในหมวดหมู่อื่น ๆ ที่มีให้บริการในร้านยืมหน่อย",
        "3. เชิญชวนอย่างสุภาพให้ผู้ใช้สอบถามหรือค้นหาอุปกรณ์ในหมวดหมู่ที่มีให้บริการได้เสมอ:",
        "3. เชิญชวนอย่างสุภาพให้ผู้ใช้สอบถามหรือค้นหาอุปกรณ์ในหมวดหมู่ที่มีให้บริการได้เสมอ",
        "เชิญชวนอย่างสุภาพให้ผู้ใช้สอบถามหรือค้นหาอุปกรณ์ในหมวดหมู่ที่มีให้บริการได้เสมอ",
    ]

    lines = text.split("\n")
    cleaned_lines = []

    for line in lines:
        line_strip = line.strip()
        if not line_strip:
            cleaned_lines.append("")
            continue

        # 1. ตรวจสอบว่ามีข้อความกฎเกณฑ์ต้องห้ามหรือไม่ ถ้ามีให้ข้ามบรรทัดนี้ทิ้ง
        if any(sub in line_strip for sub in forbidden_substrings):
            continue

        # 2. ตรวจสอบบรรทัดที่เป็นหัวข้อคำสั่งล้วนๆ หรือคำสั่งรั่วไหลในวงเล็บก้ามปู
        if any(line_strip == r or line_strip.startswith(r) for r in lines_to_remove):
            continue

        if (line_strip.startswith("[") and ("เขียน" in line_strip or "ประโยค" in line_strip)) or \
           ("เขียนประโยคสรุปปิดท้าย" in line_strip) or ("เขียนประโยคเปิด" in line_strip):
            if "ปิดท้าย" in line_strip or "เชิญชวน" in line_strip or "เช่า" in line_strip or "อุปกรณ์เสริม" in line_strip:
                cleaned_lines.append("คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติมและกดเช่าจากรายการสินค้าด้านล่าง หรือสอบถามเรื่องอุปกรณ์เสริมได้เลยนะคะ")
            continue

        # 3. จัดการบรรทัดสรุปหมวดหมู่ เช่น "2. สรุปหมวดหมู่หลักที่ทางร้านมีให้บริการพร้อมเช่า..."
        if "สรุปหมวดหมู่หลักที่ทางร้านมีให้บริการ" in line_strip:
            cleaned_lines.append("หมวดหมู่สินค้าที่ทางร้านยืมหน่อยมีให้บริการพร้อมเช่าในปัจจุบันค่ะ:")
            continue

        # 4. สกัด prefix ของหัวข้อคำสั่งออก
        processed_line = line_strip
        for prefix in header_prefixes_to_strip:
            if processed_line.startswith(prefix):
                processed_line = processed_line[len(prefix):].strip()
                break

        # ถ้ามีเครื่องหมายคำพูดครอบประโยคทั้งบรรทัด ให้ตัดออก (ป้องกันเครื่องหมาย " ตกค้าง)
        if (processed_line.startswith('"') and processed_line.endswith('"')) or \
           (processed_line.startswith('“') and processed_line.endswith('”')):
            processed_line = processed_line[1:-1].strip()

        # ถ้าสกัดแล้วเหลือข้อความเปล่า แสดงว่าเป็นแค่หัวข้อ
        if not processed_line:
            continue

        cleaned_lines.append(processed_line)

    # รวมบรรทัดและทำความสะอาดบรรทัดว่างซ้ำซ้อน
    result = []
    for line in cleaned_lines:
        if line != "":
            result.append(line)
        elif result and result[-1] != "":
            result.append("")

    full_cleaned = "\n".join(result).strip()
    # แยกประโยค CTA ปิดท้ายที่อาจติดอยู่ท้ายบรรทัดคุณสมบัติสินค้าให้อยู่ในย่อหน้าใหม่
    return separate_trailing_card_cta(full_cleaned)


def separate_trailing_card_cta(text: str) -> str:
    """แยกประโยคเชิญชวนดูการ์ดด้านล่างที่อาจติดอยู่ท้ายบรรทัดคุณสมบัติสินค้า (bullet point) ให้ขึ้นบรรทัดใหม่ (Zero-Regex)."""
    if not text:
        return text

    cta_markers = [
        "คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติมและกดเช่าจากรายการสินค้าด้านล่างได้เลยนะคะ",
        "คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติมและกดเช่าจากรายการสินค้าด้านล่าง",
        "คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติมและราคาเช่า",
        "คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติม",
        "คุณลูกค้าสามารถแตะดูข้อมูลเพิ่มเติม",
        "สามารถแตะดูรายละเอียดเพิ่มเติมและกดเช่าจากรายการสินค้าด้านล่างได้เลยนะคะ",
        "สามารถแตะดูรายละเอียดเพิ่มเติมและกดเช่าจากรายการสินค้าด้านล่าง",
        "สามารถแตะดูรายละเอียดเพิ่มเติม",
    ]

    lines = text.split("\n")
    processed_lines = []

    for line in lines:
        clean_line = line.strip()
        is_bullet = clean_line.startswith(("-", "•", "*"))
        if is_bullet:
            found_marker = None
            found_idx = -1
            for marker in cta_markers:
                idx = clean_line.find(marker)
                if idx != -1:
                    found_marker = marker
                    found_idx = idx
                    break

            if found_marker is not None and found_idx > 0:
                bullet_part = clean_line[:found_idx].strip()
                while bullet_part.endswith(('"', '“', ' ')):
                    bullet_part = bullet_part[:-1].strip()

                cta_part = clean_line[found_idx:].strip()
                if (cta_part.startswith('"') and cta_part.endswith('"')) or \
                   (cta_part.startswith('“') and cta_part.endswith('”')):
                    cta_part = cta_part[1:-1].strip()
                elif cta_part.endswith(('"', '”')):
                    cta_part = cta_part[:-1].strip()

                processed_lines.append(bullet_part)
                processed_lines.append("")
                processed_lines.append(cta_part)
                continue

        processed_lines.append(line)

    # ถ้าบรรทัดสุดท้ายเป็นประโยค CTA เชิญชวนแตะดูการ์ดที่ยังไม่จบบริบูรณ์ (จบที่ 'ด้านล่าง') ให้เติม 'ได้เลยนะคะ' ให้สุภาพและสมบูรณ์
    if processed_lines and processed_lines[-1].strip().endswith("ด้านล่าง"):
        processed_lines[-1] = processed_lines[-1].strip() + "ได้เลยนะคะ"

    return "\n".join(processed_lines)


def trim_verbose_recommendation_intro(text: str) -> str:
    """ตัดข้อความเกริ่นต้อนรับหรือคำทักทายเวิ่นเว้อในประโยคเปิดแนะนำสินค้าออก (Zero-Regex).
    
    ช่วยให้ประโยคเปิดสั้นกระชับ ตรงประเด็น ไม่เกริ่นยาวตามที่ผู้ใช้ต้องการ
    """
    if not text:
        return text

    # ดำเนินการเฉพาะข้อความที่มีโครงสร้างแนะนำสินค้า
    has_items = (
        "• **ค่าเช่า**:" in text
        or "• ค่าเช่า:" in text
        or "• **จุดเด่น**:" in text
        or "### " in text
    )
    if not has_items:
        return text

    welcome_phrases = [
        "ยินดีต้อนรับสู่ร้านยืมหน่อยนะคะ! ",
        "ยินดีต้อนรับสู่ร้านยืมหน่อยนะคะ ",
        "ยินดีต้อนรับสู่ร้านยืมหน่อยค่ะ! ",
        "ยินดีต้อนรับสู่ร้านยืมหน่อยค่ะ ",
        "ยินดีต้อนรับสู่ร้านยืมหน่อย! ",
        "ยินดีต้อนรับสู่ร้านยืมหน่อย ",
        "ยินดีต้อนรับสู่ร้าน ยืมหน่อยนะคะ! ",
        "ยินดีต้อนรับสู่ร้าน ยืมหน่อยนะคะ ",
        "ยินดีต้อนรับสู่ร้าน ยืมหน่อยค่ะ! ",
        "ยินดีต้อนรับสู่ร้าน ยืมหน่อยค่ะ ",
    ]
    for phrase in welcome_phrases:
        text = text.replace(phrase, "")

    return text


class StreamingLineSanitizer:
    """ตัวกรองโทเคนระดับบรรทัดสำหรับการสตรีมแบบเรียลไทม์ (Zero-Regex).
    
    บัฟเฟอร์ข้อความช่วงเริ่มต้นของแต่ละบรรทัด เพื่อตรวจจับและตัดหัวข้อคำสั่ง/กฎเกณฑ์
    (เช่น '1. ประโยคเปิดการสนทนา: ', '2. สรุปรายละเอียดของรุ่น:') ออกก่อนส่งไปยังไคลเอนต์แบบเรียลไทม์
    ป้องกันไม่ให้ผู้ใช้มองเห็นหัวข้อคำสั่งหลุดบนหน้าจอขณะพิมพ์ (ขจัดปัญหาหน้าจอกระตุกเมื่อสตรีมจบ).
    """

    FORBIDDEN_PREFIXES = [
        "1. ประโยคเปิดการสนทนา (1 บรรทัด):",
        "1. ประโยคเปิดการสนทนา:",
        "1. ประโยคเปิด (1 บรรทัด):",
        "1. ประโยคเปิด:",
        "ประโยคเปิดการสนทนา (1 บรรทัด):",
        "ประโยคเปิดการสนทนา:",
        "ประโยคเปิด (1 บรรทัด):",
        "ประโยคเปิด:",
        "2. สรุปรายละเอียดของรุ่น:",
        "สรุปรายละเอียดของรุ่น:",
        "2. สรุปรายละเอียดของแต่ละรุ่น:",
        "สรุปรายละเอียดของแต่ละรุ่น:",
        "2. รายละเอียดสินค้า:",
        "2. รายละเอียดของแต่ละรุ่น:",
        "รายละเอียดสินค้า:",
        "รายละเอียดของแต่ละรุ่น:",
        "3. ย่อหน้าสรุปปิดท้าย:",
        "ย่อหน้าสรุปปิดท้าย:",
        "4. ย่อหน้าสรุปปิดท้าย:",
        "3. ประโยคปิดท้าย (1 บรรทัด):",
        "3. ประโยคปิดท้าย:",
        "ประโยคปิดท้าย (1 บรรทัด):",
        "ประโยคปิดท้าย:",
        "[เขียนประโยคสรุปปิดท้าย",
        "[เขียนประโยคเปิด",
        "[เขียน",
        "เขียนประโยคสรุปปิดท้าย",
        "เขียนประโยคเปิด",
        "3. ข้อห้ามเด็ดขาดเรื่องคำแนะนำในการเลือก:",
        "ข้อห้ามเด็ดขาดเรื่องคำแนะนำในการเลือก:",
        "คำสั่งในการตอบ:",
        "คำสั่ง: ตอบตามรูปแบบ Markdown",
        "1. แจ้งขออภัยอย่างสุภาพและเป็นมิตรว่า",
        "แจ้งขออภัยอย่างสุภาพและเป็นมิตรว่า",
        "3. เชิญชวนอย่างสุภาพให้ผู้ใช้สอบถามหรือค้นหาอุปกรณ์ในหมวดหมู่อื่น ๆ",
        "3. เชิญชวนอย่างสุภาพให้ผู้ใช้สอบถามหรือค้นหาอุปกรณ์ในหมวดหมู่ที่มีให้บริการได้เสมอ:",
        "3. เชิญชวนอย่างสุภาพให้ผู้ใช้สอบถามหรือค้นหาอุปกรณ์ในหมวดหมู่ที่มีให้บริการได้เสมอ",
        "เชิญชวนอย่างสุภาพให้ผู้ใช้สอบถามหรือค้นหาอุปกรณ์ในหมวดหมู่ที่มีให้บริการได้เสมอ",
    ]

    FORBIDDEN_SUBSTRINGS = [
        "เขียนประโยคสรุปปิดท้าย",
        "เขียนประโยคเปิด",
        "กฎเหล็ก",
        "แชตบอตเป็นผู้หญิง 100%",
        "เว้นวรรคระหว่างภาษาไทย",
        "ห้ามพิมพ์หัวข้อคำสั่ง",
        "ห้ามใส่คำนำหน้าหัวข้อว่า",
    ]

    def __init__(self):
        self.buffer = ""
        self.is_buffering_line = True
        self.discard_current_line = False
        self.just_stripped_prefix = False
        self.stripped_opening_quote = False
        self.discarded_closing_leak = False

    def _is_potential_prefix(self, text: str) -> bool:
        """ตรวจสอบว่าข้อความในบัฟเฟอร์มีโอกาสเป็นส่วนหนึ่งของหัวข้อต้องห้ามหรือไม่ (Zero-Regex)."""
        stripped = text.strip()
        if not stripped:
            return True
        return any(
            p.startswith(stripped) or stripped.startswith(p)
            for p in self.FORBIDDEN_PREFIXES
        ) or any(
            sub in stripped for sub in self.FORBIDDEN_SUBSTRINGS
        )

    def process_token(self, raw_token: str) -> list[str]:
        """ประมวลผลโทเคนเดี่ยวและคืนค่ารายการโทเคนที่สะอาดแล้วสำหรับส่ง SSE delta (Zero-Regex)."""
        clean_token = sanitize_streaming_token(raw_token)
        if not clean_token:
            return []

        out_chunks: list[str] = []

        for char in clean_token:
            if char == "\n":
                if self.discard_current_line:
                    self.buffer = ""
                    self.discard_current_line = False
                    self.is_buffering_line = True
                    self.just_stripped_prefix = False
                    self.stripped_opening_quote = False
                    continue

                if self.is_buffering_line:
                    buf_strip = self.buffer.strip()
                    if any(buf_strip == p or buf_strip.startswith(p) for p in self.FORBIDDEN_PREFIXES) or \
                       any(sub in buf_strip for sub in self.FORBIDDEN_SUBSTRINGS):
                        self.buffer = ""
                    else:
                        out_chunks.append(self.buffer + "\n")
                        self.buffer = ""
                else:
                    if self.stripped_opening_quote and out_chunks and out_chunks[-1].endswith(('"', '”')):
                        out_chunks[-1] = out_chunks[-1][:-1]
                    out_chunks.append("\n")

                self.is_buffering_line = True
                self.discard_current_line = False
                self.just_stripped_prefix = False
                self.stripped_opening_quote = False
                continue

            if self.discard_current_line:
                continue

            if self.is_buffering_line:
                self.buffer += char
                buf_strip = self.buffer.strip()

                # ตรวจจับข้อความกฎเกณฑ์ที่ต้องทิ้งทั้งบรรทัด
                if any(sub in buf_strip for sub in self.FORBIDDEN_SUBSTRINGS):
                    if "ปิดท้าย" in buf_strip or "สรุปปิดท้าย" in buf_strip or "เชิญชวน" in buf_strip:
                        self.discarded_closing_leak = True
                    self.discard_current_line = True
                    self.buffer = ""
                    continue

                # ตรวจสอบว่าตรงกับ prefix ต้องห้ามตัวใดตัวหนึ่งเต็มรูปแบบ
                matched_prefix = None
                for p in self.FORBIDDEN_PREFIXES:
                    if buf_strip.startswith(p):
                        matched_prefix = p
                        break

                if matched_prefix is not None:
                    if "ปิดท้าย" in matched_prefix or "สรุปปิดท้าย" in matched_prefix or "[เขียน" in matched_prefix:
                        self.discarded_closing_leak = True
                        self.discard_current_line = True
                        self.buffer = ""
                        continue

                    remainder = buf_strip[len(matched_prefix):].strip()
                    if remainder.startswith(('"', '“')):
                        remainder = remainder[1:].strip()
                        self.stripped_opening_quote = True
                    self.buffer = ""
                    self.is_buffering_line = False
                    self.just_stripped_prefix = True
                    if remainder:
                        out_chunks.append(remainder)
                    continue

                # ถ้าข้อความไม่ใช่ prefix ต้องห้ามแน่นอน หรือบัฟเฟอร์ยาวเกิน 40 ตัวอักษร
                if not self._is_potential_prefix(buf_strip) or len(buf_strip) > 40:
                    self.is_buffering_line = False
                    out_chunks.append(self.buffer)
                    self.buffer = ""
            else:
                # กำลังสตรีมเนื้อหาของบรรทัด
                if self.just_stripped_prefix and char in ('"', '“', ' '):
                    if char in ('"', '“'):
                        self.stripped_opening_quote = True
                        self.just_stripped_prefix = False
                    continue
                self.just_stripped_prefix = False
                out_chunks.append(char)

        if out_chunks:
            return ["".join(out_chunks)]
        return []

    def flush(self) -> list[str]:
        """ปล่อยข้อความที่ยังค้างอยู่ในบัฟเฟอร์เมื่อสิ้นสุดสตรีม."""
        if self.discard_current_line or not self.buffer:
            self.buffer = ""
            if self.discarded_closing_leak:
                self.discarded_closing_leak = False
                return ["\n\nคุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติมและกดเช่าจากรายการสินค้าด้านล่าง หรือสอบถามเรื่องอุปกรณ์เสริมได้เลยนะคะ"]
            return []
        buf_strip = self.buffer.strip()
        if any(buf_strip == p or buf_strip.startswith(p) for p in self.FORBIDDEN_PREFIXES) or \
           any(sub in buf_strip for sub in self.FORBIDDEN_SUBSTRINGS):
            is_closing = self.discarded_closing_leak or ("ปิดท้าย" in buf_strip or "สรุปปิดท้าย" in buf_strip or "[เขียน" in buf_strip)
            self.buffer = ""
            if is_closing:
                return ["\n\nคุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติมและกดเช่าจากรายการสินค้าด้านล่าง หรือสอบถามเรื่องอุปกรณ์เสริมได้เลยนะคะ"]
            return []
        res = [self.buffer]
        self.buffer = ""
        return res

def strip_example_clauses(text: str) -> str:
    """ตัดข้อความยกตัวอย่าง เช่น 'เช่น Sony A7 IV กับ iPhone 15 Pro' ออกจากประโยค เพื่อให้ลูกค้าพิมพ์รุ่นเองอย่างอิสระ (Zero-Regex)."""
    if not text:
        return text

    # กรณีที่ 1: ยกตัวอย่างในวงเล็บ เช่น '(เช่น Sony A7 IV กับ iPhone 15 Pro)'
    while "(" in text and ")" in text:
        start = text.find("(")
        end = text.find(")", start)
        if end != -1:
            inside = text[start + 1:end]
            if "เช่น" in inside:
                text = (text[:start].rstrip() + " " + text[end + 1:].lstrip()).strip()
            else:
                break
        else:
            break

    # กรณีที่ 2: ' ตัวอย่างเช่น ', ' เช่น ', หรือ 'เช่น ' ในประโยค
    for marker in (" ตัวอย่างเช่น ", " เช่น ", "เช่น "):
        if marker in text:
            parts = text.split(marker, 1)
            prefix = parts[0].rstrip()
            suffix = parts[1].strip()

            # หาคำลงท้ายสุภาพใน suffix เช่น 'ได้เลยนะคะ', 'ได้เลยค่ะ', 'นะคะ', 'ค่ะ'
            polite_tail = ""
            for ending in ("ได้เลยนะคะ", "ได้เลยค่ะ", "นะคะ", "ค่ะ"):
                if suffix.endswith(ending):
                    polite_tail = ending
                    break

            if polite_tail:
                if not prefix.endswith(("นะคะ", "ค่ะ", "ได้เลย")):
                    if polite_tail in ("นะคะ", "ค่ะ"):
                        text = f"{prefix} ได้เลย{polite_tail}"
                    else:
                        text = f"{prefix} {polite_tail}"
                else:
                    text = prefix
            else:
                if not prefix.endswith(("นะคะ", "ค่ะ")):
                    text = f"{prefix} ได้เลยนะคะ"
                else:
                    text = prefix
            break

    return text.strip()

