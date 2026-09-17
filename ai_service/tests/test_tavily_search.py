import pytest
from unittest.mock import patch, MagicMock, AsyncMock
from app.infrastructure.search.tavily_client import TavilyClient
from app.core.config import get_settings
from app.core.exceptions import SearchServiceException
from app.application.services.web_grounding_service import WebGroundingService
from app.infrastructure.cache.memory_cache import MemoryCacheService

@pytest.mark.asyncio
async def test_tavily_client_extracts_instant_answer_and_results():
    settings = get_settings()
    client = TavilyClient(settings)

    mock_response_data = {
        "query": "Sony A7 IV สเปก",
        "answer": "Sony Alpha A7 IV features a 33MP Full-Frame Exmor R BSI CMOS sensor and BIONZ XR processor.",
        "results": [
            {
                "title": "Sony A7 IV Full Specifications",
                "url": "https://www.sony.co.th/th/electronics/interchangeable-lens-cameras/ilce-7m4",
                "content": "Full technical specs for Sony A7 IV: 33MP Full-Frame, 4K 60p, 10-bit 4:2:2.",
                "published_date": "2024-01-10",
                "score": 0.98
            },
            {
                "title": "Sony A7 IV Camera Review",
                "url": "https://www.dpreview.com/reviews/sony-a7-iv-review",
                "content": "Detailed hands-on review and ISO comparisons for Sony A7 IV.",
                "published_date": "2024-02-15",
                "score": 0.92
            }
        ]
    }

    mock_resp = MagicMock()
    mock_resp.json.return_value = mock_response_data
    mock_resp.raise_for_status.return_value = None

    with patch("httpx.AsyncClient.post", return_value=mock_resp):
        results = await client.search("Sony A7 IV สเปก")

    assert len(results) == 3
    # 1. Instant Answer
    assert results[0]["is_instant_answer"] is True
    assert "[Tavily Instant Answer]" in results[0]["title"]
    assert "33MP Full-Frame Exmor R" in results[0]["snippet"]

    # 2. First Organic Result
    assert results[1]["is_instant_answer"] is False
    assert results[1]["title"] == "Sony A7 IV Full Specifications"
    assert results[1]["link"] == "https://www.sony.co.th/th/electronics/interchangeable-lens-cameras/ilce-7m4"
    assert "4K 60p" in results[1]["snippet"]

    # 3. Second Organic Result
    assert results[2]["is_instant_answer"] is False
    assert results[2]["title"] == "Sony A7 IV Camera Review"

@pytest.mark.asyncio
async def test_tavily_client_raises_search_exception_on_network_error():
    settings = get_settings()
    client = TavilyClient(settings)

    with patch("httpx.AsyncClient.post", side_effect=Exception("Connection timed out")):
        with pytest.raises(SearchServiceException) as exc_info:
            await client.search("Canon EOS R50")

    assert "Failed to query Tavily search" in str(exc_info.value)

@pytest.mark.asyncio
async def test_web_grounding_service_with_tavily_formatting():
    mock_search = AsyncMock()
    mock_llm = AsyncMock()
    cache_service = MemoryCacheService()

    mock_search.search.return_value = [
        {
            "title": "[Tavily Instant Answer] Direct Spec Summary",
            "link": "https://tavily.com",
            "snippet": "คำตอบตรง: Canon EOS R50 น้ำหนัก 375 กรัม เซนเซอร์ APS-C 24.2 MP",
            "is_instant_answer": True
        },
        {
            "title": "Canon EOS R50 Review",
            "link": "https://www.canon.com",
            "snippet": "Canon EOS R50 specs and detailed overview",
            "is_instant_answer": False
        }
    ]

    service = WebGroundingService(
        search_service=mock_search,
        llm_service=mock_llm,
        cache_service=cache_service
    )

    result = await service.search_and_ground_spec("Canon EOS R50", "สเปก")

    assert "[Tavily Instant Answer / Spec Box]:" in result.snippets_text
    assert "[Web Research Sources]:" in result.snippets_text
    assert "375 กรัม" in result.snippets_text
    assert len(result.sources) == 2
    assert result.sources[0].relevance_score == 0.95
