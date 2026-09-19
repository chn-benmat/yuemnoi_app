from typing import List, Optional, Protocol
from app.domain.entities.item import Item


class ItemRepositoryInterface(Protocol):
    """Abstract port for accessing rental inventory."""

    async def get_all_items(self) -> List[Item]:
        """Retrieve all active rental items from database."""
        ...

    async def search_items(self, query: str, category: Optional[str] = None) -> List[Item]:
        """Search items matching query or category."""
        ...
