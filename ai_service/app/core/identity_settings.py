from pathlib import Path
from typing import Literal
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
    IDENTITY_OCR_DECODER: Literal["greedy", "beamsearch"] = "greedy"
    IDENTITY_OCR_BEAM_WIDTH: int = Field(default=5, gt=0, le=20)
    IDENTITY_OCR_CANVAS_SIZE: int = Field(default=2560, ge=640, le=4096)
    IDENTITY_OCR_MAG_RATIO: float = Field(default=1.5, ge=1, le=3)
    IDENTITY_OCR_MIN_SIZE: int = Field(default=10, gt=0)
    IDENTITY_OCR_MARGIN: float = Field(default=0.15, ge=0, le=0.5)
    IDENTITY_OCR_WIDTH_THRESHOLD: float = Field(default=1.0, gt=0, le=2)
    IDENTITY_OCR_HEIGHT_THRESHOLD: float = Field(default=0.7, gt=0, le=1)
    IDENTITY_OCR_CONTRAST_THRESHOLD: float = Field(default=0.3, ge=0, le=1)
    IDENTITY_OCR_ENHANCE: bool = True
    IDENTITY_OCR_CLAHE_CLIP: float = Field(default=2.0, gt=0)
    IDENTITY_OCR_CLAHE_GRID: int = Field(default=8, ge=1, le=32)

identity_settings = IdentitySettings()
