import httpx
from typing import List, Optional
from app.domain.entities.item import Item
from app.domain.interfaces.item_repository import ItemRepositoryInterface
from app.core.config import Settings
from app.core.exceptions import ItemNotFoundException
from app.core.logging import logger

class SupabaseRepository(ItemRepositoryInterface):
    """Repository accessing item_tb in Supabase via PostgREST async API."""

    def __init__(self, settings: Settings):
        self.base_url = settings.SUPABASE_URL.rstrip('/')
        self.api_key = settings.SUPABASE_KEY
        self.headers = {
            "apikey": self.api_key,
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
            "Prefer": "return=representation"
        }
        self.endpoint = f"{self.base_url}/rest/v1/item_tb"

    def _map_row_to_item(self, row: dict) -> Item:
        return Item(
            id=int(row.get("id")),
            user_id=str(row.get("user_id", "")),
            item_name=str(row.get("item_name", "")),
            item_image_url=list(row.get("item_image_url") or []),
            description=str(row.get("description") or ""),
            category=str(row.get("category") or ""),
            price=float(row.get("price") or 0.0),
            status=str(row.get("status") or "available"),
            type=str(row.get("type") or "daily"),
            created_at=row.get("created_at"),
            updated_at=row.get("updated_at")
        )

    async def get_all_items(self) -> List[Item]:
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                url = f"{self.endpoint}?select=*"
                response = await client.get(url, headers=self.headers)
                response.raise_for_status()
                data = response.json()
                return [self._map_row_to_item(row) for row in data]
        except Exception as e:
            logger.error(f"Error fetching all items from Supabase: {e}")
            return []

    async def get_item_by_id(self, item_id: int) -> Optional[Item]:
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                url = f"{self.endpoint}?id=eq.{item_id}&select=*"
                response = await client.get(url, headers=self.headers)
                response.raise_for_status()
                data = response.json()
                if not data:
                    return None
                return self._map_row_to_item(data[0])
        except Exception as e:
            logger.error(f"Error fetching item {item_id} from Supabase: {e}")
            return None

    async def find_by_category(self, category: str) -> List[Item]:
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                url = f"{self.endpoint}?category=eq.{category}&select=*"
                response = await client.get(url, headers=self.headers)
                response.raise_for_status()
                data = response.json()
                return [self._map_row_to_item(row) for row in data]
        except Exception as e:
            logger.error(f"Error querying items by category {category}: {e}")
            return []

    async def find_by_ids(self, ids: List[int]) -> List[Item]:
        if not ids:
            return []
        try:
            ids_param = ",".join(str(i) for i in ids)
            async with httpx.AsyncClient(timeout=10.0) as client:
                url = f"{self.endpoint}?id=in.({ids_param})&select=*"
                response = await client.get(url, headers=self.headers)
                response.raise_for_status()
                data = response.json()
                return [self._map_row_to_item(row) for row in data]
        except Exception as e:
            logger.error(f"Error querying items by IDs {ids}: {e}")
            return []
