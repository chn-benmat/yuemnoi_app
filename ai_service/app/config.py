import os
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # Supabase
    SUPABASE_URL: str
    SUPABASE_KEY: str

    # ใช้ Serper.dev สำหรับดึงสเปคอุปกรณ์ภายนอก
    SERPER_API_KEY: str

    # Token สำหรับดาวน์โหลดโมเดล Qwen จาก Hugging Face
    HF_TOKEN: str

    # เลือกขนาดโมเดล Qwen หรือรันผ่าน vLLM Local Endpoint
    MODEL_NAME: str = "Qwen/Qwen2.5-7B-Instruct"
    VLLM_ENDPOINT: str = "http://localhost:8000/v1"  # กรณีใช้ vLLM เร่งความเร็วโมเดล

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")


settings = Settings()
