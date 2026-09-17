from pydantic import BaseModel
from typing import List
from app.application.dtos.item_dto import ItemDTO

class ItemListResponse(BaseModel):
    total: int
    items: List[ItemDTO]
