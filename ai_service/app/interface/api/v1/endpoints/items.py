from typing import List
from fastapi import APIRouter, HTTPException, status

from app.application.dtos.chat_dto import ItemDTO
from app.core.container import container
from app.core.logging import logger

router = APIRouter()


@router.get(
    "/items",
    response_model=List[ItemDTO],
    summary="Get cached list of rental inventory items",
)
async def get_items_endpoint() -> List[ItemDTO]:
    try:
        items = await container.item_repository.get_all_items()
        return [ItemDTO.from_entity(i) for i in items]
    except Exception as exc:
        logger.error(f"Failed to fetch catalog items: {exc}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve inventory items",
        )
