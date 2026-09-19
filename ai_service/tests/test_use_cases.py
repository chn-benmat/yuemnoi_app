import json
import pytest
from unittest.mock import AsyncMock, MagicMock
from app.application.dtos.chat_dto import ChatRequestDTO
from app.application.services.fact_verification_service import FactVerificationService
from app.application.use_cases.compare_items_use_case import CompareItemsUseCase
from app.application.use_cases.generate_clarification_use_case import GenerateClarificationUseCase
from app.application.use_cases.process_chat_message_use_case import ProcessChatMessageUseCase
from app.application.use_cases.query_items_use_case import QueryItemsUseCase
from app.application.use_cases.route_intent_use_case import RouteIntentUseCase
from app.domain.entities.chat_message import ChatMessage
from app.domain.entities.clarification import ClarificationQuestion, ChoiceOption, QuestionStep
from app.domain.entities.comparison import ComparisonMatrix
from app.domain.entities.intent_decision import IntentDecision
from app.domain.entities.item import Item
from app.domain.entities.search_source import SearchSource
from app.domain.entities.semantic_item_filter import SemanticItemFilterDecision



@pytest.mark.asyncio
async def test_query_items_zero_bias_ranking():
    """Verifies that query items filters and ranks purely by relevance and constraints without brand bias."""
    mock_repo = MagicMock()
    mock_repo.get_all_items = AsyncMock(return_value=[
        Item(id="1", name="Sony Alpha A7 IV", category="Camera", price=1200.0, description="ฟูลเฟรม"),
        Item(id="2", name="Canon EOS R6 Mark II", category="Camera", price=1100.0, description="ฟูลเฟรม"),
        Item(id="3", name="MacBook Pro M3", category="Laptop", price=1500.0, description="โน้ตบุ๊กทำงาน"),
    ])

    query_uc = QueryItemsUseCase(item_repository=mock_repo)

    decision = IntentDecision(
        intent="inventory_search",
        target_items=["Canon"],
        categories=["Camera"],
        budget_max=1300.0,
    )

    results = await query_uc.execute(decision)
    assert len(results) >= 1
    # Canon should be top because user specified target_items=["Canon"]
    assert "Canon" in results[0].name


@pytest.mark.asyncio
async def test_process_chat_clarification_flow():
    """Verifies that when ambiguity level >= 0.5, clarification question and choices are returned."""
    mock_llm = MagicMock()
    mock_repo = MagicMock()
    mock_search = MagicMock()

    mock_repo.get_all_items = AsyncMock(return_value=[
        Item(id="1", name="Sony A7 IV", category="Camera", price=1200.0),
    ])

    route_uc = RouteIntentUseCase(llm_service=mock_llm)
    # Mock route returning high ambiguity
    route_uc.execute = AsyncMock(return_value=IntentDecision(
        intent="clarification_needed",
        ambiguity_level=0.8,
        confidence=0.9,
        missing_slots=["category", "use_case"],
    ))

    clarification_uc = GenerateClarificationUseCase(llm_service=mock_llm, item_repository=mock_repo)
    clarification_uc.execute = AsyncMock(return_value=ClarificationQuestion(
        question="ต้องการเช่าอุปกรณ์ประเภทไหนดีคะ?",
        options=[
            ChoiceOption(id="1", label="กล้องถ่ายรูป", action_value="กล้องถ่ายรูป"),
            ChoiceOption(id="2", label="คอมพิวเตอร์/โน้ตบุ๊ก", action_value="โน้ตบุ๊ก"),
        ],
        questions=[
            QuestionStep(id="q1", title="ต้องการเช่าอุปกรณ์ประเภทไหนดีคะ?", options=["กล้องถ่ายรูป", "โน้ตบุ๊ก"]),
        ]
    ))

    query_uc = QueryItemsUseCase(item_repository=mock_repo)
    fact_service = FactVerificationService(llm_service=mock_llm)
    compare_uc = CompareItemsUseCase(llm_service=mock_llm, search_service=mock_search, fact_service=fact_service)

    process_uc = ProcessChatMessageUseCase(
        route_intent=route_uc,
        query_items=query_uc,
        compare_items=compare_uc,
        generate_clarification=clarification_uc,
        llm_service=mock_llm,
        search_service=mock_search,
    )

    req = ChatRequestDTO(message="อยากเช่าของ")
    resp = await process_uc.execute(req)

    assert resp.intent == "clarification_needed"
    assert resp.ambiguity_level >= 0.5
    assert resp.clarification is not None
    assert len(resp.clarification.options) == 2
    assert resp.clarification.options[0].label == "กล้องถ่ายรูป"


@pytest.mark.asyncio
async def test_process_chat_bot_capabilities():
    """Verifies that asking about bot capabilities directly answers without clarification."""
    mock_llm = MagicMock()
    mock_repo = MagicMock()
    mock_search = MagicMock()

    route_uc = RouteIntentUseCase(llm_service=mock_llm)
    route_uc.execute = AsyncMock(return_value=IntentDecision(
        intent="bot_capabilities",
        ambiguity_level=0.0,
        confidence=0.98,
    ))
    mock_llm.generate_text = AsyncMock(return_value="น้องยืมหน่อยช่วยค้นหาและแนะนำอุปกรณ์เช่าค่ะ")

    process_uc = ProcessChatMessageUseCase(
        route_intent=route_uc,
        query_items=QueryItemsUseCase(item_repository=mock_repo),
        compare_items=CompareItemsUseCase(llm_service=mock_llm, search_service=mock_search, fact_service=MagicMock()),
        generate_clarification=MagicMock(),
        llm_service=mock_llm,
        search_service=mock_search,
    )

    req = ChatRequestDTO(message="ทำไรได้")
    resp = await process_uc.execute(req)

    assert resp.intent == "bot_capabilities"
    assert resp.clarification is None
    assert "น้องยืมหน่อยช่วยค้นหา" in resp.response


@pytest.mark.asyncio
async def test_process_chat_item_inquiry_with_context():
    """Verifies that asking about capabilities when items are in context queries items and explains their features."""
    mock_llm = MagicMock()
    mock_repo = MagicMock()
    mock_search = MagicMock()

    mock_repo.get_all_items = AsyncMock(return_value=[
        Item(id="1", name="PlayStation 5", category="Game", price=700.0, description="คอนโซลเกม 4K 120fps"),
    ])

    route_uc = RouteIntentUseCase(llm_service=mock_llm)
    route_uc.execute = AsyncMock(return_value=IntentDecision(
        intent="item_inquiry",
        target_items=["PlayStation 5"],
        ambiguity_level=0.0,
        confidence=0.95,
    ))
    mock_llm.generate_text = AsyncMock(return_value="PlayStation 5 รองรับการเล่นเกม 4K HDR ค่ะ")

    query_uc = QueryItemsUseCase(item_repository=mock_repo)

    process_uc = ProcessChatMessageUseCase(
        route_intent=route_uc,
        query_items=query_uc,
        compare_items=CompareItemsUseCase(llm_service=mock_llm, search_service=mock_search, fact_service=MagicMock()),
        generate_clarification=MagicMock(),
        llm_service=mock_llm,
        search_service=mock_search,
    )

    req = ChatRequestDTO(message="ทำไรได้")
    resp = await process_uc.execute(req)

    assert resp.intent == "item_inquiry"
    assert resp.clarification is None
    assert len(resp.items) >= 1
    assert "PlayStation 5" in resp.items[0].name
    assert "4K HDR" in resp.response


@pytest.mark.asyncio
async def test_process_chat_item_inquiry_multiple_items_balanced():
    """Verifies that asking about capabilities when multiple items are in context queries all items and returns all cards."""
    import json
    mock_llm = MagicMock()
    mock_repo = MagicMock()
    mock_search = MagicMock()

    item1 = Item(id="1", name="iPhone 15 Pro", category="โทรศัพท์และอุปกรณ์สื่อสาร", price=850.0, description="ชิป A17 Pro กล้องระดับโปร")
    item2 = Item(id="2", name="Samsung Galaxy S24 Ultra", category="โทรศัพท์และอุปกรณ์สื่อสาร", price=800.0, description="Galaxy AI พร้อม S-Pen")

    mock_repo.get_all_items = AsyncMock(return_value=[item1, item2])

    route_uc = RouteIntentUseCase(llm_service=mock_llm)
    route_uc.execute = AsyncMock(return_value=IntentDecision(
        intent="item_inquiry",
        target_items=["iPhone 15 Pro", "Samsung Galaxy S24 Ultra"],
        ambiguity_level=0.0,
        confidence=0.95,
    ))

    balanced_response = (
        "สำหรับอุปกรณ์ทั้ง 2 รุ่นมีความสามารถโดดเด่นดังนี้ค่ะ:\n\n"
        "**iPhone 15 Pro**\n"
        "- **จุดเด่น/ความสามารถ:** ชิป A17 Pro ประสิทธิภาพสูง กล้องระดับโปร ถ่ายวิดีโอ ProRes คมชัด\n"
        "- **ราคาเช่า:** 850 บาท ต่อ วัน\n\n"
        "**Samsung Galaxy S24 Ultra**\n"
        "- **จุดเด่น/ความสามารถ:** ขับเคลื่อนด้วยฟีเจอร์ Galaxy AI อัจฉริยะ กล้องซูมไกล 100x พร้อมปากกา S-Pen\n"
        "- **ราคาเช่า:** 800 บาท ต่อ วัน\n\n"
        "คุณผู้ใช้งานสามารถแตะดูรายละเอียดเพิ่มเติมที่การ์ดด้านล่างนี้ได้เลยนะคะ"
    )
    mock_llm.generate_text = AsyncMock(return_value=balanced_response)

    query_uc = QueryItemsUseCase(item_repository=mock_repo)

    process_uc = ProcessChatMessageUseCase(
        route_intent=route_uc,
        query_items=query_uc,
        compare_items=CompareItemsUseCase(llm_service=mock_llm, search_service=mock_search, fact_service=MagicMock()),
        generate_clarification=MagicMock(),
        llm_service=mock_llm,
        search_service=mock_search,
    )

    req = ChatRequestDTO(
        message="ทำไรได้บ้าง",
        history=[
            ChatMessage(role="user", content="อยากเช่าโทรศัพท์"),
            ChatMessage(
                role="assistant",
                content=json.dumps({
                    "answer": "ขอแนะนำ iPhone 15 Pro และ Samsung Galaxy S24 Ultra ค่ะ",
                    "items": [{"id": "1", "name": "iPhone 15 Pro"}, {"id": "2", "name": "Samsung Galaxy S24 Ultra"}],
                }),
            ),
        ],
    )
    resp = await process_uc.execute(req)

    assert resp.intent == "item_inquiry"
    assert len(resp.items) == 2
    item_names = [i.name for i in resp.items]
    assert "iPhone 15 Pro" in item_names
    assert "Samsung Galaxy S24 Ultra" in item_names
    assert "**iPhone 15 Pro**" in resp.response
    assert "**Samsung Galaxy S24 Ultra**" in resp.response

    # Verify stream mode also returns both recommended_items in done event
    async def mock_stream(*args, **kwargs):
        chunks = [
            "**iPhone 15 Pro**\n- **จุดเด่น/ความสามารถ:** ชิป A17 Pro\n\n",
            "**Samsung Galaxy S24 Ultra**\n- **จุดเด่น/ความสามารถ:** Galaxy AI\n\n",
            "คุณผู้ใช้งานสามารถแตะดูรายละเอียดเพิ่มเติมที่การ์ดด้านล่างนี้ได้เลยนะคะ",
        ]
        for c in chunks:
            yield c

    mock_llm.generate_stream = mock_stream

    events = []
    async for event_line in process_uc.execute_stream(req):
        events.append(event_line)

    done_events = [e for e in events if "event: done" in e]
    assert len(done_events) == 1
    # Extract JSON data from done event
    done_line = [line for line in done_events[0].split("\n") if line.startswith("data: ")][0]
    done_data = json.loads(done_line[6:])
    assert len(done_data["recommended_items"]) == 2
    stream_names = [i["name"] for i in done_data["recommended_items"]]
    assert "iPhone 15 Pro" in stream_names
    assert "Samsung Galaxy S24 Ultra" in stream_names



@pytest.mark.asyncio
async def test_query_items_phone_category_alias():
    """Verifies that searching with colloquial phone/mobile terms matches category 'โทรศัพท์และอุปกรณ์สื่อสาร' via AI-Native semantic selection."""
    mock_repo = MagicMock()
    mock_repo.get_all_items = AsyncMock(return_value=[
        Item(id="1", name="iPhone 15 Pro Max", category="โทรศัพท์และอุปกรณ์สื่อสาร", price=900.0, description="สมาร์ตโฟนเรือธง"),
        Item(id="2", name="Samsung Galaxy S24 Ultra", category="โทรศัพท์และอุปกรณ์สื่อสาร", price=850.0, description="กล้องซูม 100x"),
        Item(id="3", name="เต็นท์สนาม Coleman", category="แคมป์ปิงและกิจกรรมกลางแจ้ง", price=300.0, description="เต็นท์กันฝน"),
    ])

    mock_llm = MagicMock()
    mock_llm.generate_structured = AsyncMock(
        return_value=SemanticItemFilterDecision(matched_item_ids=["1", "2"])
    )

    query_uc = QueryItemsUseCase(item_repository=mock_repo, llm_service=mock_llm)

    # 1. Test target_items=["มือถือ"] via AI-Native LLM semantic selection
    decision = IntentDecision(
        intent="inventory_search",
        target_items=["มือถือ"],
        categories=[],
    )
    results = await query_uc.execute(decision)
    assert len(results) == 2
    assert {r.name for r in results} == {"iPhone 15 Pro Max", "Samsung Galaxy S24 Ultra"}

    # 2. Test category=["โทรศัพท์และอุปกรณ์สื่อสาร"] via deterministic zero-hardcode matching
    query_uc_no_llm = QueryItemsUseCase(item_repository=mock_repo)
    decision2 = IntentDecision(
        intent="inventory_search",
        target_items=[],
        categories=["โทรศัพท์และอุปกรณ์สื่อสาร"],
    )
    results2 = await query_uc_no_llm.execute(decision2)
    assert len(results2) == 2
    assert {r.name for r in results2} == {"iPhone 15 Pro Max", "Samsung Galaxy S24 Ultra"}



@pytest.mark.asyncio
async def test_sync_recommended_items_filters_unmentioned_candidates():
    """Verifies that items not mentioned in the AI response are excluded from recommended_items."""
    mock_llm = MagicMock()
    mock_repo = MagicMock()
    mock_search = MagicMock()

    candidate_items = [
        Item(id="1", name="เต็นท์ Coleman Instant Cabin 4 คน", category="แคมป์ปิงและกิจกรรมกลางแจ้ง", price=450.0),
        Item(id="2", name="ชุดโต๊ะพับและเก้าอี้สนาม Naturehike 4 ตัว", category="แคมป์ปิงและกิจกรรมกลางแจ้ง", price=250.0),
        Item(id="3", name="ชุดเตาแก๊สสนามและหม้อแคมป์ปิ้ง พร้อมตะเกียง LED", category="แคมป์ปิงและกิจกรรมกลางแจ้ง", price=180.0),
    ]

    route_uc = RouteIntentUseCase(llm_service=mock_llm)
    route_uc.execute = AsyncMock(return_value=IntentDecision(
        intent="inventory_search",
        categories=["แคมป์ปิงและกิจกรรมกลางแจ้ง"],
        ambiguity_level=0.0,
    ))

    # AI mentions ONLY Coleman and Naturehike, omitting Gas Stove
    ai_answer = (
        "สำหรับหมวดหมู่แคมป์ปิงและกิจกรรมกลางแจ้ง น้องยืมหน่อยมีอุปกรณ์พร้อมแนะนำดังนี้นะคะ\n\n"
        "• **เต็นท์ Coleman Instant Cabin 4 คน** - กางและพับเก็บง่าย (ค่าเช่า 450.0 บาท/วัน)\n"
        "• **ชุดโต๊ะพับและเก้าอี้สนาม Naturehike 4 ตัว** - น้ำหนักเบาพกพาสะดวก (ค่าเช่า 250.0 บาท/วัน)\n\n"
        "คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติมจากการ์ดอุปกรณ์ด้านล่างนี้ได้เลยนะคะ"
    )
    mock_llm.generate_text = AsyncMock(return_value=ai_answer)

    query_uc = MagicMock()
    query_uc.execute = AsyncMock(return_value=candidate_items)

    process_uc = ProcessChatMessageUseCase(
        route_intent=route_uc,
        query_items=query_uc,
        compare_items=MagicMock(),
        generate_clarification=MagicMock(),
        llm_service=mock_llm,
        search_service=mock_search,
    )

    req = ChatRequestDTO(message="อยากเช่าอุปกรณ์แคมป์ปิ้ง")
    resp = await process_uc.execute(req)

    # Must contain ONLY 2 items (Coleman and Naturehike), Gas Stove must be filtered out!
    assert len(resp.items) == 2
    item_names = [it.name for it in resp.items]
    assert "เต็นท์ Coleman Instant Cabin 4 คน" in item_names
    assert "ชุดโต๊ะพับและเก้าอี้สนาม Naturehike 4 ตัว" in item_names
    assert "ชุดเตาแก๊สสนามและหม้อแคมป์ปิ้ง พร้อมตะเกียง LED" not in item_names


@pytest.mark.asyncio
async def test_sync_recommended_items_with_structured_device_blocks():
    """Verifies that items formatted in structured device blocks are correctly matched and unmentioned items filtered."""
    candidate_items = [
        Item(id="19", name="เต็นท์ Coleman Instant Cabin 4 คน", category="แคมป์ปิงและกิจกรรมกลางแจ้ง", price=450.0),
        Item(id="20", name="ชุดโต๊ะพับและเก้าอี้สนาม Naturehike 4 ตัว", category="แคมป์ปิงและกิจกรรมกลางแจ้ง", price=250.0),
        Item(id="21", name="ชุดเตาแก๊สสนามและหม้อแคมป์ปิ้ง พร้อมตะเกียง LED", category="แคมป์ปิงและกิจกรรมกลางแจ้ง", price=180.0),
    ]

    mock_llm = MagicMock()
    mock_search = MagicMock()

    route_uc = RouteIntentUseCase(llm_service=mock_llm)
    route_uc.execute = AsyncMock(return_value=IntentDecision(
        intent="inventory_search",
        categories=["แคมป์ปิงและกิจกรรมกลางแจ้ง"],
        ambiguity_level=0.0,
    ))

    ai_answer = (
        "ยินดีแนะนำอุปกรณ์สำหรับแคมป์ปิ้งให้ค่ะ:\n\n"
        "**ชื่ออุปกรณ์:** เต็นท์ Coleman Instant Cabin 4 คน\n"
        "- **รายละเอียด:** กางและพับเก็บเสร็จใน 1 นาที กันฝนและลมแรง\n"
        "- **ราคาเช่า:** 450.0 บาท/วัน\n\n"
        "**ชื่ออุปกรณ์: ชุดโต๊ะพับและเก้าอี้สนาม Naturehike 4 ตัว**\n"
        "- **รายละเอียด:** โต๊ะพับพร้อมเก้าอี้ 4 ตัว น้ำหนักเบาพกพาสะดวก\n"
        "- **ราคาเช่า:** 250.0 บาท/วัน\n\n"
        "เชิญแตะดูรายละเอียดเพิ่มเติมจากการ์ดอุปกรณ์ด้านล่างนี้ได้เลยนะคะ"
    )
    mock_llm.generate_text = AsyncMock(return_value=ai_answer)

    query_uc = MagicMock()
    query_uc.execute = AsyncMock(return_value=candidate_items)

    process_uc = ProcessChatMessageUseCase(
        route_intent=route_uc,
        query_items=query_uc,
        compare_items=MagicMock(),
        generate_clarification=MagicMock(),
        llm_service=mock_llm,
        search_service=mock_search,
    )

    req = ChatRequestDTO(message="อยากเช่าอุปกรณ์แคมป์ปิ้ง")
    resp = await process_uc.execute(req)

    assert len(resp.items) == 2
    item_names = [it.name for it in resp.items]
    assert "เต็นท์ Coleman Instant Cabin 4 คน" in item_names
    assert "ชุดโต๊ะพับและเก้าอี้สนาม Naturehike 4 ตัว" in item_names
    assert "ชุดเตาแก๊สสนามและหม้อแคมป์ปิ้ง พร้อมตะเกียง LED" not in item_names


@pytest.mark.asyncio
async def test_generate_clarification_injects_category_inventory_context():
    """Verifies that GenerateClarificationUseCase passes category inventory context to LLM and syncs options."""
    mock_llm = MagicMock()
    mock_repo = MagicMock()

    mock_repo.get_all_items = AsyncMock(return_value=[
        Item(id="10", name="iPhone 15 Pro 128GB", category="โทรศัพท์และอุปกรณ์สื่อสาร", description="ชิป A17 Pro กล้อง 48MP", price=800.0),
        Item(id="11", name="Samsung Galaxy S24 Ultra", category="โทรศัพท์และอุปกรณ์สื่อสาร", description="ปากกา S-Pen ซูม 100x", price=850.0),
        Item(id="1", name="Sony A7 IV", category="กล้องและอุปกรณ์ถ่ายภาพ", description="กล้อง Full Frame", price=1200.0),
    ])

    generated_clarification = ClarificationQuestion(
        question="ต้องการเช่าโทรศัพท์มือถือสำหรับใช้งานด้านใดคะ?",
        options=[
            ChoiceOption(id="opt_1", label="ถ่ายภาพและวิดีโอโปร", action_value="ถ่ายภาพและวิดีโอโปร"),
            ChoiceOption(id="opt_2", label="ทำงานและ AI", action_value="ทำงานและ AI"),
        ],
    )
    mock_llm.generate_structured = AsyncMock(return_value=generated_clarification)

    uc = GenerateClarificationUseCase(llm_service=mock_llm, item_repository=mock_repo)
    decision = IntentDecision(
        intent="clarification_needed",
        ambiguity_level=0.7,
        categories=["โทรศัพท์และอุปกรณ์สื่อสาร"],
        missing_slots=["intended_use", "target_model"],
    )

    result = await uc.execute("อยากเช่ามือถือ", decision)

    # Verify structured LLM prompt was invoked with category items
    call_args = mock_llm.generate_structured.call_args
    prompt_text = call_args.kwargs.get("prompt") or call_args.args[0]
    assert "iPhone 15 Pro 128GB" in prompt_text
    assert "Samsung Galaxy S24 Ultra" in prompt_text
    assert "Sony A7 IV" not in prompt_text  # Camera shouldn't be in phone category context

    # Verify options & question steps are synchronized for 2 continuous steps
    assert result.question == "ต้องการเช่าโทรศัพท์มือถือสำหรับใช้งานด้านใดคะ?"
    assert len(result.options) == 2
    assert len(result.questions) == 2
    assert result.questions[0].step == 1
    assert result.questions[0].total_steps == 2
    assert result.questions[0].options == ["ถ่ายภาพและวิดีโอโปร", "ทำงานและ AI"]
    assert result.questions[1].step == 2
    assert result.questions[1].total_steps == 2


@pytest.mark.asyncio
async def test_query_items_matches_intended_use_tokens():
    """Verifies that QueryItemsUseCase boosts items whose description matches intended use tokens."""
    mock_repo = MagicMock()
    items = [
        Item(id="10", name="iPhone 15 Pro 128GB", category="โทรศัพท์และอุปกรณ์สื่อสาร", description="กล้องระดับโปร 48MP ถ่ายคอนเทนต์และวิดีโอ", price=800.0),
        Item(id="11", name="Samsung Galaxy S24 Ultra", category="โทรศัพท์และอุปกรณ์สื่อสาร", description="ปากกา S-Pen และ Galaxy AI สำหรับจดบันทึก", price=850.0),
    ]
    mock_repo.get_all_items = AsyncMock(return_value=items)

    uc = QueryItemsUseCase(item_repository=mock_repo)
    decision = IntentDecision(
        intent="inventory_search",
        categories=["โทรศัพท์และอุปกรณ์สื่อสาร"],
        intended_use="ถ่ายภาพ/คอนเทนต์/วิดีโอ",
    )

    results = await uc.execute(decision, limit=2)
    assert len(results) >= 1
    # iPhone has more matching tokens ('กล้อง', 'คอนเทนต์', 'วิดีโอ') -> should be first
    assert results[0].name == "iPhone 15 Pro 128GB"


@pytest.mark.asyncio
async def test_query_items_out_of_catalog_target_items_returns_empty():
    """Verifies that QueryItemsUseCase returns [] when target equipment does not exist in inventory."""
    mock_repo = MagicMock()
    items = [
        Item(id="1", name="Dyson V12 Detect Slim", category="เครื่องใช้ไฟฟ้าและอุปกรณ์ภายในบ้าน", description="เครื่องดูดฝุ่นไร้สาย", price=450.0),
        Item(id="2", name="Wanbo T2 Max New", category="เครื่องใช้ไฟฟ้าและอุปกรณ์ภายในบ้าน", description="โปรเจกเตอร์พกพา", price=350.0),
        Item(id="3", name="รถเข็นของพับได้ Heavy Duty 150 กก.", category="อื่น ๆ", description="รถเข็นขนของ สำหรับออกงาน", price=200.0),
    ]
    mock_repo.get_all_items = AsyncMock(return_value=items)

    uc = QueryItemsUseCase(item_repository=mock_repo)

    # User asks for suits / formal clothes which do not exist
    decision = IntentDecision(
        intent="inventory_search",
        target_items=["เสื้อผ้า", "สูทสากล"],
        categories=["อื่น ๆ"],
        intended_use="ออกงาน",
    )

    results = await uc.execute(decision)
    # Must return empty list, NOT leaking Dyson, Wanbo or รถเข็น
    assert results == []


@pytest.mark.asyncio
async def test_query_items_prevents_unrelated_categories_from_leaking():
    """Verifies that items from completely unrelated categories do not qualify as candidates."""
    mock_repo = MagicMock()
    items = [
        Item(id="1", name="Sony Alpha 7 IV", category="กล้องและอุปกรณ์ถ่ายภาพ", description="กล้องฟูลเฟรมสำหรับงานวิดีโอและภาพนิ่ง", price=850.0),
        Item(id="2", name="JBL PartyBox Stage 320", category="เครื่องเสียงและอุปกรณ์จัดงาน", description="ลำโพงบลูทูธสำหรับจัดงานปาร์ตี้ งานอีเวนต์", price=750.0),
    ]
    mock_repo.get_all_items = AsyncMock(return_value=items)

    uc = QueryItemsUseCase(item_repository=mock_repo)

    # User searches for camera for events
    decision = IntentDecision(
        intent="inventory_search",
        target_items=["กล้อง"],
        categories=["กล้องและอุปกรณ์ถ่ายภาพ"],
        intended_use="จัดงานอีเวนต์",
    )

    results = await uc.execute(decision)
    assert len(results) == 1
    assert results[0].name == "Sony Alpha 7 IV"


@pytest.mark.asyncio
async def test_sync_recommended_items_with_negative_response_returns_empty():
    """Verifies that _sync_recommended_items returns [] when the AI response is negative."""
    mock_repo = MagicMock()
    candidate_items = [
        Item(id="1", name="Dyson V12 Detect Slim", category="เครื่องใช้ไฟฟ้าและอุปกรณ์ภายในบ้าน", description="เครื่องดูดฝุ่นไร้สาย", price=450.0),
        Item(id="2", name="Wanbo T2 Max New", category="เครื่องใช้ไฟฟ้าและอุปกรณ์ภายในบ้าน", description="โปรเจกเตอร์พกพา", price=350.0),
    ]
    process_uc = ProcessChatMessageUseCase(
        route_intent=MagicMock(),
        query_items=MagicMock(),
        compare_items=MagicMock(),
        generate_clarification=MagicMock(),
        llm_service=MagicMock(),
        search_service=MagicMock(),
    )

    response_text = "ขณะนี้ทางยืมหน่อยยังไม่มีบริการให้เช่าเสื้อผ้าหรือสูทสากลสำหรับออกงานค่ะ"
    matched = process_uc._sync_recommended_items(candidate_items, response_text)
    assert matched == []


@pytest.mark.asyncio
async def test_route_intent_passes_history_and_active_items_context():
    """Verifies that RouteIntentUseCase extracts active items from history and formats them in prompt."""
    import json
    from app.domain.entities.chat_message import ChatMessage

    mock_llm = MagicMock()
    mock_llm.generate_structured = AsyncMock(return_value=IntentDecision(
        intent="item_inquiry",
        target_items=["กล้อง Sony Alpha A7 IV"],
        ambiguity_level=0.0,
    ))

    uc = RouteIntentUseCase(llm_service=mock_llm)
    history = [
        ChatMessage(role="user", content="อยากเช่ากล้องถ่ายภาพมืออาชีพ"),
        ChatMessage(
            role="assistant",
            content=json.dumps({
                "answer": "น้องยืมหน่อยขอแนะนำกล้อง Sony Alpha A7 IV นะคะ",
                "items": [{"id": "1", "name": "กล้อง Sony Alpha A7 IV"}],
            }),
        ),
    ]

    result = await uc.execute("ทำไรได้", history=history)

    assert result.intent == "item_inquiry"
    assert "กล้อง Sony Alpha A7 IV" in result.target_items

    # Verify prompt sent to LLM contains active item context
    call_args = mock_llm.generate_structured.call_args
    prompt_sent = call_args.kwargs.get("prompt") or call_args.args[0]
    assert "กล้อง Sony Alpha A7 IV" in prompt_sent
    assert "[อุปกรณ์ที่เพิ่งแนะนำในบริบท: กล้อง Sony Alpha A7 IV]" in prompt_sent


@pytest.mark.asyncio
async def test_process_chat_multi_item_decision_support_retains_items():
    """Verifies that when comparing/choosing between items, synthesis gives rationale and retains both item cards."""
    mock_llm = MagicMock()
    mock_repo = MagicMock()
    mock_search = MagicMock()

    candidate_items = [
        Item(id="1", name="กล้อง Sony Alpha A7 IV", category="กล้องและอุปกรณ์ถ่ายภาพ", price=1200.0, description="ฟูลเฟรม 33MP โฟกัสไว"),
        Item(id="2", name="กล้อง Canon EOS R6 Mark II", category="กล้องและอุปกรณ์ถ่ายภาพ", price=1150.0, description="ฟูลเฟรม 24MP ถ่ายรัว 40fps"),
    ]
    mock_repo.get_all_items = AsyncMock(return_value=candidate_items)

    route_uc = MagicMock()
    route_uc.execute = AsyncMock(return_value=IntentDecision(
        intent="comparison",
        target_items=["กล้อง Sony Alpha A7 IV", "กล้อง Canon EOS R6 Mark II"],
        ambiguity_level=0.0,
    ))

    # Mock compare use case returning recommendation with both items mentioned in bold
    compare_answer = (
        "ระหว่าง **กล้อง Sony Alpha A7 IV** กับ **กล้อง Canon EOS R6 Mark II** ขอแนะนำดังนี้นะคะ:\n\n"
        "• หากเน้นความละเอียดสูงสำหรับงานภาพนิ่ง ปริ้นท์รูปขนาดใหญ่ แนะนำ **กล้อง Sony Alpha A7 IV** เพราะเซนเซอร์ 33MP ให้รายละเอียดภาพที่คมชัดกว่าค่ะ\n"
        "• แต่หากเน้นถ่ายงานแอ็กชัน กีฬา หรืออีเวนต์ที่ต้องการความเร็ว แนะนำ **กล้อง Canon EOS R6 Mark II** เพราะถ่ายภาพรัวได้สูงถึง 40 fps ค่ะ"
    )
    compare_uc = MagicMock()
    compare_uc.execute = AsyncMock(return_value=(compare_answer, []))

    process_uc = ProcessChatMessageUseCase(
        route_intent=route_uc,
        query_items=QueryItemsUseCase(item_repository=mock_repo),
        compare_items=compare_uc,
        generate_clarification=MagicMock(),
        llm_service=mock_llm,
        search_service=mock_search,
    )

    req = ChatRequestDTO(message="เลือกอันไหนดี")
    resp = await process_uc.execute(req)

    assert resp.intent == "comparison"
    assert resp.clarification is None
    assert len(resp.items) == 2
    item_names = {i.name for i in resp.items}
    assert "กล้อง Sony Alpha A7 IV" in item_names
    assert "กล้อง Canon EOS R6 Mark II" in item_names
    assert "เพราะ" in resp.response


@pytest.mark.asyncio
async def test_query_items_cross_category_intended_use_gaming():
    """Verifies that when computer category lacks gaming models, gaming consoles from entertainment category are discovered."""
    mock_repo = MagicMock()
    all_shop_items = [
        Item(id="7", name="MacBook Air M2 13 นิ้ว", category="คอมพิวเตอร์และอุปกรณ์ไอที", description="แล็ปท็อปบางเบา เหมาะสำหรับงานเอกสาร กราฟิก", price=900.0),
        Item(id="8", name="iPad Pro 11 นิ้ว M2 พร้อม Apple Pencil", category="คอมพิวเตอร์และอุปกรณ์ไอที", description="แท็บเล็ต เหมาะสำหรับวาดรูปและจดบันทึก", price=650.0),
        Item(id="25", name="PlayStation 5 พร้อมจอย 2 ตัวและเกม 3 แผ่น", category="เกมและความบันเทิง", description="เครื่องเล่นเกม PS5 รุ่นใส่แผ่น พร้อมจอย 2 ตัวและเกมยอดนิยม", price=700.0),
        Item(id="26", name="Nintendo Switch OLED พร้อมจอย 4 ตัว", category="เกมและความบันเทิง", description="เครื่องเล่นเกมพกพาหน้าจอ OLED พร้อมเกมสำหรับปาร์ตี้", price=400.0),
    ]
    mock_repo.get_all_items = AsyncMock(return_value=all_shop_items)

    uc = QueryItemsUseCase(item_repository=mock_repo)
    decision = IntentDecision(
        intent="inventory_search",
        categories=["คอมพิวเตอร์และอุปกรณ์ไอที"],
        intended_use="เล่นเกม",
        ambiguity_level=0.0,
    )

    results = await uc.execute(decision, limit=3)
    assert len(results) >= 2
    # PS5 and Nintendo Switch must be ranked above MacBook Air for gaming
    top_item_names = [r.name for r in results]
    assert "PlayStation 5 พร้อมจอย 2 ตัวและเกม 3 แผ่น" in top_item_names
    assert "Nintendo Switch OLED พร้อมจอย 4 ตัว" in top_item_names
    # Top item must be a gaming device, NOT MacBook Air
    assert "เครื่องเล่นเกม" in results[0].description


@pytest.mark.asyncio
async def test_process_chat_intended_use_honest_alternative_recommends_gaming_device():
    """Verifies that asking for a computer to play games truthfully informs user and recommends gaming consoles."""
    mock_llm = MagicMock()
    mock_repo = MagicMock()
    mock_search = MagicMock()

    shop_items = [
        Item(id="7", name="MacBook Air M2 13 นิ้ว", category="คอมพิวเตอร์และอุปกรณ์ไอที", description="แล็ปท็อปบางเบา เหมาะสำหรับงานเอกสาร กราฟิก", price=900.0),
        Item(id="25", name="PlayStation 5 พร้อมจอย 2 ตัวและเกม 3 แผ่น", category="เกมและความบันเทิง", description="เครื่องเล่นเกม PS5 รุ่นใส่แผ่น", price=700.0),
    ]
    mock_repo.get_all_items = AsyncMock(return_value=shop_items)

    route_uc = MagicMock()
    route_uc.execute = AsyncMock(return_value=IntentDecision(
        intent="inventory_search",
        categories=["คอมพิวเตอร์และอุปกรณ์ไอที"],
        intended_use="เล่นเกม",
        ambiguity_level=0.0,
    ))

    honest_ai_answer = (
        "ขณะนี้ในระบบยืมหน่อยยังไม่มีคอมพิวเตอร์สำหรับเล่นเกมโดยตรงให้เช่าค่ะ (อุปกรณ์ในหมวดคอมพิวเตอร์ เช่น MacBook Air M2 จะเน้นงานเอกสารและกราฟิกทั่วไปนะคะ)\n\n"
        "แต่หากสนใจอุปกรณ์สำหรับเล่นเกม ขอแนะนำเครื่องเล่นเกมที่มีในระบบดังนี้นะคะ:\n\n"
        "**PlayStation 5 พร้อมจอย 2 ตัวและเกม 3 แผ่น**\n"
        "- **รายละเอียด:** เครื่องเล่นเกม PS5 รุ่นใส่แผ่น พร้อมจอย 2 ตัวและเกมยอดนิยม\n"
        "- **ราคาเช่า:** 700 บาท ต่อ วัน\n\n"
        "คุณลูกค้าสามารถแตะดูรายละเอียดที่การ์ดด้านล่างได้เลยนะคะ"
    )
    mock_llm.generate_text = AsyncMock(return_value=honest_ai_answer)

    process_uc = ProcessChatMessageUseCase(
        route_intent=route_uc,
        query_items=QueryItemsUseCase(item_repository=mock_repo),
        compare_items=MagicMock(),
        generate_clarification=MagicMock(),
        llm_service=mock_llm,
        search_service=mock_search,
    )

    req = ChatRequestDTO(message="อยากเช่าคอมมีแนะนำบ้างไหมว่าเช่าคอมไปเล่นเกมต้องเช่าคอมตัวไหน")
    resp = await process_uc.execute(req)

    # Must NOT trigger clarification
    assert resp.intent == "inventory_search"
    assert resp.clarification is None
    # Must attach PlayStation 5 card, and NOT attach MacBook Air
    assert len(resp.items) == 1
    assert "PlayStation 5" in resp.items[0].name
    assert "ยังไม่มีคอมพิวเตอร์สำหรับเล่นเกมโดยตรง" in resp.response


@pytest.mark.asyncio
async def test_clean_square_brackets_removes_brackets_and_formats_bold():
    """Verifies that _clean_square_brackets removes [ ] and bolds device names."""
    raw_text = (
        "ขณะนี้ในระบบยังไม่มีคอมพิวเตอร์สำหรับเล่นเกมโดยตรงนะคะ\n"
        "ทางเราขอแนะนำเครื่องเล่นเกมคอนโซลยอดนิยมเป็นทางเลือกเสริมค่ะ:\n"
        "[PlayStation 5 พร้อมจอย 2 ตัวและเกม 3 แผ่น]\n"
        "[Nintendo Switch OLED พร้อมจอย 4 ตัว]\n"
        "และยังมี **[Sony A7 IV]** ให้เช่าอีกด้วยนะคะ"
    )
    cleaned = ProcessChatMessageUseCase._clean_square_brackets(raw_text)

    # Brackets must be removed
    assert "[" not in cleaned
    assert "]" not in cleaned
    # Devices must be bolded
    assert "**PlayStation 5 พร้อมจอย 2 ตัวและเกม 3 แผ่น**" in cleaned
    assert "**Nintendo Switch OLED พร้อมจอย 4 ตัว**" in cleaned
    assert "**Sony A7 IV**" in cleaned


@pytest.mark.asyncio
async def test_sync_recommended_items_with_negative_primary_and_positive_alternatives():
    """Verifies that alternative recommended items retain their cards even if primary category is negated."""
    candidate_items = [
        Item(id="7", name="MacBook Air M2 13 นิ้ว", category="คอมพิวเตอร์และอุปกรณ์ไอที", description="แล็ปท็อปบางเบา", price=900.0),
        Item(id="25", name="PlayStation 5 พร้อมจอย 2 ตัวและเกม 3 แผ่น", category="เกมและความบันเทิง", description="เครื่องเล่นเกม PS5", price=700.0),
        Item(id="26", name="Nintendo Switch OLED พร้อมจอย 4 ตัว", category="เกมและความบันเทิง", description="เครื่องเล่นเกมพกพา", price=400.0),
    ]

    process_uc = ProcessChatMessageUseCase(
        route_intent=MagicMock(),
        query_items=MagicMock(),
        compare_items=MagicMock(),
        generate_clarification=MagicMock(),
        llm_service=MagicMock(),
        search_service=MagicMock(),
    )

    # Real text from LLM response in user bug report
    ai_response = (
        "ขณะนี้ในระบบยังไม่มีคอมพิวเตอร์สำหรับเล่นเกมโดยตรงนะคะ (มีเฉพาะแล็ปท็อปสำหรับงานเอกสารทั่วไป)\n\n"
        "ทางเราขอแนะนำเครื่องเล่นเกมคอนโซลยอดนิยมที่ตอบโจทย์การเล่นเกมได้เป็นอย่างดีเป็นทางเลือกเสริมค่ะ:\n"
        "[PlayStation 5 พร้อมจอย 2 ตัวและเกม 3 แผ่น]\n"
        "[Nintendo Switch OLED พร้อมจอย 4 ตัว]\n\n"
        "สามารถกดดูรายละเอียดหรือเลือกเช่าที่การ์ดด้านล่างได้เลยนะคะ"
    )

    matched = process_uc._sync_recommended_items(candidate_items, ai_response)

    # PlayStation 5 and Nintendo Switch OLED must be returned as cards
    assert len(matched) == 2
    matched_names = [m.name for m in matched]
    assert "PlayStation 5 พร้อมจอย 2 ตัวและเกม 3 แผ่น" in matched_names
    assert "Nintendo Switch OLED พร้อมจอย 4 ตัว" in matched_names
    # MacBook Air must NOT be returned
    assert "MacBook Air M2 13 นิ้ว" not in matched_names


@pytest.mark.asyncio
async def test_sync_recommended_items_filters_explicitly_negated_item():
    """Verifies that an explicitly negated item is excluded while positively recommended items are kept."""
    candidate_items = [
        Item(id="1", name="Sony Alpha 7 IV", category="กล้องและอุปกรณ์ถ่ายภาพ", price=1200.0),
        Item(id="2", name="Sony Alpha 7C II", category="กล้องและอุปกรณ์ถ่ายภาพ", price=1100.0),
    ]

    process_uc = ProcessChatMessageUseCase(
        route_intent=MagicMock(),
        query_items=MagicMock(),
        compare_items=MagicMock(),
        generate_clarification=MagicMock(),
        llm_service=MagicMock(),
        search_service=MagicMock(),
    )

    response_text = (
        "ขออภัยด้วยนะคะ ขณะนี้ในระบบยืมหน่อยยังไม่มี Sony Alpha 7 IV ให้เช่าค่ะ "
        "แต่ทางเราขอแนะนำ Sony Alpha 7C II เป็นทางเลือกเสริมแทนนะคะ มีเซนเซอร์ Full Frame และขนาดกะทัดรัดค่ะ"
    )

    matched = process_uc._sync_recommended_items(candidate_items, response_text)

    assert len(matched) == 1
    assert matched[0].name == "Sony Alpha 7C II"


@pytest.mark.asyncio
async def test_process_chat_removes_square_brackets_and_displays_cards():
    """End-to-end test verifying response text has no [ ] and cards are attached."""
    mock_llm = MagicMock()
    mock_repo = MagicMock()
    mock_search = MagicMock()

    shop_items = [
        Item(id="7", name="MacBook Air M2 13 นิ้ว", category="คอมพิวเตอร์และอุปกรณ์ไอที", description="แล็ปท็อปบางเบา", price=900.0),
        Item(id="25", name="PlayStation 5 พร้อมจอย 2 ตัวและเกม 3 แผ่น", category="เกมและความบันเทิง", description="เครื่องเล่นเกม PS5", price=700.0),
        Item(id="26", name="Nintendo Switch OLED พร้อมจอย 4 ตัว", category="เกมและความบันเทิง", description="เครื่องเล่นเกมพกพา", price=400.0),
    ]
    mock_repo.get_all_items = AsyncMock(return_value=shop_items)

    route_uc = MagicMock()
    route_uc.execute = AsyncMock(return_value=IntentDecision(
        intent="inventory_search",
        categories=["คอมพิวเตอร์และอุปกรณ์ไอที"],
        intended_use="เล่นเกม",
        ambiguity_level=0.0,
    ))

    raw_ai_answer = (
        "ขณะนี้ในระบบยังไม่มีคอมพิวเตอร์สำหรับเล่นเกมโดยตรงนะคะ (มีเฉพาะแล็ปท็อปสำหรับงานเอกสารทั่วไป)\n\n"
        "ทางเราขอแนะนำเครื่องเล่นเกมคอนโซลยอดนิยมที่ตอบโจทย์การเล่นเกมได้เป็นอย่างดีเป็นทางเลือกเสริมค่ะ:\n"
        "[PlayStation 5 พร้อมจอย 2 ตัวและเกม 3 แผ่น]\n"
        "[Nintendo Switch OLED พร้อมจอย 4 ตัว]\n\n"
        "สามารถกดดูรายละเอียดหรือเลือกเช่าที่การ์ดด้านล่างได้เลยนะคะ"
    )
    mock_llm.generate_text = AsyncMock(return_value=raw_ai_answer)

    process_uc = ProcessChatMessageUseCase(
        route_intent=route_uc,
        query_items=QueryItemsUseCase(item_repository=mock_repo),
        compare_items=MagicMock(),
        generate_clarification=MagicMock(),
        llm_service=mock_llm,
        search_service=mock_search,
    )

    req = ChatRequestDTO(message="เราอยากเช่าคอมเอาไปเล่นเกม")
    resp = await process_uc.execute(req)

    # 1. No square brackets in response
    assert "[" not in resp.response
    assert "]" not in resp.response
    assert "**PlayStation 5 พร้อมจอย 2 ตัวและเกม 3 แผ่น**" in resp.response
    assert "**Nintendo Switch OLED พร้อมจอย 4 ตัว**" in resp.response

    # 2. Both console cards are attached
    assert len(resp.items) == 2
    item_names = [i.name for i in resp.items]
    assert "PlayStation 5 พร้อมจอย 2 ตัวและเกม 3 แผ่น" in item_names
    assert "Nintendo Switch OLED พร้อมจอย 4 ตัว" in item_names


@pytest.mark.asyncio
async def test_process_chat_greeting_asks_for_rental_products():
    """Verifies that greeting prompts ask what rental products user wants to find/rent and empty message returns updated greeting."""
    process_uc = ProcessChatMessageUseCase(
        route_intent=MagicMock(),
        query_items=MagicMock(),
        compare_items=MagicMock(),
        generate_clarification=MagicMock(),
        llm_service=MagicMock(),
        search_service=MagicMock(),
    )

    # Empty message fallback greeting
    resp_empty = await process_uc.execute(ChatRequestDTO(message=""))
    assert resp_empty.intent == "general_greeting"
    assert "หาสินค้าเช่า" in resp_empty.response or "เช่า" in resp_empty.response
    assert "ช่วยดูแล" not in resp_empty.response

    # Verify stream empty message
    stream_events = []
    async for event in process_uc.execute_stream(ChatRequestDTO(message="")):
        stream_events.append(event)
    done_event = [e for e in stream_events if "event: done" in e][0]
    assert "หาสินค้าเช่า" in done_event or "เช่า" in done_event
    assert "ช่วยดูแล" not in done_event


@pytest.mark.asyncio
async def test_process_chat_enforces_structured_blocks_for_recommendations():
    """Verifies that prompts enforce structured bullet blocks for recommendations and forbid dense single paragraphs."""
    mock_llm = MagicMock()
    mock_repo = MagicMock()
    mock_search = MagicMock()

    shop_items = [
        Item(id="7", name="MacBook Air M2 13 นิ้ว", category="คอมพิวเตอร์และอุปกรณ์ไอที", description="แล็ปท็อปบางเบา", price=900.0),
        Item(id="25", name="PlayStation 5 พร้อมจอย 2 ตัวและเกม 3 แผ่น", category="เกมและความบันเทิง", description="เครื่องเล่นเกม PS5", price=700.0),
        Item(id="26", name="Nintendo Switch OLED พร้อมจอย 4 ตัว", category="เกมและความบันเทิง", description="เครื่องเล่นเกมพกพา", price=400.0),
    ]
    mock_repo.get_all_items = AsyncMock(return_value=shop_items)

    route_uc = MagicMock()
    route_uc.execute = AsyncMock(return_value=IntentDecision(
        intent="inventory_search",
        categories=["คอมพิวเตอร์และอุปกรณ์ไอที"],
        intended_use="เล่นเกม",
        ambiguity_level=0.0,
    ))

    captured_prompt = ""
    async def capture_generate_text(prompt, system_instruction, max_tokens, temperature):
        nonlocal captured_prompt
        captured_prompt = prompt
        return (
            "ขณะนี้ระบบของเรายังไม่มีคอมพิวเตอร์สำหรับเล่นเกมโดยเฉพาะค่ะ แต่เรามีเครื่องเล่นเกมพกพาและคอนโซลที่ตอบโจทย์ความบันเทิงแทนได้นะคะ ขอแนะนำเป็นทางเลือกเสริมดังนี้ค่ะ:\n\n"
            "**PlayStation 5 พร้อมจอย 2 ตัวและเกม 3 แผ่น**\n"
            "- **รายละเอียด:** เครื่องเล่นเกม PS5 พร้อมจอย DualSense และเกมยอดนิยม\n"
            "- **ราคาเช่า:** 700 บาท ต่อ วัน\n\n"
            "**Nintendo Switch OLED พร้อมจอย 4 ตัว**\n"
            "- **รายละเอียด:** เครื่องเล่นเกมพกพาหน้าจอ OLED 7 นิ้ว พร้อมจอยคอนและเกมปาร์ตี้\n"
            "- **ราคาเช่า:** 400 บาท ต่อ วัน\n\n"
            "คุณผู้ใช้งานสามารถแตะดูรายละเอียดเพิ่มเติมที่การ์ดด้านล่างนี้ได้เลยนะคะ"
        )
    mock_llm.generate_text = capture_generate_text

    process_uc = ProcessChatMessageUseCase(
        route_intent=route_uc,
        query_items=QueryItemsUseCase(item_repository=mock_repo),
        compare_items=MagicMock(),
        generate_clarification=MagicMock(),
        llm_service=mock_llm,
        search_service=mock_search,
    )

    req = ChatRequestDTO(message="อยากเช่าคอมเล่นเกมมีแนะนำไหม")
    resp = await process_uc.execute(req)

    # 1. Prompt must forbid single paragraph and demand structured blocks
    assert "ห้ามเขียนรวมเป็นพารากราฟเดียว" in captured_prompt
    assert "**รายละเอียด:**" in captured_prompt
    assert "**ราคาเช่า:**" in captured_prompt

    # 2. Response contains structured blocks exactly like Image 2
    assert "**PlayStation 5 พร้อมจอย 2 ตัวและเกม 3 แผ่น**" in resp.response
    assert "- **รายละเอียด:**" in resp.response
    assert "- **ราคาเช่า:**" in resp.response
    assert len(resp.items) == 2


@pytest.mark.asyncio
async def test_generate_clarification_enforces_conciseness_and_zero_bias():
    """Verifies that clarification prompts enforce ultra-concise titles and zero-bias balanced choices without single-brand leading."""
    mock_llm = MagicMock()
    mock_repo = MagicMock()

    mock_repo.get_all_items = AsyncMock(return_value=[
        Item(id="10", name="iPhone 15 Pro 128GB", category="โทรศัพท์และอุปกรณ์สื่อสาร", description="สมาร์ตโฟน A17 Pro", price=800.0),
        Item(id="11", name="Samsung Galaxy S24 Ultra", category="โทรศัพท์และอุปกรณ์สื่อสาร", description="สมาร์ตโฟน S-Pen", price=850.0),
    ])

    captured_prompt = ""
    captured_sys_prompt = ""

    async def capture_generate_structured(prompt, schema, system_instruction, temperature):
        nonlocal captured_prompt, captured_sys_prompt
        captured_prompt = prompt
        captured_sys_prompt = system_instruction
        # Simulate clean, concise, unbiased clarification
        return ClarificationQuestion(
            question="เพื่อแนะนำรุ่นที่ตอบโจทย์ รบกวนเลือกข้อมูลเบื้องต้นสักนิดนะคะ",
            questions=[
                QuestionStep(
                    id="step-1",
                    title="ต้องการเน้นใช้งานด้านใดเป็นหลักคะ?",
                    options=["ถ่ายภาพและวิดีโอโปร", "ทำงานและใช้ AI", "ใช้งานทั่วไป"],
                    step=1,
                    total_steps=2,
                    branch_titles={
                        "ถ่ายภาพและวิดีโอโปร": "มีระบบหรือแบรนด์ที่สะดวกใช้งานไหมคะ?",
                    },
                    branch_options={
                        "ถ่ายภาพและวิดีโอโปร": ["ระบบ iOS (iPhone)", "ระบบ Android (Samsung)", "ได้ทุกระบบ / ไม่จำกัด"],
                    },
                ),
                QuestionStep(
                    id="step-2",
                    title="มีระบบหรือแบรนด์ที่สะดวกใช้งานไหมคะ?",
                    options=["ระบบ iOS (iPhone)", "ระบบ Android (Samsung)", "ได้ทุกระบบ / ไม่จำกัด"],
                    step=2,
                    total_steps=2,
                ),
            ],
            options=[],
        )

    mock_llm.generate_structured = capture_generate_structured

    uc = GenerateClarificationUseCase(llm_service=mock_llm, item_repository=mock_repo)
    decision = IntentDecision(
        intent="clarification_needed",
        ambiguity_level=0.7,
        categories=["โทรศัพท์และอุปกรณ์สื่อสาร"],
        missing_slots=["intended_use", "target_model"],
    )

    result = await uc.execute("อยากเช่ามือถือ", decision)

    # 1. Prompt directives must forbid long questions and enforce zero-bias
    assert "กฎความกระชับสูงสุด" in captured_prompt
    assert "Strict Neutrality & Zero-Bias" in captured_prompt
    assert "ห้ามถามคำถามชี้นำ" in captured_prompt
    assert "iOS (iPhone)" in captured_prompt
    assert "Android (Samsung" in captured_prompt

    # 2. System prompt must also forbid leading questions
    assert "ห้ามถามคำถามชี้นำ" in captured_sys_prompt
    assert "Ultra-Concise Title" in captured_sys_prompt

    # 3. Questions must be concise (<= 45 chars)
    for q in result.questions:
        assert len(q.title) <= 45
        assert "รบกวนระบุลักษณะการใช้งานหลักในการเช่า" not in q.title

    # 4. Step 2 options must be balanced (covering both iOS and Android, not locking to iPhone)
    step2_options = result.questions[1].options
    assert any("iOS" in opt or "iPhone" in opt for opt in step2_options)
    assert any("Android" in opt or "Samsung" in opt for opt in step2_options)
    assert any("ได้ทุกระบบ" in opt or "ไม่จำกัด" in opt for opt in step2_options)


@pytest.mark.asyncio
async def test_generate_clarification_enforces_target_scope_alignment():
    """Verifies that clarifying questions align to target equipment scope and exclude unrelated instruments (e.g. keyboard for guitar)."""
    mock_llm = MagicMock()
    mock_repo = MagicMock()

    music_items = [
        Item(id="28", name="กีตาร์โปร่ง Yamaha F310", category="ดนตรีและเครื่องดนตรี", price=250.0),
        Item(id="30", name="กีตาร์เบสไฟฟ้า Fender Squier พร้อมแอมป์ซ้อม", category="ดนตรีและเครื่องดนตรี", price=380.0),
        Item(id="29", name="คีย์บอร์ดไฟฟ้า Yamaha PSR-E373 61 คีย์", category="ดนตรีและเครื่องดนตรี", price=350.0),
    ]
    mock_repo.get_all_items = AsyncMock(return_value=music_items)

    captured_prompt = ""
    captured_sys_prompt = ""

    async def capture_generate_structured(prompt, schema, system_instruction, temperature=0.2):
        nonlocal captured_prompt, captured_sys_prompt
        captured_prompt = prompt
        captured_sys_prompt = system_instruction
        return ClarificationQuestion(
            question="เพื่อแนะนำรุ่นที่ตอบโจทย์ รบกวนเลือกข้อมูลเบื้องต้นสักนิดนะคะ",
            missing_dimension="intended_use",
            questions=[
                QuestionStep(
                    id="step-1",
                    title="ต้องการเน้นใช้งานด้านใดเป็นหลักคะ?",
                    options=["ฝึกซ้อมทั่วไป", "ออกงานแสดง", "บันทึกเสียง"],
                    step=1,
                    total_steps=2,
                ),
                QuestionStep(
                    id="step-2",
                    title="สนใจกีตาร์ประเภทไหนคะ?",
                    options=["กีตาร์โปร่ง", "กีตาร์เบส / กีตาร์ไฟฟ้า", "ได้ทุกประเภท / ไม่จำกัด"],
                    step=2,
                    total_steps=2,
                ),
            ],
            options=[],
        )

    mock_llm.generate_structured = capture_generate_structured

    uc = GenerateClarificationUseCase(llm_service=mock_llm, item_repository=mock_repo)
    decision = IntentDecision(
        intent="clarification_needed",
        ambiguity_level=0.7,
        categories=["ดนตรีและเครื่องดนตรี"],
        target_items=["กีตาร์"],
        missing_slots=["intended_use", "target_model"],
    )

    result = await uc.execute("อยากเช่ากีต้า", decision)

    # 1. Scoped context block sent to LLM must contain guitars and MUST NOT contain keyboard
    assert "กีตาร์โปร่ง Yamaha F310" in captured_prompt
    assert "กีตาร์เบสไฟฟ้า Fender Squier" in captured_prompt
    assert "คีย์บอร์ดไฟฟ้า Yamaha PSR-E373" not in captured_prompt

    # 2. Directives must emphasize Target Scope Alignment & Zero-Bias
    assert "Target Scope Alignment" in captured_prompt
    assert "Strict Neutrality & Zero-Bias" in captured_prompt
    assert "ห้ามนำ คีย์บอร์ดไฟฟ้า" in captured_prompt or "คีย์บอร์ด" in captured_prompt

    # 3. Step 2 options must be scoped to guitar and balanced
    step2_options = result.questions[1].options
    assert "กีตาร์โปร่ง" in step2_options
    assert "กีตาร์เบส / กีตาร์ไฟฟ้า" in step2_options
    assert "คีย์บอร์ดไฟฟ้า" not in step2_options
    assert "ได้ทุกประเภท / ไม่จำกัด" in step2_options


@pytest.mark.asyncio
async def test_process_chat_enforces_structured_blocks_for_comparison():
    """Verifies that comparison answers enforce structured blocks for each item and forbid run-on sentences with ส่วน."""
    mock_llm = MagicMock()
    mock_repo = MagicMock()
    mock_search = MagicMock()
    mock_search.search = AsyncMock(return_value=[])
    mock_fact = MagicMock()
    from app.domain.entities.comparison import ComparisonMatrix
    mock_fact.verify_and_synthesize = AsyncMock(return_value=ComparisonMatrix(target_items=[], comparison_points=[]))

    candidate_items = [
        Item(id="28", name="กีตาร์โปร่ง Yamaha F310", category="ดนตรีและเครื่องดนตรี", price=250.0),
        Item(id="30", name="กีตาร์เบสไฟฟ้า Fender Squier พร้อมแอมป์ซ้อม", category="ดนตรีและเครื่องดนตรี", price=380.0),
        Item(id="29", name="คีย์บอร์ดไฟฟ้า Yamaha PSR-E373 61 คีย์", category="ดนตรีและเครื่องดนตรี", price=350.0),
    ]

    route_uc = RouteIntentUseCase(llm_service=mock_llm)
    route_uc.execute = AsyncMock(return_value=IntentDecision(
        intent="comparison",
        target_items=["กีตาร์โปร่ง Yamaha F310", "กีตาร์เบสไฟฟ้า Fender Squier พร้อมแอมป์ซ้อม"],
        categories=["ดนตรีและเครื่องดนตรี"],
        ambiguity_level=0.0,
    ))

    query_uc = MagicMock()
    query_uc.execute = AsyncMock(return_value=candidate_items)

    captured_prompt = ""

    async def capture_generate_text(prompt, system_instruction, max_tokens=400, temperature=0.3):
        nonlocal captured_prompt
        captured_prompt = prompt
        return (
            "ทั้ง 2 รุ่นมีจุดเด่นและลักษณะการใช้งานที่แตกต่างกันดังนี้นะคะ\n\n"
            "**กีตาร์โปร่ง Yamaha F310**\n"
            "- **จุดเด่น/การใช้งาน:** กีตาร์โปร่งทรงมาตรฐาน เสียงกังวานใส เหมาะฝึกซ้อมและท่องเที่ยว\n"
            "- **ราคาเช่า:** 250 บาท ต่อ วัน\n\n"
            "**กีตาร์เบสไฟฟ้า Fender Squier พร้อมแอมป์ซ้อม**\n"
            "- **จุดเด่น/การใช้งาน:** กีตาร์เบส 4 สาย พร้อมแอมป์ซ้อม 15W เหมาะสำหรับเล่นในวงดนตรี\n"
            "- **ราคาเช่า:** 380 บาท ต่อ วัน\n\n"
            "คุณผู้ใช้งานสามารถแตะดูรายละเอียดเพิ่มเติมที่การ์ดด้านล่างนี้ได้เลยนะคะ"
        )

    mock_llm.generate_text = capture_generate_text

    compare_uc = CompareItemsUseCase(
        llm_service=mock_llm,
        search_service=mock_search,
        fact_service=mock_fact,
    )

    process_uc = ProcessChatMessageUseCase(
        route_intent=route_uc,
        query_items=query_uc,
        compare_items=compare_uc,
        generate_clarification=MagicMock(),
        llm_service=mock_llm,
        search_service=mock_search,
    )

    history = [
        ChatMessage(role="user", content="อยากเช่ากีต้า"),
        ChatMessage(role="assistant", content="กีตาร์โปร่ง Yamaha F310 250 บาท และ กีตาร์เบสไฟฟ้า Fender Squier 380 บาท"),
    ]
    req = ChatRequestDTO(message="แล้วอันนี้ต่างกันไง", history=history)
    resp = await process_uc.execute(req)

    # 1. Comparison prompt must ban single-sentence run-on with 'ส่วน'
    assert "ห้ามเขียนเปรียบเทียบอุปกรณ์รวมกันในประโยคเดียวติดกันด้วยคำว่า 'ส่วน'" in captured_prompt
    assert "จุดเด่น/การใช้งาน" in captured_prompt

    # 2. Response must be formatted in structured blocks with bullet points
    assert "**กีตาร์โปร่ง Yamaha F310**" in resp.response
    assert "**กีตาร์เบสไฟฟ้า Fender Squier พร้อมแอมป์ซ้อม**" in resp.response
    assert "- **จุดเด่น/การใช้งาน:**" in resp.response
    assert "- **ราคาเช่า:**" in resp.response

    # 3. Synchronized items must include only the 2 compared guitars, excluding the keyboard
    item_names = [i.name for i in resp.items]
    assert "กีตาร์โปร่ง Yamaha F310" in item_names
    assert "กีตาร์เบสไฟฟ้า Fender Squier พร้อมแอมป์ซ้อม" in item_names
    assert "คีย์บอร์ดไฟฟ้า Yamaha PSR-E373 61 คีย์" not in item_names


@pytest.mark.asyncio
async def test_query_items_target_equipment_strictly_excludes_different_equipment_in_same_category():
    """Verifies that asking for guitar returns only guitars, completely excluding keyboards even within the same music category."""
    mock_repo = MagicMock()
    mock_repo.get_all_items = AsyncMock(return_value=[
        Item(id="1", name="กีตาร์โปร่ง Yamaha F310", category="ดนตรีและเครื่องดนตรี", price=250.0, description="กีตาร์โปร่งพร้อมกระเป๋า"),
        Item(id="2", name="กีตาร์เบสไฟฟ้า Fender Squier พร้อมแอมป์ซ้อม", category="ดนตรีและเครื่องดนตรี", price=380.0, description="กีตาร์เบส 4 สาย"),
        Item(id="3", name="คีย์บอร์ดไฟฟ้า Yamaha PSR-E373 61 คีย์", category="ดนตรีและเครื่องดนตรี", price=350.0, description="คีย์บอร์ดไฟฟ้า 61 คีย์"),
    ])

    query_uc = QueryItemsUseCase(item_repository=mock_repo)
    decision = IntentDecision(
        intent="item_search",
        target_items=["กีตาร์"],
        ambiguity_level=0.0,
        confidence=0.95,
    )

    items = await query_uc.execute(decision=decision, limit=5)

    names = [i.name for i in items]
    assert "กีตาร์โปร่ง Yamaha F310" in names
    assert "กีตาร์เบสไฟฟ้า Fender Squier พร้อมแอมป์ซ้อม" in names
    # Keyboards must NEVER be present when target is guitar
    assert "คีย์บอร์ดไฟฟ้า Yamaha PSR-E373 61 คีย์" not in names
    assert len(items) == 2


@pytest.mark.asyncio
async def test_query_items_ai_native_semantic_selection_no_quota_backfill():
    """Verifies that AI-Native semantic selection returns only genuinely matching items without backfilling up to limit."""
    mock_repo = MagicMock()
    mock_repo.get_all_items = AsyncMock(return_value=[
        Item(id="1", name="กีตาร์โปร่ง Yamaha F310", category="ดนตรีและเครื่องดนตรี", price=250.0, description="กีตาร์โปร่งพร้อมกระเป๋า"),
        Item(id="2", name="กีตาร์เบสไฟฟ้า Fender Squier พร้อมแอมป์ซ้อม", category="ดนตรีและเครื่องดนตรี", price=380.0, description="กีตาร์เบส 4 สาย"),
        Item(id="3", name="คีย์บอร์ดไฟฟ้า Yamaha PSR-E373 61 คีย์", category="ดนตรีและเครื่องดนตรี", price=350.0, description="คีย์บอร์ดไฟฟ้า 61 คีย์"),
        Item(id="4", name="กลองไฟฟ้า Roland TD-02KV", category="ดนตรีและเครื่องดนตรี", price=600.0, description="กลองชุดไฟฟ้า 5 ชิ้น"),
        Item(id="5", name="ไมโครโฟน Shure SM58", category="เครื่องเสียงและอุปกรณ์จัดงาน", price=200.0, description="ไมค์ร้องเพลง"),
    ])

    mock_llm = MagicMock()
    mock_llm.generate_structured = AsyncMock(
        return_value=SemanticItemFilterDecision(
            matched_item_ids=["1", "2"],
            reasoning="Only items 1 and 2 are guitars/basses. Keyboards, drums, and microphones are different equipment."
        )
    )

    query_uc = QueryItemsUseCase(item_repository=mock_repo, llm_service=mock_llm)
    decision = IntentDecision(
        intent="inventory_search",
        target_items=["กีตาร์"],
        categories=["ดนตรีและเครื่องดนตรี"],
        ambiguity_level=0.0,
    )

    # limit is 5, but catalog only has 2 guitars
    items = await query_uc.execute(decision=decision, limit=5)

    # Must return ONLY 2 items, never filling the remaining 3 slots with keyboards, drums or microphones
    assert len(items) == 2
    item_ids = [i.id for i in items]
    assert item_ids == ["1", "2"]
    assert "3" not in item_ids
    assert "4" not in item_ids
    assert "5" not in item_ids


@pytest.mark.asyncio
async def test_compare_items_creates_fallback_query_and_includes_closing_guidelines():
    """Verifies that CompareItemsUseCase generates a fallback search query if none provided,
    and prompts for 'ยังไม่มีให้บริการในระบบค่ะ' and 'หากสนใจสินค้าที่มีให้เช่าในระบบตอนนี้ สามารถแตะดูรายละเอียดเพิ่มเติมที่การ์ดด้านล่างนี้ได้เลยนะคะ'."""
    mock_llm = MagicMock()
    mock_search = MagicMock()
    mock_fact = MagicMock()

    mock_search.search = AsyncMock(return_value=[
        SearchSource(title="iPhone 16 Pro Review", snippet="A18 Pro chip, 6.3 inch", domain="tech.com", url="https://tech.com")
    ])
    mock_fact.verify_and_synthesize = AsyncMock(return_value=ComparisonMatrix(
        target_items=["iPhone 15 Pro", "iPhone 16 Pro"],
        specifications={"iPhone 16 Pro": {"chip": "A18 Pro"}, "iPhone 15 Pro": {"chip": "A17 Pro"}},
        pros_and_cons={},
        verdict="iPhone 16 Pro แรงกว่า"
    ))
    mock_llm.generate_text = AsyncMock(return_value=(
        "ทั้งสองรุ่นมีจุดเด่นแตกต่างกันดังนี้นะคะ\n\n"
        "**iPhone 15 Pro**\n- **จุดเด่น/การใช้งาน:** ชิป A17 Pro จอ 6.1 นิ้ว\n- **ราคาเช่า:** 380 บาท ต่อ วัน\n\n"
        "**iPhone 16 Pro**\n- **จุดเด่น/การใช้งาน:** ชิป A18 Pro จอ 6.3 นิ้ว\n- **ราคาเช่า:** ยังไม่มีให้บริการในระบบค่ะ\n\n"
        "หากสนใจสินค้าที่มีให้เช่าในระบบตอนนี้ สามารถแตะดูรายละเอียดเพิ่มเติมที่การ์ดด้านล่างนี้ได้เลยนะคะ"
    ))

    uc = CompareItemsUseCase(
        llm_service=mock_llm,
        search_service=mock_search,
        fact_service=mock_fact,
    )

    decision = IntentDecision(
        intent="comparison",
        target_items=["iPhone 15 Pro", "iPhone 16 Pro"],
        categories=["โทรศัพท์และอุปกรณ์สื่อสาร"],
        ambiguity_level=0.0,
        search_query=None,
    )
    candidate_items = [
        Item(id="15", name="iPhone 15 Pro 128GB", category="โทรศัพท์และอุปกรณ์สื่อสาร", price=380.0, type="day")
    ]

    answer, sources = await uc.execute(decision, candidate_items)

    assert mock_search.search.called
    assert decision.search_query == "compare iPhone 15 Pro vs iPhone 16 Pro specs"
    assert len(sources) == 1
    assert "ยังไม่มีให้บริการในระบบค่ะ" in answer
    assert "หากสนใจสินค้าที่มีให้เช่าในระบบตอนนี้ สามารถแตะดูรายละเอียดเพิ่มเติมที่การ์ดด้านล่างนี้ได้เลยนะคะ" in answer

    # Verify prompt guidelines sent to LLM
    prompt_sent = mock_llm.generate_text.call_args[1]["prompt"]
    assert "ยังไม่มีให้บริการในระบบค่ะ" in prompt_sent
    assert "หากสนใจสินค้าที่มีให้เช่าในระบบตอนนี้ สามารถแตะดูรายละเอียดเพิ่มเติมที่การ์ดด้านล่างนี้ได้เลยนะคะ" in prompt_sent


@pytest.mark.asyncio
async def test_process_chat_stream_external_search_fallback_and_done_payload():
    """Verifies that execute_stream falls back to an effective search query when search_query is None,
    and returns search_sources and search_query in done payload."""
    mock_llm = MagicMock()
    mock_search = MagicMock()
    mock_route = MagicMock()
    mock_query = MagicMock()
    mock_compare = MagicMock()
    mock_clarification = MagicMock()

    mock_route.execute = AsyncMock(return_value=IntentDecision(
        intent="comparison",
        target_items=["iPhone 15 Pro", "iPhone 16 Pro"],
        needs_external_search=True,
        search_query=None,
        ambiguity_level=0.0,
    ))

    candidate_items = [
        Item(id="15", name="iPhone 15 Pro 128GB", category="โทรศัพท์และอุปกรณ์สื่อสาร", price=380.0, type="day")
    ]
    mock_query.execute = AsyncMock(return_value=candidate_items)

    mock_search.search = AsyncMock(return_value=[
        SearchSource(title="iPhone 16 Pro Specs", snippet="A18 Pro chip", domain="apple.com", url="https://apple.com")
    ])

    async def fake_stream(*args, **kwargs):
        yield "ทั้งสองรุ่น"
        yield "ต่างกันค่ะ"

    mock_llm.generate_stream = fake_stream

    process_uc = ProcessChatMessageUseCase(
        route_intent=mock_route,
        query_items=mock_query,
        compare_items=mock_compare,
        generate_clarification=mock_clarification,
        llm_service=mock_llm,
        search_service=mock_search,
    )

    request = ChatRequestDTO(message="แล้ว iphone 15 เทียบกับ iPhone รุ่นล่าสุดอันไหนโหดกว่ากัน")
    events = []
    async for event in process_uc.execute_stream(request):
        events.append(event)

    # Verify web search was called with fallback
    assert mock_search.search.called
    search_query_arg = mock_search.search.call_args[0][0]
    assert "compare iPhone 15 Pro vs iPhone 16 Pro specs" in search_query_arg

    # Verify done event contains search_query and search_sources
    done_event = next(e for e in events if "event: done" in e)
    done_json_str = done_event.split("data: ")[1].strip()
    done_data = json.loads(done_json_str)
    assert done_data["search_query"] == "compare iPhone 15 Pro vs iPhone 16 Pro specs"
    assert len(done_data["search_sources"]) == 1
    assert done_data["search_sources"][0]["title"] == "iPhone 16 Pro Specs"














