from typing import Any, Optional, Protocol


class CacheServiceInterface(Protocol):
    """Abstract port for in-memory caching."""

    async def get(self, key: str) -> Optional[Any]:
        """Retrieve cached value if present and not expired."""
        ...

    async def set(self, key: str, value: Any, ttl_seconds: int = 300) -> None:
        """Store value in cache with time-to-live."""
        ...

    async def invalidate(self, key: str) -> None:
        """Invalidate a specific cache key."""
        ...
