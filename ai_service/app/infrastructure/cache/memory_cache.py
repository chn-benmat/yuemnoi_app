import time
from typing import Optional, Any, Dict, Tuple
from app.domain.interfaces.cache_service import CacheServiceInterface

class MemoryCacheService(CacheServiceInterface):
    """In-memory cache with Time-To-Live (TTL) support."""
    def __init__(self):
        self._store: Dict[str, Tuple[Any, float]] = {}

    async def get(self, key: str) -> Optional[Any]:
        if key not in self._store:
            return None
        value, expiry = self._store[key]
        if time.time() > expiry:
            del self._store[key]
            return None
        return value

    async def set(self, key: str, value: Any, ttl_seconds: int = 300) -> None:
        expiry = time.time() + ttl_seconds
        self._store[key] = (value, expiry)

    async def clear(self) -> None:
        self._store.clear()
