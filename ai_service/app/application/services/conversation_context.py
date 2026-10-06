"""Serialize supplied conversation data without guessing its meaning."""

import json
from hashlib import sha256
from dataclasses import dataclass
from typing import Sequence

from app.domain.entities.chat_message import ChatMessage


@dataclass(frozen=True)
class ContextLimits:
    max_messages: int
    max_characters: int

    def __post_init__(self):
        if self.max_messages < 1 or self.max_characters < 1:
            raise ValueError("Context limits must be positive")


def message_source_id(role: str, content: str) -> str:
    return 'message:' + sha256(json.dumps([role, content], ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()


def conversation_context(history: Sequence[ChatMessage], limits: ContextLimits, *, include_source_ids=False) -> dict:
    """Keep a bounded suffix of complete messages, including questionnaire JSON.

    IDs refer to this request's history only. They are not persistent memory.
    A message that cannot fit is omitted with explicit truncation metadata.
    """
    selected = []
    characters = 0
    for index in range(len(history) - 1, -1, -1):
        message = history[index]
        entry = {"id": f"h{index}", "role": message.role, "content": message.content}
        if include_source_ids:
            entry['source_id'] = message_source_id(message.role, message.content)
        try:
            parsed = json.loads(message.content)
            if isinstance(parsed, (dict, list)):
                entry["content"] = parsed
        except (ValueError, TypeError):
            pass
        size = len(json.dumps(entry, ensure_ascii=False))
        if len(selected) >= limits.max_messages or characters + size > limits.max_characters:
            break
        selected.append(entry)
        characters += size
    selected.reverse()
    return {
        "messages": selected,
        "omitted_messages": len(history) - len(selected),
        "truncated": len(selected) != len(history),
    }
