from abc import ABC, abstractmethod
from typing import List, Optional
from app.domain.entities.item import Item

class ItemRepositoryInterface(ABC):
    @abstractmethod
    async def get_all_items(self) -> List[Item]:
        """Fetch all items from the database."""
        pass

    @abstractmethod
    async def get_item_by_id(self, item_id: int) -> Optional[Item]:
        """Fetch a specific item by its primary key ID."""
        pass

    @abstractmethod
    async def find_by_category(self, category: str) -> List[Item]:
        """Fetch items matching a category."""
        pass

    @abstractmethod
    async def find_by_ids(self, ids: List[int]) -> List[Item]:
        """Fetch items matching a list of IDs."""
        pass
