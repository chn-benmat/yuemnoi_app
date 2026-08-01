import unittest
from unittest.mock import patch

from app.tools.google_tool import GoogleTool


class FakeResponse:
    def __init__(self, payload=None, error=None):
        self.payload = payload or {}
        self.error = error

    def raise_for_status(self):
        if self.error:
            raise self.error

    def json(self):
        return self.payload


class FakeAsyncClient:
    def __init__(self, response):
        self.response = response
        self.request_payload = None

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, traceback):
        return False

    async def post(self, _url, **kwargs):
        self.request_payload = kwargs.get("json")
        return self.response


class GoogleToolTest(unittest.IsolatedAsyncioTestCase):
    async def test_searches_without_database_item(self):
        response = FakeResponse(
            {
                "organic": [
                    {
                        "title": "Official camera specifications",
                        "link": "https://example.com/specs",
                        "snippet": "รองรับการถ่ายวิดีโอ 4K",
                    }
                ]
            }
        )
        client = FakeAsyncClient(response)

        with patch("app.tools.google_tool.httpx.AsyncClient", return_value=client):
            context, status = await GoogleTool().search_spec("ถ่าย 4k")

        self.assertEqual(status, "checked_google")
        self.assertIn("https://example.com/specs", context)
        self.assertIn("ถ่าย 4k", client.request_payload["q"])
        self.assertEqual(client.request_payload["num"], 5)

    async def test_reports_when_google_has_no_results(self):
        client = FakeAsyncClient(FakeResponse({"organic": []}))

        with patch("app.tools.google_tool.httpx.AsyncClient", return_value=client):
            context, status = await GoogleTool().search_spec("ถ่าย 4k")

        self.assertEqual(context, "")
        self.assertEqual(status, "google_no_results")

    async def test_reports_google_failure(self):
        client = FakeAsyncClient(FakeResponse(error=RuntimeError("service unavailable")))

        with patch("app.tools.google_tool.httpx.AsyncClient", return_value=client):
            context, status = await GoogleTool().search_spec("ถ่าย 4k")

        self.assertEqual(context, "")
        self.assertEqual(status, "google_search_failed")


if __name__ == "__main__":
    unittest.main()
