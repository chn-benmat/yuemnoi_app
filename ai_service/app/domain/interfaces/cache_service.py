from abc import ABC, abstractmethod
from typing import Optional, Any

class CacheServiceInterface(ABC):
    @abstractmethod
    async def get(self, key: str) -> Optional[Any]:
        """Retrieve an item from cache if not expired."""
        pass

    @abstractmethod
    async def set(self, key: str, value: Any, ttl_seconds: int = 300) -> None:
        """Store an item in cache with a TTL (seconds)."""
        pass

    @abstractmethod
    async def clear(self) -> None:
        """Clear all items in the cache."""
        pass
