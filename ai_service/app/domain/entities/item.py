from typing import List, Optional
from pydantic import BaseModel, Field


class Item(BaseModel):
    """Domain entity representing a rental item from the catalog."""
    id: str
    name: str
    category: str
    price: float = Field(ge=0, allow_inf_nan=False)
    type: str = "วัน"
    status: str = "available"
    image_urls: List[str] = Field(default_factory=list)
    description: str = ""

    @property
    def is_available(self) -> bool:
        return self.status.lower() == "available"
