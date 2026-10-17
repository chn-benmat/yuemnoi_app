from fastapi import APIRouter
from app.interface.api.endpoints.chat import router as chat_router
from app.interface.api.endpoints.items import router as items_router

api_router = APIRouter()
api_router.include_router(chat_router, tags=["Chat"])
api_router.include_router(items_router, tags=["Items"])
