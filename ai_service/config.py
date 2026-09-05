from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # Supabase
    SUPABASE_URL: str
    SUPABASE_KEY: str

    # ใช้ Serper.dev สำหรับดึงสเปคอุปกรณ์ภายนอก
    SERPER_API_KEY: str

    # โมเดล Qwen ที่รันภายในเครื่องผ่าน Ollama
    MODEL_NAME: str = "qwen3:8b"
    OLLAMA_ENDPOINT: str = "http://localhost:11434"
    OLLAMA_CONTEXT_LENGTH: int = 4096
    OLLAMA_KEEP_ALIVE: int = -1
    PIPELINE_TIMEOUT: float = 45.0
    ROUTING_TIMEOUT: float = 35.0
    MATCH_TIMEOUT: float = 35.0

    # จำกัดข้อมูลที่ส่งเข้าโมเดลและผลลัพธ์จากฐานข้อมูล
    MAX_SEARCH_RESULTS: int = 5
    MAX_CATALOG_ITEMS: int = 50
    MAX_HISTORY_MESSAGES: int = 6

    # Output budgets for each structured Qwen task. These must leave enough room
    # for complete JSON; truncated JSON is treated as an unavailable assistant.
    INTERPRETATION_MAX_TOKENS: int = 384
    CONVERSATIONAL_MAX_TOKENS: int = 512
    ROUTING_MAX_TOKENS: int = 256
    LANGUAGE_REPAIR_MAX_TOKENS: int = 150
    FINAL_RESPONSE_MAX_TOKENS: int = 250
    INVENTORY_MATCH_MAX_TOKENS: int = 150
    INVENTORY_VERIFICATION_MAX_TOKENS: int = 80

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")


settings = Settings()
