import json
import logging
import re
from typing import Any, AsyncGenerator, Dict, List, Optional

from config import settings
from ..llm.ollama_client import OllamaClient
from ..tools.database_tool import DatabaseTool
from .stream_parser import StreamJsonParser

logger = logging.getLogger("uvicorn.error")


class YuemnoiConsultantService:
    """
    Intelligent, consultative rental AI service powered by local LLM (Typhoon 2 8B / Qwen 3 8B) and Supabase.
    Follows Gemini 3.8 Flash conversational patterns:
    - High accuracy, grounded in Supabase inventory
    - Never sorts by ID; ranks by semantic relevance and value
    - Proactively asks clarifying questions when queries are broad (mode: questionnaire)
    - Directly answers platform policies and FAQs without forcing product cards (mode: general_chat)
    - Recommends 1-3 tailored items with structured Markdown when context is clear (mode: recommendation)
    """

    GREETING_PATTERN = re.compile(
        r"^(สวัสดี|หวัดดี|ดีครับ|ดีค่ะ|hello|hi|hey|สวัสดียาม|ทักทาย)[\s!.,คะค่ะครับจ้าจ้ะ~]*$",
        re.IGNORECASE,
    )

    CAPABILITY_PATTERNS = [
        r"ทำ(อะไร|ไร)ได้บ้าง",
        r"ช่วย(อะไร|ไร)ได้บ้าง",
        r"มีอะไรให้ช่วยบ้าง",
        r"มีความสามารถอะไร",
        r"มี(ฟีเจอร์|ฟังก์ชัน)อะไร",
        r"ทำหน้าที่อะไร",
        r"(แอป|แอพ|ระบบ|บอท|ai|เว็บ|แพลตฟอร์ม)(นี้|ยืมน้อย)?.*ทำ(อะไร|ไร)ได้บ้าง",
        r"(แอป|แอพ|ระบบ|บอท|ai|เว็บ|แพลตฟอร์ม)(นี้|ยืมน้อย)?.*ช่วย(อะไร|ไร)ได้บ้าง",
        r"what can you do",
        r"what do you do",
        r"how can you help",
    ]

    IDENTITY_PATTERNS = [
        r"^(คุณ|เธอ|นาย|บอท|ai|you)\s*(คือ|เป็น)\s*ใคร",
        r"^แนะนำตัว(หน่อย|สิ|ครับ|ค่ะ|จ้า)*",
        r"who are you",
    ]

    ACKNOWLEDGEMENT_PATTERNS = [
        r"^(ขอบคุณ|ขอบใจ|thanks|thank you)(มาก|มากๆ|หลายๆ)?[\s!.,คะค่ะครับจ้าจ้ะ~]*$",
        r"^(โอเค|ok|okay|รับทราบ|เข้าใจแล้ว|สุดยอด|เยี่ยมเลย|เจ๋ง)(เลย|มาก|มากๆ)?[\s!.,คะค่ะครับจ้าจ้ะ~]*$",
    ]

    GENERAL_INQUIRY_PATTERNS = [
        r"^(สอบถามหน่อย|มีเรื่องจะถาม|ขอถามหน่อย|สอบถามครับ|สอบถามค่ะ)[\s!.,คะค่ะครับจ้าจ้ะ~]*$",
    ]

    FAQ_PATTERNS = [
        r"ประกัน", r"ความเสียหาย", r"ของพัง", r"ชำรุด", r"ทำหาย", r"สูญหาย", r"เคลม",
        r"มัดจำ", r"เงินประกัน", r"คืนมัดจำ", r"ส่งของ", r"จัดส่ง", r"นัดรับ", r"รับของ",
        r"ค่าส่ง", r"ขั้นตอนการเช่า", r"เช่ายังไง", r"ยืมยังไง", r"วิธีเช่า", r"เงื่อนไข",
        r"ใช้เอกสาร", r"เอกสารอะไร", r"เอกสารการเช่า", r"เอกสารที่ต้องใช้", r"เอกสารประกอบ", r"บัตรประชาชน", r"สำเนา",
        r"ยกเลิก", r"ชำระเงิน", r"จ่ายเงิน", r"มีหน้าร้านไหม", r"อยู่ที่ไหน",
        r"ปล่อยเช่า", r"นำของมาปล่อย", r"เอาของมาปล่อย", r"ลงของปล่อยเช่า", r"อยากให้เช่า", r"วิธีให้เช่า", r"ขั้นตอนให้เช่า", r"ลงประกาศ",
    ]

    IN_SCOPE_TERMS = [
        # Rental & Lending
        "เช่า", "ยืม", "ปล่อยเช่า", "ให้เช่า", "ผู้เช่า", "ผู้ให้เช่า",
        "ของเช่า", "อุปกรณ์", "ของใช้", "สินค้า", "ของ",
        # Platform & Services
        "yuemnoi", "ยืมน้อย", "แพลตฟอร์ม", "แอป", "แอพ", "ระบบ",
        "มัดจำ", "ประกัน", "เคลม", "ความเสียหาย", "ชำรุด", "พัง", "หาย",
        "จัดส่ง", "ส่งของ", "นัดรับ", "รับของ", "ค่าส่ง", "พัสดุ", "แมส",
        "จอง", "ยกเลิก", "ชำระ", "จ่ายเงิน", "โอนเงิน", "คืนเงิน", "ราคา", "ค่าเช่า",
        "ขั้นตอน", "วิธี", "เงื่อนไข", "กฎ", "นโยบาย", "ติดต่อ", "หน้าร้าน", "ร้าน",
        "ลงของ", "ลงประกาศ", "สร้างรายได้", "ลงทะเบียน",
        # Recommendations & Inquiries
        "มีอะไร", "แนะนำ", "ช่วยเลือก", "หาของ", "ใช้อะไร", "มีไหม", "มีมั้ย", "มีป่าว",
        # Greetings & Acknowledgements
        "สวัสดี", "หวัดดี", "ดีครับ", "ดีค่ะ", "hello", "hi", "ขอบคุณ", "ขอบใจ", "thanks", "ok", "โอเค",
    ]

    BROAD_ACTIVITIES = [
        "เดินป่า", "เดินเขา", "ปีนเขา", "ขึ้นเขา", "แคมป์", "แคมปิ้ง", "กางเต็นท์", "เที่ยว", "ทริป",
        "ถ่ายรูป", "ถ่ายภาพ", "ถ่ายวิดีโอ", "ทำคลิป", "vlog", "พอร์ตเทรต",
        "จัดงาน", "ปาร์ตี้", "สัมมนา", "อีเวนต์", "งานแต่ง", "งานแต่งงาน",
        "ดนตรี", "เล่นดนตรี", "ซ้อมดนตรี", "คอนเสิร์ต",
        "คอม", "ทำงาน", "ตัดต่อ", "เล่นเกม", "live", "สตรีม",
        "ออกกำลังกาย", "วิ่ง", "ฟิตเนส",
        "ดำน้ำ", "ดำน้ำตื้น", "ดำน้ำลึก", "สกินไดฟ์", "ฟรีไดฟ์",
        "ทำสวน", "ตัดต้นไม้", "งานช่าง", "ช่าง", "ซ่อมบ้าน",
        "ปิกนิก", "ล่องแพ", "พายเรือ", "ตกปลา",
    ]

    BROAD_CATEGORIES = [
        "กล้อง", "เลนส์", "โดรน", "โกโปร", "gopro",
        "เต็นท์", "โต๊ะแคมป์", "เก้าอี้แคมป์", "ตะเกียง", "ฟลายชีท", "อุปกรณ์แคมป์", "อุปกรณ์เดินป่า",
        "โน้ตบุ๊ก", "โน้ตบุค", "คอมพิวเตอร์", "คอม", "แล็ปท็อป", "แท็บเล็ต", "ipad",
        "เครื่องเสียง", "ลำโพง", "ไมค์", "ไมโครโฟน", "มิกเซอร์",
        "ไฟสตูดิโอ", "ไฟต่อเนื่อง", "ขาตั้งกล้อง",
        "ลู่วิ่ง", "จักรยานออกกำลังกาย",
        "เครื่องฉีดน้ำ", "สว่าน", "เครื่องมือช่าง", "อุปกรณ์ดำน้ำ",
        "อุปกรณ์", "ของเช่า",
    ]

    SPECIFIC_BRANDS_AND_MODELS = [
        "canon", "sony", "nikon", "eos", "r50", "a7", "fx3", "zv", "lumix", "fuji", "fujifilm", "gopro", "dji",
        "coleman", "k2", "naturehike", "quechua", "dod", "blackdeer",
        "macbook", "dell", "asus", "lenovo", "acer", "hp", "ipad", "iphone", "ps5", "playstation",
        "jbl", "marshall", "yamaha", "bose", "rode", "shure", "saramonic", "motorola",
        "johnson", "bosch", "dyson", "xiaomi", "trek",
    ]

    SPECIFIC_TECH_SPECS = [
        "4k", "full frame", "ฟูลเฟรม", "mirrorless", "มิลเลอร์เลส",
        "core i", "ryzen", "rtx", "ram", "ssd", "m1", "m2", "m3",
    ]

    QUESTIONNAIRE_FOLLOWUP_WORDS = [
        "1", "2", "3", "4", "ข้อ 1", "ข้อ 2", "ข้อ 3", "ข้อ 4", "อันแรก", "แบบแรก",
        "เอกสาร", "พิมพ์งาน", "ออฟฟิศ", "office", "word", "excel",
        "ตัดต่อ", "กราฟิก", "วิดีโอ", "video", "photo", "vlog",
        "โปรแกรม", "โค้ด", "เขียนโค้ด", "developer", "coding",
        "เกม", "เล่นเกม", "สตรีม", "gaming", "stream",
        "windows", "macos", "macbook", "ram", "ssd", "intel", "ryzen",
        "ท่องเที่ยว", "พอร์ตเทรต", "บุคคล", "สินค้า", "อีเวนต์", "วิว",
        "มือใหม่", "พื้นฐาน", "มืออาชีพ", "โปร", "ชำนาญ", "เคยเดิน",
        "เลนส์ฟิกซ์", "เลนส์ซูม", "ไมค์", "ขาตั้ง", "แสงน้อย", "สตูดิโอ",
        "day hike", "trekking", "ค้างคืน", "ไปเช้า", "ไปคนเดียว", "high altitude", "altitude",
        "หน้าฝน", "หน้าหนาว", "หน้าร้อน", "อากาศเย็น", "ชื้นแฉะ", "ลุยฝน",
        "2 คน", "3-4 คน", "ครอบครัว", "5 คน", "ชุด", "ยังไม่มี", "มีแล้ว",
        "ปาร์ตี้", "สังสรรค์", "สัมมนา", "บรรยาย", "มินิคอนเสิร์ต", "ดนตรีสด", "งานแต่ง",
        "กลางแจ้ง", "ในร่ม", "20 คน", "50 คน", "น้ำหนักเบา", "พกพา",
        "วัน", "คืน", "คน", "ทริป", "ชิ้น", "งบ", "บาท", "ไม่เกิน", "ประหยัด",
    ]

    OUT_OF_SCOPE_RESPONSE_TEXT = (
        "ขออภัยด้วยนะคะ ฉันเป็นผู้ช่วย AI ประจำแพลตฟอร์ม **Yuemnoi (ยืมน้อย)** "
        "ซึ่งพร้อมให้บริการเฉพาะข้อมูลเกี่ยวกับการเช่าอุปกรณ์, การลงประกาศปล่อยเช่า, "
        "รวมถึงขั้นตอนและนโยบายการใช้งานของแพลตฟอร์มเท่านั้นค่ะ 😊\n\n"
        "คุณลูกค้าสามารถสอบถามเกี่ยวกับ:\n"
        "- 🎒 **ค้นหาและแนะนำอุปกรณ์เช่า** (กล้อง, แคมปิ้ง, โน้ตบุ๊ก/คอมพิวเตอร์, เครื่องเสียง ฯลฯ)\n"
        "- 📋 **ขั้นตอนการเช่าและการส่งคืนอุปกรณ์**\n"
        "- 💼 **วิธีการลงประกาศนำอุปกรณ์มาปล่อยเช่า**\n"
        "- 🛡️ **นโยบายเงินมัดจำและการประกันความคุ้มครอง**\n\n"
        "หากมีเรื่องใดเกี่ยวกับบริการของ Yuemnoi ให้ฉันช่วย สามารถสอบถามได้เลยนะคะ!"
    )

    OUT_OF_SCOPE_SUGGESTED_REPLIES = [
        "แนะนำอุปกรณ์สำหรับไปแคมปิ้ง",
        "ขั้นตอนการเช่าอุปกรณ์ทำยังไง",
        "อยากนำอุปกรณ์มาปล่อยเช่า",
        "นโยบายการรับประกันและมัดจำ",
    ]

    def __init__(
        self,
        ollama: OllamaClient,
        db_tool: DatabaseTool,
        feedback_store: Optional[Any] = None,
    ):
        self.ollama = ollama
        self.db_tool = db_tool
        self.feedback_store = feedback_store

    @staticmethod
    def _is_simple_greeting(query: str) -> bool:
        trimmed = query.strip()
        return bool(YuemnoiConsultantService.GREETING_PATTERN.match(trimmed))

    def _detect_general_chat_type(self, norm: str) -> Optional[str]:
        """
        Detects if query is a conversational inquiry (greetings, bot capabilities, self-intro, acknowledgements).
        Ensures equipment inquiries (even if containing capability words like 'กล้องนี้ทำอะไรได้บ้าง')
        pass through to equipment evaluation.
        """
        has_item_context = (
            any(cat in norm for cat in self.BROAD_CATEGORIES if cat not in ("อุปกรณ์", "ของเช่า"))
            or any(brand in norm for brand in self.SPECIFIC_BRANDS_AND_MODELS)
            or any(spec in norm for spec in self.SPECIFIC_TECH_SPECS)
        )
        if has_item_context:
            return None

        trimmed = norm.strip()
        if self.GREETING_PATTERN.match(trimmed):
            return "greeting"

        if any(re.search(p, norm) for p in self.CAPABILITY_PATTERNS):
            return "capability"

        if any(re.search(p, norm) for p in self.IDENTITY_PATTERNS):
            return "identity"

        if any(re.search(p, norm) for p in self.ACKNOWLEDGEMENT_PATTERNS):
            return "acknowledgement"

        if self._is_custom_input_request(norm):
            return "custom_input_prompt"

        if any(re.search(p, norm) for p in self.GENERAL_INQUIRY_PATTERNS):
            return "inquiry_opening"

        return None

    def _get_general_chat_response(self, chat_type: str) -> Dict[str, Any]:
        """Returns friendly conversational response introducing Yuemnoi AI capabilities."""
        if chat_type == "custom_input_prompt":
            answer = (
                "ยินดีเลยค่ะ! คุณลูกค้าสามารถพิมพ์เล่าหรืออธิบายลักษณะการใช้งานที่ต้องการ หรืออุปกรณ์ที่มองหาได้เลยนะคะ "
                "Yuemnoi AI จะช่วยค้นหาและแนะนำสิ่งที่ตรงใจที่สุดให้ค่ะ 😊"
            )
            suggested_replies = [
                "อยากได้สำหรับงานทั่วไป",
                "มีงบประมาณจำกัด",
                "ขอดูอุปกรณ์ยอดนิยม",
            ]
        elif chat_type in ("capability", "identity"):
            answer = (
                "สวัสดีค่ะ! ฉันคือ **Yuemnoi AI** ผู้ช่วยอัจฉริยะประจำแพลตฟอร์ม **ยืมน้อย (Yuemnoi)** ค่ะ 😊\n\n"
                "ฉันสามารถช่วยอำนวยความสะดวกให้คุณได้หลากหลายเรื่องเลยค่ะ เช่น:\n"
                "1. 🔍 **ค้นหาและแนะนำอุปกรณ์เช่าตามความต้องการ**: บอกประเภทงาน กิจกรรม หรืองบประมาณที่คุณตั้งไว้ "
                "(เช่น กล้องถ่ายภาพ, อุปกรณ์แคมปิ้งเดินป่า, โน้ตบุ๊กทำงาน หรือเครื่องเสียงจัดงาน) ฉันจะช่วยคัดสรรอุปกรณ์ที่คุ้มค่าและตรงใจที่สุด\n"
                "2. 📋 **แนะนำขั้นตอนการเช่าและส่งคืน**: ให้ข้อมูลวิธีจอง, ค่าบริการ, เอกสารที่ต้องใช้ และขั้นตอนการตรวจรับ-ส่งคืนของ\n"
                "3. 💼 **ขั้นตอนการลงประกาศปล่อยเช่า**: แนะนำสำหรับผู้ที่มีอุปกรณ์และอยากนำมาปล่อยเช่าเพื่อสร้างรายได้บนแพลตฟอร์ม\n"
                "4. 🛡️ **ข้อมูลนโยบาย มัดจำ และความคุ้มครอง**: ให้คำตอบเรื่องเงินมัดจำ การเคลมกรณีของเสียหาย และข้อตกลงการใช้งาน\n\n"
                "วันนี้สนใจอุปกรณ์ประเภทไหน หรือมีเรื่องใดให้ฉันช่วยดูแลเป็นพิเศษ สามารถพิมพ์บอกได้เลยนะคะ!"
            )
            suggested_replies = [
                "แนะนำกล้องถ่ายรูปหน่อยค่ะ",
                "มีอุปกรณ์แคมปิ้งอะไรบ้าง",
                "ขั้นตอนการเช่าอุปกรณ์ทำยังไง",
                "อยากนำอุปกรณ์มาปล่อยเช่า",
            ]
        elif chat_type == "acknowledgement":
            answer = (
                "ยินดีมากๆ เลยค่ะ! 😊 หากต้องการค้นหาอุปกรณ์เพิ่มเติม หรือมีข้อสงสัยขั้นตอนการเช่า "
                "สอบถาม Yuemnoi AI ได้ตลอดเวลาเลยนะคะ ขอให้มีความสุขกับการใช้งานค่ะ ✨"
            )
            suggested_replies = [
                "แนะนำอุปกรณ์ยอดนิยม",
                "ขั้นตอนการเช่าอุปกรณ์",
                "นโยบายเงินมัดจำ",
            ]
        elif chat_type == "inquiry_opening":
            answer = (
                "ยินดีเลยค่ะ! คุณลูกค้าสามารถสอบถามข้อมูลอุปกรณ์เช่า นโยบาย หรือขั้นตอนการใช้งานได้เลยนะคะ 😊\n\n"
                "วันนี้สนใจอุปกรณ์ประเภทไหน หรือมีเรื่องใดให้ฉันช่วยดูแลเป็นพิเศษไหมคะ?"
            )
            suggested_replies = [
                "แนะนำกล้องถ่ายรูปหน่อยค่ะ",
                "มีอุปกรณ์แคมปิ้งอะไรบ้าง",
                "ขั้นตอนการเช่าทำยังไง",
                "อยากลงประกาศปล่อยเช่า",
            ]
        else:  # greeting
            answer = (
                "สวัสดีค่ะ! ฉันคือ **Yuemnoi AI** ผู้ช่วยแนะนำอุปกรณ์เช่าประจำแพลตฟอร์ม ยืมน้อย 😊\n\n"
                "ไม่ว่าคุณจะมองหากล้องถ่ายภาพ, อุปกรณ์แคมปิ้ง, โน้ตบุ๊กทำงาน หรือเครื่องเสียงจัดงาน "
                "บอกความต้องการหรือสไตล์การใช้งานมาได้เลยค่ะ วันนี้สนใจอุปกรณ์ประเภทไหนเป็นพิเศษไหมคะ?"
            )
            suggested_replies = [
                "แนะนำกล้องถ่ายรูปหน่อยค่ะ",
                "มีอุปกรณ์แคมปิ้งอะไรบ้าง",
                "ขอดูคอมพิวเตอร์และโน้ตบุ๊ก",
                "มีลำโพงสำหรับจัดงานไหม",
            ]

        return {
            "status": "success",
            "mode": "general_chat",
            "answer": answer,
            "questions": [],
            "recommended_items": [],
            "suggested_replies": suggested_replies,
        }

    def _build_out_of_inventory_response(
        self,
        query: str,
        unsupported_domain: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Builds a polite, warm refusal response when the requested item or category does not exist in inventory.
        Guarantees recommended_items is strictly empty ([]) and no hallucinated recommendations occur.
        """
        if unsupported_domain:
            target_desc = f"**{unsupported_domain}**"
        else:
            clean_q = re.sub(r"^(อยากได้|อยากเช่า|ต้องการ|สนใจ|มี|ขอ|ช่วยแนะนำ|หา)\s*", "", query.strip())
            clean_q = re.sub(r"\s*(ไหม|มั้ย|คะ|ครับ|บ้าง|หน่อย|นะ|จ๊ะ|รึเปล่า)$", "", clean_q).strip()
            target_desc = f"**{clean_q}**" if clean_q else "อุปกรณ์หรือบริการดังกล่าว"

        cats_text = (
            "- 📷 **กล้องและอุปกรณ์ถ่ายภาพ** (เช่น Sony A7 IV, เลนส์, โดรน DJI, ขาตั้งกล้อง)\n"
            "- ⛺ **แคมป์ปิงและกิจกรรมกลางแจ้ง** (เช่น เต็นท์ Naturehike/Coleman, เก้าอี้แคมป์)\n"
            "- 💻 **คอมพิวเตอร์และอุปกรณ์ไอที** (เช่น โน้ตบุ๊ก, แท็บเล็ต, หน้าจอ, อุปกรณ์เสริม)\n"
            "- 🔊 **เครื่องเสียงและอุปกรณ์จัดงาน** (เช่น ลำโพง Marshall, ไมค์ลอย, เครื่องดนตรี)"
        )

        answer = (
            f"ขออภัยด้วยนะคะ ขณะนี้แพลตฟอร์ม **Yuemnoi (ยืมน้อย)** ยังไม่มีบริการให้เช่า {target_desc} ในระบบค่ะ 🙏\n\n"
            f"ปัจจุบัน Yuemnoi มุ่งเน้นการให้บริการเช่าอุปกรณ์ในหมวดหมู่ยอดนิยมดังนี้ค่ะ:\n{cats_text}\n\n"
            "หากคุณลูกค้าสนใจอุปกรณ์ในหมวดหมู่ข้างต้น สามารถสอบถามหรือพิมพ์บอกความต้องการให้ Yuemnoi แนะนำได้เลยนะคะ 😊"
        )

        return {
            "status": "success",
            "mode": "general_chat",
            "answer": answer,
            "questions": [],
            "recommended_items": [],
            "suggested_replies": [
                "แนะนำกล้องถ่ายรูป",
                "มีอุปกรณ์แคมปิ้งอะไรบ้าง",
                "อยากเช่าโน้ตบุ๊กทำงาน",
                "ขั้นตอนการเช่าอุปกรณ์",
            ],
        }

    def _is_query_in_scope(self, query: str, history: Optional[List[Dict[str, str]]] = None) -> bool:
        norm = query.strip().lower()
        # If in active conversation thread where assistant recently engaged
        if history:
            for msg in reversed(history[-4:]):
                if msg.get("role") == "assistant":
                    return True

        if any(term in norm for term in self.IN_SCOPE_TERMS):
            return True
        if any(cat in norm for cat in self.BROAD_CATEGORIES):
            return True
        if any(act in norm for act in self.BROAD_ACTIVITIES):
            return True
        if any(brand in norm for brand in self.SPECIFIC_BRANDS_AND_MODELS):
            return True
        if any(spec in norm for spec in self.SPECIFIC_TECH_SPECS):
            return True
        if any(p in norm for p in ("วัน", "คืน", "คน", "บาท", "งบ")):
            return True

        # Dynamic fuzzy match against in-scope core words and categories
        for core_word in ("อุปกรณ์", "เครื่องมือ", "ของเช่า", "เช่า", "ยืม", "ปล่อยเช่า", "ซ่อม", "กล้อง", "เต็นท์", "คอมพิวเตอร์", "เครื่องเสียง"):
            matched, _ = DatabaseTool._fuzzy_contains(norm, core_word, threshold=0.74)
            if matched:
                return True

        return False

    def classify_query(self, query: str, history: Optional[List[Dict[str, str]]] = None) -> str:
        """
        Classifies user query into 5 modes:
        - 'general_chat': Greetings, bot capabilities, identity, gratitude, acknowledgements
        - 'faq': Policy, insurance, deposit, delivery, cancellation, rental & lending process
        - 'out_of_scope': Off-topic questions completely unrelated to platform, renting or equipment
        - 'recommendation': Specific query with clear details (brand, model, budget, specs, duration/people) or follow-up response
        - 'questionnaire': Open-ended / underspecified query lacking necessary details to choose the best item
        """
        norm = query.strip().lower()

        # 0. Custom input request ("อื่นๆ (จะพิมพ์อธิบายเอง)", "ตอบเอง", "something else")
        if self._is_custom_input_request(norm):
            return "general_chat"

        # 0.1 Explicit skip questionnaire
        if any(s in norm for s in ("ข้ามแบบสอบถาม", "ข้าม", "skip", "ไม่ต้องถาม")):
            return "recommendation"

        # 0.2 General Chat & Capability Check (Never force questionnaire on bot intro/capability questions)
        general_type = self._detect_general_chat_type(norm)
        if general_type:
            return "general_chat"

        # 1. FAQ Check
        if any(re.search(p, norm) for p in self.FAQ_PATTERNS):
            return "faq"

        # 2. Out-of-Scope Check (Guardrail for non-platform queries like general programming, weather, cooking, etc.)
        if not self._is_query_in_scope(norm, history):
            return "out_of_scope"

        # 3. History / Follow-up Check
        if history:
            prior_context = self._extract_activity_context(history)
            has_assistant_prompt = any(msg.get("role") == "assistant" for msg in history[-3:])
            last_assistant_msg = next((msg for msg in reversed(history) if msg.get("role") == "assistant"), None)
            last_assistant_content = (last_assistant_msg.get("content") or "").lower() if last_assistant_msg else ""
            was_questionnaire_prompt = any(
                indicator in last_assistant_content
                for indicator in (
                    "เลือกตอบ", "บริบท", "แบบสอบถาม", "ข้อมูลด้านล่าง", "เพื่อช่วยแนะนำได้ตรงใจ",
                    "ตอบเร็วๆ", "ประเภทไหนเป็นพิเศษ", "หมวดหมู่ไหนเป็นพิเศษ", "ตรงจุดต้องรู้",
                    "สเปกที่เหมาะสม", "รบกวนเลือกข้อมูล", "ช่วยแนะนำได้ตรงใจ", "ขอถามนิดนึง",
                    "ขอเช็คบริบทก่อน", "อยากให้ตรงจุดเลยขอถาม", "ก่อนสักนิด เพราะคำแนะนำจะต่างกันมาก",
                    "ขอสอบถามเพิ่มเติมอีกนิด", "สอดคล้อง", "ตรงใจที่สุด", "ข้อมูลเพิ่มเติมอีกนิด",
                    "ขอเช็ก", "ขอเช็ค", "สเปกที่ตรงใจ"
                )
            )

            is_followup_answer = any(
                re.search(r"\b" + re.escape(w) + r"\b" if w.isascii() else re.escape(w), norm)
                for w in self.QUESTIONNAIRE_FOLLOWUP_WORDS
            ) or ("," in norm or "、" in norm)

            # User correcting or clarifying assistant (e.g. "ไม่ๆ...", "ไม่ใช่...", "ต้องการจะ...")
            is_correction = any(c in norm for c in ("ไม่ๆ", "ไม่ใช่", "หมายถึง", "ต้องการจะ", "ต้องการจะเช่า"))
            if has_assistant_prompt and is_correction:
                return "recommendation"

            # User answering questionnaire options or replying after questionnaire prompt
            if (was_questionnaire_prompt and (prior_context or has_assistant_prompt)) or ((prior_context or has_assistant_prompt) and is_followup_answer):
                return "recommendation"

        # 4. Check if initial query is SPECIFIC ENOUGH:
        # If user asks clearly with brand, model, budget, duration, or specific purpose -> RECOMMEND IMMEDIATELY (no questionnaire)!
        if self._check_is_sufficiently_specific(norm):
            return "recommendation"

        # 5. Any other non-specific query is OPEN-ENDED!
        # Must ask clarifying question (questionnaire step 1) dynamically tailored to topic!
        return "questionnaire"

    def _is_custom_input_request(self, text: str) -> bool:
        """Detects if user tapped 'อื่นๆ (จะพิมพ์อธิบายเอง)' or wants to explain manually."""
        norm = text.strip().lower()
        return any(phrase in norm for phrase in (
            "อื่นๆ (จะพิมพ์อธิบายเอง)",
            "อื่นๆ อยากอธิบายเพิ่มเติม",
            "พิมพ์อธิบายเอง",
            "พิมพ์ตอบเอง",
            "ตอบเอง",
            "something else",
            "จะพิมพ์อธิบายเอง",
        ))

    def _count_previous_questionnaire_steps(self, history: Optional[List[Dict[str, str]]]) -> int:
        """Counts how many questionnaire steps have been asked in recent history."""
        if not history:
            return 0
        count = 0
        for msg in history:
            if msg.get("role") == "assistant":
                content = (msg.get("content") or "").lower()
                if any(ind in content for ind in (
                    "เลือกตอบ", "บริบท", "แบบสอบถาม", "ข้อมูลด้านล่าง", "เพื่อช่วยแนะนำได้ตรงใจ",
                    "ตอบเร็วๆ", "ประเภทไหนเป็นพิเศษ", "หมวดหมู่ไหนเป็นพิเศษ", "ตรงจุดต้องรู้",
                    "สเปกที่เหมาะสม", "รบกวนเลือกข้อมูล", "ช่วยแนะนำได้ตรงใจ", "ขอถามนิดนึง",
                    "ขอเช็คบริบทก่อน", "อยากให้ตรงจุดเลยขอถาม", "ก่อนสักนิด เพราะคำแนะนำจะต่างกันมาก",
                    "ขอสอบถามเพิ่มเติมอีกนิด", "สอดคล้อง", "ตรงใจที่สุด", "ข้อมูลเพิ่มเติมอีกนิด",
                    "ขอเช็ก", "ขอเช็ค", "สเปกที่ตรงใจ"
                )):
                    count += 1
        return count

    def _check_is_sufficiently_specific(self, norm: str) -> bool:
        """Determines if query or reply is concrete enough to recommend without clarifying questions."""
        # A) Specific brand or model indicator
        has_specific_brand_or_model = any(brand in norm for brand in self.SPECIFIC_BRANDS_AND_MODELS)

        # B) Specific budget constraint
        has_budget = any(b in norm for b in ("งบ", "บาท", "ราคาไม่เกิน", "ไม่เกิน"))

        # C) Specific capacity + duration combination (e.g. '2 คน 1 คืน', '3 วัน 2 คืน')
        has_duration_and_capacity = (
            ("คน" in norm and any(d in norm for d in ("วัน", "คืน", "ชั่วโมง")))
            or ("วัน" in norm and "คืน" in norm)
        )

        # D) Specific technical specification
        has_technical_spec = any(spec in norm for spec in self.SPECIFIC_TECH_SPECS)

        # E) Specific concrete purpose/duration combination
        has_purpose_and_duration = (
            any(w in norm for w in ("ทำงาน", "ออฟฟิศ", "ตัดต่อ", "เกม", "ไลฟ์สด", "สตรีม", "งานแต่ง", "สัมมนา"))
            and any(d in norm for d in ("วัน", "คืน", "เดือน", "ปี", "สัปดาห์"))
        )

        return bool(
            has_specific_brand_or_model
            or has_budget
            or has_duration_and_capacity
            or has_technical_spec
            or has_purpose_and_duration
        )

    def _extract_activity_context(self, history: Optional[List[Dict[str, str]]]) -> str:
        """Finds the most recent user query that specified an activity or item category."""
        if not history:
            return ""
        # 1. Primary: user message matching categories, activities, or brands
        for msg in reversed(history[-6:]):
            if msg.get("role") == "user":
                content = str(msg.get("content") or "").strip()
                if not any(re.search(p, content.lower()) for p in self.FAQ_PATTERNS):
                    if (
                        any(w in content.lower() for w in self.BROAD_ACTIVITIES)
                        or any(cat in content.lower() for cat in self.BROAD_CATEGORIES)
                        or any(ind in content.lower() for ind in self.SPECIFIC_BRANDS_AND_MODELS)
                    ):
                        return content

        # 2. Fallback: most recent non-FAQ user query
        for msg in reversed(history[-6:]):
            if msg.get("role") == "user":
                content = str(msg.get("content") or "").strip()
                if not any(re.search(p, content.lower()) for p in self.FAQ_PATTERNS):
                    return content

        return ""

    def build_system_prompt(
        self,
        intent: str,
        compact_catalog: List[Dict[str, Any]],
        learned_insights: Optional[Dict[str, List[str]]] = None,
        available_categories: Optional[List[str]] = None,
        followup_context: Optional[Dict[str, str]] = None,
    ) -> str:
        """Builds specialized system prompt based on classified intent, catalog inventory, continuous learning, and multi-turn context."""
        learning_block = ""
        if learned_insights:
            pos = learned_insights.get("positive_exemplars") or []
            neg = learned_insights.get("negative_constraints") or []
            if pos or neg:
                learning_block = "\n\n### 🧠 บทเรียนที่ AI ได้เรียนรู้จากผู้ใช้งาน (Learned Insights from Feedback):\n"
                if pos:
                    learning_block += "แนวทางการตอบที่ผู้ใช้ชื่นชมและถูกต้อง (Positive Examples to Follow):\n"
                    for p in pos:
                        learning_block += f"- {p}\n"
                if neg:
                    learning_block += "ข้อผิดพลาดที่ผู้ใช้เคยแจ้งไม่พึงพอใจ (Mistakes to Strictly Avoid):\n"
                    for n in neg:
                        learning_block += f"- {n}\n"

        if intent == "faq":
            base_prompt = (
                "คุณคือ Yuemnoi AI ผู้ช่วยประจำแพลตฟอร์มเช่าอุปกรณ์ 'Yuemnoi' (ยืมน้อย)\n"
                "มีบุคลิกภาพสุภาพ อบอุ่น เป็นมิตร เชี่ยวชาญ ให้ข้อมูลบริการและนโยบายอย่างชัดเจนและสบายใจ\n\n"
                "ข้อมูลบริการและนโยบายของ Yuemnoi:\n"
                "1. ประกันอุปกรณ์: แพลตฟอร์ม Yuemnoi มีระบบประกันความคุ้มครองอุปกรณ์จากการชำรุดเสียหายระหว่างใช้งานตามปกติ โดยผู้เช่าสามารถเลือกแพ็กเกจประกันความคุ้มครองได้ตอนทำการจอง หากเกิดอุบัติเหตุหรือความเสียหายที่ไม่ใช่ความตั้งใจ ประกันจะช่วยดูแลค่าซ่อมแซมตามวงเงินคุ้มครองที่ระบุค่ะ\n"
                "2. เงินมัดจำ: อุปกรณ์แต่ละชิ้นอาจมีการกำหนดเงินมัดจำความปลอดภัย ซึ่งระบบจะคืนเงินมัดจำให้เต็มจำนวนภายใน 24-48 ชั่วโมงหลังส่งคืนอุปกรณ์และผู้ให้เช่าตรวจสอบสภาพเรียบร้อยค่ะ\n"
                "3. การรับและส่งมอบอุปกรณ์: มี 2 รูปแบบ คือ 'นัดรับด้วยตัวเอง' กับผู้ให้เช่าในจุดนัดพบ หรือเลือกใช้ 'บริการจัดส่งพัสดุ/แมสเซนเจอร์' ถึงที่พักตามความสะดวกค่ะ\n"
                "4. ขั้นตอนการเช่า:\n"
                "   1. เลือกอุปกรณ์และระบุวันที่ต้องการเช่า\n"
                "   2. ชำระค่าเช่าและเงินมัดจำผ่านระบบอย่างปลอดภัย\n"
                "   3. รับอุปกรณ์และตรวจสอบสภาพก่อนเริ่มใช้งาน\n"
                "   4. ส่งคืนอุปกรณ์เมื่อครบกำหนด\n"
                "5. การยกเลิก: สามารถยกเลิกได้ฟรีล่วงหน้าก่อนวันเช่าตามเงื่อนไขที่ผู้ให้เช่ากำหนด\n"
                "6. การลงประกาศปล่อยเช่า: สมาชิกสามารถนำอุปกรณ์ที่ไม่ได้ใช้งานมาลงประกาศปล่อยเช่าเพื่อสร้างรายได้เสริมได้ง่ายๆ:\n"
                "   1. ถ่ายรูปอุปกรณ์และระบุรายละเอียดกับราคาเช่าต่อวัน\n"
                "   2. กำหนดเงินมัดจำและเงื่อนไขการรับส่ง\n"
                "   3. ยืนยันตัวตนและเริ่มเปิดรับการจอง เมื่อมีผู้เช่าส่งคำขอ สามารถกดยอมรับและนัดหมายส่งมอบของได้เลยค่ะ\n\n"
                "ข้อกำหนดการตอบ:\n"
                "- ตอบเป็นภาษาไทยที่สุภาพ อบอุ่น เป็นกันเอง ชัดเจน (ใช้คำลงท้าย ค่ะ/คะ)\n"
                "- ตอบตรงประเด็นที่ผู้ใช้ถาม โดยไม่ต้องแบ่งเป็น 4 หัวข้อ และไม่ต้องแนะนำอุปกรณ์เช่าใหม่\n"
                "- **สำคัญมากเรื่องรูปแบบรายการ**: หากคำตอบมีขั้นตอน ข้อย่อย หรือรายการ ต้องขึ้นบรรทัดใหม่เป็นข้อๆ เสมอ (ห้ามเขียนติดกันในบรรทัดเดียวเป็น 1) ... 2) ... หรือ 1. ... 2. ... เด็ดขาด) ตัวอย่าง:\n"
                "1. ...\n"
                "2. ...\n"
                "3. ...\n"
                "4. ...\n"
                "- จัดเรียงลำดับคีย์ใน JSON ตามนี้เป๊ะๆ:\n"
                "  1) 'mode': 'general_chat'\n"
                "  2) 'recommended_item_ids': []\n"
                "  3) 'questions': []\n"
                "  4) 'answer': ข้อความตอบคำถามนโยบาย/บริการอย่างละเอียดและอบอุ่น (หากมีขั้นตอนให้ขึ้นบรรทัดใหม่เป็น 1. 2. 3. 4.)\n"
                "  5) 'suggested_replies': ตัวเลือกคำถามที่เกี่ยวข้อง 2-3 ข้อ\n\n"
                "ตัวอย่างรูปแบบ JSON ที่ต้องตอบ:\n"
                "{\n"
                '  "mode": "general_chat",\n'
                '  "recommended_item_ids": [],\n'
                '  "questions": [],\n'
                '  "answer": "ขั้นตอนการเช่าอุปกรณ์บน Yuemnoi ทำได้ง่ายๆ 4 ขั้นตอนดังนี้ค่ะ:\\n\\n1. เลือกอุปกรณ์และระบุวันที่ต้องการเช่า\\n2. ชำระค่าเช่าและเงินมัดจำผ่านระบบอย่างปลอดภัย\\n3. รับอุปกรณ์และตรวจเช็กสภาพก่อนใช้งาน\\n4. ส่งคืนอุปกรณ์เมื่อครบกำหนดค่ะ",\n'
                '  "suggested_replies": ["นโยบายเงินมัดจำ", "มีประกันอุปกรณ์ไหม", "ค้นหาอุปกรณ์ที่ต้องการเช่า"]\n'
                "}"
            )
        elif intent == "questionnaire":
            cat_list_str = ", ".join(f"'{c}'" for c in available_categories) if available_categories else ""

            base_prompt = (
                "คุณคือ Yuemnoi AI ผู้ช่วยแนะนำอุปกรณ์เช่าอัจฉริยะ ประจำแพลตฟอร์ม 'Yuemnoi' (ยืมน้อย)\n"
                "มีบุคลิกภาพสุภาพ อบอุ่น เป็นมิตร เชี่ยวชาญ (ลงท้าย ค่ะ/คะ)\n\n"
                "ภารกิจในรอบนี้: วิเคราะห์ความต้องการเชิงลึก (Adaptive Needs Discovery Questionnaire)\n"
                "ผู้ใช้สอบถามอุปกรณ์แบบกว้างหรือปลายเปิด คุณต้องสร้างชุดคำถามที่จำเป็นจำนวน **2 ถึง 4 ข้อ** ในคราวเดียว โดยประเมินจากระดับความชัดเจนของคำถามผู้ใช้:\n"
                "- **กรณีคำถามกว้างปานกลาง (ระบุหมวดหมู่แล้ว เช่น 'อยากเช่าเต็นท์', 'อยากเช่าคอม', 'หาเช่ากล้อง')**: ให้สร้างชุดคำถาม **2 ข้อ**:\n"
                "  * ข้อ 1 (step: 1): วัตถุประสงค์หลัก / ลักษณะการใช้งาน พร้อมตัวเลือก 3-4 ข้อ + 'อื่นๆ (จะพิมพ์อธิบายเอง)'\n"
                "  * ข้อ 2 (step: 2): ขนาดความจุ / จำนวนคน / สเปกสำคัญ / หรือระยะเวลาเช่า พร้อมตัวเลือก 3-4 ข้อ + 'อื่นๆ'\n"
                "- **กรณีคำถามกว้างมาก / คลุมเครือ / ขาดรายละเอียดสำคัญ (เช่น 'จะไปเที่ยว', 'จัดงานปาร์ตี้', 'ทำคอนเทนต์', 'มีอะไรแนะนำบ้าง')**: ให้สร้างชุดคำถาม **3 ถึง 4 ข้อ** เพื่อรวบรวมข้อมูลให้รอบด้านก่อนแนะนำ:\n"
                "  * ข้อ 1: กิจกรรมหลักหรือประเภทอุปกรณ์ที่สนใจ\n"
                "  * ข้อ 2: สไตล์การใช้งานหรือสถานที่\n"
                "  * ข้อ 3: ขนาด / จำนวนคน หรือระยะเวลาเช่า\n"
                "  * ข้อ 4 (หากจำเป็น): อุปกรณ์เสริมหรืองบประมาณ\n\n"
                "ตัวอย่างชุดคำถามตามระดับความคลุมเครือ:\n"
                "- กรณี 2 ข้อ (เรื่องเต็นท์): [ข้อ 1: กิจกรรม (step: 1, total_steps: 2), ข้อ 2: ขนาดคนพัก (step: 2, total_steps: 2)]\n"
                "- กรณี 3 ข้อ (เรื่องไปเที่ยว/ทำคอนเทนต์):\n"
                "  * ข้อ 1: 'สนใจอุปกรณ์ประเภทไหนสำหรับทริปนี้?' ตัวเลือก: ['กล้องถ่ายภาพ/วิดีโอ', 'เต็นท์และอุปกรณ์แคมปิ้ง', 'ลำโพงฟังเพลงพกพา', 'อื่นๆ (จะพิมพ์อธิบายเอง)'] (step: 1, total_steps: 3)\n"
                "  * ข้อ 2: 'สถานที่หรือสไตล์การท่องเที่ยวเป็นแบบไหน?' ตัวเลือก: ['ขึ้นเขา/เดินป่าธรรมชาติ', 'ริมทะเล/พักผ่อนรีสอร์ต', 'เที่ยวในเมือง/คาเฟ่', 'อื่นๆ'] (step: 2, total_steps: 3)\n"
                "  * ข้อ 3: 'ระยะเวลาเช่าหรือรูปแบบการเดินทาง?' ตัวเลือก: ['ทริปสั้น 1-3 วัน', 'ทริปยาว 4-7 วัน', 'อื่นๆ'] (step: 3, total_steps: 3)\n\n"
                "กฎเหล็กสำคัญที่สุดสำหรับการสร้างแบบสอบถาม (CRITICAL QUESTIONNAIRE RULES):\n"
                "1. **ความยืดหยุ่นของจำนวนคำถาม (2 ถึง 4 ข้อ)**: ปรับจำนวนคำถามตามความจำเป็นของข้อมูล หากคำถามกว้างมากให้ถาม 3-4 ข้อ หากเจาะจงพอสมควรให้ถาม 2 ข้อ (ระบุ total_steps เท่ากับจำนวนข้อทั้งหมดที่สร้าง เช่น ถ้ามี 3 ข้อ ให้ total_steps: 3 ทุกข้อ และ step เป็น 1, 2, 3 ตามลำดับ)\n"
                "2. **ห้ามล็อคคำตอบคำถาม (No Rigid Hardcoded Questions)**: ให้สร้างคำถามและช้อยตามสิ่งที่ผู้ใช้ถามเข้ามาจริงๆ ให้ตรงกับบริบท\n"
                "3. **ความเข้าใจคำพิมพ์ผิด (Typo Tolerance)**: วิเคราะห์เจตนาที่แท้จริงของผู้ใช้เสมอ แม้จะสะกดผิด\n"
                "4. ตอบ `answer` เป็นประโยคทักทายสั้นๆ เชิญชวน 1 ประโยค เช่น 'จะแนะนำให้ตรงจุดต้องรู้บริบทก่อน ให้เลือกตอบเร็วๆ ได้เลยนะคะ 😊'\n"
                "5. ให้ `recommended_item_ids`: [] เสมอ (ห้ามแนะนำสินค้าก่อนผู้ใช้ตอบแบบสอบถาม)\n"
                "6. จัดเรียงลำดับคีย์ใน JSON ตามนี้เป๊ะๆ:\n"
                "   1) 'mode': 'questionnaire'\n"
                "   2) 'recommended_item_ids': []\n"
                "   3) 'questions': [\n"
                "        {'id': 'q1', 'step': 1, 'total_steps': N, 'title': '<คำถามข้อที่ 1>', 'options': ['<ตัวเลือก 1>', '<ตัวเลือก 2>', '<ตัวเลือก 3>', 'อื่นๆ (จะพิมพ์อธิบายเอง)']},\n"
                "        ...\n"
                "      ]\n"
                "   4) 'answer': ข้อความทักทายสั้นๆ\n"
                "   5) 'suggested_replies': ['พิมพ์ตอบเอง', 'ข้ามแบบสอบถาม']\n\n"
                f"หมวดหมู่สินค้าที่มีในระบบ: {cat_list_str}\n"
                f"รายการอุปกรณ์ที่พร้อมให้บริการในระบบ:\n{json.dumps(compact_catalog, ensure_ascii=False, indent=2)}\n"
            )
        else:
            base_prompt = (
                "คุณคือ Yuemnoi AI ผู้ช่วยแนะนำอุปกรณ์เช่าอัจฉริยะ ประจำแพลตฟอร์ม 'Yuemnoi' (ยืมน้อย)\n"
                "มีบุคลิกภาพสุภาพ อบอุ่น เป็นมิตร เชี่ยวชาญ ให้คำแนะนำอย่างชาญฉลาดเหมือนที่ปรึกษามืออาชีพที่ใส่ใจลูกค้า\n\n"
                "กฎเหล็กสำคัญที่สุด (CRITICAL RULES):\n"
                "1. **ความเข้าใจคำพิมพ์ผิด (Typo Tolerance)**: ผู้ใช้อาจพิมพ์ตกหล่นหรือพิมพ์ผิด ให้วิเคราะห์เจตนาที่แท้จริงเสมอ เช่น 'อุปกรร์ว่อมรถ' หรือ 'ที่ซ้อมรถ' หมายถึง 'อุปกรณ์ซ่อมรถ / เครื่องมือช่าง' ห้ามตีความผิดเป็นสนามฝึกซ้อมกอล์ฟ หรือรถยนต์เด็ดขาด\n"
                "2. **ห้ามแต่งหรือจินตนาการอุปกรณ์หรือยี่ห้อที่ไม่มีขึ้นมาเด็ดขาด (Strict Inventory Grounding)**: ให้แนะนำเฉพาะอุปกรณ์ที่มีชื่อและรายละเอียดปรากฏอยู่ใน `รายการอุปกรณ์ที่พร้อมให้บริการในระบบ` ด้านล่างนี้เท่านั้น! ห้ามแนะนำ 'รถยนต์', 'รถตู้', 'Toyota Alphard', 'สนามฝึกซ้อมกอล์ฟ', หรืออุปกรณ์ใดๆ ที่ไม่มีในรายการเด็ดขาด! หากไม่มีอุปกรณ์ที่ตรงกับความต้องการในรายการ ให้ตอบแจ้งผู้ใช้อย่างสุภาพตรงๆ ว่าไม่มีอุปกรณ์ดังกล่าวในระบบ และห้ามใส่หัวข้อ '### 🎒 อุปกรณ์ที่แนะนำ:' เด็ดขาด\n"
                "3. **กรณีไม่มีอุปกรณ์เฉพาะทางที่ผู้ใช้ถาม (เช่น ซ่อมรถ, อุปกรณ์ช่างเฉพาะทาง)**: ให้อธิบายอย่างสุภาพว่าขณะนี้แพลตฟอร์ม Yuemnoi ยังไม่มีเครื่องมือซ่อมรถยนต์เฉพาะทาง แต่มีเครื่องมือช่างอเนกประสงค์ในระบบ (เช่น สว่านไร้สาย Bosch, เครื่องฉีดน้ำแรงดันสูง) ที่อาจนำไปปรับใช้ได้ค่ะ หรือแนะนำให้สอบถามอุปกรณ์อื่น\n"
                "4. **ข้อห้ามเรื่อง ID**: ห้ามใส่คำว่า (ID: xx) หรือ ID ในข้อความตอบกลับเด็ดขาด ให้ระบุเฉพาะชื่อรุ่นอุปกรณ์\n"
                "5. **โครงสร้างคำตอบ `answer`** (มีเพียงหัวข้อเดียวเท่านั้น):\n"
                "   - เกริ่นนำสั้นๆ 1-2 ประโยค (หากผู้ใช้ตอบแบบสอบถามหรือระบุบริบทมา ให้อ้างอิงบริบทที่ผู้ใช้เลือก เช่น 'สำหรับทริปค้างคืนช่วงหน้าหนาว Yuemnoi ขอแนะนำอุปกรณ์ที่เหมาะสมตามนี้ค่ะ:')\n"
                "   - หัวข้อไฮไลท์ (ต้องขึ้นบรรทัดใหม่ \\n\\n และเว้นวรรคหลัง ### เสมอ):\n"
                "     '### 🎒 อุปกรณ์ที่แนะนำ:'\n"
                "     - **ชื่อรุ่นอุปกรณ์**: อธิบายจุดเด่นสั้นๆ 1-2 บรรทัดว่าตอบโจทย์บริบทและความต้องการของผู้ใช้อย่างไร (ห้ามใส่ ID)\n"
                "   - หากไม่มีอุปกรณ์ที่ตรงเป๊ะ ให้แจ้งตามตรงและแนะนำอุปกรณ์ใกล้เคียงที่มีในระบบ\n"
                "   - ชวนคุยปิดท้าย 1 ประโยค (เช่น 'สนใจรับชิ้นนี้หรือสอบถามข้อมูลเพิ่มเติมได้เลยนะคะ 😊')\n"
                "6. **หากมีขั้นตอนหรือรายการ** ต้องขึ้นบรรทัดใหม่เป็นข้อๆ เสมอ (1. ...\\n2. ...\\n3. ...)\n"
                "7. จัดเรียงลำดับคีย์ใน JSON ตามนี้เป๊ะๆ:\n"
                "   1) 'mode': 'recommendation'\n"
                "   2) 'recommended_item_ids': [ไอดีอุปกรณ์ในระบบที่ตรงกับอุปกรณ์แนะนำ 1-3 ชิ้น ถ้าไม่มีที่ตรงเลยให้ใส่ []]\n"
                "   3) 'questions': []\n"
                "   4) 'answer': ข้อความ Markdown ตามโครงสร้างกระชับข้างต้น\n"
                "   5) 'suggested_replies': ตัวเลือกคำถามติดตาม 2-4 ข้อ\n\n"
                f"รายการอุปกรณ์ที่พร้อมให้บริการในระบบ:\n{json.dumps(compact_catalog, ensure_ascii=False, indent=2)}\n\n"
                "ตัวอย่างรูปแบบ JSON ที่ต้องตอบ:\n"
                "{\n"
                '  "mode": "recommendation",\n'
                '  "recommended_item_ids": [39],\n'
                '  "questions": [],\n'
                '  "answer": "สำหรับอุปกรณ์งานช่างและซ่อมแซม Yuemnoi ขอแนะนำอุปกรณ์ที่พร้อมให้บริการตามนี้ค่ะ:\\n\\n### 🎒 อุปกรณ์ที่แนะนำ:\\n- **สว่านไร้สาย Bosch**: แรงบิดสูง ใช้งานขันน็อต เจาะวัสดุได้อย่างคล่องตัว เหมาะสำหรับงานช่างและงานซ่อมทั่วไปค่ะ\\n\\nหากต้องการอุปกรณ์ช่างประเภทอื่นเพิ่มเติม สามารถแจ้งได้เลยนะคะ 😊",\n'
                '  "suggested_replies": ["ขอดูเครื่องมือช่างอื่น", "สอบถามขั้นตอนการเช่า", "มีประกันอุปกรณ์ไหม"]\n'
                "}"
            )

        return base_prompt + learning_block

    @staticmethod
    def _clean_delta(text: str) -> str:
        # Strip ID patterns without stripping newlines or whitespace
        ans = re.sub(r"\s*\(ID:\s*\d+\)", "", text, flags=re.IGNORECASE)
        ans = re.sub(r"\s*ID:\s*\d+", "", ans, flags=re.IGNORECASE)
        # Normalize old heading if generated
        ans = ans.replace("อุปกรณ์แนะนำที่ตอบโจทย์ที่สุด", "อุปกรณ์ที่แนะนำ")
        return ans

    @staticmethod
    def _clean_answer(text: str) -> str:
        # Clean any accidental (ID: 31) or ID: 31 from output text
        ans = re.sub(r"\s*\(ID:\s*\d+\)", "", text, flags=re.IGNORECASE)
        ans = re.sub(r"\s*ID:\s*\d+", "", ans, flags=re.IGNORECASE)
        # Replace old heading
        ans = ans.replace("อุปกรณ์แนะนำที่ตอบโจทย์ที่สุด", "อุปกรณ์ที่แนะนำ")
        # Clean any accidental template placeholders
        ans = ans.replace("คำตอบ Markdown 4 หัวข้อที่เป็นมิตรตามที่กำหนดข้างต้น", "")
        # Strip deprecated sections if generated
        ans = re.sub(r"###\s*💡\s*สิ่งที่แนะนำสำหรับการใช้งานของคุณ:[^\n#]*(\n(?![#]).*)*", "", ans)
        ans = re.sub(r"###\s*🌱\s*ทริคประหยัดงบ:[^\n#]*(\n(?![#]).*)*", "", ans)
        ans = re.sub(r"###\s*⭐\s*ข้อแนะนำเพิ่มเติม:[^\n#]*(\n(?![#]).*)*", "", ans)

        # Ensure numbered lists (1. 2. 3. or 1) 2) 3)) start on a new line
        ans = re.sub(r'(?:^|(?<=\S)\s+)(\d+)\)\s*', r'\n\n\1. ', ans)
        ans = re.sub(r'(?<=\S)\s+(\d+\.\s+)', r'\n\n\1', ans)

        ans = re.sub(r"\n{3,}", "\n\n", ans)
        return ans.strip()

    def _get_fallback_questions(
        self,
        query: str,
        catalog: Optional[List[Dict[str, Any]]] = None,
    ) -> List[Dict[str, Any]]:
        """
        Dynamically derives 2 clarification questions tailored to the topic (Step 1 & Step 2).
        Returns a complete 2-step discovery suite for the client-side questionnaire.
        """
        norm = query.strip().lower()

        if any(w in norm for w in ("คอม", "โน้ตบุ๊ก", "โน้ตบุค", "pc", "laptop", "คอมพิวเตอร์")):
            return [
                {
                    "id": "q1",
                    "step": 1,
                    "total_steps": 2,
                    "title": "เช่าคอมไปใช้งานแบบไหน?",
                    "options": [
                        "ทำงาน/ออฟฟิศ (โน้ตบุ๊ก/PC)",
                        "จัดอีเวนต์/บูธ (หลายเครื่อง)",
                        "เล่นเกม/สเปกแรง",
                        "ตัดต่อ/กราฟิก สเปกสูง",
                    ],
                },
                {
                    "id": "q2",
                    "step": 2,
                    "total_steps": 2,
                    "title": "ระยะเวลาเช่าหรือรูปแบบเครื่องที่ต้องการ?",
                    "options": [
                        "เน้นพกพา (โน้ตบุ๊ก)",
                        "ตั้งโต๊ะ (PC สเปกสูง)",
                        "เช่าสั้น (1-3 วัน)",
                        "เช่าระยะยาว (รายเดือน)",
                    ],
                },
            ]
        elif any(w in norm for w in ("มือถือ", "โทรศัพท์", "สมาร์ทโฟน", "แท็บเล็ต", "tablet", "ipad")):
            return [
                {
                    "id": "q1",
                    "step": 1,
                    "total_steps": 2,
                    "title": "คุณต้องการอุปกรณ์แบบไหน?",
                    "options": [
                        "เช่า WiFi/SIM พกพาไว้ใช้เน็ตตอนเดินทาง",
                        "เช่าตัวเครื่องมือถือ/แท็บเล็ตมาใช้ชั่วคราว",
                        "อุปกรณ์สำหรับทำธุรกิจปล่อยเช่ามือถือ",
                        "อื่นๆ (จะพิมพ์อธิบายเอง)",
                    ],
                },
                {
                    "id": "q2",
                    "step": 2,
                    "total_steps": 2,
                    "title": "ต้องการระบบปฏิบัติการหรือระยะเวลาใช้งาน?",
                    "options": [
                        "iOS (iPhone)",
                        "Android",
                        "เช่า 1-3 วัน",
                        "เช่ารายเดือน/ระยะยาว",
                    ],
                },
            ]
        elif any(w in norm for w in ("แอร์", "เครื่องปรับอากาศ", "พัดลมไอเย็น")):
            return [
                {
                    "id": "q1",
                    "step": 1,
                    "total_steps": 2,
                    "title": "ต้องการอุปกรณ์แอร์แบบไหน?",
                    "options": [
                        "เช่าแอร์เคลื่อนที่ใช้เองชั่วคราว (งานอีเวนต์/บ้าน/ออฟฟิศ)",
                        "อุปกรณ์สำหรับทำธุรกิจปล่อยเช่าแอร์ (ซื้อมาปล่อยเช่า)",
                        "อื่นๆ อยากอธิบายเพิ่มเติม",
                    ],
                },
                {
                    "id": "q2",
                    "step": 2,
                    "total_steps": 2,
                    "title": "ขนาดพื้นที่หรือระยะเวลาการใช้งานประมาณไหน?",
                    "options": [
                        "ห้องขนาดเล็ก-กลาง (9,000 - 12,000 BTU)",
                        "พื้นที่จัดงาน / โถงใหญ่ (15,000+ BTU)",
                        "เช่าชั่วคราว 1-3 วัน",
                        "เช่าระยะยาว",
                    ],
                },
            ]
        elif any(w in norm for w in ("กล้อง", "ถ่ายรูป", "เลนส์", "ถ่ายวิดีโอ")):
            return [
                {
                    "id": "q1",
                    "step": 1,
                    "total_steps": 2,
                    "title": "ลักษณะการใช้งานกล้องหลักเป็นแบบไหน?",
                    "options": [
                        "ถ่าย Vlog / ท่องเที่ยว",
                        "ถ่ายภาพนิ่ง / พอร์ตเทรต / บุคคล",
                        "ถ่ายงานอีเวนต์ / วิดีโอจริงจัง",
                        "อื่นๆ (จะพิมพ์อธิบายเอง)",
                    ],
                },
                {
                    "id": "q2",
                    "step": 2,
                    "total_steps": 2,
                    "title": "ต้องการเลนส์หรืออุปกรณ์เสริมประเภทไหน?",
                    "options": [
                        "เฉพาะตัวกล้อง + เลนส์คิตทั่วไป",
                        "เลนส์ละลายหลัง / เลนส์ซูมไกล",
                        "ขาตั้งกล้องหรือไมค์ไวร์เลสด้วย",
                        "อื่นๆ (จะพิมพ์อธิบายเอง)",
                    ],
                },
            ]
        elif any(w in norm for w in ("แคมปิ้ง", "เดินป่า", "ขึ้นเขา", "เต็นท์", "เต้น", "ดอย")):
            return [
                {
                    "id": "q1",
                    "step": 1,
                    "total_steps": 2,
                    "title": "คุณต้องการเต็นท์สำหรับกิจกรรมอะไร?",
                    "options": [
                        "เดินป่าและแคมปิ้ง",
                        "จัดงานอีเวนต์/กิจกรรมกลางแจ้ง",
                        "ปาร์ตี้/พักผ่อนทั่วไป",
                        "อื่นๆ (จะพิมพ์อธิบายเอง)",
                    ],
                },
                {
                    "id": "q2",
                    "step": 2,
                    "total_steps": 2,
                    "title": "ขนาดหรือจำนวนผู้พักประมาณกี่คน?",
                    "options": [
                        "1-2 คน (น้ำหนักเบา/พกพาง่าย)",
                        "3-4 คน (มาตรฐานครอบครัว)",
                        "4-6 คนขึ้นไป (กลุ่มใหญ่/มีพื้นที่เก็บของ)",
                        "อื่นๆ",
                    ],
                },
            ]
        elif any(w in norm for w in ("เที่ยว", "เดินทาง", "ทริป", "ปาร์ตี้", "งานเลี้ยง", "อีเวนต์", "คอนเทนต์")):
            return [
                {
                    "id": "q1",
                    "step": 1,
                    "total_steps": 3,
                    "title": "สนใจอุปกรณ์ประเภทใดสำหรับกิจกรรมนี้คะ?",
                    "options": [
                        "กล้องถ่ายภาพ / ถ่ายวิดีโอ / โดรน",
                        "เต็นท์และอุปกรณ์แคมปิ้งพักแรม",
                        "ลำโพงบลูทูธ / เครื่องเสียงงานปาร์ตี้",
                        "อื่นๆ (จะพิมพ์อธิบายเอง)",
                    ],
                },
                {
                    "id": "q2",
                    "step": 2,
                    "total_steps": 3,
                    "title": "สถานที่หรือสไตล์การใช้งานเป็นแบบไหน?",
                    "options": [
                        "ธรรมชาติ / ขึ้นเขา / เดินป่า",
                        "ริมทะเล / พักผ่อนรีสอร์ต",
                        "ในร่ม / คาเฟ่ / จัดงานในสถานที่",
                        "อื่นๆ",
                    ],
                },
                {
                    "id": "q3",
                    "step": 3,
                    "total_steps": 3,
                    "title": "ระยะเวลาเช่าที่ต้องการประมาณไหน?",
                    "options": [
                        "1-3 วัน (ทริปสั้น / สุดสัปดาห์)",
                        "4-7 วัน (ทริปยาว)",
                        "รายสัปดาห์ขึ้นไป",
                        "อื่นๆ",
                    ],
                },
            ]
        else:
            top_cat = ""
            if catalog:
                ranked = self.db_tool.rank_relevant_items(query, catalog, limit=3)
                if ranked and ranked[0].get("category"):
                    top_cat = ranked[0]["category"]
            return [
                {
                    "id": "q1",
                    "step": 1,
                    "total_steps": 2,
                    "title": f"สนใจอุปกรณ์ในหมวด {top_cat or 'ใด'} สำหรับรูปแบบการใช้งานใดคะ?",
                    "options": [
                        "ใช้งานทั่วไป / ชั่วคราว",
                        "ใช้งานจริงจัง / กึ่งมืออาชีพ",
                        "ใช้งานระดับโปร / สเปกระดับสูง",
                        "อื่นๆ (จะพิมพ์อธิบายเอง)",
                    ],
                },
                {
                    "id": "q2",
                    "step": 2,
                    "total_steps": 2,
                    "title": "ระยะเวลาเช่าที่ต้องการประมาณไหน?",
                    "options": [
                        "1-3 วัน (รายวัน)",
                        "1-2 สัปดาห์",
                        "รายเดือน / ระยะยาว",
                        "อื่นๆ",
                    ],
                },
            ]

    def _get_fallback_questionnaire_intro(
        self,
        query: str,
        catalog: Optional[List[Dict[str, Any]]] = None,
    ) -> str:
        """
        Generates dynamic friendly greeting asking for context without rigid templates.
        """
        norm = query.strip().lower()
        if any(w in norm for w in ("มือถือ", "โทรศัพท์", "สมาร์ทโฟน")):
            return "อุปกรณ์เช่ามือถือมีได้หลายแบบ อยากให้ตรงจุดเลยขอถามนิดนึงว่าคุณหมายถึงอะไรคะ 😊"
        elif any(w in norm for w in ("แอร์", "เครื่องปรับอากาศ")):
            return "อยากให้ช่วยแนะนำแบบไหนคะ ขอเช็คบริบทก่อนสักนิด เพราะคำแนะนำจะต่างกันมากระหว่าง 2 แบบนี้ 😊"
        elif any(w in norm for w in ("คอม", "โน้ตบุ๊ก", "โน้ตบุค", "pc", "laptop", "คอมพิวเตอร์")):
            return "จะแนะนำอุปกรณ์คอมพิวเตอร์ให้ตรงจุดต้องรู้บริบทก่อน ให้เลือกตอบเร็วๆ ได้เลยนะคะ 😊"
        elif any(w in norm for w in ("เต็นท์", "เต้น", "แคมปิ้ง", "เดินป่า")):
            return "จะแนะนำเต็นท์และอุปกรณ์แคมปิ้งให้ตรงใจ ขอทราบข้อมูลเบื้องต้นสักนิดนะคะ 😊"

        return "จะแนะนำให้ตรงจุดต้องรู้บริบทก่อน ให้เลือกตอบเร็วๆ ได้เลยนะคะ 😊"

    def _validate_and_align_questionnaire(
        self,
        questions: List[Dict[str, Any]],
        query: str,
        relevant_candidates: List[Dict[str, Any]],
        catalog: List[Dict[str, Any]],
    ) -> List[Dict[str, Any]]:
        """
        Validates the clarification questions generated by LLM:
        1. Ensures 2 questions with valid titles and options.
        2. Assigns step 1 and step 2 with total_steps = 2.
        3. Falls back to complete 2-question fallback if output is empty or incomplete.
        """
        if not questions:
            return self._get_fallback_questions(query, catalog=catalog)

        cleaned_qs = []
        for i, q in enumerate(questions):
            if isinstance(q, dict):
                title = str(q.get("title") or "").strip()
                raw_options = q.get("options", [])
                cleaned_options = []
                for opt in raw_options:
                    opt_str = str(opt).strip()
                    if opt_str and opt_str not in cleaned_options:
                        cleaned_options.append(opt_str)

                if len(title) >= 3 and len(cleaned_options) >= 2:
                    step_num = i + 1
                    cleaned_qs.append({
                        "id": str(q.get("id") or f"q{step_num}"),
                        "step": step_num,
                        "total_steps": 2,
                        "title": title,
                        "options": cleaned_options[:4],
                    })

        # Allow 2 to 4 questions dynamically
        if len(cleaned_qs) >= 2:
            cleaned_qs = cleaned_qs[:4]
            total_n = len(cleaned_qs)
            for idx, item in enumerate(cleaned_qs):
                item["step"] = idx + 1
                item["total_steps"] = total_n
            return cleaned_qs
        elif len(cleaned_qs) == 1:
            fallbacks = self._get_fallback_questions(query, catalog=catalog)
            if len(fallbacks) >= 2:
                merged = [cleaned_qs[0]] + fallbacks[1:]
                merged = merged[:4]
                total_n = len(merged)
                for idx, item in enumerate(merged):
                    item["step"] = idx + 1
                    item["total_steps"] = total_n
                return merged
            return cleaned_qs

        return self._get_fallback_questions(query, catalog=catalog)

    async def process_chat(
        self,
        query: str,
        history: Optional[List[Dict[str, str]]] = None,
    ) -> Dict[str, Any]:
        cleaned_query = query.strip()
        if not cleaned_query:
            return {
                "status": "success",
                "mode": "general_chat",
                "answer": "สวัสดีค่ะ! Yuemnoi AI พร้อมช่วยแนะนำอุปกรณ์เช่าค่ะ สามารถสอบถามอุปกรณ์ที่สนใจได้เลยนะคะ",
                "questions": [],
                "recommended_items": [],
                "suggested_replies": [
                    "แนะนำกล้องถ่ายรูปหน่อยค่ะ",
                    "มีอุปกรณ์แคมปิ้งอะไรบ้าง",
                    "อยากเช่าคอมพิวเตอร์ทำงาน",
                    "มีลำโพงจัดงานปาร์ตี้ไหม",
                ],
            }

        intent = self.classify_query(cleaned_query, history)
        if intent == "general_chat":
            chat_type = self._detect_general_chat_type(cleaned_query.lower()) or "greeting"
            return self._get_general_chat_response(chat_type)

        if intent == "out_of_scope":
            return {
                "status": "success",
                "mode": "general_chat",
                "answer": self.OUT_OF_SCOPE_RESPONSE_TEXT,
                "questions": [],
                "recommended_items": [],
                "suggested_replies": self.OUT_OF_SCOPE_SUGGESTED_REPLIES,
            }

        catalog = []
        relevant_candidates = []
        compact_catalog = []

        if intent != "faq":
            try:
                catalog = await self.db_tool.list_available_items()
            except Exception as e:
                logger.error("Failed to load catalog from Supabase: %s", e)
                catalog = []

            # Check unsupported domain first (e.g. vehicles/cars/vans, real estate, pets)
            unsupported_domain = DatabaseTool.get_unsupported_category_name(cleaned_query)
            search_query = cleaned_query
            if not unsupported_domain:
                prior_context = self._extract_activity_context(history)
                if prior_context:
                    has_category = any(cat in cleaned_query.lower() for cat in self.BROAD_CATEGORIES)
                    if not has_category or prior_context.lower() in cleaned_query.lower():
                        search_query = f"{prior_context} {cleaned_query}"
                unsupported_domain = DatabaseTool.get_unsupported_category_name(search_query)

            if unsupported_domain:
                return self._build_out_of_inventory_response(
                    query=search_query,
                    unsupported_domain=unsupported_domain,
                )

            relevant_candidates = self.db_tool.rank_relevant_items(
                query=search_query,
                items=catalog,
                limit=settings.MAX_RECOMMENDED_ITEMS + 3,
            )

            # If no items match in catalog and intent is recommendation, politely refuse immediately
            if not relevant_candidates and intent == "recommendation":
                return self._build_out_of_inventory_response(query=cleaned_query)

            compact_catalog = [
                {
                    "id": item.get("id"),
                    "name": item.get("item_name"),
                    "category": item.get("category"),
                    "price_per_day": item.get("price"),
                    "description": str(item.get("description") or "")[:120],
                }
                for item in relevant_candidates
            ]

        learned_insights = None
        if self.feedback_store:
            try:
                learned_insights = await self.feedback_store.get_learned_insights(cleaned_query)
            except Exception as e:
                logger.warning("Could not retrieve learned insights: %s", e)

        all_categories = sorted(list({
            item.get("category")
            for item in catalog
            if item.get("category") and item.get("category") not in ("อื่น ๆ", "อื่นๆ")
        }))

        system_prompt = self.build_system_prompt(
            intent=intent,
            compact_catalog=compact_catalog,
            learned_insights=learned_insights,
            available_categories=all_categories,
        )

        messages: List[Dict[str, Any]] = [{"role": "system", "content": system_prompt}]
        if history:
            for msg in history[-settings.MAX_HISTORY_MESSAGES:]:
                role = msg.get("role")
                content = str(msg.get("content") or "").strip()
                if role in ("user", "assistant") and content:
                    messages.append({"role": role, "content": content[:300]})
        messages.append({"role": "user", "content": cleaned_query})

        try:
            raw_response = await self.ollama.chat(
                messages=messages,
                format="json",
                max_tokens=1500,
                temperature=0.3,
                timeout=settings.PIPELINE_TIMEOUT,
                think=False,
            )
            parsed = self._extract_json(raw_response)
        except Exception as exc:
            logger.error("Error during LLM inference: %s", exc)
            parsed = None

        if parsed and isinstance(parsed, dict) and "answer" in parsed:
            mode = str(parsed.get("mode") or ("questionnaire" if parsed.get("questions") else "recommendation"))
            answer = self._clean_answer(str(parsed.get("answer", "")))
            raw_ids = parsed.get("recommended_item_ids") or []
            suggested_replies = [
                str(reply).strip()
                for reply in (parsed.get("suggested_replies") or [])
                if str(reply).strip()
            ][:4]

            questions = self._format_questions(parsed.get("questions"))
            if questions and mode == "questionnaire":
                questions = self._validate_and_align_questionnaire(
                    questions=questions,
                    query=cleaned_query,
                    relevant_candidates=relevant_candidates,
                    catalog=catalog,
                )

            recommended_items = self._resolve_recommended_items(
                raw_ids=raw_ids,
                catalog=catalog,
                relevant_candidates=relevant_candidates,
                cleaned_query=cleaned_query,
                mode=mode,
                has_questions=bool(questions),
            )

            # Post-generation Hallucination Guardrail:
            # If in recommendation mode but zero items were matched/resolved from database
            if mode == "recommendation" and not recommended_items:
                if "### 🎒 อุปกรณ์ที่แนะนำ:" in answer or any(w in answer.lower() for w in ("รถตู้", "toyota", "alphard")):
                    out_resp = self._build_out_of_inventory_response(cleaned_query)
                    answer = out_resp["answer"]
                    mode = "general_chat"
                    suggested_replies = out_resp["suggested_replies"]

            return {
                "status": "success",
                "mode": mode,
                "answer": answer,
                "questions": questions,
                "recommended_items": recommended_items[:settings.MAX_RECOMMENDED_ITEMS],
                "suggested_replies": suggested_replies or [
                    "ขอทราบรายละเอียดเพิ่มเติมค่ะ",
                    "มีตัวเลือกอื่นที่ราคาถูกกว่านี้ไหม",
                ],
            }

        # Safe fallback based on intent
        if intent == "faq":
            return {
                "status": "success",
                "mode": "general_chat",
                "answer": (
                    "แพลตฟอร์ม Yuemnoi มีระบบดูแลและคุ้มครองความปลอดภัยสำหรับผู้เช่าและผู้ให้เช่าค่ะ "
                    "คุณลูกค้าสามารถสอบถามข้อมูลเกี่ยวกับเงินมัดจำ, ประกันความคุ้มครอง, หรือขั้นตอนการเช่าเพิ่มเติมได้เลยนะคะ 😊"
                ),
                "questions": [],
                "recommended_items": [],
                "suggested_replies": [
                    "สอบถามขั้นตอนการเช่า",
                    "มีประกันอุปกรณ์ไหม",
                    "นโยบายเงินมัดจำ",
                ],
            }
        elif intent == "questionnaire":
            fallback_qs = self._get_fallback_questions(
                cleaned_query,
                catalog=catalog,
            )
            fallback_intro = self._get_fallback_questionnaire_intro(
                cleaned_query,
                catalog=catalog,
            )
            return {
                "status": "success",
                "mode": "questionnaire",
                "answer": fallback_intro,
                "questions": fallback_qs,
                "recommended_items": [],
                "suggested_replies": ["พิมพ์ตอบเอง", "ข้ามแบบสอบถาม"],
            }
        else:
            fallback_items = [self._format_card(item) for item in relevant_candidates[:2]]
            return {
                "status": "success",
                "mode": "recommendation",
                "answer": (
                    "ขออภัยในความไม่สะดวกค่ะ ขณะนี้ระบบกำลังประมวลผลข้อมูลอุปกรณ์ "
                    "เบื้องต้นได้ค้นหาอุปกรณ์ที่อาจตรงกับความต้องการของคุณลูกค้าไว้ให้แล้วนะคะ "
                    "คุณลูกค้าต้องการใช้งานในลักษณะใด หรือมีงบประมาณที่กำหนดไว้ไหมคะ?"
                ),
                "questions": [],
                "recommended_items": fallback_items,
                "suggested_replies": [
                    "งบไม่เกิน 500 บาท/วัน",
                    "ขออุปกรณ์สำหรับมืออาชีพ",
                    "มีบริการจัดส่งไหม",
                ],
            }

    @staticmethod
    def _format_card(item: Dict[str, Any]) -> Dict[str, Any]:
        return {
            "id": item.get("id"),
            "item_name": item.get("item_name", "อุปกรณ์เช่า"),
            "price": float(item.get("price") or 0.0),
            "unit": "วัน",
            "image_url": item.get("item_image_url") or "",
            "status": item.get("status", "available"),
            "category": item.get("category", "ทั่วไป"),
            "description": item.get("description", ""),
        }

    @staticmethod
    def _extract_json(text: str) -> Optional[Dict[str, Any]]:
        text = text.strip()
        # Direct json load
        try:
            return json.loads(text)
        except Exception:
            pass

        # Search for {...} markdown block
        match = re.search(r"\{.*\}", text, re.DOTALL)
        if match:
            try:
                return json.loads(match.group(0))
            except Exception:
                pass

        # Try auto-closing suffixes if truncated
        for suffix in ['"}', '"]}', ']}', '}']:
            try:
                return json.loads(text + suffix)
            except Exception:
                pass

        # Fallback regex extraction for answer if JSON was truncated mid-way
        answer_match = re.search(r'"answer"\s*:\s*"((?:[^"\\]|\\.)*)', text, re.DOTALL)
        if answer_match:
            try:
                raw_ans = answer_match.group(1)
                decoded_ans = json.loads(f'"{raw_ans}"')
                mode_match = re.search(r'"mode"\s*:\s*"([^"]+)"', text)
                mode = mode_match.group(1) if mode_match else "recommendation"
                return {
                    "mode": mode,
                    "answer": decoded_ans,
                    "questions": [],
                    "recommended_item_ids": [],
                    "suggested_replies": [],
                }
            except Exception:
                pass

        return None

    def _resolve_recommended_items(
        self,
        raw_ids: List[Any],
        catalog: List[Dict[str, Any]],
        relevant_candidates: List[Dict[str, Any]],
        cleaned_query: str,
        mode: str = "recommendation",
        has_questions: bool = False,
    ) -> List[Dict[str, Any]]:
        # Strictly return empty list for general_chat or questionnaire
        if mode in ("general_chat", "questionnaire") or has_questions:
            return []

        item_map = {item["id"]: item for item in catalog if "id" in item}
        candidate_ids = {item["id"] for item in relevant_candidates if "id" in item}
        recommended_items = []
        seen_ids = set()

        for item_id in raw_ids:
            if isinstance(item_id, (int, str)):
                try:
                    int_id = int(item_id)
                    # Strictly ensure item comes from semantically relevant candidates
                    if candidate_ids and int_id not in candidate_ids:
                        continue
                    if int_id in item_map and int_id not in seen_ids:
                        recommended_items.append(self._format_card(item_map[int_id]))
                        seen_ids.add(int_id)
                except ValueError:
                    continue

        return recommended_items

    @staticmethod
    def _format_questions(raw_questions: Any) -> List[Dict[str, Any]]:
        questions = []
        if isinstance(raw_questions, list):
            for q in raw_questions:
                if isinstance(q, dict) and "title" in q and "options" in q:
                    options = [str(opt).strip() for opt in q["options"] if str(opt).strip()]
                    if options:
                        questions.append({
                            "id": str(q.get("id") or f"q_{len(questions) + 1}"),
                            "step": int(q.get("step") or 1),
                            "total_steps": int(q.get("total_steps") or 2),
                            "title": str(q["title"]).strip(),
                            "options": options,
                        })
        return questions

    async def process_chat_stream(
        self,
        query: str,
        history: Optional[List[Dict[str, str]]] = None,
    ) -> AsyncGenerator[Dict[str, Any], None]:
        cleaned_query = query.strip()
        if not cleaned_query:
            yield {"event": "status", "data": {"step": "ready", "message": "พร้อมให้บริการค่ะ"}}
            yield {"event": "metadata", "data": {"mode": "general_chat", "recommended_items": [], "questions": []}}
            yield {"event": "delta", "data": {"text": "สวัสดีค่ะ! Yuemnoi AI พร้อมช่วยแนะนำอุปกรณ์เช่าค่ะ สามารถสอบถามอุปกรณ์ที่สนใจได้เลยนะคะ"}}
            yield {
                "event": "done",
                "data": {
                    "suggested_replies": [
                        "แนะนำกล้องถ่ายรูปหน่อยค่ะ",
                        "มีอุปกรณ์แคมปิ้งอะไรบ้าง",
                        "อยากเช่าคอมพิวเตอร์ทำงาน",
                        "มีลำโพงจัดงานปาร์ตี้ไหม",
                    ],
                    "recommended_items": [],
                    "questions": [],
                },
            }
            return

        intent = self.classify_query(cleaned_query, history)
        if intent == "general_chat":
            chat_type = self._detect_general_chat_type(cleaned_query.lower()) or "greeting"
            resp_data = self._get_general_chat_response(chat_type)
            yield {"event": "status", "data": {"step": "ready", "message": "พร้อมให้บริการค่ะ"}}
            yield {"event": "metadata", "data": {"mode": "general_chat", "recommended_items": [], "questions": []}}
            yield {"event": "delta", "data": {"text": resp_data["answer"]}}
            yield {
                "event": "done",
                "data": {
                    "suggested_replies": resp_data["suggested_replies"],
                    "recommended_items": [],
                    "questions": [],
                },
            }
            return

        if intent == "out_of_scope":
            yield {"event": "status", "data": {"step": "ready", "message": "พร้อมให้บริการค่ะ"}}
            yield {"event": "metadata", "data": {"mode": "general_chat", "recommended_items": [], "questions": []}}
            yield {"event": "delta", "data": {"text": self.OUT_OF_SCOPE_RESPONSE_TEXT}}
            yield {
                "event": "done",
                "data": {
                    "suggested_replies": self.OUT_OF_SCOPE_SUGGESTED_REPLIES,
                    "recommended_items": [],
                    "questions": [],
                },
            }
            return

        catalog = []
        relevant_candidates = []
        compact_catalog = []

        if intent == "faq":
            yield {"event": "status", "data": {"step": "searching", "message": "กำลังค้นหาข้อมูลนโยบายและบริการ..."}}
        else:
            yield {"event": "status", "data": {"step": "searching", "message": "กำลังค้นหาอุปกรณ์ในคลังสินค้า..."}}
            try:
                catalog = await self.db_tool.list_available_items()
            except Exception as e:
                logger.error("Failed to load catalog from Supabase: %s", e)
                catalog = []

            # Check unsupported domain first (e.g. vehicles/cars/vans, real estate, pets)
            unsupported_domain = DatabaseTool.get_unsupported_category_name(cleaned_query)
            search_query = cleaned_query
            if not unsupported_domain:
                prior_context = self._extract_activity_context(history)
                if prior_context:
                    has_category = any(cat in cleaned_query.lower() for cat in self.BROAD_CATEGORIES)
                    if not has_category or prior_context.lower() in cleaned_query.lower():
                        search_query = f"{prior_context} {cleaned_query}"
                unsupported_domain = DatabaseTool.get_unsupported_category_name(search_query)

            if unsupported_domain:
                resp_data = self._build_out_of_inventory_response(
                    query=search_query,
                    unsupported_domain=unsupported_domain,
                )
                yield {"event": "status", "data": {"step": "ready", "message": "พร้อมให้บริการค่ะ"}}
                yield {"event": "metadata", "data": {"mode": "general_chat", "recommended_items": [], "questions": []}}
                yield {"event": "delta", "data": {"text": resp_data["answer"]}}
                yield {
                    "event": "done",
                    "data": {
                        "suggested_replies": resp_data["suggested_replies"],
                        "recommended_items": [],
                        "questions": [],
                    },
                }
                return

            relevant_candidates = self.db_tool.rank_relevant_items(
                query=search_query,
                items=catalog,
                limit=settings.MAX_RECOMMENDED_ITEMS + 3,
            )

            # If no items match in catalog and intent is recommendation, politely refuse immediately
            if not relevant_candidates and intent == "recommendation":
                resp_data = self._build_out_of_inventory_response(query=cleaned_query)
                yield {"event": "status", "data": {"step": "ready", "message": "พร้อมให้บริการค่ะ"}}
                yield {"event": "metadata", "data": {"mode": "general_chat", "recommended_items": [], "questions": []}}
                yield {"event": "delta", "data": {"text": resp_data["answer"]}}
                yield {
                    "event": "done",
                    "data": {
                        "suggested_replies": resp_data["suggested_replies"],
                        "recommended_items": [],
                        "questions": [],
                    },
                }
                return

            compact_catalog = [
                {
                    "id": item.get("id"),
                    "name": item.get("item_name"),
                    "category": item.get("category"),
                    "price_per_day": item.get("price"),
                    "description": str(item.get("description") or "")[:120],
                }
                for item in relevant_candidates
            ]

        learned_insights = None
        if self.feedback_store:
            try:
                learned_insights = await self.feedback_store.get_learned_insights(cleaned_query)
            except Exception as e:
                logger.warning("Could not retrieve learned insights for stream: %s", e)

        all_categories = sorted(list({
            item.get("category")
            for item in catalog
            if item.get("category") and item.get("category") not in ("อื่น ๆ", "อื่นๆ")
        }))

        system_prompt = self.build_system_prompt(
            intent=intent,
            compact_catalog=compact_catalog,
            learned_insights=learned_insights,
            available_categories=all_categories,
        )

        messages: List[Dict[str, Any]] = [{"role": "system", "content": system_prompt}]
        if history:
            for msg in history[-settings.MAX_HISTORY_MESSAGES:]:
                role = msg.get("role")
                content = str(msg.get("content") or "").strip()
                if role in ("user", "assistant") and content:
                    messages.append({"role": role, "content": content[:300]})
        messages.append({"role": "user", "content": cleaned_query})

        yield {"event": "status", "data": {"step": "generating", "message": "กำลังจัดเตรียมคำแนะนำ..."}}

        parser = StreamJsonParser()
        stream_had_output = False
        resolved_items: List[Dict[str, Any]] = []
        resolved_questions: List[Dict[str, Any]] = []
        if intent == "faq":
            resolved_mode = "general_chat"
        elif intent == "questionnaire":
            resolved_mode = "questionnaire"
        else:
            resolved_mode = "recommendation"

        try:
            async for chunk in self.ollama.stream_chat(
                messages=messages,
                format="json",
                max_tokens=1500,
                temperature=0.3,
                timeout=settings.PIPELINE_TIMEOUT,
                think=False,
            ):
                events = parser.feed(chunk)
                for ev in events:
                    stream_had_output = True
                    if ev["event"] == "metadata":
                        resolved_mode = ev["data"].get("mode", resolved_mode)
                        raw_ids = ev["data"].get("recommended_item_ids") or []
                        raw_qs = ev["data"].get("questions") or []
                        resolved_questions = self._format_questions(raw_qs)
                        if resolved_questions and resolved_mode == "questionnaire":
                            resolved_questions = self._validate_and_align_questionnaire(
                                questions=resolved_questions,
                                query=cleaned_query,
                                relevant_candidates=relevant_candidates,
                                catalog=catalog,
                            )
                        resolved_items = self._resolve_recommended_items(
                            raw_ids=raw_ids,
                            catalog=catalog,
                            relevant_candidates=relevant_candidates,
                            cleaned_query=cleaned_query,
                            mode=resolved_mode,
                            has_questions=bool(resolved_questions),
                        )
                        yield {
                            "event": "metadata",
                            "data": {
                                "mode": resolved_mode,
                                "recommended_items": resolved_items[:settings.MAX_RECOMMENDED_ITEMS],
                                "questions": resolved_questions,
                            },
                        }
                    elif ev["event"] == "delta":
                        raw_delta = ev["data"].get("text", "")
                        clean_delta = self._clean_delta(raw_delta)
                        if clean_delta:
                            yield {"event": "delta", "data": {"text": clean_delta}}
                    else:
                        yield ev

            finish_events = parser.finish()
            for ev in finish_events:
                stream_had_output = True
                if ev["event"] == "metadata":
                    resolved_mode = ev["data"].get("mode", resolved_mode)
                    raw_ids = ev["data"].get("recommended_item_ids") or []
                    raw_qs = ev["data"].get("questions") or []
                    resolved_questions = self._format_questions(raw_qs)
                    if resolved_questions and resolved_mode == "questionnaire":
                        resolved_questions = self._validate_and_align_questionnaire(
                            questions=resolved_questions,
                            query=cleaned_query,
                            relevant_candidates=relevant_candidates,
                            catalog=catalog,
                        )
                    resolved_items = self._resolve_recommended_items(
                        raw_ids=raw_ids,
                        catalog=catalog,
                        relevant_candidates=relevant_candidates,
                        cleaned_query=cleaned_query,
                        mode=resolved_mode,
                        has_questions=bool(resolved_questions),
                    )
                    yield {
                        "event": "metadata",
                        "data": {
                            "mode": resolved_mode,
                            "recommended_items": resolved_items[:settings.MAX_RECOMMENDED_ITEMS],
                            "questions": resolved_questions,
                        },
                    }
                elif ev["event"] == "done":
                    final_data = dict(ev["data"])
                    final_data["recommended_items"] = resolved_items[:settings.MAX_RECOMMENDED_ITEMS]
                    final_data["questions"] = resolved_questions
                    if not final_data.get("suggested_replies"):
                        if resolved_mode == "questionnaire":
                            final_data["suggested_replies"] = ["พิมพ์ตอบเอง", "ข้ามแบบสอบถาม"]
                        elif resolved_mode == "general_chat":
                            final_data["suggested_replies"] = ["สอบถามขั้นตอนการเช่า", "นโยบายเงินมัดจำ"]
                        else:
                            final_data["suggested_replies"] = ["ขอดูอุปกรณ์เสริมเพิ่ม", "สอบถามขั้นตอนการเช่า"]
                    yield {"event": "done", "data": final_data}
                elif ev["event"] == "delta":
                    raw_delta = ev["data"].get("text", "")
                    clean_delta = self._clean_delta(raw_delta)
                    if clean_delta:
                        yield {"event": "delta", "data": {"text": clean_delta}}
                else:
                    yield ev

        except Exception as exc:
            logger.error("Error during streaming LLM inference: %s", exc)
            if not stream_had_output:
                if intent == "faq":
                    yield {
                        "event": "metadata",
                        "data": {"mode": "general_chat", "recommended_items": [], "questions": []},
                    }
                    yield {
                        "event": "delta",
                        "data": {
                            "text": (
                                "แพลตฟอร์ม Yuemnoi มีระบบดูแลและคุ้มครองความปลอดภัยสำหรับผู้เช่าและผู้ให้เช่าค่ะ "
                                "คุณลูกค้าสามารถสอบถามข้อมูลเกี่ยวกับเงินมัดจำ, ประกันความคุ้มครอง, หรือขั้นตอนการเช่าเพิ่มเติมได้เลยนะคะ 😊"
                            ),
                        },
                    }
                    yield {
                        "event": "done",
                        "data": {
                            "suggested_replies": ["สอบถามขั้นตอนการเช่า", "มีประกันอุปกรณ์ไหม", "นโยบายเงินมัดจำ"],
                            "recommended_items": [],
                            "questions": [],
                        },
                    }
                elif intent == "questionnaire":
                    fallback_qs = self._get_fallback_questions(
                        cleaned_query,
                        catalog=catalog,
                    )
                    fallback_intro = self._get_fallback_questionnaire_intro(
                        cleaned_query,
                        catalog=catalog,
                    )
                    yield {
                        "event": "metadata",
                        "data": {"mode": "questionnaire", "recommended_items": [], "questions": fallback_qs},
                    }
                    yield {
                        "event": "delta",
                        "data": {"text": fallback_intro},
                    }
                    yield {
                        "event": "done",
                        "data": {
                            "suggested_replies": ["พิมพ์ตอบเอง", "ข้ามแบบสอบถาม"],
                            "recommended_items": [],
                            "questions": fallback_qs,
                        },
                    }
                else:
                    fallback_items = [self._format_card(item) for item in relevant_candidates[:2]]
                    yield {
                        "event": "metadata",
                        "data": {
                            "mode": "recommendation",
                            "recommended_items": fallback_items,
                            "questions": [],
                        },
                    }
                    yield {
                        "event": "delta",
                        "data": {
                            "text": (
                                "ขออภัยในความไม่สะดวกค่ะ ขณะนี้ระบบกำลังประมวลผลข้อมูลอุปกรณ์ "
                                "เบื้องต้นได้ค้นหาอุปกรณ์ที่อาจตรงกับความต้องการของคุณลูกค้าไว้ให้แล้วนะคะ "
                                "คุณลูกค้าต้องการใช้งานในลักษณะใด หรือมีงบประมาณที่กำหนดไว้ไหมคะ?"
                            ),
                        },
                    }
                    yield {
                        "event": "done",
                        "data": {
                            "suggested_replies": [
                                "งบไม่เกิน 500 บาท/วัน",
                                "ขออุปกรณ์สำหรับมืออาชีพ",
                                "มีบริการจัดส่งไหม",
                            ],
                            "recommended_items": fallback_items,
                            "questions": [],
                        },
                    }
