import asyncio
import time
import httpx

from config import settings


class InventoryCatalogError(RuntimeError):
    pass


class DatabaseTool:
    CACHE_TTL_SECONDS = 60.0

    def __init__(self, client: httpx.AsyncClient):
        self.client = client
        self.headers = {
            "apikey": settings.SUPABASE_KEY,
            "Authorization": f"Bearer {settings.SUPABASE_KEY}",
        }
        self.items_url = f"{settings.SUPABASE_URL.rstrip('/')}/rest/v1/item_tb"
        self._cached_items: list[dict] = []
        self._cached_time: float = 0.0
        self._refresh_lock = asyncio.Lock()
        self._has_cache = False

    async def get_items(self, ids: list[int]) -> list[dict]:
        if not ids:
            return []
        try:
            response = await self.client.get(self.items_url, headers=self.headers,
                params={"select": "id,item_name,item_image_url,description,category,price,status,type,created_at",
                        "id": "in.(" + ",".join(str(int(value)) for value in ids) + ")"}, timeout=10.0)
            response.raise_for_status()
            rows = response.json()
            if not self._valid_rows(rows):
                raise ValueError("Invalid inventory")
            return rows
        except Exception as exc:
            raise InventoryCatalogError("Inventory verification unavailable") from exc

    @staticmethod
    def _valid_rows(rows) -> bool:
        return isinstance(rows, list) and all(
            isinstance(row, dict)
            and isinstance(row.get("id"), int)
            and not isinstance(row["id"], bool)
            and row["id"] > 0
            for row in rows
        )

    async def list_items(self, force_refresh: bool = False) -> list[dict]:
        requested_at = time.monotonic()
        async with self._refresh_lock:
            if force_refresh and self._cached_time > requested_at:
                return list(self._cached_items)
            return await self._load_items(force_refresh)

    async def _load_items(self, force_refresh: bool = False) -> list[dict]:
        now = time.monotonic()
        if (
            not force_refresh
            and self._has_cache
            and (now - self._cached_time < self.CACHE_TTL_SECONDS)
        ):
            return list(self._cached_items)
        params = {
            "select": (
                "id,item_name,item_image_url,description,category,price,status,type,created_at"
            ),
            "limit": str(min(max(settings.MAX_CATALOG_ITEMS, 1), 200)),
            "order": "created_at.desc",
        }

        try:
            response = await self.client.get(
                self.items_url,
                headers=self.headers,
                params=params,
                timeout=10.0,
            )
            response.raise_for_status()
            result = response.json()
        except Exception as exc:
            raise InventoryCatalogError("Inventory catalog is unavailable") from exc

        if not self._valid_rows(result):
            raise InventoryCatalogError("Inventory catalog returned an invalid response")

        self._cached_items = [item for item in result if isinstance(item, dict)]
        self._cached_time = time.monotonic()
        self._has_cache = True
        return list(self._cached_items)
