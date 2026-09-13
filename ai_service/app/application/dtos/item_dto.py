from pydantic import BaseModel
from typing import List, Optional

class ItemDTO(BaseModel):
    id: int
    name: str
    category: str
    price: float
    type: str
    status: str
    image_urls: List[str] = []
    description: str = ""

class ItemSearchCriteriaDTO(BaseModel):
    query: Optional[str] = None
    category: Optional[str] = None
    max_price: Optional[float] = None
    only_available: bool = False
