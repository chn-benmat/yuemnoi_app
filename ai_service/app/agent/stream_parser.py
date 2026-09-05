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
        self.escaped = False
        self.cursor = 0

    def feed(self, chunk: str) -> List[Dict[str, Any]]:
        events = []
        self.raw_buffer += chunk

        # 1. Check if we reached the start of "answer": "
        if not self.in_answer and not self.answer_done:
            match = re.search(r'"answer"\s*:\s*"', self.raw_buffer)
            if match:
                prefix = self.raw_buffer[: match.start()]
                self.in_answer = True
                self.cursor = match.end()

                mode_match = re.search(r'"mode"\s*:\s*"([^"]+)"', prefix)
                mode = mode_match.group(1) if mode_match else "recommendation"

                item_ids = self.extract_json_array(prefix, "recommended_item_ids")
                questions = self.extract_json_array(prefix, "questions")

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
            # Fallback extraction
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

        if not self.metadata_emitted:
            events.append(
                {
                    "event": "metadata",
                    "data": {
                        "mode": parsed.get("mode", "recommendation"),
                        "recommended_item_ids": parsed.get(
                            "recommended_item_ids", []
                        ),
                        "questions": parsed.get("questions", []),
                    },
                }
            )
            if parsed.get("answer") and not self.answer_done:
                events.append(
                    {
                        "event": "delta",
                        "data": {"text": str(parsed.get("answer"))},
                    }
                )

        events.append(
            {
                "event": "done",
                "data": {
                    "suggested_replies": parsed.get("suggested_replies", []),
                    "recommended_item_ids": parsed.get("recommended_item_ids", []),
                    "questions": parsed.get("questions", []),
                },
            }
        )
        return events
