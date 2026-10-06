"""Validate and list a knowledge document for owner review; never approve it."""

import argparse
import asyncio
import json
import sys
from collections import Counter
from pathlib import Path

from app.core.config import settings
from app.core.exceptions import KnowledgeDocumentException
from app.infrastructure.knowledge.file_knowledge_repository import _read_document


async def inspect(path):
    document, fingerprint = await asyncio.to_thread(_read_document, path)
    return {
        "document_id": document.document_id, "version": document.version,
        "document_sha256": fingerprint,
        "counts": dict(Counter(article.status for article in document.articles)),
        "articles": [{
            "id": article.id, "title": article.title, "status": article.status,
            "reviewed_at": article.reviewed_at.isoformat(), "source_count": len(article.sources),
            "approval_digest": article.approval_digest(),
        } for article in document.articles],
    }


def main() -> int:
    reconfigure = getattr(sys.stdout, "reconfigure", None)
    if reconfigure is not None:
        reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--path", type=Path, default=settings.APP_KNOWLEDGE_PATH)
    args = parser.parse_args()
    try:
        report = asyncio.run(inspect(args.path))
    except KnowledgeDocumentException as exc:
        print(json.dumps({"error_code": exc.code}))
        return 2
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
