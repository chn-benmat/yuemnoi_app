from typing import Optional
from pydantic import BaseModel


class ChatMessage(BaseModel):
    """Domain entity representing a single chat message in the conversation history."""
    role: str
    content: str
