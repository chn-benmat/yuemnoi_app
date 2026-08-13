import httpx

from config import settings


class InventoryCatalogError(RuntimeError):
    pass


class DatabaseTool:
    def __init__(self, client: httpx.AsyncClient):
        self.client = client
        self.headers = {
            "apikey": settings.SUPABASE_KEY,
            "Authorization": f"Bearer {settings.SUPABASE_KEY}",
        }
        self.items_url = f"{settings.SUPABASE_URL.rstrip('/')}/rest/v1/item_tb"

    async def list_items(self) -> list[dict]:
        params = {
            "select": (
                "id,item_name,item_image_url,description,category,price,status,type"
            ),
            "limit": str(min(max(settings.MAX_CATALOG_ITEMS, 1), 200)),
            "order": "id.asc",
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

        if not isinstance(result, list):
            raise InventoryCatalogError("Inventory catalog returned an invalid response")
        return [item for item in result if isinstance(item, dict)]
