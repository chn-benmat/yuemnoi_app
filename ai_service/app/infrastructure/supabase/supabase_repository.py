import json
from math import isfinite
from typing import List, Optional
import httpx

from app.core.config import settings
from app.core.exceptions import DatabaseException
from app.core.logging import logger
from app.domain.entities.item import Item
from app.domain.interfaces.cache_service import CacheServiceInterface
from app.domain.interfaces.item_repository import ItemRepositoryInterface
from app.infrastructure.runtime.documents import ValidatedFile
from app.infrastructure.runtime.schema import RuntimeDocument


class SupabaseRepository(ItemRepositoryInterface):
    """Supabase PostgREST repository for item_tb with in-memory caching."""

    CACHE_KEY = "all_items"

    def __init__(
        self,
        cache_service: Optional[CacheServiceInterface] = None,
        base_url: Optional[str] = None,
        api_key: Optional[str] = None,
        timeout: Optional[float] = None,
        http_client: Optional[httpx.AsyncClient] = None,
        runtime: Optional[RuntimeDocument] = None,
    ):
        self._cache = cache_service
        self._base_url = (base_url or settings.SUPABASE_URL).rstrip("/")
        self._api_key = api_key or settings.SUPABASE_KEY
        self._runtime = runtime or ValidatedFile(settings.AI_RUNTIME_PATH, RuntimeDocument).read()[0]
        self._timeout = self._runtime.http.timeout_seconds if timeout is None else timeout
        self._http = http_client
        self._owns_http = http_client is None

    async def start(self):
        if self._http is None:
            cfg = self._runtime.http
            # ใช้ connection เดิมโดยทุก refresh ยังอ่านคลังจริงใหม่
            self._http = httpx.AsyncClient(timeout=self._timeout, limits=httpx.Limits(
                max_connections=cfg.max_connections, max_keepalive_connections=cfg.max_keepalive_connections,
                keepalive_expiry=cfg.keepalive_expiry_seconds))

    async def aclose(self):
        if self._http is not None and self._owns_http:
            await self._http.aclose()
            self._http = None

    def _headers(self) -> dict:
        return {
            "apikey": self._api_key,
            "Authorization": f"Bearer {self._api_key}",
            "Accept": "application/json",
        }

    def _map_row_to_item(self, row: dict) -> Item:
        if row.get("price") is None or not isinstance(row.get("type"), str) or not row["type"].strip():
            raise DatabaseException("Catalog pricing data is incomplete")
        try:
            price = float(row["price"])
        except (TypeError, ValueError):
            raise DatabaseException("Catalog price is invalid") from None
        if isinstance(row["price"], bool) or not isfinite(price) or price < 0:
            raise DatabaseException("Catalog price is invalid")
        raw_images = row.get("item_image_url")
        image_urls: List[str] = []
        if isinstance(raw_images, list):
            image_urls = [str(url) for url in raw_images if url]
        elif isinstance(raw_images, str) and raw_images.strip():
            try:
                parsed = json.loads(raw_images)
                if isinstance(parsed, list):
                    image_urls = [str(u) for u in parsed if u]
                else:
                    image_urls = [raw_images]
            except Exception:
                image_urls = [raw_images]

        return Item(
            id=str(row.get("id", "")),
            name=row.get("item_name") or "",
            category=row.get("category") or "",
            price=price,
            type=row["type"],
            status=row.get("status") or "unknown",
            image_urls=image_urls,
            description=row.get("description") or "",
        )

    async def get_all_items(self, *, refresh: bool = False) -> List[Item]:
        """Fetch all items from Supabase or cache."""
        if self._cache and not refresh:
            cached = await self._cache.get(self.CACHE_KEY)
            if cached is not None:
                return cached

        endpoint = f"{self._base_url}/rest/v1/item_tb?select=id,item_name,category,price,type,status,item_image_url,description"
        try:
            await self.start()
            resp = await self._http.get(endpoint, headers=self._headers(), timeout=self._timeout)
            if resp.status_code != 200:
                logger.error(f"Supabase returned status {resp.status_code}")
                raise DatabaseException(f"Failed to fetch items from Supabase: status {resp.status_code}")
            rows = resp.json()
            items = [self._map_row_to_item(r) for r in rows]
            if self._cache:
                await self._cache.set(self.CACHE_KEY, items, ttl_seconds=settings.CACHE_TTL_SECONDS)
            return items
        except httpx.RequestError as exc:
            logger.error(f"Network error querying Supabase: {exc}")
            raise DatabaseException(f"Network error accessing Supabase: {exc}") from exc

    async def search_items(self, query: str, category: Optional[str] = None) -> List[Item]:
        """Filter items in memory from cached catalog."""
        items = await self.get_all_items()
        filtered = items
        if category:
            cat_norm = category.strip().lower()
            filtered = [i for i in filtered if cat_norm in i.category.lower()]

        if query:
            q_norm = query.strip().lower()
            filtered = [
                i for i in filtered
                if q_norm in i.name.lower() or q_norm in i.description.lower() or q_norm in i.category.lower()
            ]
        return filtered
