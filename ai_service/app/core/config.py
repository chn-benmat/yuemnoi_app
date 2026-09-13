from pydantic_settings import BaseSettings, SettingsConfigDict
from typing import Optional

class Settings(BaseSettings):
    # Supabase Configuration
    SUPABASE_URL: str
    SUPABASE_KEY: str

    # Tavily Search Configuration
    TAVILY_API_KEY: str
    TAVILY_API_URL: str = "https://api.tavily.com/search"
    TAVILY_SEARCH_DEPTH: str = "basic"

    # Ollama Local LLM Configuration
    OLLAMA_BASE_URL: str = "http://localhost:11434"
    OLLAMA_MODEL: str = "llama3.1-typhoon2-8b-instruct:latest"
    OLLAMA_NUM_CTX: int = 8192
    OLLAMA_TEMPERATURE: float = 0.2
    OLLAMA_REPEAT_PENALTY: float = 1.05
    OLLAMA_TIMEOUT: float = 60.0

    # Application Configuration
    APP_NAME: str = "AI Rental Chatbot Service"
    APP_ENV: str = "development"
    DEBUG: bool = False
    API_PREFIX: str = "/api/v1"
    INTERNAL_SERVICE_KEY: str = ""
    CATALOG_CACHE_TTL: int = 600  # seconds (10 minutes)
    CATALOG_WARMUP_INTERVAL: int = 540  # seconds (9 minutes)
    ENABLE_BACKGROUND_WARMUP: bool = True

    @property
    def internal_service_keys(self) -> list[str]:
        """Returns list of valid internal keys (supporting comma-separated multi-key rotation)."""
        return [k.strip() for k in self.INTERNAL_SERVICE_KEY.split(",") if k.strip()]

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore"
    )

from functools import lru_cache

@lru_cache
def get_settings() -> Settings:
    return Settings()
