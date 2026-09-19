import json
import pytest
import httpx
from unittest.mock import AsyncMock, patch

from main import app
from app.application.dtos.chat_dto import ChatResponseDTO, ItemDTO
from app.core.config import settings
from app.core.container import container
from app.domain.entities.item import Item


@pytest.mark.asyncio
async def test_health_endpoint():
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/health")
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "healthy"
        assert "providers" in data


@pytest.mark.asyncio
async def test_get_items_endpoint():
    mock_items = [
        Item(id="1", name="Sony A7IV", category="Camera", price=1000.0, description="ฟูลเฟรม"),
    ]
    with patch.object(container.item_repository, "get_all_items", new_callable=AsyncMock) as mock_get:
        mock_get.return_value = mock_items
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/api/v1/items")
            assert resp.status_code == 200
            data = resp.json()
            assert len(data) == 1
            assert data[0]["name"] == "Sony A7IV"


@pytest.mark.asyncio
async def test_post_chat_endpoint():
    expected_resp = ChatResponseDTO(
        response="สวัสดีค่ะ มีกล้อง Sony A7 IV ให้เช่าค่ะ",
        intent="inventory_search",
        confidence=0.95,
        ambiguity_level=0.1,
        items=[
            ItemDTO(id="1", name="Sony A7 IV", category="Camera", price=1200.0)
        ],
    )
    with patch.object(container.process_chat_message_use_case, "execute", new_callable=AsyncMock) as mock_exec:
        mock_exec.return_value = expected_resp
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            payload = {
                "query": "อยากเช่ากล้อง Sony",
                "history": [],
            }
            headers = {}
            if settings.INTERNAL_SERVICE_KEY:
                headers["X-Internal-Service-Key"] = settings.INTERNAL_SERVICE_KEY
            resp = await client.post("/api/v1/chat", json=payload, headers=headers)
            assert resp.status_code == 200
            data = resp.json()
            assert data["response"] == "สวัสดีค่ะ มีกล้อง Sony A7 IV ให้เช่าค่ะ"
            assert data["intent"] == "inventory_search"
            assert len(data["items"]) == 1


@pytest.mark.asyncio
async def test_post_chat_unauthorized():
    if not settings.INTERNAL_SERVICE_KEY:
        return
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        payload = {"query": "test"}
        resp = await client.post("/api/v1/chat", json=payload, headers={"X-Internal-Service-Key": "wrong-key"})
        assert resp.status_code == 401
