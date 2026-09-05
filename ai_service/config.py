from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # Supabase credentials
    SUPABASE_URL: str
    SUPABASE_KEY: str

    # Optional external tool (if needed)
    SERPER_API_KEY: str = ""

    # Ollama Local Model
    MODEL_NAME: str = "qwen3:8b"
    OLLAMA_ENDPOINT: str = "http://localhost:11434"
    OLLAMA_CONTEXT_LENGTH: int = 8192
    OLLAMA_KEEP_ALIVE: int = -1
    PIPELINE_TIMEOUT: float = 45.0

    # Catalog & Chat limits
    MAX_CATALOG_ITEMS: int = 50
    MAX_HISTORY_MESSAGES: int = 6
    MAX_RECOMMENDED_ITEMS: int = 4

    # Allow extra fields in .env without crashing
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


settings = Settings()
