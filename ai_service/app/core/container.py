from app.application.services.fact_verification_service import FactVerificationService
from app.application.use_cases.compare_items_use_case import CompareItemsUseCase
from app.application.use_cases.generate_clarification_use_case import GenerateClarificationUseCase
from app.application.use_cases.process_chat_message_use_case import ProcessChatMessageUseCase
from app.application.use_cases.query_items_use_case import QueryItemsUseCase
from app.application.use_cases.route_intent_use_case import RouteIntentUseCase
from app.infrastructure.cache.memory_cache_service import MemoryCacheService
from app.infrastructure.llm.cascade_llm_service import CascadeLLMService
from app.infrastructure.llm.gemini_client import GeminiClient
from app.infrastructure.llm.groq_client import GroqClient
from app.infrastructure.search.tavily_client import TavilyClient
from app.infrastructure.supabase.supabase_repository import SupabaseRepository


class Container:
    """Dependency Injection container wiring ports to adapters."""

    def __init__(self):
        # Infrastructure
        self.cache_service = MemoryCacheService(default_ttl=300)
        self.item_repository = SupabaseRepository(cache_service=self.cache_service)
        self.search_service = TavilyClient()
        self.gemini_client = GeminiClient()
        self.groq_client = GroqClient()
        self.llm_service = CascadeLLMService(
            gemini_client=self.gemini_client,
            groq_client=self.groq_client,
        )

        # Domain / Application Services
        self.fact_service = FactVerificationService(llm_service=self.llm_service)

        # Application Use Cases
        self.route_intent_use_case = RouteIntentUseCase(llm_service=self.llm_service)
        self.query_items_use_case = QueryItemsUseCase(
            item_repository=self.item_repository,
            llm_service=self.llm_service,
        )
        self.compare_items_use_case = CompareItemsUseCase(
            llm_service=self.llm_service,
            search_service=self.search_service,
            fact_service=self.fact_service,
        )
        self.generate_clarification_use_case = GenerateClarificationUseCase(
            llm_service=self.llm_service,
            item_repository=self.item_repository,
        )
        self.process_chat_message_use_case = ProcessChatMessageUseCase(
            route_intent=self.route_intent_use_case,
            query_items=self.query_items_use_case,
            compare_items=self.compare_items_use_case,
            generate_clarification=self.generate_clarification_use_case,
            llm_service=self.llm_service,
            search_service=self.search_service,
        )


container = Container()
