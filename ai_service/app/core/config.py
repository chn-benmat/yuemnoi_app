from typing import Tuple
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application configuration loaded from environment variables (.env)."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # API & Database Keys
    SUPABASE_URL: str = Field(default="", description="Supabase project URL")
    SUPABASE_KEY: str = Field(default="", description="Supabase service role or anon key")
    TAVILY_API_KEY: str = Field(default="", description="Tavily search API key")
    GEMINI_API_KEY: str = Field(default="", description="Google Gemini API key")
    GROQ_API_KEY: str = Field(default="", description="Groq API key")
    INTERNAL_SERVICE_KEY: str = Field(default="", description="Shared internal key for backend-to-ai auth")

    # Application Settings
    APP_NAME: str = "Yuemnoi AI Service"
    APP_ENV: str = "production"
    LOG_LEVEL: str = "INFO"
    CACHE_TTL_SECONDS: int = 300
    HTTP_TIMEOUT_SECONDS: float = 30.0

    # Gemini Cascade: Primary -> Fallback 1 -> Fallback 2
    GEMINI_PRIMARY_MODEL: str = "gemini-3.5-flash-lite"
    GEMINI_FALLBACK_MODEL_1: str = "gemini-3.1-flash-lite"
    GEMINI_FALLBACK_MODEL_2: str = "gemini-flash-lite-latest"

    # Groq Cascade: Primary -> Fallback 1 -> Fallback 2
    GROQ_PRIMARY_MODEL: str = "qwen/qwen3.8-27b"
    GROQ_FALLBACK_MODEL_1: str = "openai/gpt-oss-120b"
    GROQ_FALLBACK_MODEL_2: str = "openai/gpt-oss-20b"

    @property
    def gemini_models(self) -> Tuple[str, ...]:
        return (
            self.GEMINI_PRIMARY_MODEL,
            self.GEMINI_FALLBACK_MODEL_1,
            self.GEMINI_FALLBACK_MODEL_2,
        )

    @property
    def groq_models(self) -> Tuple[str, ...]:
        return (
            self.GROQ_PRIMARY_MODEL,
            self.GROQ_FALLBACK_MODEL_1,
            self.GROQ_FALLBACK_MODEL_2,
        )


settings = Settings()
