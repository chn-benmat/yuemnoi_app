from typing import List, Protocol
from app.domain.entities.search_source import SearchSource


class SearchServiceInterface(Protocol):
    """Abstract port for web search retrieval."""

    async def search(self, query: str, max_results: int = 3) -> List[SearchSource]:
        """Search the web for technical specifications and relevant sources."""
        ...
