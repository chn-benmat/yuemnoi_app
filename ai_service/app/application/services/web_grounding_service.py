from typing import List, Dict, Any, Optional
from dataclasses import dataclass, field
from app.domain.entities.comparison import VerifiedSource
from app.domain.interfaces.search_service import SearchServiceInterface
from app.domain.interfaces.llm_service import LLMServiceInterface
from app.domain.interfaces.cache_service import CacheServiceInterface
from app.application.services.fact_verification import FactVerificationService, FactVerificationResult
from app.core.logging import logger

@dataclass
class GroundedSpecResult:
    """Result of factual web grounding for item specifications."""
    search_query: str
    snippets_text: str
    sources: List[VerifiedSource] = field(default_factory=list)

class WebGroundingService:
    """Universal Web Grounding Service coordinating query formulation,
    web retrieval, and spam/ad filtering across use cases (spec inquiries and comparisons).
    Features Spec Memory Caching (TTL 24h) and Tavily Instant Answer/Web Grounding integration.
    """

    def __init__(
        self,
        search_service: SearchServiceInterface,
        llm_service: LLMServiceInterface,
        fact_verification_service: Optional[FactVerificationService] = None,
        cache_service: Optional[CacheServiceInterface] = None
    ):
        self.search_service = search_service
        self.llm_service = llm_service
        self.fact_verification_service = fact_verification_service or FactVerificationService(llm_service)
        self.cache_service = cache_service

    def formulate_spec_query(self, item_name: str, attribute: Optional[str] = None) -> str:
        """Formulates targeted technical search query for item specifications."""
        clean_item = item_name.strip()
        if attribute and attribute.strip():
            clean_attr = attribute.strip()
            return f"{clean_item} {clean_attr} สเปก specs"
        return f"{clean_item} สเปก ข้อมูลทางเทคนิค specs"

    def formulate_comparison_query(
        self,
        item_a_name: str,
        item_b_name: str,
        attribute: Optional[str] = None
    ) -> str:
        """Formulates targeted technical search query for item comparisons."""
        clean_a = item_a_name.strip()
        clean_b = item_b_name.strip()
        if attribute and attribute.strip():
            clean_attr = attribute.strip()
            return f"{clean_a} vs {clean_b} {clean_attr} specs comparison"
        return f"{clean_a} vs {clean_b} specs comparison รีวิว"

    async def search_and_ground_spec(
        self,
        item_name: str,
        attribute: Optional[str] = None,
        num_results: int = 4
    ) -> GroundedSpecResult:
        """Retrieves and filters web search results for factual item specifications.
        Uses in-memory caching to return instant results (0ms) on repeated queries.
        """
        clean_item = item_name.strip()
        clean_attr = attribute.strip() if attribute else ""
        cache_key = f"spec_cache:{clean_item.lower()}:{clean_attr.lower() if clean_attr else 'general'}"

        # 1. Check in-memory spec cache
        if self.cache_service:
            cached = await self.cache_service.get(cache_key)
            if cached and isinstance(cached, GroundedSpecResult):
                logger.info(f"Spec Memory Cache Hit for '{cache_key}' (0ms latency)")
                return cached

        search_query = self.formulate_spec_query(clean_item, clean_attr)
        logger.info(f"WebGroundingService Spec Query: '{search_query}'")

        instant_answers: List[str] = []
        knowledge_graphs: List[str] = []
        organic_snippets: List[str] = []
        sources: List[VerifiedSource] = []

        try:
            raw_results = await self.search_service.search(query=search_query, num_results=num_results)
            for res in raw_results:
                title = (res.get("title") or "").strip()
                link = (res.get("link") or "").strip()
                snippet = (res.get("snippet") or "").strip()
                is_instant = res.get("is_instant_answer", False)
                is_kg = res.get("is_knowledge_graph", False)

                if snippet and link:
                    if is_instant:
                        instant_answers.append(f"- {title}: {snippet}")
                    elif is_kg:
                        knowledge_graphs.append(f"- {title}: {snippet}")
                    else:
                        organic_snippets.append(f"- {title}: {snippet}")

                    sources.append(
                        VerifiedSource(
                            title=title,
                            link=link,
                            snippet=snippet,
                            relevance_score=0.95 if (is_instant or is_kg) else 0.9,
                            is_credible=True
                        )
                    )
        except Exception as e:
            logger.warning(f"Web search failed in WebGroundingService: {e}")

        # Assemble prioritized, hierarchical grounding context
        formatted_blocks: List[str] = []
        if instant_answers:
            formatted_blocks.append("[Tavily Instant Answer / Spec Box]:\n" + "\n".join(instant_answers))
        if knowledge_graphs:
            formatted_blocks.append("[Official Specifications]:\n" + "\n".join(knowledge_graphs))
        if organic_snippets:
            formatted_blocks.append("[Web Research Sources]:\n" + "\n".join(organic_snippets))

        snippets_text = "\n\n".join(formatted_blocks) if formatted_blocks else "ไม่มีข้อมูลสเปกจากการค้นหาภายนอก ให้ตอบตามองค์ความรู้ที่ถูกต้องของโมเดล"
        result = GroundedSpecResult(
            search_query=search_query,
            snippets_text=snippets_text,
            sources=sources
        )

        # Cache valid grounding result for 24 hours (86,400s)
        if self.cache_service and sources:
            await self.cache_service.set(cache_key, result, ttl_seconds=86400)

        return result

    async def search_and_ground_comparison(
        self,
        item_a_name: str,
        item_b_name: str,
        attribute: Optional[str] = None,
        num_results: int = 4
    ) -> tuple[str, FactVerificationResult]:
        """Retrieves, filters, and cross-checks web search results for side-by-side comparison.
        Uses in-memory caching to return instant results (0ms) on repeated queries.
        """
        clean_a = item_a_name.strip()
        clean_b = item_b_name.strip()
        clean_attr = attribute.strip() if attribute else ""
        cache_key = f"comp_cache:{clean_a.lower()}:{clean_b.lower()}:{clean_attr.lower() if clean_attr else 'general'}"

        if self.cache_service:
            cached = await self.cache_service.get(cache_key)
            if cached and isinstance(cached, tuple) and len(cached) == 2:
                logger.info(f"Comparison Memory Cache Hit for '{cache_key}' (0ms latency)")
                return cached

        search_query = self.formulate_comparison_query(clean_a, clean_b, attribute=attribute)
        logger.info(f"WebGroundingService Comparison Query: '{search_query}'")

        raw_results = await self.search_service.search(query=search_query, num_results=num_results)
        fact_result = await self.fact_verification_service.verify_and_filter(
            item_a_name=clean_a,
            item_b_name=clean_b,
            raw_search_results=raw_results
        )

        result_tuple = (search_query, fact_result)
        if self.cache_service and fact_result.filtered_sources:
            await self.cache_service.set(cache_key, result_tuple, ttl_seconds=86400)

        return result_tuple

