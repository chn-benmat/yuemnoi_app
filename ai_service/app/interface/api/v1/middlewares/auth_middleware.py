import hmac
from fastapi import Header, HTTPException, status
from app.core.config import get_settings

async def verify_internal_service_key(
    x_internal_service_key: str = Header(None, alias="X-Internal-Service-Key")
) -> None:
    """Verifies that requests originate from the authorized Go Backend service (with multi-key rotation support)."""
    settings = get_settings()
    expected_keys = settings.internal_service_keys
    if not expected_keys:
        return

    if not x_internal_service_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unauthorized: missing internal service key header"
        )

    provided_clean = x_internal_service_key.strip().encode("utf-8")
    matched = any(
        hmac.compare_digest(provided_clean, exp.encode("utf-8"))
        for exp in expected_keys
    )

    if not matched:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unauthorized: invalid internal service key"
        )
