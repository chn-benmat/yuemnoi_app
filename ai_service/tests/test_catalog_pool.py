"""ตรวจการใช้ connection ซ้ำโดยไม่ลดความสดของคลัง."""
import httpx
import pytest

from app.infrastructure.supabase.supabase_repository import SupabaseRepository


@pytest.mark.asyncio
async def test_catalog_refresh_reuses_client_and_reads_changed_rows(monkeypatch):
    clients, requests = [], []
    original = httpx.AsyncClient

    def respond(request):
        requests.append(request)
        return httpx.Response(200, json=[{"id": "fixture-item", "item_name": "fixture",
            "category": "fixture", "price": len(requests), "type": "daily", "status": "available"}])

    def build(*args, **kwargs):
        client = original(*args, transport=httpx.MockTransport(respond), **kwargs)
        clients.append(client)
        return client

    monkeypatch.setattr(httpx, "AsyncClient", build)
    repo = SupabaseRepository(api_key="fixture", base_url="https://fixture.invalid")
    first = await repo.get_all_items(refresh=True)
    second = await repo.get_all_items(refresh=True)
    assert first[0].price == 1 and second[0].price == 2
    assert len(requests) == 2
    assert len(clients) == 1
    await repo.aclose()
    assert clients[0].is_closed


@pytest.mark.asyncio
async def test_repository_does_not_close_injected_client():
    async with httpx.AsyncClient(transport=httpx.MockTransport(
            lambda request: httpx.Response(200, json=[]))) as client:
        repo = SupabaseRepository(api_key="fixture", base_url="https://fixture.invalid", http_client=client)
        assert await repo.get_all_items(refresh=True) == []
        await repo.aclose()
        assert not client.is_closed
