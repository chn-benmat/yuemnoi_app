import unittest
from unittest.mock import AsyncMock

from pydantic import ValidationError

from app.tools.database_tool import DatabaseTool, ItemSearchFilters


class FakeResponse:
    def __init__(self, payload):
        self.payload = payload

    def raise_for_status(self):
        return None

    def json(self):
        return self.payload


class DatabaseToolTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.client = AsyncMock()
        self.client.get.return_value = FakeResponse([])
        self.tool = DatabaseTool(self.client)

    async def test_queries_postgrest_with_typed_filters(self):
        filters = ItemSearchFilters(
            search_text="sony",
            category="camera",
            max_price=1500,
            limit=5,
        )

        await self.tool.search_items(filters)

        _, kwargs = self.client.get.await_args
        params = kwargs["params"]
        self.assertIn(("limit", "5"), params)
        self.assertIn(("category", "eq.camera"), params)
        self.assertIn(("price", "lte.1500"), params)
        select_value = dict(params)["select"]
        self.assertNotIn("user_id", select_value)
        self.assertNotIn("created_at", select_value)

    async def test_empty_filters_fail_closed_without_querying_inventory(self):
        await self.tool.search_items(ItemSearchFilters())

        self.client.get.assert_not_awaited()

    async def test_explicit_list_all_queries_inventory_without_text_matching(self):
        await self.tool.search_items(ItemSearchFilters(list_all=True))

        _, kwargs = self.client.get.await_args
        params = kwargs["params"]
        self.assertNotIn("or", dict(params))
        self.assertIn(("limit", "5"), params)

    def test_sanitizes_tool_filter_values(self):
        cleaned = self.tool._safe_filter_text("Sony); DROP TABLE item_tb;--")
        self.assertNotIn(")", cleaned)
        self.assertNotIn(";", cleaned)

    async def test_semantic_category_does_not_require_a_literal_user_keyword(self):
        await self.tool.search_items(ItemSearchFilters(category="camping"))

        _, kwargs = self.client.get.await_args
        params = kwargs["params"]
        self.assertIn(("category", "eq.camping"), params)
        self.assertNotIn("or", dict(params))

    async def test_search_text_matches_individual_terms_instead_of_exact_phrase(self):
        await self.tool.search_items(
            ItemSearchFilters(search_text="Sony action", category="camera")
        )

        _, kwargs = self.client.get.await_args
        query = dict(kwargs["params"])["or"]
        self.assertIn("item_name.ilike.*Sony*", query)
        self.assertIn("description.ilike.*action*", query)
        self.assertNotIn("*Sony action*", query)

    async def test_uncategorized_product_search_does_not_match_descriptions(self):
        await self.tool.search_items(ItemSearchFilters(search_text="รถยนต์"))

        _, kwargs = self.client.get.await_args
        query = dict(kwargs["params"])["or"]
        self.assertIn("item_name.ilike.*รถยนต์*", query)
        self.assertNotIn("description", query)

    def test_unknown_canonical_category_is_rejected_by_schema(self):
        with self.assertRaises(ValidationError):
            ItemSearchFilters(category="vehicle")

if __name__ == "__main__":
    unittest.main()
