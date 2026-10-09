from fastapi import APIRouter
from app.core.config import settings
from app.core.container import container

router = APIRouter()


@router.get(
    "/health",
    summary="Health check endpoint for AI service, external dependencies, and hot reload status",
)
async def health_check():
    status_report = {
        "status": "healthy",
        "service": settings.APP_NAME,
        "hot_reload": True,
        "providers": {
            "gemini_primary": settings.GEMINI_PRIMARY_MODEL,
            "groq_primary": settings.GROQ_PRIMARY_MODEL,
        },
        "dependencies": {},
    }

    # Check Supabase
    try:
        items = await container.item_repository.get_all_items()
        status_report["dependencies"]["supabase"] = {
            "status": "connected",
            "items_count": len(items),
        }
    except Exception as e:
        status_report["dependencies"]["supabase"] = {
            "status": "error",
            "detail": str(e),
        }

    # Check Search
    status_report["dependencies"]["tavily"] = {
        "status": "configured" if settings.TAVILY_API_KEY else "not_configured",
    }

    # Check Groq Key
    status_report["dependencies"]["groq"] = {
        "status": "configured" if settings.GROQ_API_KEY else "not_configured",
    }

    # Check Gemini Key
    status_report["dependencies"]["gemini"] = {
        "status": "disabled" if not any(p.enabled and p.protocol == "gemini_json_schema" for p in container.llm_service.runtime.providers) else (
            "configured" if settings.GEMINI_API_KEY else "not_configured"),
    }

    status_report["providers"]["profiles"] = [{"id": p.id, "enabled": p.enabled,
        "disabled_reason": p.disabled_reason} for p in container.llm_service.runtime.providers]

    return status_report
