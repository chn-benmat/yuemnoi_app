from typing import Protocol

from app.domain.entities.app_knowledge import KnowledgeSnapshot


class KnowledgeRepositoryInterface(Protocol):
    """Read approved facts; never infer application policies from missing data."""

    async def get_approved_knowledge(self) -> KnowledgeSnapshot:
        ...
