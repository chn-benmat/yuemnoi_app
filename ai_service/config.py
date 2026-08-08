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

    # จำกัดข้อมูลที่ส่งเข้าโมเดลและผลลัพธ์จากฐานข้อมูล
    MAX_SEARCH_RESULTS: int = 5
    MAX_HISTORY_MESSAGES: int = 6

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")


settings = Settings()
