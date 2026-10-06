"""Strict storage format. Approval checks are structural, not intent routing."""

import hashlib
import hmac
import json
from datetime import date
from typing import Annotated, Literal, Optional, Tuple

from pydantic import AwareDatetime, BaseModel, ConfigDict, StringConstraints, model_validator

NonBlank = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1)]


class DocumentModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)


class SourceDocument(DocumentModel):
    title: NonBlank
    reference: NonBlank
    locator: Optional[NonBlank] = None
    revision: Optional[NonBlank] = None


class ArticleApproval(DocumentModel):
    approved_by: NonBlank
    approved_at: AwareDatetime
    content_sha256: NonBlank


class ArticleDocument(DocumentModel):
    id: NonBlank
    title: NonBlank
    content: NonBlank
    sources: Tuple[SourceDocument, ...]
    reviewed_at: date
    status: Literal["draft", "approved", "unverified", "rejected"]
    approval: Optional[ArticleApproval] = None

    def approval_digest(self) -> str:
        """Bind approval to text, identity, review date and source references."""
        material = self.model_dump(mode="json", exclude={"status", "approval"})
        canonical = json.dumps(material, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(canonical.encode("utf-8")).hexdigest()

    @model_validator(mode="after")
    def validate_approval(self):
        if self.status in ("draft", "approved") and not self.sources:
            raise ValueError("Evidence is required for a factual article")
        if self.status == "approved":
            if self.approval is None:
                raise ValueError("An approved article requires explicit approval metadata")
            if self.approval.approved_at.date() < self.reviewed_at:
                raise ValueError("Approval cannot precede the content review")
            if not hmac.compare_digest(self.approval.content_sha256.encode("utf-8"), self.approval_digest().encode("utf-8")):
                raise ValueError("Content or evidence changed since approval")
        elif self.approval is not None:
            raise ValueError("Unapproved articles cannot carry approval metadata")
        return self


class KnowledgeDocument(DocumentModel):
    schema_version: Literal["1"]
    document_id: NonBlank
    version: NonBlank
    articles: Tuple[ArticleDocument, ...]

    @model_validator(mode="after")
    def validate_unique_ids(self):
        identifiers = [article.id for article in self.articles]
        if len(identifiers) != len(set(identifiers)):
            raise ValueError("Knowledge article IDs must be unique")
        return self
