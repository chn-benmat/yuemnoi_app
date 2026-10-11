"""การตรวจบัตรเป็นหน้าที่ backend และพนักงาน ไม่ผ่าน AI service."""
import sys

import httpx
import pytest

from main import app


@pytest.mark.asyncio
@pytest.mark.parametrize("method,path", [
    ("GET", "/api/identity/health"),
    ("POST", "/api/identity/read-card"),
    ("POST", "/api/identity/analyze"),
])
async def test_identity_ocr_endpoints_are_removed(method, path):
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.request(method, path)
    assert response.status_code == 404
    assert "app.infrastructure.identity.engine" not in sys.modules
    assert "app.interface.api.v1.endpoints.identity" not in sys.modules
