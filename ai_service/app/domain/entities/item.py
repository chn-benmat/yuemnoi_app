from dataclasses import dataclass, field
from typing import List, Optional

@dataclass(frozen=True)
class Item:
    """Domain Entity representing a rental item in item_tb."""
    id: int
    user_id: str
    item_name: str
    item_image_url: List[str] = field(default_factory=list)
    description: str = ""
    category: str = ""
    price: float = 0.0
    status: str = "available"  # available, unavailable, rented, etc.
    type: str = "daily"        # daily, hourly, etc.
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    model_name: str = ""

    @property
    def is_available(self) -> bool:
        return self.status.strip().lower() == "available"

    @property
    def display_name(self) -> str:
        return self.model_name if self.model_name else self.item_name

