from app.core.config import Settings, get_settings
from app.infrastructure.cache.memory_cache import MemoryCacheService
from app.infrastructure.db.supabase_repository import SupabaseRepository
from app.infrastructure.search.tavily_client import TavilyClient
from app.infrastructure.llm.ollama_client import OllamaClient
from app.application.services.fact_verification import FactVerificationService
from app.application.services.web_grounding_service import WebGroundingService
from app.application.services.catalog_warmup_service import CatalogWarmupService
from app.application.use_cases.route_intent import RouteIntentUseCase
from app.application.use_cases.query_items import QueryItemsUseCase
from app.application.use_cases.compare_items import CompareItemsUseCase
from app.application.use_cases.generate_clarification import GenerateClarificationUseCase
from app.application.use_cases.inquire_item_spec import InquireItemSpecUseCase
from app.application.use_cases.process_chat_message import ProcessChatMessageUseCase

class Container:
    """Dependency Injection Container for AI Service."""

    def __init__(self, settings: Settings):
        self.settings = settings
        
        # Infrastructure
        self.cache_service = MemoryCacheService()
        self.item_repository = SupabaseRepository(settings)
        self.search_service = TavilyClient(settings)
        self.llm_service = OllamaClient(settings)
        
        # Domain & Application Services
        self.fact_verification_service = FactVerificationService(self.llm_service)
        self.web_grounding_service = WebGroundingService(
            search_service=self.search_service,
            llm_service=self.llm_service,
            fact_verification_service=self.fact_verification_service,
            cache_service=self.cache_service
        )
        
        # Use Cases
        self.route_intent_use_case = RouteIntentUseCase(self.llm_service)
        self.query_items_use_case = QueryItemsUseCase(
            item_repo=self.item_repository,
            cache_service=self.cache_service,
            llm_service=self.llm_service,
            cache_ttl_seconds=settings.CATALOG_CACHE_TTL
        )
        self.catalog_warmup_service = CatalogWarmupService(
            query_items_use_case=self.query_items_use_case,
            interval_seconds=settings.CATALOG_WARMUP_INTERVAL,
            ttl_seconds=settings.CATALOG_CACHE_TTL
        )
        self.compare_items_use_case = CompareItemsUseCase(
            item_repo=self.item_repository,
            query_items_use_case=self.query_items_use_case,
            search_service=self.search_service,
            fact_verification_service=self.fact_verification_service,
            llm_service=self.llm_service,
            web_grounding_service=self.web_grounding_service
        )
        self.generate_clarification_use_case = GenerateClarificationUseCase(
            llm_service=self.llm_service,
            item_repo=self.item_repository,
            cache_service=self.cache_service
        )
        self.inquire_item_spec_use_case = InquireItemSpecUseCase(
            query_items_use_case=self.query_items_use_case,
            search_service=self.search_service,
            llm_service=self.llm_service,
            web_grounding_service=self.web_grounding_service
        )
        self.process_chat_message_use_case = ProcessChatMessageUseCase(
            route_intent_use_case=self.route_intent_use_case,
            query_items_use_case=self.query_items_use_case,
            compare_items_use_case=self.compare_items_use_case,
            generate_clarification_use_case=self.generate_clarification_use_case,
            inquire_item_spec_use_case=self.inquire_item_spec_use_case,
            llm_service=self.llm_service
        )

_container_instance = None

def get_container() -> Container:
    global _container_instance
    if _container_instance is None:
        settings = get_settings()
        _container_instance = Container(settings)
    return _container_instance
