import json
import logging
import re
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

from ..llm.ollama_client import OllamaClient

logger = logging.getLogger("uvicorn.error")


@dataclass
class CognitiveResult:
    """
    Structured outcome of the Constitutional Cognitive Scratchpad analysis.
    """
    thought: str
    intent: str  # "general_chat", "faq", "comparison", "recommendation", "questionnaire", "out_of_scope"
    entities: List[str] = field(default_factory=list)
    domain_category: Optional[str] = None
    clarity: str = "clear"  # "clear" | "ambiguous"
    unsupported_domain: Optional[str] = None
    search_query: str = ""
    raw_analysis: Dict[str, Any] = field(default_factory=dict)


class CognitiveAnalyzer:
    """
    Constitutional Cognitive Scratchpad & Intent Analyzer for Yuemnoi AI.
    Employs the core principles of Claude's Constitution (Anthropic, 2026):
      1. Good Judgment over Rigid Rules: Dynamic understanding of human nuances instead of regex.
      2. Immediate Desires vs. Final Goals: Discerning the literal words vs. the user's underlying mission.
      3. Calibrated Clarification: Asking questions ONLY when genuinely ambiguous; never over-interrogating.
      4. Honest, Grounded Epistemology: Clean entity extraction and truthful boundary recognition.
    """

    CONSTITUTIONAL_PROMPT = """คุณคือสมองวิเคราะห์เจตนา บริบท และคุณค่าอัจฉริยะ (Constitutional Cognitive Scratchpad) ประจำแพลตฟอร์มเช่าอุปกรณ์ Yuemnoi (ยืมน้อย)
ภารกิจของคุณคือวิเคราะห์ข้อความของผู้ใช้และประวัติการสนทนาอย่างลึกซึ้ง โดยยึดหลัก "วิจารณญาณที่ดีเหนือกว่ากฎเกณฑ์ตายตัว (Good Judgment over Strict Rules)" เหมือน Claude

หน้าที่หลัก:
1. วิเคราะห์ Immediate Desires (สิ่งที่ผู้ใช้พิมพ์) ควบคู่กับ Final Goals (เป้าหมายเบื้องลึกที่แท้จริง)
2. ประเมินความชัดเจนของคำขอ (Clarity Assessment):
   - "clear": ผู้ใช้ระบุรุ่น, แบรนด์, สเปก, งบ, หรือความต้องการเฉพาะเจาะจงเพียงพอที่จะแนะนำอุปกรณ์หรือตอบได้ทันที (เช่น "เราสนใจ martin", "อยากเช่า Sony A7 IV 3 วัน", "มีสว่านไร้สายไหม")
   - "ambiguous": คำถามกว้างมาก, การสำรวจ, หรือคำถามที่ยังไม่มีรุ่นหรือแบรนด์เฉพาะเจาะจง จำเป็นต้องถามคำถามคัดกรองเพื่อช่วยเลือก (เช่น "มีไรให้เช่าบ้าง", "สนใจกีตาร์", "แนะนำกล้องหน่อย", "หาของไปเที่ยว")
3. จำแนกเจตนา (Intent Classification):
   - "comparison": ต้องการเปรียบเทียบความแตกต่าง จุดเด่น จุดด้อย เลือกระหว่าง 2 อุปกรณ์/แบรนด์ขึ้นไป (เช่น "แล้ว martin กับ Yamaha ต่างกันไง", "สองตัวนี้ต่างกันตรงไหน")
   - "questionnaire": คำถามกว้าง, คำถามที่ยังไม่มีรุ่นหรือแบรนด์ชัดเจน, หรือ clarity เป็น "ambiguous" ที่ต้องการแบบสอบถามช่วยคัดกรอง (เช่น "มีไรให้เช่าบ้าง", "สนใจกีตาร์", "แนะนำกล้องหน่อย", "หาของไปเที่ยว")
   - "recommendation": ผู้ใช้ระบุรุ่น แบรนด์ สเปก หรืองบประมาณที่ชัดเจนแล้ว ("clarity": "clear") เพื่อขอดูอุปกรณ์หรือเช่าอุปกรณ์ที่เฉพาะเจาะจง (เช่น "เราสนใจ martin", "อยากเช่า Sony A7 IV", "มีสว่านไร้สายไหม")
   - "faq": สอบถามนโยบาย มัดจำ ประกัน การจัดส่ง ขั้นตอนเช่า/คืน หรือการนำของมาปล่อยเช่า
   - "general_chat": ทักทาย, ขอบคุณ, ถามชื่อบอท, คุยเล่นทั่วไป
   - "out_of_scope": เรื่องที่ไม่เกี่ยวกับการเช่าอุปกรณ์เลย หรือขัดกับขอบเขตแพลตฟอร์ม
4. สกัด Entities ที่สะอาด 100% (Zero-Regex Entity Extraction):
   - ตัดคำเกริ่นสนทนาและคำเชื่อมภาษาไทยออกทั้งหมด (เช่น "แล้ว", "แล้วถ้า", "ถ้า", "งั้น", "สรุป", "เราสนใจ", "ผมอยากได้", "ช่วยดู", "เปรียบเทียบ", "ระหว่าง", "กับ", "และ")
   - คืนชื่อเฉพาะที่สะอาดและถูกต้องตามหลักสากล เช่น ถ้าผู้ใช้ถาม 'แล้ว martin กับ Yamaha ต่างกันไง' -> entities คือ ["Martin", "Yamaha"]
5. ระบุ Unsupported Domain (หมวดที่แพลตฟอร์มไม่รองรับ):
   - หากผู้ใช้ต้องการเช่ารถ, รถตู้, รถยนต์, มอเตอร์ไซค์, เรือ, เครื่องบิน -> "ยานพาหนะหรือรถเช่า"
   - หากต้องการเช่าบ้าน, คอนโด, ห้องพัก -> "ที่พักและอสังหาริมทรัพย์"
   - หากต้องการเช่าหมา, แมว -> "สัตว์เลี้ยง"
   - หากไม่มี ให้ระบุ null
6. สรุป search_query และ domain_category:
   - domain_category: หมวดหมู่หลักของสิ่งที่พูดถึง เช่น "ดนตรีและเครื่องดนตรี", "กล้องและอุปกรณ์ถ่ายภาพ", "เครื่องมือช่าง", "แคมปิ้งและกิจกรรมกลางแจ้ง", "คอมพิวเตอร์และอุปกรณ์ไอที" หรือ null
   - search_query: คำค้นหาที่เหมาะสมที่สุดสำหรับค้นหาในคลังสินค้า

ตอบในรูปแบบ JSON โครงสร้างนี้เท่านั้น (ห้ามใส่ข้อความนอก JSON):
{
  "thought": "การวิเคราะห์เชิงลึกสั้นๆ 1-2 ประโยค ถึงเจตนา บริบท และความต้องการของผู้ใช้",
  "intent": "comparison" | "recommendation" | "questionnaire" | "faq" | "general_chat" | "out_of_scope",
  "entities": ["ชื่ออุปกรณ์ แบรนด์ หรือรุ่นที่สะอาด 100%"],
  "domain_category": "หมวดหมู่อุปกรณ์ หรือ null",
  "clarity": "clear" | "ambiguous",
  "unsupported_domain": "ยานพาหนะหรือรถเช่า" | "ที่พักและอสังหาริมทรัพย์" | "สัตว์เลี้ยง" | null,
  "search_query": "คำค้นหาสำหรับค้นหาอุปกรณ์ในระบบ"
}"""

    def __init__(self, ollama: OllamaClient):
        self.ollama = ollama

    async def analyze(
        self,
        query: str,
        history: Optional[List[Dict[str, str]]] = None,
    ) -> CognitiveResult:
        """
        Executes Cognitive Scratchpad reasoning over the query and context.
        """
        cleaned = query.strip()
        if not cleaned:
            return CognitiveResult(
                thought="ข้อความว่างเปล่า",
                intent="general_chat",
                entities=[],
                clarity="clear",
            )

        # Micro-guardrail for trivial single-word greetings / acknowledgements (sub-millisecond latency)
        fast_result = self._check_fast_conversational(cleaned)
        if fast_result:
            return fast_result

        # Build Context-Aware Analysis Messages
        messages: List[Dict[str, Any]] = [
            {"role": "system", "content": self.CONSTITUTIONAL_PROMPT},
        ]
        if history:
            # Include up to 4 recent context turns for multi-turn intent resolution
            for msg in history[-4:]:
                role = msg.get("role")
                content = str(msg.get("content") or "").strip()
                if role in ("user", "assistant") and content:
                    messages.append({"role": role, "content": content[:250]})

        messages.append({"role": "user", "content": cleaned})

        try:
            raw = await self.ollama.chat(
                messages=messages,
                format="json",
                temperature=0.0,
                max_tokens=300,
                timeout=12.0,
                think=False,
            )
            parsed = self._extract_json(raw)
            # A valid cognitive analysis result must contain "thought" or "intent" (distinguishing from final agent output payloads)
            if parsed and isinstance(parsed, dict) and ("thought" in parsed or "intent" in parsed):
                thought = str(parsed.get("thought") or "").strip()
                intent = str(parsed.get("intent") or "recommendation").strip().lower()
                if intent not in ("comparison", "recommendation", "questionnaire", "faq", "general_chat", "out_of_scope"):
                    intent = "recommendation"

                raw_entities = parsed.get("entities") or []
                entities = [str(e).strip() for e in raw_entities if str(e).strip()]

                domain_category = parsed.get("domain_category")
                if domain_category and str(domain_category).strip().lower() in ("null", "none", ""):
                    domain_category = None

                clarity = str(parsed.get("clarity") or "clear").strip().lower()
                if clarity not in ("clear", "broad_needs_clarification", "ambiguous"):
                    clarity = "clear"

                # Calibrated Clarification Guardrail (Anthropic Principle 3):
                # If clarity is ambiguous / broad (e.g. "สนใจกีตาร์", "มีไรให้เช่า", "แนะนำหน่อย"),
                # and user did not specify a specific model/brand to rent or compare, intent must be questionnaire.
                if clarity in ("ambiguous", "broad_needs_clarification") and intent not in ("comparison", "faq", "general_chat", "out_of_scope"):
                    intent = "questionnaire"

                if intent == "questionnaire":
                    clarity = "ambiguous"

                unsupported = parsed.get("unsupported_domain")
                if unsupported and str(unsupported).strip().lower() in ("null", "none", ""):
                    unsupported = None

                search_query = str(parsed.get("search_query") or cleaned).strip()

                return CognitiveResult(
                    thought=thought,
                    intent=intent,
                    entities=entities,
                    domain_category=domain_category,
                    clarity=clarity,
                    unsupported_domain=unsupported,
                    search_query=search_query,
                    raw_analysis=parsed,
                )
        except Exception as err:
            logger.warning("CognitiveAnalyzer LLM reasoning failed: %s; falling back safely", err)

        # Resilient Fallback if LLM fails
        return self._safe_fallback(cleaned, history)

    @staticmethod
    def _check_fast_conversational(query: str) -> Optional[CognitiveResult]:
        """
        Sub-millisecond pass-through for exact trivial greetings or acknowledgements.
        """
        norm = query.lower().strip()
        greetings = {"สวัสดี", "หวัดดี", "ดีครับ", "ดีค่ะ", "hello", "hi", "hey"}
        acknowledgements = {"ขอบคุณ", "ขอบใจ", "thanks", "thank you", "โอเค", "ok", "okay", "รับทราบ", "เข้าใจแล้ว"}

        if norm in greetings:
            return CognitiveResult(
                thought="คำทักทายมาตรฐาน",
                intent="general_chat",
                clarity="clear",
                raw_analysis={"type": "greeting"},
            )
        if norm in acknowledgements:
            return CognitiveResult(
                thought="คำขอบคุณหรือรับทราบ",
                intent="general_chat",
                clarity="clear",
                raw_analysis={"type": "acknowledgement"},
            )
        return None

    @staticmethod
    def _extract_json(text: Any) -> Optional[Dict[str, Any]]:
        if isinstance(text, dict):
            return text
        if not isinstance(text, str):
            return None
        text = text.strip()
        try:
            return json.loads(text)
        except Exception:
            pass
        match = re.search(r"\{.*\}", text, re.DOTALL)
        if match:
            try:
                return json.loads(match.group(0))
            except Exception:
                pass
        return None

    @staticmethod
    def _safe_fallback(query: str, history: Optional[List[Dict[str, str]]] = None) -> CognitiveResult:
        """
        Simple resilient fallback in case LLM is completely offline or test mocks final payload.
        """
        norm = query.lower().strip()

        # 1. Comparison check (including follow-ups referencing comparison in history)
        is_comparison = any(w in norm for w in ("ต่างกับ", "ต่างจาก", "เทียบกับ", "vs", "versus", "อันไหนดีกว่า", "ข้อดีข้อเสีย", "ต่างกัน", "ต่างกันไง", "ต่างกันยังไง"))
        if not is_comparison and any(w in norm for w in ("ต่าง", "เทียบ")):
            is_comparison = True
        if not is_comparison and history:
            prev_user_queries = [str(m.get("content") or "").lower() for m in history if m.get("role") == "user"]
            if any(any(w in q for w in ("ต่าง", "เทียบ", "vs")) for q in prev_user_queries):
                if any(w in norm for w in ("ไม่", "ถามว่า", "สรุป", "ว่า", "ไง", "อันไหน", "ตัวไหน")):
                    is_comparison = True

        if is_comparison:
            return CognitiveResult(
                thought="ตรวจพบเจตนาเปรียบเทียบ (Fallback)",
                intent="comparison",
                search_query=query,
            )

        # 2. General discovery / broad questionnaire
        if any(w in norm for w in ("มีไร", "มีอะไร", "แนะนำ", "อะไรบ้าง", "ช่วยเลือก", "ไปเที่ยว", "จัดงาน")):
            return CognitiveResult(
                thought="ตรวจพบคำถามกว้าง ต้องการแบบสอบถาม (Fallback)",
                intent="questionnaire",
                clarity="broad_needs_clarification",
                search_query=query,
            )

        return CognitiveResult(
            thought="การทำงานสำรองในกรณีฉุกเฉิน",
            intent="recommendation",
            clarity="clear",
            search_query=query,
        )
