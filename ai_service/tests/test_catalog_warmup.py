import pytest
import asyncio
from unittest.mock import AsyncMock, MagicMock
from app.domain.entities.item import Item
from app.application.use_cases.query_items import QueryItemsUseCase, CatalogModelNames, ItemModelName
from app.application.services.catalog_warmup_service import CatalogWarmupService
from app.infrastructure.cache.memory_cache import MemoryCacheService

@pytest.fixture
def mock_items():
    return [
        Item(
            id=1,
            user_id="u1",
            item_name="กล้อง Canon EOS R50 พร้อมเลนส์ Kit",
            item_image_url=["https://example.com/r50.jpg"],
            description="กล้องมิเรอร์เลส",
            category="กล้องและอุปกรณ์ถ่ายภาพ",
            price=450.0,
            status="available",
            type="day",
            created_at="2025-01-01",
            updated_at="2025-01-01"
        ),
        Item(
            id=2,
            user_id="u2",
            item_name="กล้อง Sony A7 IV สภาพนางฟ้า",
            item_image_url=["https://example.com/a7iv.jpg"],
            description="กล้องฟูลเฟรมโปร",
            category="กล้องและอุปกรณ์ถ่ายภาพ",
            price=850.0,
            status="available",
            type="day",
            created_at="2025-01-01",
            updated_at="2025-01-01"
        )
    ]

@pytest.mark.asyncio
async def test_refresh_catalog_cache_success(mock_items):
    cache_service = MemoryCacheService()
    mock_repo = AsyncMock()
    mock_repo.get_all_items.return_value = mock_items

    mock_llm = AsyncMock()
    mock_llm.generate_structured.return_value = CatalogModelNames(
        items=[
            ItemModelName(id=1, model_name="Canon EOS R50"),
            ItemModelName(id=2, model_name="Sony A7 IV")
        ]
    )

    use_case = QueryItemsUseCase(
        item_repo=mock_repo,
        cache_service=cache_service,
        llm_service=mock_llm,
        cache_ttl_seconds=540
    )

    # 1. Force refresh
    items = await use_case.refresh_catalog_cache(ttl_seconds=540)
    assert len(items) == 2
    assert items[0].model_name == "Canon EOS R50"
    assert items[1].model_name == "Sony A7 IV"

    # 2. Check cache hit
    cached = await cache_service.get(use_case.CACHE_KEY)
    assert cached is not None
    assert len(cached) == 2

    # 3. get_all_cached_items without force_refresh should hit cache and NOT call repo or LLM again
    mock_repo.get_all_items.reset_mock()
    mock_llm.generate_structured.reset_mock()
    items_cached = await use_case.get_all_cached_items(force_refresh=False)
    assert len(items_cached) == 2
    assert mock_repo.get_all_items.call_count == 0
    assert mock_llm.generate_structured.call_count == 0

@pytest.mark.asyncio
async def test_refresh_catalog_cache_stale_while_revalidate(mock_items):
    cache_service = MemoryCacheService()
    await cache_service.set(QueryItemsUseCase.CACHE_KEY, mock_items, ttl_seconds=600)

    failing_repo = AsyncMock()
    failing_repo.get_all_items.side_effect = RuntimeError("Supabase network error")

    mock_llm = AsyncMock()

    use_case = QueryItemsUseCase(
        item_repo=failing_repo,
        cache_service=cache_service,
        llm_service=mock_llm
    )

    # When refresh fails, it serves stale items without crashing
    items = await use_case.refresh_catalog_cache()
    assert len(items) == 2
    assert items[0].item_name == "กล้อง Canon EOS R50 พร้อมเลนส์ Kit"

@pytest.mark.asyncio
async def test_catalog_warmup_service_lifecycle(mock_items):
    mock_use_case = AsyncMock()
    mock_use_case.refresh_catalog_cache.return_value = mock_items

    service = CatalogWarmupService(
        query_items_use_case=mock_use_case,
        interval_seconds=1,  # Fast 1s interval for unit test
        ttl_seconds=540
    )

    # Trigger single warm-up
    res = await service.trigger_warmup()
    assert len(res) == 2
    mock_use_case.refresh_catalog_cache.assert_called_once_with(ttl_seconds=540)

    # Start periodic warm-up and cancel after short delay
    task = asyncio.create_task(service.start_periodic_warmup())
    await asyncio.sleep(1.2)  # Wait for 1 tick
    assert mock_use_case.refresh_catalog_cache.call_count >= 2

    # Clean cancellation
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    assert not service.is_running
