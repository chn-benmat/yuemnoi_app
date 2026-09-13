from dataclasses import dataclass, field
from enum import Enum
from typing import List, Optional, Dict, Any
from datetime import datetime

class ChatRole(str, Enum):
    SYSTEM = "system"
    USER = "user"
    ASSISTANT = "assistant"

@dataclass
class ChatMessage:
    role: ChatRole
    content: str
    created_at: datetime = field(default_factory=datetime.utcnow)
    metadata: Dict[str, Any] = field(default_factory=dict)

@dataclass
class ConversationSession:
    session_id: str
    messages: List[ChatMessage] = field(default_factory=list)

    def add_message(self, role: ChatRole, content: str, metadata: Optional[Dict[str, Any]] = None):
        self.messages.append(ChatMessage(role=role, content=content, metadata=metadata or {}))
