from fastapi import APIRouter, Depends
from typing import List
from app.interface.schemas.item_response import ItemListResponse
from app.application.dtos.item_dto import ItemDTO
from app.core.container import Container, get_container

router = APIRouter(prefix="/items", tags=["Items"])

@router.get("", response_model=ItemListResponse)
async def list_items(
    container: Container = Depends(get_container)
) -> ItemListResponse:
    """Retrieve all rental items cached from Supabase item_tb."""
    items = await container.query_items_use_case.get_all_cached_items()
    item_dtos = [
        ItemDTO(
            id=it.id,
            name=it.item_name,
            category=it.category,
            price=it.price,
            type=it.type,
            status=it.status,
            image_urls=it.item_image_url,
            description=it.description
        )
        for it in items
    ]
    return ItemListResponse(total=len(item_dtos), items=item_dtos)
