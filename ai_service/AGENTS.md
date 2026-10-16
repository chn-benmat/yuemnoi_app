# AGENTS.md - AI Coding Assistant & Architecture Guidelines

This document provides definitive instructions, architectural principles, and operational guidelines for any AI agent or developer working on the `ai_service` repository.

---

## 1. Project Overview & Role

- **Repository**: `ai_service` (Backend for Mobile Rental Chatbot)
- **Role**: AI Assistant & Rental Consultant Service
- **Runtime**: Python 3.12 (Virtual Environment: `.venv`)
- **LLM Providers & API Keys**: Groq Cloud API with distinct models for generation, independent review and failover:
  - **Groq API** (`GROQ_API_KEY`) - Sole LLM provider; model profiles and stage order come from `config/ai_runtime.json`
  *(User-selected Groq plan; Developer usage and a monthly budget were authorized on 2026-10-08. No local Ollama dependency.)*
- **Database**: **Supabase** table `item_tb` (33 active rental inventory items)
- **Search Provider**: **Tavily Search API** (1,000 monthly free credits, basic depth)

---

## 2. STRICT CONSTRAINTS & CODING POLICIES

### 🚫 ZERO-REGEX, ZERO-KEYWORD, ZERO-HARDCODE POLICY

Any modification or addition to this codebase **MUST strictly adhere** to the following rules:

1. **NO Keyword Matching & NO Keyword Locking in Prompts (Zero-Keyword Policy)**:
   - ❌ **No Code-Level Keyword Routing**: Never use `if "compare" in text:` or `if "กล้อง" in query:` to route user intent, match categories, or select items.
   - ❌ **No Keyword Locking in Prompts & Schemas**: Never hardcode lists of canned user phrases, rigid sentence templates, or specific Thai keywords into system prompts, Pydantic field descriptions, or routing instructions (e.g., listing `"ทำไรได้"`, `"ช่วยอะไรได้บ้าง"`, `"คุณคือใคร"`, `"ยืมหน่อยคืออะไร"`, `"เช่ายังไง"`, or `"อยากเช่าคอม"`, `"อยากเช่ากล้อง"`).
     - *Technical Rationale & Anti-Bias*: Locking specific phrases in prompts introduces strong attention bias into the LLM, causing overfitting to exact wording while failing on colloquial, regional, or creative phrasing. This creates artificial behavioral bias and contradicts AI-Native semantic reasoning.
   - ✅ **Pure Semantic Intent Definitions (นิยามเจตนาเชิงความหมาย)**:
     - Prompts, schema docstrings, and Pydantic field descriptions must be framed entirely around **communicative purpose (เป้าหมายการสื่อสาร)**, **information completeness (ความครบถ้วนของข้อมูล)**, and **conceptual hierarchy (ลำดับชั้นเชิงมโนทัศน์)**.
     - Classify by *intent state* (e.g., "inquiries regarding bot identity, capabilities, platform onboarding, or rental FAQ", "broad category-level queries lacking specific model names", "comparisons across 2+ equipment models").
     - All semantic routing and entity extraction must be performed via **AI-Native Structured Reasoning** (`generate_structured` with Pydantic schemas) grounded on conceptual definitions.

2. **NO Regular Expressions**:
   - ❌ Never use `re.search()`, `re.findall()`, or regex patterns for intent routing, slot extraction, or ambiguity detection.
   - ✅ Extract entities (`target_items`, `categories`, `budget_max`, `intended_use`, `missing_slots`) through guided LLM decoding.

3. **NO Hardcoded Values & Logic (Strictly Zero-Hardcode Policy)**:
   - ❌ **No Hardcoded Configurations / Secrets**: Never hardcode API keys, URLs, endpoints, IP addresses, ports, database credentials, timeouts, retry counts, or model names in the source code.
     - ✅ Must always inject configuration via `Settings` (`app/core/config.py`) loaded from `.env` through `pydantic-settings` (e.g., `GROQ_API_KEY`, `SUPABASE_KEY`, `TAVILY_API_KEY`).
   - ❌ **No Hardcoded Catalog / Inventory Data**: Never hardcode item catalogs, item IDs, category lists, technical specifications, or rental prices into code or static prompt strings.
     - ✅ Item inventory and category lists must be retrieved dynamically from Supabase (`item_tb`) or `MemoryCacheService`.
   - ❌ **No Hardcoded Dialogues / Canned Responses / Fallbacks**: Never hardcode canned assistant responses, static greetings, clarification questions, or interactive button options/chips.
     - ✅ All user-facing dialogues, clarification questions, and interactive choices must be synthesized dynamically by the LLM using Structured Output grounded on real database context.
   - ❌ **No Hardcoded Decision Trees / Business Rules**: Never use static `if/else` or dictionary lookups to simulate business logic (e.g., `if category == "Camera": ...` or hardcoded intent-to-action routing).
     - ✅ Rely on LLM Semantic Reasoning and Clean Architecture Use Cases / Domain Entities for semantic decisions.
   - ❌ **No Mock / Dummy Data in Production Flow**: Never inject mock data, dummy items, or hardcoded fallback returns into the Application or Infrastructure layers to bypass external dependencies.
     - ✅ If an external system or service fails, rely on structured exception handling and domain-level error handling following Clean Architecture.

4. **Groq Cloud Inference & User-Authorized Billing**:
   - ❌ Never configure, enforce, or assume local Ollama (`http://localhost:11434`) or local hardware VRAM execution.
   - ✅ Use Groq Cloud via `GROQ_API_KEY` on the user's selected Free or Developer plan. Configure the monthly spend limit in Groq Console; provider billing updates may lag, so this is not an exact cost guarantee.
   - ✅ Use the approved stage order in `config/ai_runtime.json`. Keep the Production writer/reviewer pair first; qualify the user-authorized Qwen Preview fallback with real structured chat and review before enabling it. Retain qualification evidence and keep model-order measurement status truthful.
   - ✅ Preserve distinct writer/reviewer model IDs; if only one model is available, return a structured error within the configured deadline.

### ⚖️ STRICT NEUTRALITY & ZERO-BIAS POLICY

Any algorithm, prompt design, ranking logic, recommendation engine, or response synthesis in this service **MUST strictly adhere** to the following anti-bias rules:

1. **NO Brand & Merchant Favoritism**:
   - ❌ **No Brand Bias**: Never favor, boost, or denigrate any brand (e.g., Apple vs Samsung, Sony vs Canon) based on subjective preference or brand prestige.
   - ❌ **No Commercial / Margin Favoritism**: Never prioritize items based on higher rental prices, profitability, merchant identity, or commercial incentives.
   - ✅ **Objective Match**: Recommend items solely based on semantic alignment with user needs, stated budget, verified specifications, and actual availability in `item_tb`.

2. **NO Exaggerated Claims & Marketing Fluff**:
   - ❌ Never use exaggerated marketing buzzwords or unsubstantiated claims ("best in the world", "flawlessly superior to all brands", "terrible model, do not rent").
   - ❌ Never conceal or downplay hardware limitations, trade-offs, or downsides of recommended equipment.
   - ✅ Present fair, balanced, and objective pros and cons grounded in verified technical specifications.

3. **Unbiased Catalog & External Comparisons**:
   - ❌ Never denigrate or unfairly diminish out-of-catalog or competitor models simply to push items that are currently in stock.
   - ✅ If an out-of-catalog device is objectively better suited for the user's specific workflow, acknowledge its strengths honestly and impartially, while politely stating the shop's inventory status without forceful cross-selling.

4. **Algorithmic Fairness & Code-Level Objectivity**:
   - ❌ Never hardcode heuristic ranking boosts, tie-breaker favoritism, or algorithmic weights biased toward specific brands, price tiers, or item owners.
   - ✅ All scoring, sorting, and filtering in use cases (`QueryItemsUseCase`, `CompareItemsUseCase`, etc.) must be explainable, transparent, and purely driven by user constraints (`budget_max`, `intended_use`, `categories`, and semantic similarity).

---

## 3. Clean Architecture Structure

The codebase strictly follows Clean Architecture principles. Dependencies point **inwards only**:

```
Domain (Pure Python)
  ▲
  │
Application (Use Cases, DTOs, Services)
  ▲
  │
Infrastructure (Adapters: DB, LLM, Search, Cache) & Interface (FastAPI Controllers)
```

### Layer Responsibilities:

- **`app/domain/` (Core Enterprise Business Rules)**:
  - Contains domain models and pure entities: `Item`, `ChatMessage`, `IntentDecision`, `ComparisonMatrix`, `ClarificationQuestion`.
  - Defines abstraction ports (Protocols / Abstract Base Classes): `ItemRepositoryInterface`, `LLMServiceInterface`, `SearchServiceInterface`, `CacheServiceInterface`.
  - ⚠️ **Strict Rule**: Zero dependencies on frameworks (No FastAPI, No HTTP libraries, No DB drivers).

- **`app/application/` (Application Business Rules)**:
  - Use cases implemented with Single Responsibility Principle (SRP):
    - `RouteIntentUseCase`: Classifies user semantic intent and calculates ambiguity without keywords.
    - `QueryItemsUseCase`: Performs semantic catalog matching and ranking against Supabase items.
    - `CompareItemsUseCase`: Coordinates internal catalog data, Tavily web search, fact verification, and grounded comparison synthesis.
    - `GenerateClarificationUseCase`: Builds clarifying questions and interactive choices for vague inputs.
    - `ProcessChatMessageUseCase`: Master orchestrator coordinating intent routing and execution.
  - Domain services:
    - `FactVerificationService`: Filters out search spam, advertisements, and clickbaits; verifies consistency of technical specs.
  - Data Transfer Objects (DTOs): `chat_dto.py`, `item_dto.py`, `comparison_dto.py`, `clarification_dto.py`.

- **`app/infrastructure/` (Frameworks & Drivers)**:
  - `SupabaseRepository`: Interacts asynchronously with Supabase PostgREST endpoint for `item_tb`.
  - `LLM Adapter` (`GroqClient` via `CascadeLLMService`): Uses `GROQ_API_KEY` for strict JSON schema generation. SSE reports progress and publishes the buffered answer after validation and independent review.
  - `TavilyClient`: Asynchronous client for Tavily Search API.
  - `MemoryCacheService`: In-memory TTL cache for the 33-item catalog to minimize DB roundtrips.
  - `prompt_templates.py`: Structured system instructions in Thai for the model.

- **`app/interface/` (Presentation & Delivery)**:
  - `app/interface/api/endpoints/`:
    - `chat.py`: `POST /api/chat` (Full JSON response) and `POST /api/chat/stream` (SSE tokens).
    - `items.py`: `GET /api/items` (Catalog list).
    - `health.py`: `GET /health` (Cloud LLM [Groq], Supabase, and Tavily health checks).
  - `app/interface/schemas/`: Pydantic request and response schemas for web APIs.

- **`app/core/` (Cross-Cutting Concerns)**:
  - `config.py`: Type-safe settings via Pydantic BaseSettings.
  - `container.py`: Dependency injection container wiring ports to adapters.
  - `logging.py`: Structured console logging.
  - `exceptions.py`: Custom domain exceptions.

---

## 4. Key Workflows & Operational Logic

### 4.1 Fact-Checking & Comparison Flow

When users ask to compare rental items:

1. **Catalog Retrieval**: Use semantic entity matching (`QueryItemsUseCase`) to retrieve matching items from `item_tb`.
2. **Search Query Generation**: Formulate a targeted technical search query.
3. **Web Search**: Query Tavily Search API for verified web search results.
4. **Fact Verification Engine (`FactVerificationService`)**:
   - The LLM parses raw snippets and filters out promotional fluff, spam, and irrelevant models.
   - Cross-checks technical specifications (sensor, resolution, ports, battery, weight).
   - Generates a verified `ComparisonMatrix` with credible sources and verified specs.
5. **Grounded Synthesis**: Produces a balanced Thai response highlighting actual shop rental prices, item availability in `item_tb`, and situational recommendations.

### 4.2 Interactive Clarification Flow

When the user query is underspecified or ambiguous (e.g., _"อยากได้คอมทำงาน"_, _"ขอยืมกล้องหน่อย"_):

1. `RouteIntentUseCase` evaluates `ambiguity_level >= 0.5` and identifies `missing_slots`.
2. `GenerateClarificationUseCase` reads available shop categories from cache.
3. The LLM generates:
   - A polite, concise Thai clarifying question.
   - 3 to 4 actionable choices (`ChoiceOption` with `id`, `label`, `description`, `action_value`).
4. The client (Flutter Mobile App) renders these options as interactive chips or buttons.

---

## 5. Coding Standards & Conventions

1. **Python Version**: Always write Python 3.12 compliant code.
2. **Async-First**: All network operations (Supabase, Tavily, Cloud LLM API: Groq, GitHub) must be asynchronous using `httpx.AsyncClient` or native async primitives. Never block the event loop with synchronous I/O.
3. **Typing**: Use standard Python type annotations (`typing.List`, `typing.Optional`, `typing.Dict`, `typing.Tuple`).
4. **Pydantic v2**: Use `model_validate_json()`, `model_dump()`, and `model_json_schema()`. Avoid deprecated Pydantic v1 methods.
5. **Virtual Environment**:
   - Location: `e:\Projects\Mobiles\Flutter\ai_service\.venv`
   - Python executable: `.venv\Scripts\python.exe`
6. **Strictly Zero-Hardcode Policy**:
   - Never write static system constants (API keys, URLs, credentials), item/catalog data, canned dialogue responses, or static business rules into the codebase. All behavior must be configuration-driven (`.env`), dynamically retrieved from Supabase (`item_tb`), and evaluated via AI-Native Semantic Reasoning.
7. **Strict Neutrality & Zero-Bias**:
   - Maintain 100% technical objectivity across all prompts, use cases, and ranking logic. Never steer users based on commercial incentives, brand loyalty, or subjective bias.

---

## 6. Execution & Testing Commands

- **Run Server**:
  ```powershell
  python main.py
  # or
  .\.venv\Scripts\python.exe main.py
  ```
- **API Documentation**:
  Access Swagger UI at `http://localhost:8000/docs`

- **Run Test Suites**:
  ```powershell
  .\.venv\Scripts\python.exe -m pytest tests/ -v
  ```
