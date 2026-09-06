import json
import re
from typing import Any, Dict, List


class StreamJsonParser:
    """
    Progressive JSON streamer and parser for Ollama outputs.
    Extracts metadata (mode, items, questions) early, streams the answer tokens
    with JSON unescaping, and guarantees complete parsing on stream completion.
    """

    def __init__(self):
        self.raw_buffer = ""
        self.in_answer = False
        self.answer_done = False
        self.metadata_emitted = False
        self.emitted_mode: str = "recommendation"
        self.emitted_item_ids: List[Any] = []
        self.emitted_questions: List[Any] = []
        self.streamed_answer_text: str = ""
        self.escaped = False
        self.cursor = 0

    def feed(self, chunk: str) -> List[Dict[str, Any]]:
        events = []
        self.raw_buffer += chunk

        # 1. Check if we reached the start of "answer": "
        if not self.in_answer and not self.answer_done:
            match = re.search(r'"answer"\s*:\s*"', self.raw_buffer)
            if match:
                self.in_answer = True
                self.cursor = match.end()

                mode_match = re.search(r'"mode"\s*:\s*"([^"]+)"', self.raw_buffer)
                mode = mode_match.group(1) if mode_match else "recommendation"

                item_ids = self.extract_json_array(self.raw_buffer, "recommended_item_ids")
                questions = self.extract_json_array(self.raw_buffer, "questions")

                self.emitted_mode = mode
                self.emitted_item_ids = item_ids
                self.emitted_questions = questions

                events.append(
                    {
                        "event": "metadata",
                        "data": {
                            "mode": mode,
                            "recommended_item_ids": item_ids,
                            "questions": questions,
                        },
                    }
                )
                self.metadata_emitted = True

        # 2. If inside answer, stream characters unescaped
        if self.in_answer:
            delta_chars = []
            i = self.cursor
            buf_len = len(self.raw_buffer)

            while i < buf_len:
                c = self.raw_buffer[i]
                if self.escaped:
                    if c == "n":
                        delta_chars.append("\n")
                    elif c == "r":
                        delta_chars.append("\r")
                    elif c == "t":
                        delta_chars.append("\t")
                    elif c == '"':
                        delta_chars.append('"')
                    elif c == "\\":
                        delta_chars.append("\\")
                    else:
                        delta_chars.append(c)
                    self.escaped = False
                    i += 1
                elif c == "\\":
                    self.escaped = True
                    i += 1
                elif c == '"':
                    # End of answer string reached
                    self.in_answer = False
                    self.answer_done = True
                    i += 1
                    self.cursor = i
                    break
                else:
                    delta_chars.append(c)
                    i += 1

            self.cursor = i
            if delta_chars:
                text = "".join(delta_chars)
                # Filter out any stray internal IDs
                clean_text = re.sub(r"\(ID:\s*\d+\)", "", text)
                clean_text = re.sub(r"ID:\s*\d+", "", clean_text)
                if clean_text:
                    self.streamed_answer_text += clean_text
                    events.append(
                        {
                            "event": "delta",
                            "data": {"text": clean_text},
                        }
                    )

        return events

    @staticmethod
    def extract_json_array(text: str, key: str) -> List[Any]:
        pattern = rf'"{key}"\s*:\s*\['
        m = re.search(pattern, text)
        if not m:
            return []
        start = m.end() - 1
        bracket_depth = 0
        in_string = False
        escape = False
        for idx in range(start, len(text)):
            char = text[idx]
            if escape:
                escape = False
                continue
            if char == '\\':
                escape = True
                continue
            if char == '"':
                in_string = not in_string
                continue
            if not in_string:
                if char == '[':
                    bracket_depth += 1
                elif char == ']':
                    bracket_depth -= 1
                    if bracket_depth == 0:
                        array_str = text[start : idx + 1]
                        try:
                            return json.loads(array_str)
                        except Exception:
                            return []
        return []

    def finish(self) -> List[Dict[str, Any]]:
        events = []
        parsed = {}
        try:
            parsed = json.loads(self.raw_buffer)
        except Exception:
            # Fallback regex extraction
            match = re.search(r"\{.*\}", self.raw_buffer, re.DOTALL)
            if match:
                try:
                    parsed = json.loads(match.group(0))
                except Exception:
                    pass

            if not parsed:
                mode_m = re.search(r'"mode"\s*:\s*"([^"]+)"', self.raw_buffer)
                if mode_m:
                    parsed["mode"] = mode_m.group(1)

                parsed["recommended_item_ids"] = self.extract_json_array(
                    self.raw_buffer, "recommended_item_ids"
                )
                parsed["questions"] = self.extract_json_array(
                    self.raw_buffer, "questions"
                )
                parsed["suggested_replies"] = self.extract_json_array(
                    self.raw_buffer, "suggested_replies"
                )

                ans_m = re.search(r'"answer"\s*:\s*"(.*?)"', self.raw_buffer, re.DOTALL)
                if ans_m:
                    parsed["answer"] = ans_m.group(1)

        # Single item dict recovery (e.g. LLM returned raw item `{ "id": 40, "name": ... }`)
        if isinstance(parsed, dict) and "id" in parsed and "name" in parsed and "answer" not in parsed:
            item_id = parsed["id"]
            item_name = parsed["name"]
            item_desc = str(parsed.get("description") or "").strip()
            parsed["mode"] = "recommendation"
            parsed["recommended_item_ids"] = [item_id]
            parsed["questions"] = []
            desc_part = f": {item_desc}" if item_desc else ""
            parsed["answer"] = (
                f"Yuemnoi ขอแนะนำ **{item_name}** สำหรับการใช้งานของคุณลูกค้าค่ะ:\n\n"
                f"### 🎒 อุปกรณ์ที่แนะนำ:\n- **{item_name}**{desc_part}\n\n"
                f"หากสนใจรับ {item_name} หรือต้องการสอบถามข้อมูลเพิ่มเติม สามารถแจ้งได้เลยนะคะ 😊"
            )
            parsed["suggested_replies"] = ["ขอดูอุปกรณ์เสริมเพิ่ม", "สอบถามขั้นตอนการเช่า"]

        resolved_mode = parsed.get("mode") or self.emitted_mode or "recommendation"
        resolved_items = parsed.get("recommended_item_ids")
        if resolved_items is None or (not resolved_items and self.emitted_item_ids):
            resolved_items = self.emitted_item_ids or []

        resolved_questions = parsed.get("questions")
        if resolved_questions is None or (not resolved_questions and self.emitted_questions):
            resolved_questions = self.emitted_questions or []

        if not self.metadata_emitted:
            events.append(
                {
                    "event": "metadata",
                    "data": {
                        "mode": resolved_mode,
                        "recommended_item_ids": resolved_items,
                        "questions": resolved_questions,
                    },
                }
            )
            self.metadata_emitted = True
        elif (resolved_items != self.emitted_item_ids or resolved_questions != self.emitted_questions):
            # Update metadata if new items or questions were discovered after answer streaming
            events.append(
                {
                    "event": "metadata",
                    "data": {
                        "mode": resolved_mode,
                        "recommended_item_ids": resolved_items,
                        "questions": resolved_questions,
                    },
                }
            )
            self.emitted_item_ids = resolved_items
            self.emitted_questions = resolved_questions

        # Guarantee answer text is emitted
        raw_ans = parsed.get("answer")
        if raw_ans:
            clean_ans = re.sub(r"\(ID:\s*\d+\)", "", str(raw_ans))
            clean_ans = re.sub(r"ID:\s*\d+", "", clean_ans)
            if not self.streamed_answer_text:
                events.append(
                    {
                        "event": "delta",
                        "data": {"text": clean_ans},
                    }
                )
                self.streamed_answer_text = clean_ans
            elif len(clean_ans) > len(self.streamed_answer_text):
                remaining = clean_ans[len(self.streamed_answer_text):]
                if remaining:
                    events.append(
                        {
                            "event": "delta",
                            "data": {"text": remaining},
                        }
                    )
                    self.streamed_answer_text += remaining

        events.append(
            {
                "event": "done",
                "data": {
                    "suggested_replies": parsed.get("suggested_replies", []),
                    "recommended_item_ids": resolved_items,
                    "questions": resolved_questions,
                },
            }
        )
        return events
