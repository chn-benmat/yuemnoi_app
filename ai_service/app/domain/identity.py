from typing import Protocol
from dataclasses import dataclass, field, asdict

@dataclass
class IdentityAnalysis:
    ocr_text: str
    face_similarity: float | None
    live_score: float | None
    warnings: list[str] = field(default_factory=list)
    models: dict[str, str] = field(default_factory=dict)

    def to_dict(self) -> dict:
        return asdict(self)

class IdentityAnalyzer(Protocol):
    def analyze(self, card: bytes, selfie: bytes) -> IdentityAnalysis: ...
    def read_card(self, card: bytes) -> dict: ...
