import re
from typing import Literal, Optional, get_args

import httpx
from pydantic import BaseModel, ConfigDict, Field

from config import settings


InventoryCategory = Literal[
    "camera",
    "computer",
    "camping",
    "projector",
    "gaming",
    "tools",
    "cleaning",
    "event",
    "sports",
    "drone",
    "lighting",
    "audio",
    "power_equipment",
    "phone",
    "television",
    "lens",
]
INVENTORY_CATEGORIES = tuple(get_args(InventoryCategory))


class ItemSearchFilters(BaseModel):
    """Typed arguments accepted from Qwen's semantic routing decision."""

    model_config = ConfigDict(extra="ignore")

    search_text: Optional[str] = Field(default=None, max_length=80)
    category: Optional[InventoryCategory] = None
    min_price: Optional[int] = Field(default=None, ge=0, le=1_000_000)
    max_price: Optional[int] = Field(default=None, ge=0, le=1_000_000)
    limit: int = Field(default=5, ge=1, le=5)
    list_all: bool = False


class DatabaseTool:
    def __init__(self, client: httpx.AsyncClient):
        self.client = client
        self.headers = {
            "apikey": settings.SUPABASE_KEY,
            "Authorization": f"Bearer {settings.SUPABASE_KEY}",
        }
        self.items_url = f"{settings.SUPABASE_URL.rstrip('/')}/rest/v1/item_tb"

    @staticmethod
    def _safe_filter_text(value: Optional[str]) -> Optional[str]:
        if not value:
            return None
        cleaned = re.sub(r"[^\w\s.\-\u0E00-\u0E7F]", " ", value, flags=re.UNICODE)
        return " ".join(cleaned.split())[:80] or None

    async def search_items(self, filters: ItemSearchFilters) -> list[dict]:
        params: list[tuple[str, str]] = [
            (
                "select",
                "id,item_name,item_image_url,description,category,price,status,type",
            ),
            ("limit", str(min(filters.limit, settings.MAX_SEARCH_RESULTS))),
            ("order", "price.asc"),
        ]

        search_text = self._safe_filter_text(filters.search_text)
        category = filters.category

        has_price_filter = (
            filters.min_price is not None or filters.max_price is not None
        )
        if not filters.list_all and not search_text and not category and not has_price_filter:
            return []

        if search_text:
            # Match useful words independently instead of requiring one exact phrase.
            # With no semantic category, only item names are searched to avoid a use-case
            # word accidentally matching an unrelated description.
            terms = list(dict.fromkeys(search_text.split()))[:6]
            fields = ("item_name", "description") if category else ("item_name",)
            clauses = [
                f"{field}.ilike.*{term}*"
                for term in terms
                for field in fields
            ]
            params.append(
                (
                    "or",
                    f"({','.join(clauses)})",
                )
            )
        if category:
            params.append(("category", f"eq.{category}"))
        if filters.min_price is not None:
            params.append(("price", f"gte.{filters.min_price}"))
        if filters.max_price is not None:
            params.append(("price", f"lte.{filters.max_price}"))

        try:
            response = await self.client.get(
                self.items_url,
                headers=self.headers,
                params=params,
                timeout=10.0,
            )
            response.raise_for_status()
            result = response.json()
            return result if isinstance(result, list) else []
        except Exception as exc:
            print(f"[Supabase Search Error]: {exc}")
            return []
