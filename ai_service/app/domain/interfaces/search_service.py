from abc import ABC, abstractmethod
from typing import List, Dict, Any

class SearchServiceInterface(ABC):
    @abstractmethod
    async def search(
        self,
        query: str,
        gl: str = "th",
        hl: str = "th",
        num_results: int = 5
    ) -> List[Dict[str, Any]]:
        """Perform external web search and return structured organic results."""
        pass
