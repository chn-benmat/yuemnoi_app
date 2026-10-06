from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.core.container import container
from app.core.logging import logger
from app.infrastructure.server import run_server
from app.interface.api.v1.endpoints.health import router as health_router
from app.interface.api.v1.router import api_v1_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifecycle events: pre-warm catalog cache on startup."""
    logger.info(f"Starting {settings.APP_NAME} in [{settings.APP_ENV}] environment...")
    await container.start()
    try:
        items = await container.item_repository.get_all_items()
        logger.info(f"Pre-warmed catalog cache with {len(items)} rental items.")
    except Exception as exc:
        logger.warning(f"Failed to pre-warm catalog cache on startup: {exc}")
    try:
        yield
    finally:
        await container.aclose()
        logger.info("Shutting down AI service gracefully...")


app = FastAPI(
    title=settings.APP_NAME,
    description="Clean Architecture AI Chatbot Service for Yuemnoi Rental Platform",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Route registration
app.include_router(health_router, prefix="", tags=["Health"])
app.include_router(api_v1_router, prefix="/api/v1")


if __name__ == "__main__":
    run_server(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level=settings.LOG_LEVEL.lower(),
    )
