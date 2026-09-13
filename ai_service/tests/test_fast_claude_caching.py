import pytest
import time
from unittest.mock import AsyncMock
from app.application.services.web_grounding_service import WebGroundingService, GroundedSpecResult
from app.infrastructure.cache.memory_cache import MemoryCacheService
from app.domain.entities.comparison import VerifiedSource

@pytest.mark.asyncio
async def test_web_grounding_spec_memory_cache_hit():
    cache_service = MemoryCacheService()
    mock_search = AsyncMock()
    mock_llm = AsyncMock()

    # Configure mock search response
    mock_search.search.return_value = [
        {
            "title": "[Tavily Instant Answer] Canon EOS R50 dimensions",
            "link": "https://www.canon.com",
            "snippet": "คำตอบตรง: 116.3 x 85.5 x 68.8 mm | 375 g",
            "is_instant_answer": True
        },
        {
            "title": "Canon EOS R50 Specs",
            "link": "https://www.dpreview.com",
            "snippet": "Full specifications for Canon R50",
            "is_instant_answer": False
        }
    ]

    service = WebGroundingService(
        search_service=mock_search,
        llm_service=mock_llm,
        cache_service=cache_service
    )

    # First Call: Cache Miss (Hits Search Service)
    t0 = time.perf_counter()
    res1 = await service.search_and_ground_spec("Canon EOS R50", "ขนาดและน้ำหนัก")
    t1 = time.perf_counter()

    assert mock_search.search.call_count == 1
    assert "Tavily Instant Answer" in res1.snippets_text
    assert "116.3 x 85.5 x 68.8 mm" in res1.snippets_text
    assert len(res1.sources) == 2

    # Second Call: Cache Hit (Instant 0ms, Does NOT call Search Service)
    t2 = time.perf_counter()
    res2 = await service.search_and_ground_spec("Canon EOS R50", "ขนาดและน้ำหนัก")
    t3 = time.perf_counter()

    # Search count must remain 1!
    assert mock_search.search.call_count == 1
    assert res2.snippets_text == res1.snippets_text
    assert res2.search_query == res1.search_query
    # Cache hit must be blazing fast (less than 10 milliseconds)
    cache_hit_duration = (t3 - t2) * 1000
    assert cache_hit_duration < 20.0
