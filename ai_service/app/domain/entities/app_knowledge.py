"""Approved application facts without storage or framework dependencies."""

from dataclasses import dataclass
from datetime import date, datetime
from typing import Optional, Tuple


@dataclass(frozen=True)
class KnowledgeSource:
    title: str
    reference: str
    locator: Optional[str]
    revision: Optional[str]


@dataclass(frozen=True)
class KnowledgeArticle:
    id: str
    title: str
    content: str
    sources: Tuple[KnowledgeSource, ...]
    reviewed_at: date
    approved_by: str
    approved_at: datetime
    content_sha256: str


@dataclass(frozen=True)
class KnowledgeTopic:
    id: str
    title: str
    status: str


@dataclass(frozen=True)
class KnowledgeSnapshot:
    document_id: str
    version: str
    document_sha256: str
    articles: Tuple[KnowledgeArticle, ...]
    topics: Tuple[KnowledgeTopic, ...] = ()
