from fastapi import APIRouter
from app.interface.api.v1.endpoints.chat import router as chat_router
from app.interface.api.v1.endpoints.items import router as items_router
from app.interface.api.v1.endpoints.identity import router as identity_router

api_v1_router = APIRouter()
api_v1_router.include_router(chat_router, tags=["Chat"])
api_v1_router.include_router(items_router, tags=["Items"])
api_v1_router.include_router(identity_router, tags=["Identity"])
