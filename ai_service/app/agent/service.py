import json
import logging
import re
from typing import Any, AsyncGenerator, Dict, List, Optional, Tuple

from config import settings
from ..llm.ollama_client import OllamaClient
from ..tools.database_tool import DatabaseTool
from .cognitive_analyzer import CognitiveAnalyzer, CognitiveResult
from .stream_parser import StreamJsonParser

logger = logging.getLogger("uvicorn.error")


class YuemnoiConsultantService:
    """
    Intelligent, consultative rental AI service powered by local LLM (Typhoon 2 8B) and Supabase.
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
        "สนใจ", "อยากได้", "มองหา", "ต้องการ", "ขอดู", "อยากลอง",
        # Greetings & Acknowledgements
        "สวัสดี", "หวัดดี", "ดีครับ", "ดีค่ะ", "hello", "hi", "ขอบคุณ", "ขอบใจ", "thanks", "ok", "โอเค",
    ]

    BROAD_ACTIVITIES = [
        "เดินป่า", "เดินเขา", "ปีนเขา", "ขึ้นเขา", "แคมป์", "แคมปิ้ง", "กางเต็นท์", "เที่ยว", "ทริป",
        "ถ่ายรูป", "ถ่ายภาพ", "ถ่ายวิดีโอ", "ทำคลิป", "vlog", "พอร์ตเทรต",
        "จัดงาน", "ปาร์ตี้", "สัมมนา", "อีเวนต์", "งานแต่ง", "งานแต่งงาน",
        "ดนตรี", "เล่นดนตรี", "ซ้อมดนตรี", "คอนเสิร์ต", "ร้องเพลง",
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
        "เครื่องดนตรี", "ดนตรี", "กีตาร์", "กีต้าร์", "กีตาร์โปร่ง", "กีตาร์ไฟฟ้า", "คีย์บอร์ด", "เปียโน", "เบส", "กลอง",
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
        "martin", "fender", "gibson", "taylor", "ibanez", "roland", "casio", "korg", "epiphone", "squier", "sennheiser", "audio-technica",
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

    COMPARISON_KEYWORDS = (
        "ต่างกับ", "ต่างจาก", "ต่างกัน", "เทียบกับ", "เทียบ", "เปรียบเทียบ",
        "vs", "versus", "v.s.",
        "อันไหนดีกว่า", "อันไหนน่าใช้กว่า", "ตัวไหนดีกว่า", "รุ่นไหนดีกว่า", "อันไหนเหมาะกว่า",
        "ข้อดีข้อเสีย", "ข้อดี ข้อเสีย", "จุดเด่นจุดด้อย", "จุดเด่น จุดด้อย", "ข้อแตกต่าง",
        "ต่างกันยังไง", "ต่างกันไง", "ต่างกันอย่างไร", "ต่างกันไหม", "ต่างกันมั้ย",
        "เลือกอะไรดีระหว่าง", "เลือกรุ่นไหนดีระหว่าง", "เลือกตัวไหนดีระหว่าง",
        "ความแตกต่าง",
    )

    COMPARISON_FOLLOWUP_KEYWORDS = (
        "ถามว่าต่าง", "บอกว่าต่าง", "ว่าต่างกัน", "สรุปต่าง", "เทียบให้",
        "สองตัวนี้", "สองอันนี้", "สองรุ่นนี้", "คู่นี้", "ทั้งสองตัว", "ทั้งสองอัน",
    )

    def __init__(
        self,
        ollama: OllamaClient,
        db_tool: DatabaseTool,
        feedback_store: Optional[Any] = None,
        google_tool: Optional[Any] = None,
    ):
        self.ollama = ollama
        self.db_tool = db_tool
        self.feedback_store = feedback_store
        self.google_tool = google_tool
        self.cognitive_analyzer = CognitiveAnalyzer(self.ollama)

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
        target_entity: Optional[str] = None,
        domain_category: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Builds a polite, warm refusal response when the requested item or category does not exist in inventory.
        Guarantees recommended_items is strictly empty ([]) and no hallucinated recommendations occur.
        If the query is a general/exploratory request (e.g. asking what is available), warmly guides the user instead of refusing.
        """
        generic_inquiry_terms = {
            "ไร", "อะไร", "ไรให้เช่า", "อะไรให้เช่า", "ของ", "ของเช่า", "ของให้เช่า",
            "อะไรบ้าง", "อุปกรณ์", "อุปกรณ์เช่า", "มีอะไร", "มีไร", "มีไรให้เช่า", "มีอะไรให้เช่า",
            "ชิ้น", "อัน", "บริการ", "แนะนำ", "ช่วย", "ช่วยแนะนำ", "สินค้า", "ช่วยหน่อย",
            "มีของอะไรบ้าง", "ขอดูของ", "ขอดูของเช่า", "ขอดูของหน่อย"
        }

        if unsupported_domain:
            target_desc = f"**{unsupported_domain}**"
            is_generic_question = False
        elif target_entity and target_entity.strip():
            clean_target = self._clean_comparison_entity(target_entity.strip())
            norm_target = clean_target.lower().strip()
            if norm_target in generic_inquiry_terms or any(norm_target == term for term in generic_inquiry_terms):
                is_generic_question = True
                target_desc = "อุปกรณ์ดังกล่าว"
            else:
                target_desc = f"**{clean_target}**"
                is_generic_question = False
        else:
            clean_q = re.sub(
                r"^(?:เรา|ผม|หนู|ฉัน|พวกเรา|ทางเรา)?\s*(?:อยากได้|อยากเช่า|ต้องการ|สนใจ|มี|ขอ|ช่วยแนะนำ|หา|มองหา|อยากดู)\s*",
                "",
                query.strip(),
                flags=re.IGNORECASE,
            )
            clean_q = re.sub(
                r"\s*(?:ไหม|มั้ย|คะ|ครับ|บ้าง|หน่อย|นะ|จ๊ะ|รึเปล่า|หรือเปล่า|ได้ไหม|ได้มั้ย)$",
                "",
                clean_q,
                flags=re.IGNORECASE,
            ).strip()
            clean_q = self._clean_comparison_entity(clean_q)

            norm_cq = clean_q.lower().strip()
            is_generic_question = (
                not norm_cq
                or norm_cq in generic_inquiry_terms
                or any(norm_cq == term for term in generic_inquiry_terms)
                or any(norm_cq.startswith(term) and len(norm_cq) <= len(term) + 4 for term in ("ไร", "อะไร", "ของเช่า", "มีอะไร", "มีไร"))
            )
            target_desc = f"**{clean_q}**" if clean_q else "อุปกรณ์หรือบริการดังกล่าว"

        cats_text = (
            "- 📷 **กล้องและอุปกรณ์ถ่ายภาพ** (เช่น Sony A7 IV, เลนส์, โดรน DJI, ขาตั้งกล้อง)\n"
            "- ⛺ **แคมป์ปิงและกิจกรรมกลางแจ้ง** (เช่น เต็นท์ Naturehike/Coleman, เก้าอี้แคมป์)\n"
            "- 💻 **คอมพิวเตอร์และอุปกรณ์ไอที** (เช่น โน้ตบุ๊ก, แท็บเล็ต, หน้าจอ, อุปกรณ์เสริม)\n"
            "- 🎸 **ดนตรีและเครื่องเสียง** (เช่น กีตาร์โปร่ง Yamaha, ลำโพง Marshall, ไมค์ลอย)"
        )

        if is_generic_question:
            answer = (
                "ยินดีต้อนรับสู่ **Yuemnoi (ยืมน้อย)** ค่ะ! แพลตฟอร์มของเรามีบริการให้เช่าอุปกรณ์คุณภาพหลากหลายหมวดหมู่พร้อมให้บริการค่ะ 😊\n\n"
                f"ปัจจุบัน Yuemnoi มุ่งเน้นการให้บริการเช่าอุปกรณ์ในหมวดหมู่ยอดนิยมดังนี้ค่ะ:\n{cats_text}\n\n"
                "คุณลูกค้าสนใจอุปกรณ์ในหมวดหมู่ไหน หรือมีกิจกรรมที่ต้องการใช้งาน สามารถบอกความต้องการหรือให้ Yuemnoi แนะนำได้เลยนะคะ ✨"
            )
            suggested_replies = [
                "แนะนำกล้องถ่ายรูป",
                "มีอุปกรณ์แคมปิ้งอะไรบ้าง",
                "อยากเช่าโน้ตบุ๊กทำงาน",
                "ขั้นตอนการเช่าอุปกรณ์",
            ]
        else:
            alt_text = ""
            if domain_category:
                dom_lower = domain_category.lower()
                if any(m in dom_lower for m in ("ดนตรี", "เครื่องดนตรี", "กีตาร์", "guitar", "music")):
                    alt_text = "\n\n💡 แต่ในหมวดเครื่องดนตรี Yuemnoi มีอุปกรณ์คุณภาพรุ่นอื่นที่พร้อมให้เช่า เช่น **กีตาร์โปร่ง Yamaha F310** ซึ่งเป็นรุ่นยอดนิยม เสียงดี เล่นง่าย และเหมาะสำหรับทั้งผู้เริ่มต้นและผู้เล่นทั่วไปค่ะ"
                elif any(c in dom_lower for c in ("กล้อง", "ถ่ายภาพ", "camera", "photo")):
                    alt_text = "\n\n💡 แต่ในหมวดกล้องและอุปกรณ์ถ่ายภาพ Yuemnoi มีอุปกรณ์คุณภาพพร้อมให้บริการ เช่น **Sony Alpha A7 IV**, **Fujifilm X-T5**, หรือโดรน **DJI Mini 4 Pro** ค่ะ"
                elif any(cp in dom_lower for cp in ("แคมปิ้ง", "กลางแจ้ง", "camping", "outdoor")):
                    alt_text = "\n\n💡 แต่ในหมวดแคมปิ้ง Yuemnoi มีอุปกรณ์คุณภาพพร้อมให้เช่า เช่น **เต็นท์ Naturehike Village 13**, เก้าอี้แคมป์ปิ้ง และชุดอุปกรณ์แคมป์ครบชุดค่ะ"
                elif any(it in dom_lower for it in ("คอมพิวเตอร์", "ไอที", "it", "โน้ตบุ๊ก")):
                    alt_text = "\n\n💡 แต่ในหมวดอุปกรณ์ไอที Yuemnoi มีอุปกรณ์พร้อมให้บริการ เช่น โน้ตบุ๊กและแท็บเล็ตประสิทธิภาพสูงค่ะ"

            answer = (
                f"ขออภัยด้วยนะคะ ขณะนี้แพลตฟอร์ม **Yuemnoi (ยืมน้อย)** ยังไม่มีบริการให้เช่า {target_desc} ในระบบค่ะ 🙏"
                f"{alt_text}\n\n"
                f"ปัจจุบัน Yuemnoi มุ่งเน้นการให้บริการเช่าอุปกรณ์ในหมวดหมู่ยอดนิยมดังนี้ค่ะ:\n{cats_text}\n\n"
                "หากคุณลูกค้าสนใจอุปกรณ์ในหมวดหมู่ข้างต้น หรือต้องการให้ Yuemnoi แนะนำอุปกรณ์ทดแทน สามารถบอกได้เลยนะคะ 😊"
            )

            if domain_category and any(m in domain_category.lower() for m in ("ดนตรี", "เครื่องดนตรี", "กีตาร์", "guitar", "music")):
                suggested_replies = [
                    "สนใจเช่า Yamaha F310",
                    "มีเครื่องดนตรีอะไรบ้าง",
                    "ขั้นตอนการเช่าอุปกรณ์",
                    "นโยบายเงินมัดจำ",
                ]
            else:
                suggested_replies = [
                    "แนะนำกล้องถ่ายรูป",
                    "มีอุปกรณ์แคมปิ้งอะไรบ้าง",
                    "อยากเช่าโน้ตบุ๊กทำงาน",
                    "ขั้นตอนการเช่าอุปกรณ์",
                ]

        return {
            "status": "success",
            "mode": "general_chat",
            "answer": answer,
            "questions": [],
            "recommended_items": [],
            "suggested_replies": suggested_replies,
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

        # 1.1 Comparison Check (Direct comparisons, pros/cons, or contextual corrections like 'ไม่เราถามว่าต่างกันไง')
        if self._is_comparison_query(norm, history):
            return "comparison"

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

            # Check if query is a fresh question or exploratory inquiry rather than answering questionnaire
            is_new_inquiry = (
                any(norm.startswith(p) for p in ("มี", "ขอ", "อยากรู้", "สอบถาม", "ทำไม", "คือ", "แล้ว", "ถ้า", "หา"))
                or any(q in norm for q in ("อะไรบ้าง", "ไรบ้าง", "มีอะไร", "มีไร", "อะไรให้เช่า", "ไรให้เช่า", "เช่าอะไร", "ยืมอะไร", "อะไรดี", "แนะนำหน่อย", "ช่วยหน่อย", "มีของ"))
            )

            # User answering questionnaire options or replying after questionnaire prompt
            if not is_new_inquiry:
                if (was_questionnaire_prompt and (is_followup_answer or self._check_is_sufficiently_specific(norm))) or ((prior_context or has_assistant_prompt) and is_followup_answer):
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

    def _is_comparison_query(self, norm: str, history: Optional[List[Dict[str, str]]] = None) -> bool:
        """
        Determines if the query is asking to compare devices/equipment, either directly
        (e.g., 'ระหว่าง คีย์บอร์ด 61 คีย์ ต่างกับ กีตาร์โปร่ง Yamaha ไง', 'กล้อง A กับ กล้อง B อันไหนดีกว่า')
        or contextually / as a follow-up correction (e.g., 'ไม่เราถามว่าต่างกันไง', 'แล้วสองตัวนี้ต่างกันยังไง').
        """
        # 1. Direct comparison keywords
        if any(kw in norm for kw in self.COMPARISON_KEYWORDS):
            return True

        # 2. Pattern: ระหว่าง ... กับ ... (between X and Y) with comparison intent
        if "ระหว่าง" in norm and any(sep in norm for sep in ("กับ", "และ", "เทียบ")):
            return True

        # 3. Follow-up / Contextual comparison with reference to previous turn
        if any(kw in norm for kw in self.COMPARISON_FOLLOWUP_KEYWORDS):
            if any(w in norm for w in ("ต่าง", "เทียบ", "ดีกว่า", "เหมาะกว่า", "ข้อดี", "ข้อเสีย")):
                return True

        # 4. Contextual correction: "ไม่/ไม่ใช่ ... ถามว่า/ว่า ... ต่าง"
        if any(neg in norm for neg in ("ไม่", "ไม่ใช่", "เราถาม", "ถามว่า", "บอกว่า", "สรุป")):
            if any(w in norm for w in ("ต่าง", "เทียบ", "ดีกว่า", "ข้อดีข้อเสีย", "ข้อดี", "ความต่าง")):
                return True

        return False

    @staticmethod
    def _clean_comparison_entity(text: str) -> str:
        """
        Cleans extracted comparison entity by stripping conversational prefixes,
        fillers, question suffixes, and standardizing brand casing.
        """
        s = str(text or "").strip()
        # Strip conversational prefixes and fillers
        s = re.sub(
            r"^(?:แล้ว(?:ถ้า)?|ถ้า|งั้น|สรุป|ระหว่าง|ช่วย|อยากรู้ว่า|อยากทราบว่า|ลอง|ขอ|เปรียบเทียบ|ดู|เลือก|เอา|พวก|แบบ|ตัว|รุ่น|แบรนด์|ยี่ห้อ)\s*",
            "",
            s,
            flags=re.IGNORECASE,
        ).strip()
        # Strip leading conjunctions
        s = re.sub(r"^(?:กับ|และ|หรือ|เทียบกับ|เปรียบเทียบกับ|vs\.?|versus)\s*", "", s, flags=re.IGNORECASE).strip()
        # Strip comparison / question / politeness suffixes
        s = re.sub(
            r"\s*(?:ต่างกันยังไง|ต่างกันอย่างไร|ต่างกันไง|ต่างกันมั้ย|ต่างกันไหม|ต่างกันตรงไหน|ต่างกัน|ต่าง|ยังไง|อย่างไร|ไง|ตรงไหน|ข้อดีข้อเสีย|ข้อดี|ข้อเสีย|อันไหนดีกว่า|ตัวไหนดีกว่า|รุ่นไหนดีกว่า|อันไหนเหมาะกว่า|ตัวไหนเหมาะกว่า|อันไหนดี|ตัวไหนดี|ดีกว่า|เหมาะกว่า|หน่อย|ครับ|ค่ะ|นะคะ|หน่อยครับ|หน่อยค่ะ|บ้าง|ล่ะ|นะ)\??$",
            "",
            s,
            flags=re.IGNORECASE,
        ).strip()
        # Remove surrounding markdown symbols, quotes or brackets
        s = s.strip("*_`'\"() ")

        # Common brand name casing preservation
        known_brands_map = {
            "martin": "Martin", "yamaha": "Yamaha", "fender": "Fender", "gibson": "Gibson",
            "taylor": "Taylor", "ibanez": "Ibanez", "roland": "Roland", "casio": "Casio",
            "korg": "Korg", "sony": "Sony", "canon": "Canon", "nikon": "Nikon", "fujifilm": "Fujifilm",
            "fuji": "Fuji", "panasonic": "Panasonic", "lumix": "Lumix", "gopro": "GoPro", "dji": "DJI",
            "apple": "Apple", "macbook": "MacBook", "ipad": "iPad", "iphone": "iPhone",
            "asus": "ASUS", "dell": "Dell", "lenovo": "Lenovo", "acer": "Acer", "hp": "HP",
            "k2": "K2", "coleman": "Coleman", "naturehike": "Naturehike", "quechua": "Quechua",
            "dod": "DOD", "blackdeer": "Blackdeer", "bosch": "Bosch", "dyson": "Dyson",
            "xiaomi": "Xiaomi", "marshall": "Marshall", "jbl": "JBL", "bose": "Bose",
            "rode": "Rode", "shure": "Shure", "saramonic": "Saramonic",
        }
        low = s.lower()
        if low in known_brands_map:
            return known_brands_map[low]
        for b_low, b_proper in known_brands_map.items():
            if low == b_low:
                return b_proper
            if low.startswith(b_low + " "):
                return b_proper + s[len(b_low):]
        if s.isascii() and s.islower() and len(s) >= 2:
            return s.title()
        return s

    def _extract_comparison_entities(
        self,
        query: str,
        history: Optional[List[Dict[str, str]]] = None,
    ) -> Tuple[str, str]:
        """
        Extracts the two entities being compared from the query or conversation history.
        Handles both direct queries ('ระหว่าง X ต่างกับ Y ไง') and follow-ups ('ไม่เราถามว่าต่างกันไง').
        """
        norm = query.strip()

        # Step 1: Direct extraction from current query
        clean = norm
        # Remove common conversational prefixes
        clean = re.sub(
            r"^(?:แล้ว(?:ถ้า)?|ถ้า|งั้น|สรุป|ระหว่าง|ช่วย|อยากรู้ว่า|อยากทราบว่า|ลอง|ขอ|เปรียบเทียบ)\s*",
            "",
            clean,
            flags=re.IGNORECASE,
        )
        # Remove common question/politeness suffixes
        clean = re.sub(
            r"\s*(?:ต่างกันยังไง|ต่างกันอย่างไร|ต่างกันไง|ต่างกันมั้ย|ต่างกันไหม|ต่างกันตรงไหน|ต่างกัน|ต่าง|ยังไง|อย่างไร|ไง|ตรงไหน|ข้อดีข้อเสีย|ข้อดี|ข้อเสีย|อันไหนดีกว่า|ตัวไหนดีกว่า|รุ่นไหนดีกว่า|อันไหนเหมาะกว่า|ตัวไหนเหมาะกว่า|หน่อย|ครับ|ค่ะ|นะคะ|หน่อยครับ|หน่อยค่ะ|บ้าง|ล่ะ|นะ)\??$",
            "",
            clean,
            flags=re.IGNORECASE,
        )

        delimiters = [
            r"\s+ต่างกับ\s+",
            r"\s+ต่างจาก\s+",
            r"\s+เทียบกับ\s+",
            r"\s+เปรียบเทียบกับ\s+",
            r"\s+vs\.?\s+",
            r"\s+versus\s+",
            r"ต่างกับ",
            r"ต่างจาก",
            r"เทียบกับ",
            r"\s+กับ\s+",
        ]

        item_a, item_b = "", ""
        for delim in delimiters:
            parts = re.split(delim, clean, maxsplit=1, flags=re.IGNORECASE)
            if len(parts) == 2:
                cand_a = self._clean_comparison_entity(parts[0])
                cand_b = self._clean_comparison_entity(parts[1])
                if len(cand_a) >= 2 and len(cand_b) >= 2:
                    item_a, item_b = cand_a, cand_b
                    break

        if item_a and item_b:
            return (item_a, item_b)

        # Step 2: Contextual Extraction from History (e.g. user said "ไม่เราถามว่าต่างกันไง")
        if history:
            # 2A: Check previous user queries
            for msg in reversed(history[-6:]):
                if msg.get("role") == "user":
                    prev_query = str(msg.get("content") or "").strip()
                    if prev_query and prev_query != query:
                        prev_clean = re.sub(
                            r"^(?:แล้ว(?:ถ้า)?|ถ้า|งั้น|สรุป|ระหว่าง|ช่วย|อยากรู้ว่า|อยากทราบว่า|ลอง|ขอ|เปรียบเทียบ)\s*",
                            "",
                            prev_query,
                            flags=re.IGNORECASE,
                        )
                        prev_clean = re.sub(
                            r"\s*(?:ต่างกันยังไง|ต่างกันอย่างไร|ต่างกันไง|ต่างกันมั้ย|ต่างกันไหม|ต่างกันตรงไหน|ต่างกัน|ต่าง|ยังไง|อย่างไร|ไง|ตรงไหน|ข้อดีข้อเสีย|ข้อดี|ข้อเสีย|อันไหนดีกว่า|ตัวไหนดีกว่า|รุ่นไหนดีกว่า|อันไหนเหมาะกว่า|ตัวไหนเหมาะกว่า|หน่อย|ครับ|ค่ะ|นะคะ|ล่ะ|นะ)\??$",
                            "",
                            prev_clean,
                            flags=re.IGNORECASE,
                        )
                        for delim in delimiters:
                            parts = re.split(delim, prev_clean, maxsplit=1, flags=re.IGNORECASE)
                            if len(parts) == 2:
                                cand_a = self._clean_comparison_entity(parts[0])
                                cand_b = self._clean_comparison_entity(parts[1])
                                if len(cand_a) >= 2 and len(cand_b) >= 2:
                                    return (cand_a, cand_b)

            # 2B: Check previous assistant response for highlighted items (- **Item Name**)
            for msg in reversed(history[-4:]):
                if msg.get("role") == "assistant":
                    content = str(msg.get("content") or "")
                    bullet_items = re.findall(r"-\s*\*\*([^*]+)\*\*", content)
                    if len(bullet_items) >= 2:
                        return (self._clean_comparison_entity(bullet_items[0]), self._clean_comparison_entity(bullet_items[1]))

        if item_a:
            return (item_a, "อุปกรณ์เปรียบเทียบ")
        return ("อุปกรณ์แรก", "อุปกรณ์ที่สอง")

    def _find_catalog_items_for_entities(
        self,
        entities: Tuple[str, str],
        catalog: List[Dict[str, Any]],
        domain_category: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        """Finds items in catalog matching either of the compared entities with contextual affinity."""
        matched = []
        seen_ids = set()
        norm_domain = (domain_category or "").lower().strip()
        for entity in entities:
            if not entity or len(entity) < 2 or entity in ("อุปกรณ์แรก", "อุปกรณ์ที่สอง", "อุปกรณ์เปรียบเทียบ"):
                continue
            entity_norm = entity.lower().strip()
            tokens = [t for t in re.split(r"[\s,]+", entity_norm) if len(t) >= 2]
            best_match = None
            best_score = 0

            # Determine other entity for contextual affinity
            other_entities = [e.lower().strip() for e in entities if e != entity and e]
            other_text = " ".join(other_entities)

            for item in catalog:
                i_id = item.get("id")
                if i_id in seen_ids:
                    continue
                name = str(item.get("item_name") or "").lower()
                desc = str(item.get("description") or "").lower()
                cat = str(item.get("category") or "").lower()

                score = 0
                has_direct_entity_match = False
                # Exact match or substring in name
                if entity_norm in name:
                    score += 100
                    has_direct_entity_match = True
                elif any(token in name for token in tokens):
                    score += 40
                    has_direct_entity_match = True

                for token in tokens:
                    if token in name:
                        score += 20
                        has_direct_entity_match = True
                    elif token in desc:
                        score += 5
                        has_direct_entity_match = True

                # If the item has no direct match with this specific compared entity, it cannot match
                if not has_direct_entity_match:
                    continue

                # Contextual affinity with the other entity being compared:
                # 1. Guitar / String instruments affinity
                if any(g in other_text for g in ("martin", "fender", "gibson", "taylor", "กีตาร์", "กีต้าร์", "guitar")):
                    if "กีตาร์" in name or "กีต้าร์" in name or "guitar" in name:
                        score += 50
                # 2. Keyboard / Piano affinity
                elif any(k in other_text for k in ("roland", "casio", "korg", "คีย์บอร์ด", "เปียโน", "keyboard")):
                    if "คีย์บอร์ด" in name or "เปียโน" in name or "keyboard" in name:
                        score += 50
                # 3. Camera / Photography affinity
                elif any(c in other_text for c in ("sony", "canon", "nikon", "fujifilm", "fuji", "panasonic", "lumix", "กล้อง", "camera")):
                    if "กล้อง" in name or "camera" in name or "lens" in name:
                        score += 50
                # 4. Camping / Outdoor affinity
                elif any(cmp in other_text for cmp in ("coleman", "naturehike", "k2", "dod", "เต็นท์", "เต้นท์", "แคมปิ้ง", "camping")):
                    if "เต็นท์" in name or "แคมปิ้ง" in name or "camping" in name:
                        score += 50

                # 5. Cognitive Domain Category Affinity
                if norm_domain:
                    if norm_domain in cat or cat in norm_domain:
                        score += 35
                    elif any(w in cat or w in name for w in norm_domain.split() if len(w) >= 3):
                        score += 25

                if score > best_score and score >= 20:
                    best_score = score
                    best_match = item

            if best_match:
                matched.append(best_match)
                seen_ids.add(best_match.get("id"))

        return matched

    def build_system_prompt(
        self,
        intent: str,
        compact_catalog: List[Dict[str, Any]],
        learned_insights: Optional[Dict[str, List[str]]] = None,
        available_categories: Optional[List[str]] = None,
        followup_context: Optional[Dict[str, str]] = None,
        comparison_search_data: Optional[str] = None,
        compared_entities: Optional[Tuple[str, str]] = None,
        domain_category: Optional[str] = None,
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
                "  5) 'suggested_replies': ตัวเลือกคำถามที่เกี่ยวข้อง 2-3 ข้อ\n"
                "- **ห้ามตอบเป็น JSON ของสินค้าชิ้นเดียวเด็ดขาด!** ต้องตอบในโครงสร้าง JSON ครบทุกคีย์เสมอ\n"
                "- **ห้ามปล่อยให้คีย์ answer เป็นค่าว่าง (\"\") เด็ดขาด!**\n\n"
                "ตัวอย่างรูปแบบ JSON ที่ต้องตอบ:\n"
                "{\n"
                '  "mode": "general_chat",\n'
                '  "recommended_item_ids": [],\n'
                '  "questions": [],\n'
                '  "answer": "ขั้นตอนการเช่าอุปกรณ์บน Yuemnoi ทำได้ง่ายๆ 4 ขั้นตอนดังนี้ค่ะ:\\n\\n1. เลือกอุปกรณ์และระบุวันที่ต้องการเช่า\\n2. ชำระค่าเช่าและเงินมัดจำผ่านระบบอย่างปลอดภัย\\n3. รับอุปกรณ์และตรวจเช็กสภาพก่อนใช้งาน\\n4. ส่งคืนอุปกรณ์เมื่อครบกำหนดค่ะ",\n'
                '  "suggested_replies": ["นโยบายเงินมัดจำ", "มีประกันอุปกรณ์ไหม", "ค้นหาอุปกรณ์ที่ต้องการเช่า"]\n'
                "}"
            )
        elif intent == "comparison":
            ent_a = compared_entities[0] if compared_entities else "อุปกรณ์แรก"
            ent_b = compared_entities[1] if compared_entities else "อุปกรณ์ที่สอง"

            search_section = ""
            if comparison_search_data:
                search_section = (
                    f"### 🌐 ข้อมูลสเปกและข้อเท็จจริงที่ตรวจสอบจากอินเทอร์เน็ต (Verified Internet Search Data):\n"
                    f"{comparison_search_data}\n\n"
                )
            else:
                search_section = (
                    f"### 🌐 ข้อมูลสเปกและข้อเท็จจริง:\n"
                    f"นำข้อมูลสเปก จุดเด่น และข้อจำกัดที่เป็นจริงของ '{ent_a}' และ '{ent_b}' มาใช้เปรียบเทียบอย่างถูกต้องและเป็นกลาง\n\n"
                )

            base_prompt = (
                "คุณคือ Yuemnoi AI ผู้ช่วยประจำแพลตฟอร์มเช่าอุปกรณ์ 'Yuemnoi' (ยืมน้อย) ผู้เชี่ยวชาญการเปรียบเทียบอุปกรณ์\n"
                "มีบุคลิกภาพสุภาพ อบอุ่น เป็นมิตร เชี่ยวชาญ ให้ข้อมูลเปรียบเทียบเชิงลึกอย่างเป็นกลาง ถูกต้องตามสเปกจริง (ลงท้าย ค่ะ/คะ)\n\n"
                f"อุปกรณ์ที่นำมาเปรียบเทียบ: '{ent_a}' กับ '{ent_b}'\n\n"
                f"{search_section}"
                "กฎเหล็กสำคัญที่สุดสำหรับการเปรียบเทียบ (CRITICAL COMPARISON RULES):\n"
                "1. **ความถูกต้องแม่นยำและห้ามเดาสเปก (Strict Fact Grounding)**:\n"
                "   - นำข้อมูลสเปก คุณสมบัติ จุดเด่น และข้อเท็จจริงจากข้อมูลที่ตรวจสอบด้านบนมาใช้ในการเปรียบเทียบ ห้ามกุสเปกทางเทคนิคขึ้นมาเองเด็ดขาด\n"
                "   - หากข้อมูลสเปกบางจุดไม่ปรากฏอย่างชัดเจน ให้อธิบายตามข้อเท็จจริงทั่วไปของการใช้งานประเภทนั้นอย่างตรงไปตรงมา\n"
                "2. **โครงสร้างคำตอบใน `answer`** (ต้องจัดรูปแบบด้วย Markdown ที่สวยงาม เป็นระเบียบ อ่านง่าย สบายตา):\n"
                f"   - **เกริ่นนำสั้นๆ 1 ประโยค**: ทักทายพร้อมสรุปว่าเป็นการเปรียบเทียบระหว่าง {ent_a} และ {ent_b}\n"
                "   - **📌 สรุปภาพรวมความแตกต่าง**: สรุปความแตกต่างหลักในภาพรวม 2-3 บรรทัด (เช่น ลักษณะการใช้งาน, ฟังก์ชันหลัก)\n"
                "   - **⚖️ เปรียบเทียบจุดต่อจุด**: เปรียบเทียบเป็นหัวข้อย่อยชัดเจน (เช่น ฟังก์ชัน/รูปแบบเสียง, ความสะดวกในการพกพา, ความยากง่ายในการเล่น/ใช้งาน)\n"
                "   - **🌟 ข้อดี - ข้อสังเกต (Pros & Cons)**:\n"
                f"     - **{ent_a}**:\n"
                "       - ข้อดี: ...\n"
                "       - ข้อสังเกต: ...\n"
                f"     - **{ent_b}**:\n"
                "       - ข้อดี: ...\n"
                "       - ข้อสังเกต: ...\n"
                f"   - **🎯 คำแนะนำการเลือกใช้งาน**: สรุปชัดเจนว่าใครควรเลือก {ent_a} และใครควรเลือก {ent_b}\n"
                "   - **ประโยคปิดท้าย 1 ประโยค**: เชิญชวนสอบถามหรือสนใจเช่าอุปกรณ์ชิ้นไหนสามารถแจ้งได้เลยค่ะ\n"
                "3. **ห้ามถามคำถามแบบสอบถามเด็ดขาด (Zero Questionnaire Questions)**:\n"
                "   - ให้ `questions: []` เสมอ ห้ามใส่คำถามหรือช้อยเลือกใดๆ ทั้งสิ้น เพราะผู้ใช้ต้องการคำตอบเปรียบเทียบทันที\n"
                "4. **อุปกรณ์แนะนำในระบบ (Recommended Items)**:\n"
                "   - หากอุปกรณ์ที่เปรียบเทียบมีอยู่ใน `รายการอุปกรณ์ที่พร้อมให้บริการในระบบ` ให้ใส่ ID ใน `recommended_item_ids`\n"
                "   - หากไม่มีในรายการ ให้ใส่ `recommended_item_ids: []` โดยที่คำตอบ `answer` ยังคงเปรียบเทียบข้อมูลจริงอย่างครบถ้วนตามปกติ\n"
                "5. **จัดเรียงลำดับคีย์ใน JSON ตามนี้เป๊ะๆ**:\n"
                "   1) 'mode': 'comparison'\n"
                "   2) 'recommended_item_ids': [ไอดีอุปกรณ์ในระบบที่เกี่ยวข้อง ถ้าไม่มีให้ใส่ []]\n"
                "   3) 'questions': []\n"
                "   4) 'answer': ข้อความ Markdown โครงสร้างเปรียบเทียบข้างต้น\n"
                "   5) 'suggested_replies': ตัวเลือกคำถาม 2-3 ข้อ\n\n"
                f"รายการอุปกรณ์ที่พร้อมให้บริการในระบบ:\n{json.dumps(compact_catalog, ensure_ascii=False, indent=2)}\n\n"
                "ตัวอย่างรูปแบบ JSON ที่ต้องตอบ:\n"
                "{\n"
                '  "mode": "comparison",\n'
                '  "recommended_item_ids": [],\n'
                '  "questions": [],\n'
                f'  "answer": "สำหรับความแตกต่างระหว่าง **{ent_a}** และ **{ent_b}** Yuemnoi สรุปเปรียบเทียบให้ดังนี้ค่ะ:\\n\\n### 📌 สรุปภาพรวม:\\n...\\n\\n### ⚖️ เปรียบเทียบจุดต่อจุด:\\n...\\n\\n### 🌟 ข้อดี - ข้อสังเกต:\\n- **{ent_a}**:\\n  - ข้อดี: ...\\n  - ข้อสังเกต: ...\\n- **{ent_b}**:\\n  - ข้อดี: ...\\n  - ข้อสังเกต: ...\\n\\n### 🎯 คำแนะนำการเลือกใช้งาน:\\n...\\n\\nหากสนใจเช่าอุปกรณ์ชิ้นใด สามารถสอบถามเพิ่มเติมได้เลยนะคะ 😊",\n'
                f'  "suggested_replies": ["สนใจเช่า {ent_a}", "สนใจเช่า {ent_b}", "สอบถามขั้นตอนการเช่า"]\n'
                "}"
            )
        elif intent == "questionnaire":
            cat_list_str = ", ".join(f"'{c}'" for c in available_categories) if available_categories else ""

            # For questionnaire, provide category names and examples WITHOUT item IDs
            # so the model focuses entirely on generating discovery questions without premature product recommendations
            sample_items_overview = []
            if compact_catalog:
                for item in compact_catalog[:8]:
                    name = item.get("name")
                    cat = item.get("category")
                    if name:
                        sample_items_overview.append(f"- {name} (หมวดหมู่: {cat or 'ทั่วไป'})")
            sample_items_text = "\n".join(sample_items_overview) if sample_items_overview else "- กล้อง Mirrorless, โดรน, เลนส์, เต็นท์, โน้ตบุ๊ก, ลำโพงบลูทูธ"

            domain_focus_str = ""
            if domain_category:
                domain_focus_str = (
                    f"หมวดหมู่บริบทหลักที่ผู้ใช้กำลังสอบถาม: '{domain_category}'\n"
                    f"(สำคัญมาก: คำถามและตัวเลือกทั้งหมดที่สร้างขึ้นต้องสอดคล้องกับบริบท '{domain_category}' 100% ห้ามถามข้ามหมวดหมู่อื่นเด็ดขาด)\n\n"
                )

            base_prompt = (
                "คุณคือ Yuemnoi AI ผู้ช่วยแนะนำอุปกรณ์เช่าอัจฉริยะ ประจำแพลตฟอร์ม 'Yuemnoi' (ยืมน้อย)\n"
                "มีบุคลิกภาพสุภาพ อบอุ่น เป็นมิตร เชี่ยวชาญ (ลงท้าย ค่ะ/คะ)\n\n"
                f"{domain_focus_str}"
                f"หมวดหมู่สินค้าที่มีในระบบ: {cat_list_str}\n"
                f"ตัวอย่างประเภทอุปกรณ์ที่มีให้บริการในระบบ (สำหรับอ้างอิงสร้างตัวเลือก):\n{sample_items_text}\n\n"
                "ภารกิจในรอบนี้: วิเคราะห์ความต้องการเชิงลึก (Adaptive Needs Discovery Questionnaire)\n"
                "ผู้ใช้สอบถามอุปกรณ์แบบกว้างหรือปลายเปิด คุณต้องสร้างชุดคำถามที่จำเป็นจำนวน **2 ถึง 4 ข้อ** ในคราวเดียว โดยประเมินจากระดับความชัดเจนของคำถามผู้ใช้:\n"
                "- **กรณีคำถามกว้างปานกลาง (ระบุหมวดหมู่แล้ว เช่น 'อยากเช่าเต็นท์', 'อยากเช่าคอม', 'หาเช่ากล้อง', 'ขอดูเครื่องมือช่างอื่น')**: ให้สร้างชุดคำถาม **2 ข้อ**:\n"
                "  * ข้อ 1 (step: 1): วัตถุประสงค์หลัก / ลักษณะการใช้งาน พร้อมตัวเลือก 3-4 ข้อ + 'อื่นๆ (จะพิมพ์อธิบายเอง)'\n"
                "  * ข้อ 2 (step: 2): ขนาดความจุ / จำนวนคน / สเปกสำคัญ / หรือระยะเวลาเช่า พร้อมตัวเลือก 3-4 ข้อ + 'อื่นๆ'\n"
                "- **กรณีคำถามกว้างมาก / คลุมเครือ / ขาดรายละเอียดสำคัญ (เช่น 'มีไรให้เช่าบ้าง', 'มีอะไรให้เช่า', 'จะไปเที่ยว', 'จัดงานปาร์ตี้', 'ทำคอนเทนต์', 'มีอะไรแนะนำบ้าง')**: ให้สร้างชุดคำถาม **2 ถึง 4 ข้อ** เพื่อรวบรวมข้อมูลให้รอบด้านก่อนแนะนำ:\n"
                "  * ข้อ 1: กิจกรรมหลักหรือประเภทอุปกรณ์ที่สนใจ\n"
                "  * ข้อ 2: สไตล์การใช้งานหรือสถานที่\n"
                "  * ข้อ 3: ขนาด / จำนวนคน หรือระยะเวลาเช่า\n"
                "  * ข้อ 4 (หากจำเป็น): อุปกรณ์เสริมหรืองบประมาณ\n\n"
                "ตัวอย่างชุดคำถามตามระดับความคลุมเครือ:\n"
                "- กรณี 2 ข้อ (เรื่องเต็นท์): [ข้อ 1: กิจกรรม (step: 1, total_steps: 2), ข้อ 2: ขนาดคนพัก (step: 2, total_steps: 2)]\n"
                "- กรณี 3 ข้อ (เรื่องไปเที่ยว/ทำคอนเทนต์/ถามภาพรวมว่ามีอะไรให้เช่า):\n"
                "  * ข้อ 1: 'สนใจอุปกรณ์ประเภทไหนสำหรับทริปนี้?' ตัวเลือก: ['กล้องถ่ายภาพ/วิดีโอ', 'เต็นท์และอุปกรณ์แคมปิ้ง', 'ลำโพงฟังเพลงพกพา', 'อื่นๆ (จะพิมพ์อธิบายเอง)'] (step: 1, total_steps: 3)\n"
                "  * ข้อ 2: 'สถานที่หรือสไตล์การท่องเที่ยวเป็นแบบไหน?' ตัวเลือก: ['ขึ้นเขา/เดินป่าธรรมชาติ', 'ริมทะเล/พักผ่อนรีสอร์ต', 'เที่ยวในเมือง/คาเฟ่', 'อื่นๆ'] (step: 2, total_steps: 3)\n"
                "  * ข้อ 3: 'ระยะเวลาเช่าหรือรูปแบบการเดินทาง?' ตัวเลือก: ['ทริปสั้น 1-3 วัน', 'ทริปยาว 4-7 วัน', 'อื่นๆ'] (step: 3, total_steps: 3)\n\n"
                "กฎเหล็กสำคัญที่สุดสำหรับการสร้างแบบสอบถาม (CRITICAL QUESTIONNAIRE RULES):\n"
                "1. **ความยืดหยุ่นของจำนวนคำถาม (2 ถึง 4 ข้อ)**: ปรับจำนวนคำถามตามความจำเป็นของข้อมูล หากคำถามกว้างมากให้ถาม 3-4 ข้อ หากเจาะจงพอสมควรให้ถาม 2 ข้อ (ระบุ total_steps เท่ากับจำนวนข้อทั้งหมดที่สร้าง เช่น ถ้ามี 3 ข้อ ให้ total_steps: 3 ทุกข้อ และ step เป็น 1, 2, 3 ตามลำดับ)\n"
                "2. **ห้ามล็อคคำตอบคำถาม (No Rigid Hardcoded Questions)**: ให้สร้างคำถามและช้อยตามสิ่งที่ผู้ใช้ถามเข้ามาจริงๆ ให้ตรงกับบริบท\n"
                "3. **ห้ามตอบเป็น JSON ของสินค้าชิ้นเดียวเด็ดขาด!** ต้องตอบในรูปแบบ JSON โครงสร้างแบบสอบถามที่มี mode, recommended_item_ids, questions, answer, suggested_replies ครบถ้วนเสมอ!\n"
                "4. **ห้ามปล่อยให้คีย์ answer เป็นค่าว่าง (\"\") เด็ดขาด!** ต้องเขียนประโยคทักทายอบอุ่น 1-2 ประโยคเสมอ เช่น 'เพื่อช่วยแนะนำอุปกรณ์ที่ตอบโจทย์และตรงใจคุณลูกค้ามากที่สุด รบกวนเลือกข้อมูลตามแบบสอบถามด้านล่างนี้ได้เลยนะคะ 😊'\n"
                "5. **ความเข้าใจคำพิมพ์ผิด (Typo Tolerance)**: วิเคราะห์เจตนาที่แท้จริงของผู้ใช้เสมอ แม้จะสะกดผิด\n"
                "6. **ห้ามแนะนำสินค้าในรอบนี้เด็ดขาด (No Premature Recommendation)**: ให้ `recommended_item_ids`: [] เสมอ (ห้ามแนะนำสินค้าก่อนผู้ใช้ตอบแบบสอบถาม และห้ามใส่ไอดีสินค้าใดๆ เด็ดขาด)\n"
                "7. จัดเรียงลำดับคีย์ใน JSON ตามนี้เป๊ะๆ:\n"
                "   1) 'mode': 'questionnaire'\n"
                "   2) 'recommended_item_ids': []\n"
                "   3) 'questions': [\n"
                "        {'id': 'q1', 'step': 1, 'total_steps': N, 'title': '<คำถามข้อที่ 1>', 'options': ['<ตัวเลือก 1>', '<ตัวเลือก 2>', '<ตัวเลือก 3>', 'อื่นๆ (จะพิมพ์อธิบายเอง)']},\n"
                "        ...\n"
                "      ]\n"
                "   4) 'answer': ข้อความทักทายเชิญชวนสั้นๆ\n"
                "   5) 'suggested_replies': ['พิมพ์ตอบเอง', 'ข้ามแบบสอบถาม']\n"
                "8. **ความสอดคล้องอย่างเคร่งครัดระหว่างคำถาม ตัวเลือก และสิ่งที่ผู้ใช้ถาม (CRITICAL CONTEXTUAL ALIGNMENT)**: คำถามและตัวเลือก (`questions` และ `options`) ต้องสอดคล้องและตรงกับหัวข้อ/ประเภทอุปกรณ์ที่ผู้ใช้ถาม 100% เสมอ!\n"
                "   - ตัวอย่าง: หากผู้ใช้ถามเรื่องเครื่องดนตรี กีตาร์ (เช่น Martin, Fender, Yamaha): คำถามและตัวเลือกต้องเป็นเรื่องเกี่ยวกับเครื่องดนตรี สเปก ทรง หรือแนวเพลง ห้ามสร้างคำถามเรื่องโทรศัพท์ เครื่องมือช่าง หรือแคมปิ้งเด็ดขาด!\n"
                "   - หากผู้ใช้ถามเรื่องกล้อง: คำถามต้องเกี่ยวกับเลนส์ วิดีโอ ภาพนิ่ง ห้ามถามเรื่องแอร์หรือเต็นท์!\n"
                "   - หากผู้ใช้ถามกว้างมากว่ามีอะไรให้เช่า: ให้ถามหมวดหมู่ยอดนิยมโดยรวมอย่างสมดุล\n\n"
                "ตัวอย่างรูปแบบ JSON ที่ต้องตอบ (ห้ามตอบแบบอื่นเด็ดขาด):\n"
                "{\n"
                '  "mode": "questionnaire",\n'
                '  "recommended_item_ids": [],\n'
                '  "questions": [\n'
                '    {\n'
                '      "id": "q1",\n'
                '      "step": 1,\n'
                '      "total_steps": 2,\n'
                '      "title": "คุณต้องการเครื่องมือช่างประเภทใด?",\n'
                '      "options": ["สว่านไร้สาย", "เครื่องฉีดน้ำแรงดันสูง", "อื่นๆ (จะพิมพ์อธิบายเอง)"]\n'
                '    },\n'
                '    {\n'
                '      "id": "q2",\n'
                '      "step": 2,\n'
                '      "total_steps": 2,\n'
                '      "title": "ต้องการนำไปใช้งานลักษณะใด?",\n'
                '      "options": ["งานซ่อมแซมทั่วไป", "ล้างทำความสะอาดพื้นที่", "งานก่อสร้าง/ต่อเติม", "อื่นๆ"]\n'
                '    }\n'
                '  ],\n'
                '  "answer": "เพื่อช่วยแนะนำเครื่องมือช่างที่เหมาะสมและคุ้มค่าที่สุด รบกวนเลือกข้อมูลการใช้งานด้านล่างนี้ได้เลยนะคะ 😊",\n'
                '  "suggested_replies": ["พิมพ์ตอบเอง", "ข้ามแบบสอบถาม"]\n'
                "}"
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
                "7. **ห้ามตอบเป็น JSON ของสินค้าชิ้นเดียวเด็ดขาด!** ต้องตอบในโครงสร้าง JSON ครบทุกคีย์เสมอ\n"
                "8. **ห้ามปล่อยให้คีย์ answer เป็นค่าว่าง (\"\") เด็ดขาด!** ต้องมีข้อความ Markdown ตามโครงสร้างข้างต้นเสมอ\n"
                "9. จัดเรียงลำดับคีย์ใน JSON ตามนี้เป๊ะๆ:\n"
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
        domain_category: Optional[str] = None,
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
        elif any(w in norm for w in (
            "ดนตรี", "เครื่องดนตรี", "กีตาร์", "กีต้าร์", "เปียโน", "คีย์บอร์ด", "เบส", "กลอง",
            "martin", "fender", "gibson", "taylor", "yamaha", "roland", "casio", "korg"
        )):
            return [
                {
                    "id": "q1",
                    "step": 1,
                    "total_steps": 2,
                    "title": "สนใจเครื่องดนตรีประเภทใดคะ?",
                    "options": [
                        "กีตาร์โปร่ง / กีตาร์คลาสสิก",
                        "คีย์บอร์ด / เปียโนไฟฟ้า",
                        "กีตาร์ไฟฟ้า / กีตาร์เบส",
                        "อื่นๆ (จะพิมพ์อธิบายเอง)",
                    ],
                },
                {
                    "id": "q2",
                    "step": 2,
                    "total_steps": 2,
                    "title": "ระดับทักษะหรือรูปแบบการนำไปใช้งานเป็นแบบไหนคะ?",
                    "options": [
                        "มือใหม่ / ฝึกซ้อมเริ่มต้น",
                        "เล่นชิลล์ๆ / ร้องเพลงสังสรรค์",
                        "ซ้อมวงดนตรี / แสดงสดในงาน",
                        "อื่นๆ",
                    ],
                },
            ]
        elif any(w in norm for w in ("ลำโพง", "ไมค์", "ไมโครโฟน", "เครื่องเสียง", "มิกเซอร์")):
            return [
                {
                    "id": "q1",
                    "step": 1,
                    "total_steps": 2,
                    "title": "ต้องการเครื่องเสียงสำหรับกิจกรรมลักษณะใดคะ?",
                    "options": [
                        "เปิดเพลงฟังชิลๆ / ปาร์ตี้เล็กๆ (ลำโพงพกพา)",
                        "จัดงานสัมมนา / บรรยาย / ปาร์ตี้กลางแจ้ง (ไมค์+ลำโพง)",
                        "งานอีเวนต์ / งานแต่ง / ดนตรีสด",
                        "อื่นๆ (จะพิมพ์อธิบายเอง)",
                    ],
                },
                {
                    "id": "q2",
                    "step": 2,
                    "total_steps": 2,
                    "title": "ขนาดพื้นที่หรือจำนวนผู้ร่วมงานประมาณกี่คนคะ?",
                    "options": [
                        "กลุ่มเล็ก 5-15 คน (ในบ้าน/ห้องส่วนตัว)",
                        "ขนาดกลาง 20-50 คน (ห้องสัมมนา/ลานกว้าง)",
                        "กลุ่มใหญ่ 50+ คนขึ้นไป (กลางแจ้ง/ห้องโถง)",
                        "อื่นๆ",
                    ],
                },
            ]
        elif any(w in norm for w in ("ช่าง", "เครื่องมือช่าง", "สว่าน", "ฉีดน้ำ", "ซ่อม")):
            return [
                {
                    "id": "q1",
                    "step": 1,
                    "total_steps": 2,
                    "title": "ต้องการเครื่องมือช่างประเภทใดคะ?",
                    "options": [
                        "สว่านไร้สาย / อุปกรณ์เจาะ-ขัน",
                        "เครื่องฉีดน้ำแรงดันสูง / ทำความสะอาด",
                        "เครื่องมือช่างงานก่อสร้าง / งานไม้",
                        "อื่นๆ (จะพิมพ์อธิบายเอง)",
                    ],
                },
                {
                    "id": "q2",
                    "step": 2,
                    "total_steps": 2,
                    "title": "ลักษณะงานหรือระยะเวลาที่ต้องการใช้งานประมาณไหนคะ?",
                    "options": [
                        "งานซ่อมแซมเล็กๆ ภายในบ้าน (1 วัน)",
                        "งานล้างทำความสะอาด / บิ๊กคลีนนิ่ง (1-2 วัน)",
                        "งานช่างโปรเจกต์ (รายสัปดาห์)",
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
            top_cat = (domain_category or "").strip()
            if not top_cat and catalog:
                ranked = self.db_tool.rank_relevant_items(query, catalog, limit=3)
                if ranked and ranked[0].get("category"):
                    top_cat = ranked[0]["category"]

            # If still no top_cat, check semantic overlap with catalog categories and themes
            if not top_cat and catalog:
                for item in catalog:
                    cat = item.get("category", "")
                    if cat:
                        cat_tokens = self.db_tool.extract_tokens(cat)
                        if any(tok.lower() in norm for tok in cat_tokens if len(tok) >= 3):
                            top_cat = cat
                            break

            if not top_cat:
                distinct_cats = [
                    "กล้องและอุปกรณ์ถ่ายภาพ",
                    "แคมปิ้งและกิจกรรมกลางแจ้ง",
                    "คอมพิวเตอร์และโน้ตบุ๊ก",
                    "ดนตรีและเครื่องเสียง",
                ]
                return [
                    {
                        "id": "q1",
                        "step": 1,
                        "total_steps": 2,
                        "title": "สนใจเช่าอุปกรณ์หมวดหมู่ไหนเป็นพิเศษคะ?",
                        "options": distinct_cats[:4],
                    },
                    {
                        "id": "q2",
                        "step": 2,
                        "total_steps": 2,
                        "title": "ระยะเวลาหรือวัตถุประสงค์ในการเช่าประมาณไหนคะ?",
                        "options": [
                            "เช่าท่องเที่ยว / ทริปสั้น (1-3 วัน)",
                            "เช่าทำงาน / ถ่ายงานโปรเจกต์",
                            "เช่าจัดงานอีเวนต์ / สังสรรค์",
                            "เช่าระยะยาว (รายสัปดาห์/เดือน)",
                        ],
                    },
                ]

            if any(k in top_cat for k in ("ดนตรี", "เครื่องดนตรี")):
                return [
                    {
                        "id": "q1",
                        "step": 1,
                        "total_steps": 2,
                        "title": "สนใจเครื่องดนตรีประเภทใดคะ?",
                        "options": [
                            "กีตาร์โปร่ง / กีตาร์คลาสสิก",
                            "คีย์บอร์ด / เปียโนไฟฟ้า",
                            "กีตาร์ไฟฟ้า / กีตาร์เบส",
                            "อื่นๆ (จะพิมพ์อธิบายเอง)",
                        ],
                    },
                    {
                        "id": "q2",
                        "step": 2,
                        "total_steps": 2,
                        "title": "ระดับทักษะหรือรูปแบบการนำไปใช้งานเป็นแบบไหนคะ?",
                        "options": [
                            "มือใหม่ / ฝึกซ้อมเริ่มต้น",
                            "เล่นชิลล์ๆ / ร้องเพลงสังสรรค์",
                            "ซ้อมวงดนตรี / แสดงสดในงาน",
                            "อื่นๆ",
                        ],
                    },
                ]
            elif any(k in top_cat for k in ("กล้อง", "ถ่ายภาพ")):
                return [
                    {
                        "id": "q1",
                        "step": 1,
                        "total_steps": 2,
                        "title": "ลักษณะการใช้งานกล้องหลักเป็นแบบไหนคะ?",
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
                        "title": "ต้องการเลนส์หรืออุปกรณ์เสริมประเภทไหนคะ?",
                        "options": [
                            "เฉพาะตัวกล้อง + เลนส์คิตทั่วไป",
                            "เลนส์ละลายหลัง / เลนส์ซูมไกล",
                            "ขาตั้งกล้องหรือไมค์ไวร์เลสด้วย",
                            "อื่นๆ (จะพิมพ์อธิบายเอง)",
                        ],
                    },
                ]
            elif any(k in top_cat for k in ("ช่าง", "ก่อสร้าง")):
                return [
                    {
                        "id": "q1",
                        "step": 1,
                        "total_steps": 2,
                        "title": "ต้องการเครื่องมือช่างประเภทใดคะ?",
                        "options": [
                            "สว่านไร้สาย / อุปกรณ์เจาะ-ขัน",
                            "เครื่องฉีดน้ำแรงดันสูง / ล้างทำความสะอาด",
                            "เครื่องมือช่างงานก่อสร้าง / งานซ่อม",
                            "อื่นๆ (จะพิมพ์อธิบายเอง)",
                        ],
                    },
                    {
                        "id": "q2",
                        "step": 2,
                        "total_steps": 2,
                        "title": "ลักษณะงานหรือระยะเวลาที่ต้องการใช้งานประมาณไหนคะ?",
                        "options": [
                            "งานซ่อมแซมเล็กๆ ภายในบ้าน (1 วัน)",
                            "งานล้างทำความสะอาด / บิ๊กคลีนนิ่ง (1-2 วัน)",
                            "งานช่างโปรเจกต์ (รายสัปดาห์)",
                            "อื่นๆ",
                        ],
                    },
                ]
            elif any(k in top_cat for k in ("เครื่องเสียง", "เสียง")):
                return [
                    {
                        "id": "q1",
                        "step": 1,
                        "total_steps": 2,
                        "title": "ต้องการเครื่องเสียงสำหรับงานลักษณะใดคะ?",
                        "options": [
                            "เปิดเพลงฟังชิลๆ / ปาร์ตี้เล็กๆ (ลำโพงพกพา)",
                            "จัดงานสัมมนา / บรรยาย / ปาร์ตี้กลางแจ้ง (ไมค์+ลำโพง)",
                            "งานอีเวนต์ / งานแต่ง / ดนตรีสด",
                            "อื่นๆ (จะพิมพ์อธิบายเอง)",
                        ],
                    },
                    {
                        "id": "q2",
                        "step": 2,
                        "total_steps": 2,
                        "title": "ขนาดพื้นที่หรือจำนวนผู้ร่วมงานประมาณกี่คนคะ?",
                        "options": [
                            "กลุ่มเล็ก 5-15 คน (ห้องส่วนตัว/ในบ้าน)",
                            "ขนาดกลาง 20-50 คน (ห้องสัมมนา/ลานกว้าง)",
                            "กลุ่มใหญ่ 50+ คนขึ้นไป (กลางแจ้ง/ห้องโถง)",
                            "อื่นๆ",
                        ],
                    },
                ]
            elif any(k in top_cat for k in ("คอมพิวเตอร์", "ไอที")):
                return [
                    {
                        "id": "q1",
                        "step": 1,
                        "total_steps": 2,
                        "title": "ต้องการนำคอมพิวเตอร์ไปใช้งานแบบไหนคะ?",
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
            elif any(k in top_cat for k in ("แคมปิ้ง", "กลางแจ้ง", "เต็นท์")):
                return [
                    {
                        "id": "q1",
                        "step": 1,
                        "total_steps": 2,
                        "title": "คุณต้องการเต็นท์สำหรับกิจกรรมอะไรคะ?",
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
                        "title": "ขนาดหรือจำนวนผู้พักประมาณกี่คนคะ?",
                        "options": [
                            "1-2 คน (น้ำหนักเบา/พกพาง่าย)",
                            "3-4 คน (มาตรฐานครอบครัว)",
                            "4-6 คนขึ้นไป (กลุ่มใหญ่/มีพื้นที่เก็บของ)",
                            "อื่นๆ",
                        ],
                    },
                ]

            return [
                {
                    "id": "q1",
                    "step": 1,
                    "total_steps": 2,
                    "title": f"สนใจอุปกรณ์ในหมวด {top_cat} สำหรับรูปแบบการใช้งานใดคะ?",
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
                    "title": "ระยะเวลาเช่าที่ต้องการประมาณไหนคะ?",
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
        domain_category: Optional[str] = None,
    ) -> str:
        """
        Generates dynamic friendly greeting asking for context without rigid templates.
        """
        if domain_category:
            d = domain_category.lower()
            if any(w in d for w in ("ดนตรี", "เครื่องดนตรี")):
                return "ยินดีเลยค่ะ หากคุณลูกค้ากำลังมองหาเครื่องดนตรี เพื่อช่วยแนะนำรุ่นที่จับถนัดมือและเสียงตรงใจที่สุด ขอทราบข้อมูลเบื้องต้นสักนิดนะคะ 😊"
            if any(w in d for w in ("กล้อง", "ถ่ายภาพ", "วิดีโอ")):
                return "จะแนะนำกล้องและอุปกรณ์ถ่ายภาพให้ตรงความต้องการที่สุด ขอทราบรูปแบบการใช้งานสักนิดนะคะ 😊"
            if any(w in d for w in ("แคมปิ้ง", "เต็นท์", "เดินป่า")):
                return "จะแนะนำเต็นท์และอุปกรณ์แคมปิ้งให้ตรงใจ ขอทราบข้อมูลเบื้องต้นสักนิดนะคะ 😊"
            if any(w in d for w in ("คอมพิวเตอร์", "ไอที", "โน้ตบุ๊ก", "laptop")):
                return "จะแนะนำอุปกรณ์คอมพิวเตอร์ให้ตรงจุดต้องรู้บริบทก่อน ให้เลือกตอบเร็วๆ ได้เลยนะคะ 😊"
            if any(w in d for w in ("ช่าง", "เครื่องมือ")):
                return "เพื่อช่วยแนะนำเครื่องมือช่างที่เหมาะสมและคุ้มค่าที่สุด รบกวนเลือกข้อมูลการใช้งานด้านล่างนี้ได้เลยนะคะ 😊"
            if any(w in d for w in ("เครื่องเสียง", "ลำโพง", "ปาร์ตี้")):
                return "ยินดีค่ะ เพื่อช่วยเลือกชุดเครื่องเสียงและลำโพงที่กำลังขับและสเปกเหมาะกับงานของคุณลูกค้า ขอสอบถามรายละเอียดสักนิดนะคะ 😊"

        norm = query.strip().lower()
        if any(w in norm for w in ("มือถือ", "โทรศัพท์", "สมาร์ทโฟน")):
            return "อุปกรณ์เช่ามือถือมีได้หลายแบบ อยากให้ตรงจุดเลยขอถามนิดนึงว่าคุณหมายถึงอะไรคะ 😊"
        elif any(w in norm for w in ("แอร์", "เครื่องปรับอากาศ")):
            return "อยากให้ช่วยแนะนำแบบไหนคะ ขอเช็คบริบทก่อนสักนิด เพราะคำแนะนำจะต่างกันมากระหว่าง 2 แบบนี้ 😊"
        elif any(w in norm for w in ("คอม", "โน้ตบุ๊ก", "โน้ตบุค", "pc", "laptop", "คอมพิวเตอร์")):
            return "จะแนะนำอุปกรณ์คอมพิวเตอร์ให้ตรงจุดต้องรู้บริบทก่อน ให้เลือกตอบเร็วๆ ได้เลยนะคะ 😊"
        elif any(w in norm for w in ("เต็นท์", "เต้น", "แคมปิ้ง", "เดินป่า")):
            return "จะแนะนำเต็นท์และอุปกรณ์แคมปิ้งให้ตรงใจ ขอทราบข้อมูลเบื้องต้นสักนิดนะคะ 😊"
        elif any(w in norm for w in ("กล้อง", "ถ่ายรูป", "เลนส์", "ถ่ายวิดีโอ")):
            return "จะแนะนำกล้องและอุปกรณ์ถ่ายภาพให้ตรงความต้องการที่สุด ขอทราบรูปแบบการใช้งานสักนิดนะคะ 😊"
        elif any(w in norm for w in ("ดนตรี", "เครื่องดนตรี", "กีตาร์", "เปียโน", "คีย์บอร์ด", "martin", "fender", "gibson", "taylor", "yamaha")):
            return "ยินดีเลยค่ะ หากคุณลูกค้ากำลังมองหาเครื่องดนตรี เพื่อช่วยแนะนำรุ่นที่จับถนัดมือและเสียงตรงใจที่สุด ขอทราบข้อมูลเบื้องต้นสักนิดนะคะ 😊"
        elif any(w in norm for w in ("ช่าง", "เครื่องมือช่าง", "สว่าน", "ฉีดน้ำ")):
            return "เพื่อช่วยแนะนำเครื่องมือช่างที่เหมาะสมและคุ้มค่าที่สุด รบกวนเลือกข้อมูลการใช้งานด้านล่างนี้ได้เลยนะคะ 😊"
        elif any(w in norm for w in ("เครื่องเสียง", "ลำโพง", "ไมค์", "ปาร์ตี้")):
            return "ยินดีค่ะ เพื่อช่วยเลือกชุดเครื่องเสียงและลำโพงที่กำลังขับและสเปกเหมาะกับงานของคุณลูกค้า ขอสอบถามรายละเอียดสักนิดนะคะ 😊"
        elif any(w in norm for w in ("เช่า", "ยืม", "มีอะไร", "มีไร", "แนะนำ")):
            return "Yuemnoi มีอุปกรณ์คุณภาพพร้อมให้เช่าหลากหลายหมวดหมู่เลยค่ะ เพื่อช่วยแนะนำอุปกรณ์ที่ตรงใจคุณลูกค้าที่สุด รบกวนเลือกข้อมูลตามนี้ได้เลยนะคะ 😊"

        return "จะแนะนำให้ตรงจุดต้องรู้บริบทก่อน ให้เลือกตอบเร็วๆ ได้เลยนะคะ 😊"

    def _validate_and_align_questionnaire(
        self,
        questions: List[Dict[str, Any]],
        query: str,
        relevant_candidates: List[Dict[str, Any]],
        catalog: List[Dict[str, Any]],
        domain_category: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        """
        Validates the clarification questions generated by LLM:
        1. Ensures 2 questions with valid titles and options.
        2. Assigns step 1 and step 2 with total_steps = 2.
        3. Falls back to complete 2-question fallback if output is empty or incomplete.
        """
        if not questions:
            return self._get_fallback_questions(query, catalog=catalog, domain_category=domain_category)

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
            fallbacks = self._get_fallback_questions(query, catalog=catalog, domain_category=domain_category)
            if len(fallbacks) >= 2:
                merged = [cleaned_qs[0]] + fallbacks[1:]
                merged = merged[:4]
                total_n = len(merged)
                for idx, item in enumerate(merged):
                    item["step"] = idx + 1
                    item["total_steps"] = total_n
                return merged
            return cleaned_qs

        return self._get_fallback_questions(query, catalog=catalog, domain_category=domain_category)

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

        # Step 1: Cognitive Analysis via Typhoon 2 (Claude-like Constitutional Pipeline)
        cognitive = await self.cognitive_analyzer.analyze(cleaned_query, history)
        logger.info(
            "Cognitive analysis: intent=%s, clarity=%s, domain=%s, entities=%s, unsupported=%s",
            cognitive.intent,
            cognitive.clarity,
            cognitive.domain_category,
            cognitive.entities,
            cognitive.unsupported_domain,
        )

        intent = cognitive.intent

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

        # Check unsupported domain first (e.g. vehicles, real estate, pets)
        unsupported_domain = cognitive.unsupported_domain or DatabaseTool.get_unsupported_category_name(cleaned_query)
        if unsupported_domain:
            return self._build_out_of_inventory_response(
                query=cleaned_query,
                unsupported_domain=unsupported_domain,
                domain_category=cognitive.domain_category,
            )

        catalog = []
        relevant_candidates = []
        compact_catalog = []
        comparison_search_data = ""
        compared_entities: Optional[Tuple[str, str]] = None
        matched_comparison_items = []

        if intent == "comparison":
            if len(cognitive.entities) >= 2:
                compared_entities = (cognitive.entities[0], cognitive.entities[1])
            elif len(cognitive.entities) == 1:
                compared_entities = (cognitive.entities[0], "อุปกรณ์เปรียบเทียบ")
            else:
                compared_entities = self._extract_comparison_entities(cleaned_query, history)

            ent_a, ent_b = compared_entities
            if self.google_tool:
                try:
                    verified_text, verified_sources, search_status = await self.google_tool.search_comparison(
                        ent_a, ent_b, cleaned_query
                    )
                    comparison_search_data = verified_text
                    logger.info("Comparison web search status: %s (length=%d)", search_status, len(verified_text))
                except Exception as err:
                    logger.warning("Comparison search failed: %s", err)

            try:
                catalog = await self.db_tool.list_available_items()
            except Exception as e:
                logger.error("Failed to load catalog for comparison: %s", e)
                catalog = []

            matched_comparison_items = self._find_catalog_items_for_entities(
                compared_entities, catalog, domain_category=cognitive.domain_category
            )
            relevant_candidates = matched_comparison_items
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
        elif intent != "faq":
            try:
                catalog = await self.db_tool.list_available_items()
            except Exception as e:
                logger.error("Failed to load catalog from Supabase: %s", e)
                catalog = []

            search_query = cognitive.search_query or cleaned_query

            relevant_candidates = self.db_tool.rank_relevant_items(
                query=search_query,
                items=catalog,
                limit=settings.MAX_RECOMMENDED_ITEMS + 3,
                domain_category=cognitive.domain_category,
                entities=cognitive.entities,
            )

            # Strict Inventory Grounding: If user asked for specific item/brand and catalog doesn't have it
            if not relevant_candidates and (intent == "recommendation" or (cognitive.entities and cognitive.clarity == "clear")):
                if cognitive.entities:
                    target_entity = cognitive.entities[0]
                    return self._build_out_of_inventory_response(
                        query=cleaned_query,
                        target_entity=target_entity,
                        domain_category=cognitive.domain_category,
                    )
                else:
                    # Broad / exploratory query with no items matched: switch to questionnaire discovery!
                    intent = "questionnaire"

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
            comparison_search_data=comparison_search_data,
            compared_entities=compared_entities,
            domain_category=cognitive.domain_category,
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
            if intent == "comparison":
                mode = "comparison"
                answer = self._clean_answer(str(parsed.get("answer", "")))
                raw_ids = parsed.get("recommended_item_ids") or []
                recommended_items = [self._format_card(it) for it in matched_comparison_items]
                if not recommended_items and raw_ids:
                    item_map = {item["id"]: item for item in catalog if "id" in item}
                    for rid in raw_ids:
                        try:
                            int_rid = int(rid)
                            if int_rid in item_map:
                                recommended_items.append(self._format_card(item_map[int_rid]))
                        except (ValueError, TypeError):
                            pass
                suggested_replies = [
                    str(reply).strip()
                    for reply in (parsed.get("suggested_replies") or [])
                    if str(reply).strip()
                ][:4]
                if not suggested_replies and compared_entities:
                    suggested_replies = [
                        f"สนใจเช่า {compared_entities[0]}",
                        f"สนใจเช่า {compared_entities[1]}",
                        "สอบถามขั้นตอนการเช่า",
                    ]
                return {
                    "status": "success",
                    "mode": mode,
                    "answer": answer,
                    "questions": [],
                    "recommended_items": recommended_items[:settings.MAX_RECOMMENDED_ITEMS],
                    "suggested_replies": suggested_replies,
                }

            mode = str(parsed.get("mode") or ("questionnaire" if parsed.get("questions") else "recommendation"))
            answer = self._clean_answer(str(parsed.get("answer", "")))
            raw_ids = parsed.get("recommended_item_ids") or []
            suggested_replies = [
                str(reply).strip()
                for reply in (parsed.get("suggested_replies") or [])
                if str(reply).strip()
            ][:4]

            questions = self._format_questions(parsed.get("questions"))
            if intent == "questionnaire":
                mode = "questionnaire"
                questions = self._validate_and_align_questionnaire(
                    questions=questions,
                    query=cleaned_query,
                    relevant_candidates=relevant_candidates,
                    catalog=catalog,
                    domain_category=cognitive.domain_category,
                )
                if "### 🎒 อุปกรณ์ที่แนะนำ:" in answer:
                    answer = re.split(r"###\s*🎒\s*อุปกรณ์ที่แนะนำ:", answer)[0].strip()
                if not answer:
                    answer = self._get_fallback_questionnaire_intro(
                        cleaned_query,
                        catalog=catalog,
                        domain_category=cognitive.domain_category,
                    )
            elif questions and mode == "questionnaire":
                questions = self._validate_and_align_questionnaire(
                    questions=questions,
                    query=cleaned_query,
                    relevant_candidates=relevant_candidates,
                    catalog=catalog,
                    domain_category=cognitive.domain_category,
                )

            recommended_items = self._resolve_recommended_items(
                raw_ids=raw_ids,
                catalog=catalog,
                relevant_candidates=relevant_candidates,
                cleaned_query=cleaned_query,
                mode=mode,
                has_questions=bool(questions),
                generated_answer=answer,
            )

            if mode == "questionnaire":
                recommended_items = []

            # Post-generation Hallucination Guardrail (Claude Constitution Strict Grounding):
            # If in recommendation mode but zero items were matched/resolved from database
            if mode == "recommendation" and not recommended_items:
                if cognitive.entities:
                    target_entity = cognitive.entities[0]
                    out_resp = self._build_out_of_inventory_response(
                        query=cleaned_query,
                        target_entity=target_entity,
                        domain_category=cognitive.domain_category,
                    )
                    answer = out_resp["answer"]
                    mode = "general_chat"
                    suggested_replies = out_resp["suggested_replies"]
                else:
                    # Broad request without specific items: Fallback to questionnaire discovery
                    mode = "questionnaire"
                    questions = self._validate_and_align_questionnaire(
                        questions=[],
                        query=cleaned_query,
                        relevant_candidates=relevant_candidates,
                        catalog=catalog,
                        domain_category=cognitive.domain_category,
                    )
                    answer = self._get_fallback_questionnaire_intro(
                        cleaned_query,
                        catalog=catalog,
                        domain_category=cognitive.domain_category,
                    )
                    suggested_replies = ["พิมพ์ตอบเอง", "ข้ามแบบสอบถาม"]

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
        if intent == "comparison":
            ent_a = compared_entities[0] if compared_entities else "อุปกรณ์แรก"
            ent_b = compared_entities[1] if compared_entities else "อุปกรณ์ที่สอง"
            fallback_answer = (
                f"สำหรับความแตกต่างระหว่าง **{ent_a}** และ **{ent_b}** Yuemnoi สรุปเปรียบเทียบให้ดังนี้ค่ะ:\n\n"
                f"### 📌 สรุปภาพรวม:\n"
                f"อุปกรณ์ทั้งสองมีจุดเด่นและลักษณะการใช้งานที่แตกต่างกันอย่างชัดเจนตามสเปกจริงค่ะ โดยเน้นตอบโจทย์ผู้ใช้งานคนละรูปแบบ\n\n"
                f"### 🎯 คำแนะนำการเลือกใช้งาน:\n"
                f"- หากเน้นความสะดวกและลักษณะเฉพาะตัว แนะนำ **{ent_a}** ค่ะ\n"
                f"- หากต้องการความคุ้มค่าและความยืดหยุ่น แนะนำ **{ent_b}** ค่ะ\n\n"
                f"หากสนใจเช่าอุปกรณ์ชิ้นไหน สามารถสอบถามเพิ่มเติมได้เลยนะคะ 😊"
            )
            return {
                "status": "success",
                "mode": "comparison",
                "answer": fallback_answer,
                "questions": [],
                "recommended_items": [self._format_card(it) for it in matched_comparison_items][:settings.MAX_RECOMMENDED_ITEMS],
                "suggested_replies": [f"สนใจเช่า {ent_a}", f"สนใจเช่า {ent_b}", "สอบถามขั้นตอนการเช่า"],
            }
        elif intent == "faq":
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
                domain_category=cognitive.domain_category,
            )
            fallback_intro = self._get_fallback_questionnaire_intro(
                cleaned_query,
                catalog=catalog,
                domain_category=cognitive.domain_category,
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
    def _extract_json(text: Any) -> Optional[Dict[str, Any]]:
        if isinstance(text, dict):
            return text
        if not isinstance(text, str):
            text = str(text or "")
        text = text.strip()
        parsed = None
        # Direct json load
        try:
            parsed = json.loads(text)
        except Exception:
            pass

        # Search for {...} markdown block
        if not parsed:
            match = re.search(r"\{.*\}", text, re.DOTALL)
            if match:
                try:
                    parsed = json.loads(match.group(0))
                except Exception:
                    pass

        # Try auto-closing suffixes if truncated
        if not parsed:
            for suffix in ['"}', '"]}', ']}', '}']:
                try:
                    parsed = json.loads(text + suffix)
                    if parsed:
                        break
                except Exception:
                    pass

        # Single item dict recovery (e.g. LLM returned raw item `{ "id": 40, "name": ... }`)
        if isinstance(parsed, dict) and "id" in parsed and "name" in parsed and "answer" not in parsed:
            item_id = parsed["id"]
            item_name = parsed["name"]
            item_desc = str(parsed.get("description") or "").strip()
            desc_part = f": {item_desc}" if item_desc else ""
            return {
                "mode": "recommendation",
                "recommended_item_ids": [item_id],
                "questions": [],
                "answer": (
                    f"Yuemnoi ขอแนะนำ **{item_name}** สำหรับการใช้งานของคุณลูกค้าค่ะ:\n\n"
                    f"### 🎒 อุปกรณ์ที่แนะนำ:\n- **{item_name}**{desc_part}\n\n"
                    f"หากสนใจรับ {item_name} หรือต้องการสอบถามข้อมูลเพิ่มเติม สามารถแจ้งได้เลยนะคะ 😊"
                ),
                "suggested_replies": ["ขอดูอุปกรณ์เสริมเพิ่ม", "สอบถามขั้นตอนการเช่า"],
            }

        if parsed and isinstance(parsed, dict):
            # Ensure answer is not empty string
            if not str(parsed.get("answer") or "").strip():
                if parsed.get("questions"):
                    parsed["answer"] = "เพื่อช่วยแนะนำอุปกรณ์ที่ตอบโจทย์และตรงใจคุณลูกค้ามากที่สุด รบกวนเลือกข้อมูลตามแบบสอบถามด้านล่างนี้ได้เลยนะคะ 😊"
                elif parsed.get("recommended_item_ids"):
                    parsed["answer"] = "Yuemnoi ขอแนะนำอุปกรณ์ที่เหมาะสมตามรายการที่คัดสรรมาให้ด้านล่างนี้ค่ะ หากสนใจหรือต้องการสอบถามเพิ่มเติม แจ้งได้เลยนะคะ 😊"
                else:
                    parsed["answer"] = "Yuemnoi AI ยินดีให้บริการค่ะ หากมีข้อสงสัยเกี่ยวกับอุปกรณ์เช่าหรือขั้นตอนการใช้งาน สามารถสอบถามได้เลยนะคะ 😊"
            return parsed

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
        generated_answer: str = "",
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

        # If LLM didn't return valid raw_ids or returned empty, but generated an answer mentioning candidates
        if not recommended_items and generated_answer and relevant_candidates:
            ans_lower = generated_answer.lower()
            for cand in relevant_candidates:
                cand_id = cand.get("id")
                if not cand_id or cand_id in seen_ids:
                    continue
                cand_name = str(cand.get("item_name") or "").strip().lower()
                cand_tokens = [t for t in cand_name.split() if len(t) >= 3 and t not in self.db_tool.STOP_WORDS]
                if cand_name and (cand_name in ans_lower or (len(cand_tokens) >= 2 and all(tok in ans_lower for tok in cand_tokens))):
                    recommended_items.append(self._format_card(cand))
                    seen_ids.add(cand_id)

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

        # Step 1: Progressive Status & Cognitive Analysis via Typhoon 2 (Constitutional Pipeline)
        yield {"event": "status", "data": {"step": "analyzing", "message": "กำลังวิเคราะห์ความต้องการและบริบท..."}}
        cognitive = await self.cognitive_analyzer.analyze(cleaned_query, history)
        logger.info(
            "Stream Cognitive analysis: intent=%s, clarity=%s, domain=%s, entities=%s, unsupported=%s",
            cognitive.intent,
            cognitive.clarity,
            cognitive.domain_category,
            cognitive.entities,
            cognitive.unsupported_domain,
        )

        intent = cognitive.intent

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

        # Check unsupported domain first (e.g. vehicles, real estate, pets)
        unsupported_domain = cognitive.unsupported_domain or DatabaseTool.get_unsupported_category_name(cleaned_query)
        if unsupported_domain:
            resp_data = self._build_out_of_inventory_response(
                query=cleaned_query,
                unsupported_domain=unsupported_domain,
                domain_category=cognitive.domain_category,
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

        catalog = []
        relevant_candidates = []
        compact_catalog = []
        comparison_search_data = ""
        compared_entities: Optional[Tuple[str, str]] = None
        matched_comparison_items = []

        if intent == "comparison":
            yield {"event": "status", "data": {"step": "searching", "message": "กำลังค้นหาและตรวจสอบข้อมูลเปรียบเทียบจากอินเทอร์เน็ต..."}}
            if len(cognitive.entities) >= 2:
                compared_entities = (cognitive.entities[0], cognitive.entities[1])
            elif len(cognitive.entities) == 1:
                compared_entities = (cognitive.entities[0], "อุปกรณ์เปรียบเทียบ")
            else:
                compared_entities = self._extract_comparison_entities(cleaned_query, history)

            ent_a, ent_b = compared_entities
            if self.google_tool:
                try:
                    verified_text, verified_sources, search_status = await self.google_tool.search_comparison(
                        ent_a, ent_b, cleaned_query
                    )
                    comparison_search_data = verified_text
                    logger.info("Stream comparison web search status: %s (length=%d)", search_status, len(verified_text))
                except Exception as err:
                    logger.warning("Stream comparison search failed: %s", err)

            try:
                catalog = await self.db_tool.list_available_items()
            except Exception as e:
                logger.error("Failed to load catalog for stream comparison: %s", e)
                catalog = []

            matched_comparison_items = self._find_catalog_items_for_entities(
                compared_entities, catalog, domain_category=cognitive.domain_category
            )
            relevant_candidates = matched_comparison_items
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
        elif intent == "faq":
            yield {"event": "status", "data": {"step": "searching", "message": "กำลังค้นหาข้อมูลนโยบายและบริการ..."}}
        else:
            yield {"event": "status", "data": {"step": "searching", "message": "กำลังค้นหาอุปกรณ์ในคลังสินค้า..."}}
            try:
                catalog = await self.db_tool.list_available_items()
            except Exception as e:
                logger.error("Failed to load catalog from Supabase: %s", e)
                catalog = []

            search_query = cognitive.search_query or cleaned_query

            relevant_candidates = self.db_tool.rank_relevant_items(
                query=search_query,
                items=catalog,
                limit=settings.MAX_RECOMMENDED_ITEMS + 3,
                domain_category=cognitive.domain_category,
                entities=cognitive.entities,
            )

            # Strict Inventory Grounding: If user asked for specific item/brand and catalog doesn't have it
            if not relevant_candidates and (intent == "recommendation" or (cognitive.entities and cognitive.clarity == "clear")):
                if cognitive.entities:
                    target_entity = cognitive.entities[0]
                    resp_data = self._build_out_of_inventory_response(
                        query=cleaned_query,
                        target_entity=target_entity,
                        domain_category=cognitive.domain_category,
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
                else:
                    # Broad / exploratory query: Switch to questionnaire mode
                    intent = "questionnaire"

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
            comparison_search_data=comparison_search_data,
            compared_entities=compared_entities,
            domain_category=cognitive.domain_category,
        )

        messages: List[Dict[str, Any]] = [{"role": "system", "content": system_prompt}]
        if history:
            for msg in history[-settings.MAX_HISTORY_MESSAGES:]:
                role = msg.get("role")
                content = str(msg.get("content") or "").strip()
                if role in ("user", "assistant") and content:
                    messages.append({"role": role, "content": content[:300]})
        messages.append({"role": "user", "content": cleaned_query})

        if intent == "comparison":
            yield {"event": "status", "data": {"step": "generating", "message": "กำลังวิเคราะห์และเปรียบเทียบข้อมูล..."}}
        else:
            yield {"event": "status", "data": {"step": "generating", "message": "กำลังจัดเตรียมคำแนะนำ..."}}

        parser = StreamJsonParser()
        total_deltas_yielded = 0
        metadata_yielded = False
        resolved_items: List[Dict[str, Any]] = []
        resolved_questions: List[Dict[str, Any]] = []
        if intent == "faq":
            resolved_mode = "general_chat"
        elif intent == "questionnaire":
            resolved_mode = "questionnaire"
        elif intent == "comparison":
            resolved_mode = "comparison"
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
                    if ev["event"] == "metadata":
                        resolved_mode = ev["data"].get("mode", resolved_mode)
                        raw_ids = ev["data"].get("recommended_item_ids") or []
                        raw_qs = ev["data"].get("questions") or []
                        resolved_questions = self._format_questions(raw_qs)
                        if intent == "comparison":
                            resolved_mode = "comparison"
                            resolved_questions = []
                            resolved_items = [self._format_card(it) for it in matched_comparison_items]
                        elif intent == "questionnaire":
                            resolved_mode = "questionnaire"
                            resolved_questions = self._validate_and_align_questionnaire(
                                questions=resolved_questions,
                                query=cleaned_query,
                                relevant_candidates=relevant_candidates,
                                catalog=catalog,
                                domain_category=cognitive.domain_category,
                            )
                        elif resolved_questions and resolved_mode == "questionnaire":
                            resolved_questions = self._validate_and_align_questionnaire(
                                questions=resolved_questions,
                                query=cleaned_query,
                                relevant_candidates=relevant_candidates,
                                catalog=catalog,
                                domain_category=cognitive.domain_category,
                            )

                        if intent != "comparison":
                            resolved_items = self._resolve_recommended_items(
                                raw_ids=raw_ids,
                                catalog=catalog,
                                relevant_candidates=relevant_candidates,
                                cleaned_query=cleaned_query,
                                mode=resolved_mode,
                                has_questions=bool(resolved_questions),
                            )
                        if resolved_mode == "questionnaire":
                            resolved_items = []
                        metadata_yielded = True
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
                            total_deltas_yielded += len(clean_delta)
                            yield {"event": "delta", "data": {"text": clean_delta}}
                    else:
                        yield ev

            finish_events = parser.finish()
            for ev in finish_events:
                if ev["event"] == "metadata":
                    resolved_mode = ev["data"].get("mode", resolved_mode)
                    raw_ids = ev["data"].get("recommended_item_ids") or []
                    raw_qs = ev["data"].get("questions") or []
                    resolved_questions = self._format_questions(raw_qs)
                    if intent == "comparison":
                        resolved_mode = "comparison"
                        resolved_questions = []
                        resolved_items = [self._format_card(it) for it in matched_comparison_items]
                    elif intent == "questionnaire":
                        resolved_mode = "questionnaire"
                        resolved_questions = self._validate_and_align_questionnaire(
                            questions=resolved_questions,
                            query=cleaned_query,
                            relevant_candidates=relevant_candidates,
                            catalog=catalog,
                            domain_category=cognitive.domain_category,
                        )
                    elif resolved_questions and resolved_mode == "questionnaire":
                        resolved_questions = self._validate_and_align_questionnaire(
                            questions=resolved_questions,
                            query=cleaned_query,
                            relevant_candidates=relevant_candidates,
                            catalog=catalog,
                            domain_category=cognitive.domain_category,
                        )

                    if intent != "comparison":
                        resolved_items = self._resolve_recommended_items(
                            raw_ids=raw_ids,
                            catalog=catalog,
                            relevant_candidates=relevant_candidates,
                            cleaned_query=cleaned_query,
                            mode=resolved_mode,
                            has_questions=bool(resolved_questions),
                        )
                    if resolved_mode == "questionnaire":
                        resolved_items = []
                    metadata_yielded = True
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
                        total_deltas_yielded += len(clean_delta)
                        yield {"event": "delta", "data": {"text": clean_delta}}
                elif ev["event"] == "done":
                    if intent == "comparison":
                        resolved_mode = "comparison"
                        resolved_questions = []
                        resolved_items = [self._format_card(it) for it in matched_comparison_items]
                    elif intent == "questionnaire" or resolved_mode == "questionnaire":
                        resolved_mode = "questionnaire"
                        if not resolved_questions:
                            resolved_questions = self._validate_and_align_questionnaire(
                                questions=[],
                                query=cleaned_query,
                                relevant_candidates=relevant_candidates,
                                catalog=catalog,
                                domain_category=cognitive.domain_category,
                            )
                        resolved_items = []
                    elif resolved_mode == "recommendation" and not resolved_items:
                        if not cognitive.entities:
                            resolved_mode = "questionnaire"
                            if not resolved_questions:
                                resolved_questions = self._validate_and_align_questionnaire(
                                    questions=[],
                                    query=cleaned_query,
                                    relevant_candidates=relevant_candidates,
                                    catalog=catalog,
                                    domain_category=cognitive.domain_category,
                                )
                            resolved_items = []
                    # Ensure metadata is emitted if it was never sent before done
                    if not metadata_yielded:
                        metadata_yielded = True
                        yield {
                            "event": "metadata",
                            "data": {
                                "mode": resolved_mode,
                                "recommended_items": resolved_items[:settings.MAX_RECOMMENDED_ITEMS],
                                "questions": resolved_questions,
                            },
                        }

                    # Absolute guarantee: a response must NEVER have empty delta text
                    if total_deltas_yielded == 0:
                        if resolved_mode == "questionnaire":
                            fallback_text = (
                                "เพื่อช่วยแนะนำอุปกรณ์ที่ตอบโจทย์และตรงใจคุณลูกค้ามากที่สุด "
                                "รบกวนเลือกข้อมูลตามแบบสอบถามด้านล่างนี้ได้เลยนะคะ 😊"
                            )
                        elif resolved_mode == "comparison":
                            ent_a = compared_entities[0] if compared_entities else "อุปกรณ์แรก"
                            ent_b = compared_entities[1] if compared_entities else "อุปกรณ์ที่สอง"
                            fallback_text = (
                                f"สำหรับความแตกต่างระหว่าง **{ent_a}** และ **{ent_b}** Yuemnoi สรุปเปรียบเทียบให้ดังนี้ค่ะ:\n\n"
                                f"อุปกรณ์ทั้งสองมีจุดเด่นและลักษณะการใช้งานที่แตกต่างกันอย่างชัดเจนตามสเปกจริงค่ะ "
                                f"หากต้องการทราบข้อมูลสเปกจุดไหนเพิ่มเติม สามารถพิมพ์ถามได้เลยนะคะ 😊"
                            )
                        elif resolved_items:
                            first_names = ", ".join(item.get("item_name", "") for item in resolved_items[:2] if item.get("item_name"))
                            fallback_text = f"Yuemnoi ขอแนะนำ {first_names} สำหรับการใช้งานของคุณลูกค้าค่ะ หากสนใจรับอุปกรณ์หรือสอบถามเพิ่มเติม แจ้งได้เลยนะคะ 😊"
                        elif relevant_candidates:
                            first_names = ", ".join(item.get("item_name", "") for item in relevant_candidates[:2] if item.get("item_name"))
                            fallback_text = f"Yuemnoi มีอุปกรณ์ในระบบ เช่น {first_names} ที่พร้อมให้บริการเช่าค่ะ สามารถสอบถามข้อมูลเพิ่มเติมได้เลยนะคะ 😊"
                        else:
                            fallback_text = "Yuemnoi AI ยินดีให้บริการค่ะ หากมีข้อสงสัยเกี่ยวกับอุปกรณ์เช่าหรือขั้นตอนการใช้งาน สามารถสอบถามได้เลยนะคะ 😊"
                        total_deltas_yielded += len(fallback_text)
                        yield {"event": "delta", "data": {"text": fallback_text}}

                    final_data = dict(ev["data"])
                    final_data["recommended_items"] = resolved_items[:settings.MAX_RECOMMENDED_ITEMS]
                    final_data["questions"] = resolved_questions
                    if not final_data.get("suggested_replies"):
                        if resolved_mode == "comparison":
                            ent_a = compared_entities[0] if compared_entities else "อุปกรณ์แรก"
                            ent_b = compared_entities[1] if compared_entities else "อุปกรณ์ที่สอง"
                            final_data["suggested_replies"] = [f"สนใจเช่า {ent_a}", f"สนใจเช่า {ent_b}", "สอบถามขั้นตอนการเช่า"]
                        elif resolved_mode == "questionnaire":
                            final_data["suggested_replies"] = ["พิมพ์ตอบเอง", "ข้ามแบบสอบถาม"]
                        elif resolved_mode == "general_chat":
                            final_data["suggested_replies"] = ["สอบถามขั้นตอนการเช่า", "นโยบายเงินมัดจำ"]
                        else:
                            final_data["suggested_replies"] = ["ขอดูอุปกรณ์เสริมเพิ่ม", "สอบถามขั้นตอนการเช่า"]
                    yield {"event": "done", "data": final_data}
                else:
                    yield ev

        except Exception as exc:
            logger.error("Error during streaming LLM inference: %s", exc)
            if total_deltas_yielded == 0:
                if intent == "comparison":
                    ent_a = compared_entities[0] if compared_entities else "อุปกรณ์แรก"
                    ent_b = compared_entities[1] if compared_entities else "อุปกรณ์ที่สอง"
                    fallback_text = (
                        f"สำหรับความแตกต่างระหว่าง **{ent_a}** และ **{ent_b}** Yuemnoi สรุปเปรียบเทียบให้ดังนี้ค่ะ:\n\n"
                        f"อุปกรณ์ทั้งสองมีจุดเด่นและลักษณะการใช้งานที่แตกต่างกันอย่างชัดเจนตามสเปกจริงค่ะ "
                        f"หากต้องการทราบข้อมูลสเปกจุดไหนเพิ่มเติม สามารถพิมพ์ถามได้เลยนะคะ 😊"
                    )
                    comparison_cards = [self._format_card(it) for it in matched_comparison_items]
                    yield {
                        "event": "metadata",
                        "data": {"mode": "comparison", "recommended_items": comparison_cards, "questions": []},
                    }
                    yield {
                        "event": "delta",
                        "data": {"text": fallback_text},
                    }
                    yield {
                        "event": "done",
                        "data": {
                            "suggested_replies": [f"สนใจเช่า {ent_a}", f"สนใจเช่า {ent_b}", "สอบถามขั้นตอนการเช่า"],
                            "recommended_items": comparison_cards,
                            "questions": [],
                        },
                    }
                elif intent == "faq":
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
                        domain_category=cognitive.domain_category,
                    )
                    fallback_intro = self._get_fallback_questionnaire_intro(
                        cleaned_query,
                        catalog=catalog,
                        domain_category=cognitive.domain_category,
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
