import asyncio
import time
from typing import List, Optional
from app.application.use_cases.query_items import QueryItemsUseCase
from app.domain.entities.item import Item
from app.core.logging import logger

class CatalogWarmupService:
    """Application Service: ดำเนินการอุ่นแคชคลังสินค้าและสกัดชื่อรุ่นสากลในเบื้องหลังเป็นระยะอัตโนมัติ (Proactive Warm-up)"""

    def __init__(
        self,
        query_items_use_case: QueryItemsUseCase,
        interval_seconds: int = 540,
        ttl_seconds: int = 600
    ):
        self.query_items = query_items_use_case
        self.interval_seconds = interval_seconds
        self.ttl_seconds = ttl_seconds
        self._is_running = False

    @property
    def is_running(self) -> bool:
        return self._is_running

    async def trigger_warmup(self) -> List[Item]:
        """สั่งให้อุ่นแคชและสกัดชื่อรุ่นในคลังสินค้าทันที"""
        start_t = time.perf_counter()
        logger.info("Executing catalog cache warm-up...")
        items = await self.query_items.refresh_catalog_cache(ttl_seconds=self.ttl_seconds)
        elapsed = time.perf_counter() - start_t
        logger.info(f"Catalog cache warm-up completed in {elapsed:.2f}s ({len(items)} items cached).")
        return items

    async def start_periodic_warmup(self) -> None:
        """ลูปเบื้องหลังเพื่ออุ่นแคชอัตโนมัติทุกๆ interval_seconds เพื่อป้องกัน Cache Miss 100%"""
        self._is_running = True
        logger.info(
            f"CatalogWarmupService started (Interval: {self.interval_seconds}s, Cache TTL: {self.ttl_seconds}s)."
        )
        try:
            while self._is_running:
                await asyncio.sleep(self.interval_seconds)
                try:
                    await self.trigger_warmup()
                except Exception as e:
                    logger.warning(f"Periodic catalog warm-up encountered an issue (will retry on next interval): {e}")
        except asyncio.CancelledError:
            logger.info("CatalogWarmupService background task was cancelled gracefully.")
            self._is_running = False
            raise
        finally:
            self._is_running = False
