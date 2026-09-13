from fastapi import APIRouter, Depends
from app.interface.api.v1.endpoints.chat import router as chat_router
from app.interface.api.v1.endpoints.items import router as items_router
from app.interface.api.v1.endpoints.health import router as health_router
from app.interface.api.v1.middlewares.auth_middleware import verify_internal_service_key

api_v1_router = APIRouter()
# Health check remains publicly accessible for orchestration/monitoring
api_v1_router.include_router(health_router)
# Internal services are protected with the shared internal key
api_v1_router.include_router(chat_router, dependencies=[Depends(verify_internal_service_key)])
api_v1_router.include_router(items_router, dependencies=[Depends(verify_internal_service_key)])
