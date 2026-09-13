import asyncio
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import get_settings
from app.core.logging import logger
from app.core.container import get_container
from app.interface.api.v1.router import api_v1_router

settings = get_settings()

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info(f"Starting {settings.APP_NAME} in {settings.APP_ENV} mode...")
    logger.info(f"Using LLM model: {settings.OLLAMA_MODEL} at {settings.OLLAMA_BASE_URL}")
    container = get_container()

    # Initial catalog cache warm-up
    try:
        items = await container.catalog_warmup_service.trigger_warmup()
        logger.info(f"Successfully loaded and cached {len(items)} items from Supabase 'item_tb'.")
    except Exception as e:
        logger.warning(f"Initial catalog cache warm-up failed: {e}")

    # Start background periodic warm-up task (Every CATALOG_WARMUP_INTERVAL seconds)
    warmup_task = None
    if settings.ENABLE_BACKGROUND_WARMUP:
        warmup_task = asyncio.create_task(container.catalog_warmup_service.start_periodic_warmup())
        logger.info(f"Started background catalog warm-up worker (Interval: {settings.CATALOG_WARMUP_INTERVAL}s).")

    try:
        yield
    finally:
        if warmup_task and not warmup_task.done():
            logger.info("Stopping background catalog warm-up worker...")
            warmup_task.cancel()
            try:
                await warmup_task
            except asyncio.CancelledError:
                pass
        logger.info(f"Shutting down {settings.APP_NAME}...")

app = FastAPI(
    title=settings.APP_NAME,
    version="1.0.0",
    description="Clean Architecture Thai Chatbot AI for Rental Services powered by Ollama (Typhoon 2.5 Qwen3), Supabase, and Tavily.",
    lifespan=lifespan
)

# Enable CORS specifically for local backend/internal consumers
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:8080", "http://127.0.0.1:8080", "http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

from app.interface.api.v1.endpoints.health import router as health_router

# Include API Routers
app.include_router(api_v1_router, prefix=settings.API_PREFIX)
# Expose /health at root for container/load-balancer checks
app.include_router(health_router)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="127.0.0.1", port=8000, reload=True)
