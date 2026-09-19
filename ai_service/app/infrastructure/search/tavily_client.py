from typing import List, Optional
from urllib.parse import urlparse
import httpx

from app.core.config import settings
from app.core.exceptions import SearchException
from app.core.logging import logger
from app.domain.entities.search_source import SearchSource
from app.domain.interfaces.search_service import SearchServiceInterface


class TavilyClient(SearchServiceInterface):
    """Asynchronous client for Tavily Search API."""

    API_URL = "https://api.tavily.com/search"

    def __init__(self, api_key: Optional[str] = None, timeout: float = 15.0):
        self._api_key = api_key or settings.TAVILY_API_KEY
        self._timeout = timeout

    async def search(self, query: str, max_results: int = 3) -> List[SearchSource]:
        if not self._api_key or not query.strip():
            return []

        payload = {
            "api_key": self._api_key,
            "query": query.strip(),
            "search_depth": "basic",
            "max_results": max_results,
            "include_answer": False,
        }

        try:
            async with httpx.AsyncClient(timeout=self._timeout) as client:
                resp = await client.post(self.API_URL, json=payload)
                if resp.status_code != 200:
                    logger.warning(f"Tavily search failed with status {resp.status_code}: {resp.text}")
                    return []

                data = resp.json()
                results = data.get("results", [])
                sources: List[SearchSource] = []
                for item in results:
                    url = item.get("url", "")
                    domain = ""
                    if url:
                        try:
                            domain = urlparse(url).netloc.replace("www.", "")
                        except Exception:
                            domain = ""

                    sources.append(
                        SearchSource(
                            title=item.get("title", ""),
                            url=url,
                            link=url,
                            domain=domain,
                            snippet=item.get("content", ""),
                        )
                    )
                return sources
        except Exception as exc:
            logger.warning(f"Error during Tavily search execution: {exc}")
            return []
