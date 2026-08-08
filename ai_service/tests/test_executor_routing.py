import unittest
from unittest.mock import AsyncMock

from app.agent.executor import AgentExecutor


class ExecutorRoutingTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.executor = object.__new__(AgentExecutor)
        self.executor.ollama = AsyncMock()
        self.executor.db_tool = AsyncMock()
        self.executor.google_tool = AsyncMock()

    def test_normalizes_male_particles_without_changing_routing(self):
        answer = self.executor._normalize_answer_style(
            "สวัสดีครับ สนใจรุ่นไหนครับ?", "สวัสดีครับ"
        )

        self.assertEqual(answer, "สวัสดีค่ะ สนใจรุ่นไหนคะ?")

    def test_normalizes_thai_brand_name(self):
        answer = self.executor._normalize_answer_style(
            "ยูเมน้อยยินดีช่วยครับ", "ช่วยอะไรได้บ้าง"
        )

        self.assertEqual(answer, "Yuemnoi ยินดีช่วยค่ะ")

        transliterated = self.executor._normalize_answer_style(
            "ยูเมโนอี้ ยินดีให้บริการค่ะ", "สวัสดี"
        )
        self.assertEqual(transliterated, "Yuemnoi ยินดีให้บริการค่ะ")

    def test_brand_name_never_has_thai_particle_attached(self):
        answer = self.executor._normalize_answer_style(
            "ขอโทษค่ะ ยืมหน่อยค่ะ ไม่สามารถช่วยเรื่องนี้ได้ค่ะ",
            "ช่วยทำการบ้านให้หน่อย",
        )

        self.assertEqual(
            answer,
            "ขอโทษค่ะ Yuemnoi ไม่สามารถช่วยเรื่องนี้ได้ค่ะ",
        )

    def test_system_prompt_defines_exact_thai_identity(self):
        prompt = self.executor._system_prompt()

        self.assertIn("exactly 'Yuemnoi'", prompt)
        self.assertIn("Never attach ค่ะ or คะ", prompt)

    def test_tool_schema_accepts_semantic_canonical_category(self):
        properties = self.executor._tool_definitions()[0]["function"][
            "parameters"
        ]["properties"]

        self.assertIn("category", properties)
        self.assertIn("specific_item", properties)
        self.assertIn("list_all", properties)
        self.assertNotIn("category_query", properties)
        self.assertIn("camping", properties["category"]["enum"])
        required = self.executor._tool_definitions()[0]["function"]["parameters"][
            "required"
        ]
        self.assertEqual(
            required,
            [
                "search_text",
                "category",
                "specific_item",
                "min_price",
                "max_price",
                "list_all",
            ],
        )

    def test_semantic_filters_do_not_need_to_be_literal_user_spans(self):
        grounded = self.executor._ground_inventory_arguments(
            {
                "category": "camping",
                "search_text": "outdoor",
                "specific_item": True,
                "list_all": True,
            },
            "จะไปนอนป่าสองคืน มีอะไรเหมาะบ้าง",
        )

        self.assertEqual(grounded["category"], "camping")
        self.assertEqual(grounded["search_text"], "outdoor")
        self.assertFalse(grounded["list_all"])

    def test_general_use_case_does_not_over_filter_semantic_category(self):
        grounded = self.executor._ground_inventory_arguments(
            {
                "category": "camping",
                "search_text": "นอนป่า",
                "specific_item": False,
                "list_all": False,
            },
            "จะไปนอนป่าสองคืน",
        )

        self.assertEqual(grounded["category"], "camping")
        self.assertIsNone(grounded["search_text"])

    def test_list_all_is_kept_when_no_specific_filter_exists(self):
        grounded = self.executor._ground_inventory_arguments(
            {"list_all": True}, "ขอดูของที่มีทั้งหมด"
        )

        self.assertTrue(grounded["list_all"])

    def test_recommended_cards_follow_single_item_mentioned_in_answer(self):
        items = [
            {
                "id": 9,
                "item_name": "กล้อง Sony A7 IV",
                "item_image_url": [],
                "price": 1500,
                "status": "available",
                "category": "camera",
                "type": "daily",
            },
            {
                "id": 8,
                "item_name": "กล้องถ่ายภาพ",
                "item_image_url": [],
                "price": 2500,
                "status": None,
                "category": "camera",
                "type": "daily",
            },
        ]

        result = self.executor._recommended_items(
            items,
            selected_id=None,
            answer="กล้องถ่ายภาพราคา 2500 บาทยังไม่ทราบสถานะค่ะ",
        )

        self.assertEqual([item["id"] for item in result], [8])

    async def test_greeting_is_a_natural_model_response_without_tools(self):
        self.executor.ollama.chat_json.return_value = (
            '{"action":"direct_response","search_text":null,'
            '"category":null,"specific_item":false,"min_price":null,'
            '"max_price":null,"list_all":false,"web_query":null,'
            '"direct_answer":"สวัสดีค่ะ วันนี้ให้ช่วยเรื่องอะไรดีคะ"}'
        )

        result = await self.executor.run_pipeline_non_stream("สวัสดีครับ", history=[])

        self.assertEqual(result["search_status"], "direct_response")
        self.assertEqual(result["answer"], "สวัสดีค่ะ วันนี้ให้ช่วยเรื่องอะไรดีคะ")
        self.assertEqual(result["recommended_items"], [])
        self.executor.db_tool.search_items.assert_not_awaited()
        self.executor.ollama.chat_json.assert_awaited_once()
        self.executor.ollama.chat_with_tools.assert_not_awaited()

    async def test_semantic_router_searches_inventory(self):
        self.executor.ollama.chat_json.side_effect = [
            '{"action":"search_inventory","search_text":null,'
            '"category":"camera","specific_item":false,"min_price":null,'
            '"max_price":null,"list_all":false,"limit":5,"web_query":null,'
            '"direct_answer":null}',
            '{"answer":"มี GoPro ราคา 650 บาทต่อวันค่ะ","selected_item_id":10}',
        ]
        self.executor.db_tool.search_items.return_value = [
            {
                "id": 10,
                "item_name": "กล้อง GoPro HERO13 Black",
                "item_image_url": [],
                "description": "กล้องแอ็กชันกันน้ำ",
                "category": "camera",
                "price": 650,
                "status": "available",
                "type": "daily",
            }
        ]

        result = await self.executor.run_pipeline_non_stream(
            "มีกล้องให้เช่าไหม", history=[]
        )

        self.assertEqual(result["search_status"], "using_supabase")
        self.assertEqual(result["recommended_items"][0]["id"], 10)
        filters = self.executor.db_tool.search_items.await_args.args[0]
        self.assertEqual(filters.category, "camera")
        self.executor.ollama.chat_with_tools.assert_not_awaited()

    def test_unknown_category_is_dropped_without_broadening_the_search(self):
        grounded = self.executor._ground_inventory_arguments(
            {
                "category": "vehicle",
                "search_text": "รถยนต์",
                "specific_item": True,
                "list_all": True,
            },
            "มีรถยนต์ให้เช่าไหม",
        )

        self.assertIsNone(grounded["category"])
        self.assertEqual(grounded["search_text"], "รถยนต์")
        self.assertFalse(grounded["list_all"])

    async def test_explicit_browse_all_preserves_list_all(self):
        self.executor.ollama.chat_json.side_effect = [
            '{"action":"search_inventory","search_text":null,'
            '"category":null,"specific_item":false,"min_price":null,'
            '"max_price":null,"list_all":true,"limit":5,"web_query":null,'
            '"direct_answer":null}',
            '{"answer":"มีอุปกรณ์ให้เช่าหลายรายการค่ะ","selected_item_id":null}',
        ]
        self.executor.db_tool.search_items.return_value = [
            {
                "id": 1,
                "item_name": "เต็นท์",
                "item_image_url": [],
                "description": "เต็นท์ให้เช่า",
                "category": "camping",
                "price": 300,
                "status": "available",
                "type": "daily",
            }
        ]

        result = await self.executor.run_pipeline_non_stream(
            "มีอะไรให้เช่าบ้าง", history=[]
        )

        self.assertEqual(result["search_status"], "using_supabase")
        filters = self.executor.db_tool.search_items.await_args.args[0]
        self.assertTrue(filters.list_all)

    async def test_repairs_direct_answer_to_latest_user_language(self):
        self.executor.ollama.chat_json.side_effect = [
            '{"action":"direct_response","search_text":null,'
            '"category":null,"specific_item":false,"min_price":null,'
            '"max_price":null,"list_all":false,"web_query":null,'
            '"direct_answer":"Yuemnoi เป็นผู้ช่วยเรื่องอุปกรณ์เช่าค่ะ"}',
            '{"answer":"I am Yuemnoi, your equipment-rental assistant."}',
        ]

        result = await self.executor.run_pipeline_non_stream(
            "Hello, who are you?", history=[]
        )

        self.assertEqual(
            result["answer"], "I am Yuemnoi, your equipment-rental assistant."
        )
        self.assertFalse(self.executor._is_thai(result["answer"]))

    async def test_inventory_tool_uses_database_then_model_response(self):
        self.executor.db_tool.search_items.return_value = [
            {
                "id": 8,
                "item_name": "กล้องถ่ายภาพ",
                "item_image_url": [],
                "description": "กล้องถ่ายภาพระบบ 4k",
                "category": "camera",
                "price": 2500,
                "status": "available",
                "type": "day",
            }
        ]
        self.executor.ollama.chat_json.side_effect = [
            '{"action":"search_inventory","search_text":null,'
            '"category":"camera","specific_item":false,"min_price":null,'
            '"max_price":3000,"list_all":false,"web_query":null,'
            '"direct_answer":null}',
            '{"answer":"มีกล้องราคา 2,500 บาทให้เช่าค่ะ",'
            '"selected_item_id":8}',
        ]

        result = await self.executor.run_pipeline_non_stream(
            "อยากเช่ากล้องไม่เกิน 3000 บาท", history=[]
        )

        self.assertEqual(result["search_status"], "using_supabase")
        self.assertEqual(result["items_found"], 1)
        self.assertEqual(result["recommended_items"][0]["id"], 8)
        filters = self.executor.db_tool.search_items.await_args.args[0]
        self.assertEqual(filters.category, "camera")
        self.assertEqual(filters.max_price, 3000)
        self.assertEqual(self.executor.ollama.chat_json.await_count, 2)
        self.executor.ollama.chat_with_tools.assert_not_awaited()

    async def test_web_spec_tool_does_not_search_inventory(self):
        self.executor.google_tool.search_spec.return_value = (
            "two verified references",
            "checked_google",
        )
        self.executor.ollama.chat_json.side_effect = [
            '{"action":"search_web_specs","search_text":null,'
            '"category":null,"specific_item":true,"min_price":null,'
            '"max_price":null,"list_all":false,'
            '"web_query":"Sony A7 III 4K specifications","direct_answer":null}',
            '{"answer":"รองรับวิดีโอ 4K ค่ะ","selected_item_id":null}',
        ]

        result = await self.executor.run_pipeline_non_stream(
            "Sony A7 III ถ่าย 4K ได้ไหม", history=[]
        )

        self.assertEqual(result["search_status"], "checked_google")
        self.assertEqual(result["recommended_items"], [])
        self.executor.db_tool.search_items.assert_not_awaited()
        self.executor.google_tool.search_spec.assert_awaited_once()
        self.executor.ollama.chat_with_tools.assert_not_awaited()


if __name__ == "__main__":
    unittest.main()
