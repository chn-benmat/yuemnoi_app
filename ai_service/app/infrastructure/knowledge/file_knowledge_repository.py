import asyncio
import hashlib
import json
import threading
from pathlib import Path
from typing import Optional, Tuple

from pydantic import ValidationError

from app.core.exceptions import KnowledgeDocumentException
from app.domain.entities.app_knowledge import KnowledgeArticle, KnowledgeSnapshot, KnowledgeSource, KnowledgeTopic
from app.domain.interfaces.knowledge_repository import KnowledgeRepositoryInterface
from app.infrastructure.knowledge.document_schema import KnowledgeDocument


def _unique_object(pairs):
    """Reject ambiguous files instead of silently keeping the last JSON key."""
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON key")
        result[key] = value
    return result


def _read_document(path: Optional[Path], cached=None) -> Tuple[KnowledgeDocument, str]:
    if path is None:
        raise KnowledgeDocumentException("not_configured")
    try:
        raw = path.read_bytes()
    except FileNotFoundError:
        raise KnowledgeDocumentException("not_found") from None
    except OSError:
        raise KnowledgeDocumentException("unreadable") from None
    digest = hashlib.sha256(raw).hexdigest()
    if cached is not None and digest == cached[1]:
        return cached
    try:
        payload = json.loads(raw.decode("utf-8-sig"), object_pairs_hook=_unique_object)
        document = KnowledgeDocument.model_validate(payload)
    except (UnicodeDecodeError, ValueError, ValidationError):
        # Do not echo content, filesystem locations, or validator inputs.
        raise KnowledgeDocumentException("invalid_document") from None
    return document, digest


class FileKnowledgeRepository(KnowledgeRepositoryInterface):
    """Read bytes every call; reuse validated data only for the same content hash."""

    def __init__(self, document_path: Optional[Path]):
        self._document_path = document_path.expanduser().resolve() if document_path is not None else None
        self._cache = None
        self._lock = threading.Lock()

    def _read(self):
        with self._lock:
            try:
                self._cache = _read_document(self._document_path, self._cache)
            except KnowledgeDocumentException:
                self._cache = None
                raise
            return self._cache

    async def get_approved_knowledge(self) -> KnowledgeSnapshot:
        document, document_sha256 = await asyncio.to_thread(self._read)
        articles = []
        for article in document.articles:
            if article.status != "approved":
                continue
            approval = article.approval
            # Document validation guarantees metadata for every approved entry.
            if approval is None:
                raise KnowledgeDocumentException("invalid_document")
            articles.append(KnowledgeArticle(
                id=article.id,
                title=article.title,
                content=article.content,
                sources=tuple(KnowledgeSource(
                    title=source.title, reference=source.reference,
                    locator=source.locator, revision=source.revision,
                ) for source in article.sources),
                reviewed_at=article.reviewed_at,
                approved_by=approval.approved_by,
                approved_at=approval.approved_at,
                content_sha256=approval.content_sha256,
            ))
        topics = tuple(KnowledgeTopic(a.id, a.title, a.status) for a in document.articles)
        return KnowledgeSnapshot(document.document_id, document.version, document_sha256, tuple(articles), topics)
