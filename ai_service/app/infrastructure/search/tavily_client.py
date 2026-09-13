import httpx
from typing import List, Dict, Any
from app.domain.interfaces.search_service import SearchServiceInterface
from app.core.config import Settings
from app.core.exceptions import SearchServiceException
from app.core.logging import logger

class TavilyClient(SearchServiceInterface):
    """Client for Tavily Search API optimized for LLM Grounding & Factual Verification."""

    def __init__(self, settings: Settings):
        self.api_key = settings.TAVILY_API_KEY
        self.endpoint = settings.TAVILY_API_URL
        self.search_depth = settings.TAVILY_SEARCH_DEPTH
        self.timeout = 15.0

    async def search(
        self,
        query: str,
        gl: str = "th",
        hl: str = "th",
        num_results: int = 5
    ) -> List[Dict[str, Any]]:
        payload = {
            "api_key": self.api_key,
            "query": query,
            "search_depth": self.search_depth,
            "include_answer": True,
            "max_results": num_results
        }
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(self.endpoint, json=payload)
                response.raise_for_status()
                data = response.json()

                results: List[Dict[str, Any]] = []

                # 1. Tavily AI Instant Answer (Direct Factual Answer / Spec Summary)
                answer = data.get("answer")
                if answer and isinstance(answer, str) and answer.strip():
                    results.append({
                        "title": "[Tavily Instant Answer] Direct Spec Summary",
                        "link": "https://tavily.com",
                        "snippet": f"คำตอบตรง: {answer.strip()}",
                        "date": "",
                        "is_instant_answer": True
                    })

                # 2. Organic Web Results (Verified Web Sources)
                raw_results = data.get("results", [])
                for item in raw_results[:num_results]:
                    title = (item.get("title") or "").strip()
                    link = (item.get("url") or "").strip()
                    snippet = (item.get("content") or "").strip()
                    date = (item.get("published_date") or "").strip()

                    if snippet and link:
                        results.append({
                            "title": title,
                            "link": link,
                            "snippet": snippet,
                            "date": date,
                            "is_instant_answer": False
                        })

                return results
        except Exception as e:
            logger.error(f"Tavily search failed for query '{query}': {e}")
            raise SearchServiceException(f"Failed to query Tavily search: {e}") from e
