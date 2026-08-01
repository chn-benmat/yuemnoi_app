import unittest
from unittest.mock import AsyncMock

from app.agent.executor import AgentExecutor


class ExecutorRoutingTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.executor = object.__new__(AgentExecutor)
        self.executor.google_tool = AsyncMock()

    async def test_uses_supabase_without_calling_google(self):
        context, status = await self.executor._get_reference_context(
            cleaned_query="กล้องถ่าย 4k",
            db_results=[{"id": 1, "item_name": "Camera"}],
        )

        self.assertEqual(context, "")
        self.assertEqual(status, "using_supabase")
        self.executor.google_tool.search_spec.assert_not_awaited()

    async def test_uses_google_when_supabase_has_no_results(self):
        self.executor.google_tool.search_spec.return_value = (
            "verified sources",
            "checked_google",
        )

        context, status = await self.executor._get_reference_context(
            cleaned_query="กล้องถ่าย 4k",
            db_results=[],
        )

        self.assertEqual(context, "verified sources")
        self.assertEqual(status, "checked_google")
        self.executor.google_tool.search_spec.assert_awaited_once_with(
            specific_query="กล้องถ่าย 4k"
        )


if __name__ == "__main__":
    unittest.main()
