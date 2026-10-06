"""Hash-checked snapshots; missing, revoked or malformed files never use stale data."""

import asyncio
import hashlib
import json
import threading
from pathlib import Path
from typing import Generic, TypeVar

from pydantic import BaseModel, ValidationError

from app.core.exceptions import RuntimeConfigurationException
from app.infrastructure.runtime.schema import unique_pairs

T = TypeVar("T", bound=BaseModel)


class ValidatedFile(Generic[T]):
    def __init__(self, path: Path, schema: type[T]):
        self.path = path.expanduser().resolve()
        self.schema = schema
        self._hash = None
        self._document = None
        self._lock = threading.Lock()

    def read(self) -> tuple[T, str]:
        with self._lock:
            try:
                raw = self.path.read_bytes()
            except OSError:
                self._hash, self._document = None, None
                raise RuntimeConfigurationException("runtime_document_unavailable") from None
            fingerprint = hashlib.sha256(raw).hexdigest()
            if fingerprint == self._hash and self._document is not None:
                return self._document, fingerprint
            self._hash, self._document = None, None
            try:
                value = json.loads(raw.decode("utf-8-sig"), object_pairs_hook=unique_pairs)
                document = self.schema.model_validate(value)
            except (UnicodeDecodeError, ValueError, ValidationError):
                raise RuntimeConfigurationException("runtime_document_invalid") from None
            self._hash, self._document = fingerprint, document
            return document, fingerprint

    async def snapshot(self) -> tuple[T, str]:
        return await asyncio.to_thread(self.read)
