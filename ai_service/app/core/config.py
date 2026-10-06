from pathlib import Path
from typing import Optional, Tuple
from pydantic import Field, PrivateAttr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from app.infrastructure.runtime.settings_source import RuntimeSettingsSource


class Settings(BaseSettings):
    """Application configuration loaded from environment variables (.env)."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    AI_RUNTIME_PATH: Path = Path(__file__).resolve().parents[2] / "config/ai_runtime.json"
    INTERPRETATION_POLICY_PATH: Optional[Path] = None
    AI_QUOTA_LEDGER_PATH: Optional[Path] = None
    _explicit_overrides: set[str] = PrivateAttr(default_factory=set)
    _loaded_env_file: object = PrivateAttr(default=None)
    _loaded_secrets_dir: object = PrivateAttr(default=None)

    def __init__(self, **values):
        super().__init__(**values)
        self._explicit_overrides = {name for name in values if name in type(self).model_fields}
        self._loaded_env_file = values.get("_env_file", self.model_config.get("env_file"))
        self._loaded_secrets_dir = values.get("_secrets_dir", self.model_config.get("secrets_dir"))

    @classmethod
    def settings_customise_sources(cls, settings_cls, init_settings, env_settings,
                                  dotenv_settings, file_secret_settings):
        return init_settings, env_settings, dotenv_settings, file_secret_settings, RuntimeSettingsSource(settings_cls)

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
    INTENT_CONTEXT_MAX_MESSAGES: int = Field(default=16, ge=1)
    INTENT_CONTEXT_MAX_CHARACTERS: int = Field(default=24000, ge=1)
    INTENT_TEMPERATURE: float = Field(default=0.1, ge=0, le=2)
    GUIDANCE_MAX_QUESTIONS: int = Field(default=3, ge=1, le=3)
    GUIDANCE_MAX_OPTIONS: int = Field(default=4, ge=1, le=4)
    GUIDANCE_TITLE_MAX_CHARACTERS: int = Field(default=80, ge=1)
    GUIDANCE_OPTION_MAX_CHARACTERS: int = Field(default=80, ge=1)
    GUIDANCE_MAX_ITEMS: int = Field(default=3, ge=1)
    GUIDANCE_GENERATION_ATTEMPTS: int = Field(default=2, ge=1)
    GUIDANCE_TEMPERATURE: float = Field(default=0.1, ge=0, le=2)
    STRUCTURED_MAX_OUTPUT_TOKENS: int = Field(default=3000, ge=1)
    CHAT_STREAM_HEARTBEAT_SECONDS: float = Field(default=10, gt=0, le=30)
    CHAT_STREAM_CHUNK_CHARACTERS: int = Field(default=64, ge=1)

    # Application knowledge is optional until owner-approved content is wired in.
    APP_KNOWLEDGE_PATH: Optional[Path] = Field(
        default=None,
        description="Owner-maintained knowledge document path; relative paths use the process working directory",
    )

    @field_validator("APP_KNOWLEDGE_PATH", mode="before")
    @classmethod
    def empty_knowledge_path_is_unconfigured(cls, value):
        if isinstance(value, str):
            stripped = value.strip()
            return stripped if stripped else None
        return value

    # Gemini Cascade: Primary -> Fallback 1 -> Fallback 2
    GEMINI_PRIMARY_MODEL: str
    GEMINI_FALLBACK_MODEL_1: str
    GEMINI_FALLBACK_MODEL_2: str

    # Groq Cascade: Primary -> Fallback 1 -> Fallback 2
    GROQ_PRIMARY_MODEL: str
    GROQ_FALLBACK_MODEL_1: str
    GROQ_FALLBACK_MODEL_2: str

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
