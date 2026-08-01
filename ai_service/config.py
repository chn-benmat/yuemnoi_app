import os
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # Supabase
    SUPABASE_URL: str
    SUPABASE_KEY: str

    # ใช้ Serper.dev สำหรับดึงสเปคอุปกรณ์ภายนอก
    SERPER_API_KEY: str

    # โมเดล Qwen ที่รันภายในเครื่องผ่าน Ollama
    MODEL_NAME: str = "qwen2.5:7b"
    OLLAMA_ENDPOINT: str = "http://localhost:11434/v1"

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")


settings = Settings()
