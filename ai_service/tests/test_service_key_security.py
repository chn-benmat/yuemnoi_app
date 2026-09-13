import pytest
from httpx import AsyncClient, ASGITransport
from fastapi import HTTPException
from main import app
from app.core.config import get_settings
from app.interface.api.v1.middlewares.auth_middleware import verify_internal_service_key

@pytest.mark.asyncio
async def test_chat_endpoint_requires_internal_key():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        # 1. Without header -> 401 Unauthorized
        res_no_key = await ac.post("/api/v1/chat", json={"message": "hello"})
        assert res_no_key.status_code == 401

        # 2. With wrong key -> 401 Unauthorized
        res_wrong_key = await ac.post(
            "/api/v1/chat",
            json={"message": "hello"},
            headers={"X-Internal-Service-Key": "wrong-key"}
        )
        assert res_wrong_key.status_code == 401

        # 3. Health check should remain open
        res_health = await ac.get("/health")
        assert res_health.status_code in [200, 503]

@pytest.mark.asyncio
async def test_internal_key_multi_key_rotation(monkeypatch):
    """Verifies that multi-key rotation allows both new and old keys while rejecting invalid ones."""
    monkeypatch.setenv("INTERNAL_SERVICE_KEY", "new_key_rotation,old_key_rotation")
    get_settings.cache_clear()
    try:
        # 1. New key should pass without exception
        await verify_internal_service_key(x_internal_service_key="new_key_rotation")

        # 2. Old key should also pass without exception
        await verify_internal_service_key(x_internal_service_key="old_key_rotation")

        # 3. Unrecognized key must raise 401
        with pytest.raises(HTTPException) as exc_info:
            await verify_internal_service_key(x_internal_service_key="unknown_key")
        assert exc_info.value.status_code == 401

        # 4. Missing key must raise 401
        with pytest.raises(HTTPException) as exc_info:
            await verify_internal_service_key(x_internal_service_key="")
        assert exc_info.value.status_code == 401
    finally:
        get_settings.cache_clear()
