from fastapi import APIRouter, Depends
import httpx
from app.core.config import Settings
from app.core.container import Container, get_container

router = APIRouter(tags=["Health"])

@router.get("/health")
async def health_check(
    container: Container = Depends(get_container)
):
    """Health check verifying connectivity to Ollama, Supabase, and Tavily API Key status."""
    ollama_ok = False
    supabase_ok = False
    tavily_ok = bool(container.settings.TAVILY_API_KEY)

    # Check Ollama
    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            res = await client.get(f"{container.settings.OLLAMA_BASE_URL}/api/tags")
            ollama_ok = res.status_code == 200
    except Exception:
        ollama_ok = False

    # Check Supabase
    try:
        items = await container.query_items_use_case.get_all_cached_items()
        supabase_ok = len(items) > 0
    except Exception:
        supabase_ok = False

    status = "healthy" if (ollama_ok and supabase_ok and tavily_ok) else "degraded"

    return {
        "status": status,
        "model": container.settings.OLLAMA_MODEL,
        "services": {
            "ollama": "ok" if ollama_ok else "error",
            "supabase": "ok" if supabase_ok else "error",
            "tavily": "ok" if tavily_ok else "missing_key"
        }
    }
