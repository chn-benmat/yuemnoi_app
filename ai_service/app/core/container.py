from app.application.use_cases.generate_clarification_use_case import GenerateClarificationUseCase
from app.application.use_cases.process_chat_message_use_case import ProcessChatMessageUseCase
from app.application.use_cases.query_items_use_case import QueryItemsUseCase
from app.application.use_cases.route_intent_use_case import RouteIntentUseCase
from app.application.use_cases.plan_chat_turn_use_case import PlanChatTurnUseCase
from app.application.services.conversation_context import ContextLimits
from app.core.config import settings
from app.domain.entities.catalog_guidance import GuidancePolicy
from app.infrastructure.cache.memory_cache_service import MemoryCacheService
from app.infrastructure.llm.cascade_llm_service import CascadeLLMService
from app.infrastructure.llm.groq_client import GroqClient
from app.infrastructure.knowledge.file_knowledge_repository import FileKnowledgeRepository
from app.infrastructure.search.tavily_client import TavilyClient
from app.infrastructure.supabase.supabase_repository import SupabaseRepository
from app.infrastructure.runtime.execution import RuntimeExecutionGuard


class Container:
    """Dependency Injection container wiring ports to adapters."""

    def __init__(self):
        self.execution_guard = RuntimeExecutionGuard(settings.AI_RUNTIME_PATH, settings.INTERPRETATION_POLICY_PATH)
        # Infrastructure
        self.cache_service = MemoryCacheService(default_ttl=settings.CACHE_TTL_SECONDS)
        self.item_repository = SupabaseRepository(cache_service=self.cache_service, runtime=self.execution_guard.runtime)
        self.knowledge_repository = FileKnowledgeRepository(settings.APP_KNOWLEDGE_PATH)
        self.search_service = TavilyClient()
        self.groq_client = GroqClient()
        self.llm_service = CascadeLLMService(
            groq_client=self.groq_client,
        )

        # Application Use Cases
        self.guidance_policy = GuidancePolicy(
            max_questions=settings.GUIDANCE_MAX_QUESTIONS,
            max_options=settings.GUIDANCE_MAX_OPTIONS,
            title_max_characters=settings.GUIDANCE_TITLE_MAX_CHARACTERS,
            option_max_characters=settings.GUIDANCE_OPTION_MAX_CHARACTERS,
            max_items=settings.GUIDANCE_MAX_ITEMS,
            generation_attempts=settings.GUIDANCE_GENERATION_ATTEMPTS,
            temperature=settings.GUIDANCE_TEMPERATURE,
        )
        self.route_intent_use_case = RouteIntentUseCase(
            llm_service=self.llm_service,
            context_limits=ContextLimits(settings.INTENT_CONTEXT_MAX_MESSAGES, settings.INTENT_CONTEXT_MAX_CHARACTERS),
            temperature=settings.INTENT_TEMPERATURE,
        )
        self.query_items_use_case = QueryItemsUseCase(
            item_repository=self.item_repository,
            llm_service=self.llm_service,
            policy=self.guidance_policy,
        )
        self.generate_clarification_use_case = GenerateClarificationUseCase(
            llm_service=self.llm_service,
            item_repository=self.item_repository,
            policy=self.guidance_policy,
        )
        self.plan_chat_turn_use_case = PlanChatTurnUseCase(
            self.llm_service, self.item_repository, self.knowledge_repository, self.query_items_use_case,
            self.search_service, ContextLimits(settings.INTENT_CONTEXT_MAX_MESSAGES, settings.INTENT_CONTEXT_MAX_CHARACTERS),
            self.guidance_policy, self.execution_guard.policy.model_dump(mode="json", exclude={"approval", "status", "production_enabled", "schema_version", "version"}),
            self.execution_guard)
        self.process_chat_message_use_case = ProcessChatMessageUseCase(
            context_limits=ContextLimits(settings.INTENT_CONTEXT_MAX_MESSAGES, settings.INTENT_CONTEXT_MAX_CHARACTERS),
            route_intent=self.route_intent_use_case,
            query_items=self.query_items_use_case,
            generate_clarification=self.generate_clarification_use_case,
            llm_service=self.llm_service,
            search_service=self.search_service,
            knowledge_repository=self.knowledge_repository,
            policy=self.guidance_policy,
            stream_heartbeat_seconds=settings.CHAT_STREAM_HEARTBEAT_SECONDS,
            stream_chunk_characters=settings.CHAT_STREAM_CHUNK_CHARACTERS,
            execution_guard=self.execution_guard,
            fast_path=self.plan_chat_turn_use_case,
        )

    async def start(self):
        await self.item_repository.start()
        await self.llm_service.start()

    async def aclose(self):
        try:
            await self.llm_service.aclose()
        finally:
            await self.item_repository.aclose()


container = Container()
