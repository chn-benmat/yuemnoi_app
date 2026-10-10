from pathlib import Path
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

class IdentitySettings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore", env_file_encoding="utf-8")
    IDENTITY_ENABLED: bool = False
    IDENTITY_MANIFEST: Path = Path("config/identity_models.json")
    IDENTITY_MAX_BYTES: int = Field(default=5*1024*1024, gt=0)
    IDENTITY_MAX_PIXELS: int = Field(default=16000000, gt=0)
    IDENTITY_REQUEST_BYTES: int = Field(default=11*1024*1024, gt=0)
    IDENTITY_TIMEOUT_SECONDS: float = Field(default=90, gt=0)
    IDENTITY_QUEUE_TIMEOUT_SECONDS: float = Field(default=5, gt=0)
    IDENTITY_FACE_CONFIDENCE: float = Field(default=0.85, gt=0, lt=1)
    IDENTITY_FACE_NMS: float = Field(default=0.3, gt=0, lt=1)
    IDENTITY_FACE_TOP_K: int = Field(default=5000, gt=0)
    IDENTITY_TORCH_THREADS: int = Field(default=2, gt=0)

identity_settings = IdentitySettings()
