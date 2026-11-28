import asyncio
from types import SimpleNamespace

import httpx
import pytest

from app.core.exceptions import DatabaseException
from app.infrastructure.supabase.supabase_repository import SupabaseRepository


def _runtime():
    http = SimpleNamespace(timeout_seconds=5, max_connections=1,
                           max_keepalive_connections=1, keepalive_expiry_seconds=1)
    return SimpleNamespace(http=http)


def _repository(handler):
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return SupabaseRepository(base_url="https://db.example", api_key="key",
                              http_client=client, runtime=_runtime())


def _row(**rates):
    return {"id": 1, "item_name": "ขาตั้งกล้อง", "category": "กล้อง",
            "status": "available", "description": "", **rates}


def test_catalog_reads_the_rates_computed_by_the_database():
    seen = {}

    def handler(request):
        seen["select"] = request.url.params["select"].split(",")
        return httpx.Response(200, json=[
            _row(hourly_rate=80, daily_rate=300),
            {**_row(hourly_rate=None, daily_rate=400), "id": 2},
        ])

    items = asyncio.run(_repository(handler).get_all_items(refresh=True))

    # รายชั่วโมงเป็นเรตหลักเมื่อมี ไม่งั้นใช้รายวัน เหมือนการ์ดในแอป
    assert [(item.price, item.type) for item in items] == [(80, "hourly"), (400, "daily")]
    # เก็บทุกเรตไว้ เพื่อให้งบรายวันเทียบกับราคารายวันได้แม้เรตหลักเป็นรายชั่วโมง
    assert [item.rates for item in items] == [{"hourly": 80, "daily": 300}, {"daily": 400}]
    assert {"hourly_rate", "daily_rate"} <= set(seen["select"])
    assert not {"price", "type"} & set(seen["select"])


def test_an_item_without_any_rate_is_incomplete():
    with pytest.raises(DatabaseException):
        _repository(lambda request: None)._map_row_to_item(_row(hourly_rate=None, daily_rate=None))


@pytest.mark.parametrize("rate", [True, -1, "abc", float("nan")])
def test_an_invalid_rate_is_rejected(rate):
    with pytest.raises(DatabaseException):
        _repository(lambda request: None)._map_row_to_item(_row(hourly_rate=rate, daily_rate=None))
