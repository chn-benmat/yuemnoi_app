# 🤖 AI Service: ยืมหน่อย AI Rental Consultant (FastAPI)

สถานะล่าสุดหลังผู้ใช้อนุมัติขั้นที่เหลือ: ใช้ structured fast path และข้อมูลจาก
`knowledge/app_knowledge.json`, `knowledge/interpretation_policy.json`,
`config/ai_runtime.json`, `config/chat_client_runtime.json` runtime v7 แก้ circuit จากคำตอบผิด schema
และตรวจ generation permission ก่อนรับแชต เปิด Gemini หลักไว้; โมเดลสำรอง Google ยังปิด
รายงานปัจจุบันอยู่ใน [evaluation/step5_fifteen_request_followup_report.md](evaluation/step5_fifteen_request_followup_report.md)
โหลดล่าสุดส่งคำตอบสำเร็จ 9/15 ยังไม่ครบ 15 และมี semantic errors รายงาน runtime v6 และก่อนหน้าเก็บเป็นประวัติ
ยังไม่มี 95% certificate หรือ UI p95 certificate และยังไม่ผ่านเกณฑ์ทดสอบสำหรับ release
รายละเอียด Step 1–6 ด้านล่างเป็นประวัติการพัฒนา pipeline เดิม ให้ใช้รายงานล่าสุดตัดสินสถานะ

[![Python](https://img.shields.io/badge/Python-3.12-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.115+-009688?style=for-the-badge&logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Google Gemini](https://img.shields.io/badge/Gemini-Primary%20Cloud-4285F4?style=for-the-badge&logo=google&logoColor=white)](https://ai.google.dev)
[![Groq](https://img.shields.io/badge/Groq-Fallback%20Cloud-F55036?style=for-the-badge&logo=fastapi&logoColor=white)](https://groq.com)
[![Tavily](https://img.shields.io/badge/Tavily-Fact%20Verification-4A90E2?style=for-the-badge)](https://tavily.com)

ไมโครเซอร์วิสผู้ช่วยอัจฉริยะ **ยืมหน่อย AI (Rental Consultant)** พัฒนาด้วย **Python 3.12** และ **FastAPI** ภายใต้สถาปัตยกรรม **Clean Architecture** ทำหน้าที่ให้คำปรึกษา แนะนำอุปกรณ์ เปรียบเทียบสเปก และตอบข้อซักถามของผู้ใช้งาน โดยเชื่อมต่อกับคลังสินค้าจริงใน Supabase (`item_tb`) และตรวจสอบข้อมูลทางเทคนิคภายนอกผ่าน Tavily Search API

---

## 📑 สารบัญ (Table of Contents)

1. [สถาปัตยกรรม Clean Architecture](#-สถาปัตยกรรม-clean-architecture)
2. [หลักการและข้อกำหนดเข้มงวด (Strict Architectural Policies)](#-หลักการและข้อกำหนดเข้มงวด-strict-architectural-policies)
3. [กลไก Dual-Cloud Cascade Failover](#-กลไก-dual-cloud-cascade-failover)
4. [โครงสร้างไดเรกทอรี (Directory Structure)](#-โครงสร้างไดเรกทอรี-directory-structure)
5. [โฟลว์การทำงานสำคัญ (Core Workflows)](#-โฟลว์การทำงานสำคัญ-core-workflows)
6. [ข้อกำหนดเบื้องต้นและการติดตั้ง (Getting Started)](#-ข้อกำหนดเบื้องต้นและการติดตั้ง-getting-started)
7. [การตั้งค่า Environment Variables](#-การตั้งค่า-environment-variables)
8. [API Endpoints Reference](#-api-endpoints-reference)
9. [การทดสอบ (Testing)](#-การทดสอบ-testing)

---

## 🏛️ สถาปัตยกรรม Clean Architecture

โค้ดทั้งหมดปฏิบัติตามหลัก Clean Architecture โดยความสัมพันธ์ของการเรียกใช้งานจะชี้ **เข้าสู่ด้านใน (Inward Only)** เท่านั้น:

```text
Domain (Pure Python)
  ▲
  │
Application (Use Cases, Domain Services, DTOs)
  ▲
  │
Infrastructure (Adapters: LLM, Tavily, Supabase, Cache) & Interface (FastAPI Controllers)
```

- **`app/domain/`**: แกนกลางธุรกิจ (Pure Python Entities) ปราศจากการพึ่งพา Framework เช่น `Item`, `ChatMessage`, `IntentDecision`, `ComparisonMatrix`, `ClarificationQuestion` และ Interface Ports (`LLMServiceInterface`, `ItemRepositoryInterface`, `SearchServiceInterface`, `CacheServiceInterface`)
- **`app/application/`**: Use Cases ตามหลัก Single Responsibility Principle (SRP):
  - `RouteIntentUseCase`: จำแนกเจตนาและความคลุมเครือของผู้ใช้โดยไม่ใช้ Keyword
  - `QueryItemsUseCase`: ค้นหาและจับคู่อุปกรณ์จากคลังสินค้าด้วยความหมายเชิงบริบท
  - `CompareItemsUseCase`: ประสานงานเปรียบเทียบอุปกรณ์ ตรวจสอบข้อเท็จจริง และสังเคราะห์ผลลัพธ์
  - `GenerateClarificationUseCase`: สร้างคำถามเจาะจงและปุ่มตัวเลือกตอบ (Actionable Choices)
  - `ProcessChatMessageUseCase`: ตัวควบคุมลำดับงานหลัก (Master Orchestrator)
- **`app/infrastructure/`**: จัดการเชื่อมต่อกับระบบภายนอก:
  - `llm/`: จัดการสลับโมเดล Dual-Cloud ระหว่าง Google Gemini และ Groq Cloud
  - `search/`: ดึงข้อมูลเปรียบเทียบผ่าน Tavily Search API
  - `database/`: เชื่อมต่อ Supabase เพื่ออ่านรายการสินค้า
  - `cache/`: In-Memory Catalog Cache (TTL 300 วินาที) ลดโหลดฐานข้อมูล
- **`app/interface/`**: รับคำขอผ่าน REST API และ SSE Streaming

---

## 🚫 หลักการและข้อกำหนดเข้มงวด (Strict Architectural Policies)

### 1. นโยบายไร้คีย์เวิร์ด ไร้ Regex ไร้การฮาร์ดโค้ด (Zero-Regex, Zero-Keyword, Zero-Hardcode)
- **ห้ามจับคู่คีย์เวิร์ด (Zero-Keyword Policy)**: ไม่ใช้คำสั่ง `if "กล้อง" in text:` หรือ `if "compare" in text:` ในโค้ด และไม่ฮาร์ดโค้ดลิสต์ประโยคตัวอย่างลงใน System Prompt ทุกอย่างต้องวิเคราะห์ด้วย AI Semantic Intent และ Pydantic Schema
- **ห้ามใช้ Regular Expressions (No Regex)**: ไม่ใช้ `re.search()` หรือ Pattern ใดๆ ในการสกัด Entities หรือความคลุมเครือ
- **ห้ามฮาร์ดโค้ดข้อมูล (Strictly Zero-Hardcode Policy)**: ห้ามใส่ค่าคงที่ แคตตาล็อกสินค้า หรือคำตอบสำเร็จรูป (Canned Responses) ลงในโค้ด ข้อมูลสินค้าต้องดึงสดจาก Supabase และคำตอบต้องสร้างขึ้นตามบริบทจริง

### 2. นโยบายความเป็นกลาง 100% (Strict Neutrality & Zero-Bias)
- **ไม่เอนเอียงตามแบรนด์หรือร้านค้า**: แนะนำสินค้าตามความสอดคล้องกับความต้องการของผู้ใช้และงบประมาณอย่างเป็นกลาง
- **ระบุข้อดี-ข้อเสียตามจริง**: แสดงจุดเด่นและข้อจำกัดของอุปกรณ์ตามสเปกทางเทคนิคที่ผ่านการตรวจสอบแล้ว โดยไม่มีการโฆษณาเกินจริง
- **การเปรียบเทียบกับภายนอก**: หากอุปกรณ์นอกร้านมีความเหมาะสมกับงานของผู้ใช้มากกว่า ให้ระบุตามจริงอย่างสุภาพโดยไม่กดดันให้เช่าสินค้าในร้าน

### 3. ระบบคลาวด์ฟรี 100% (100% Free Cloud API Policy)
- ไม่พึ่งพา Local Ollama หรือ GPU ในเครื่องของผู้ใช้
- ใช้บริการคลาวด์ระดับฟรีโดยไม่ต้องผูกบัตรเครดิต (Google Gemini Free Tier & Groq Cloud Free Tier)

---

## ⚡ กลไก Dual-Cloud Cascade Failover

ระบบมีระบบสำรองคู่ขนาน (Cascade Failover) รับประกันความพร้อมใช้งานสูง (High Availability):

```mermaid
flowchart TD
    Request["คำขอจากผู้ใช้"] --> GeminiPrimary["Google Gemini Primary<br/>(gemini-3.5-flash-lite)"]
    GeminiPrimary -->|สำเร็จ| Success["ส่งคำตอบ"]
    GeminiPrimary -->|Rate Limit / ข้อผิดพลาด| GeminiFallback1["Gemini Fallback 1<br/>(gemini-3.1-flash-lite)"]
    GeminiFallback1 -->|สำเร็จ| Success
    GeminiFallback1 -->|ข้อผิดพลาด| GeminiFallback2["Gemini Fallback 2<br/>(gemini-flash-lite-latest)"]
    GeminiFallback2 -->|สำเร็จ| Success
    GeminiFallback2 -->|Gemini ล่มทั้งหมด| GroqPrimary["Groq Cloud Primary<br/>(qwen/qwen3.8-27b)"]
    GroqPrimary -->|สำเร็จ| Success
    GroqPrimary -->|ข้อผิดพลาด| GroqFallback1["Groq Fallback 1<br/>(openai/gpt-oss-120b)"]
    GroqFallback1 -->|สำเร็จ| Success
    GroqFallback1 -->|ข้อผิดพลาด| GroqFallback2["Groq Fallback 2<br/>(openai/gpt-oss-20b)"]
    GroqFallback2 -->|สำเร็จ| Success
    GroqFallback2 -->|ล้มเหลวทั้งหมด| ErrorResponse["ตอบกลับข้อผิดพลาดอย่างปลอดภัย"]
```

---

## 📁 โครงสร้างไดเรกทอรี (Directory Structure)

```text
ai_service/
├── app/
│   ├── application/
│   │   ├── dtos/                # Data Transfer Objects (chat, item, clarification)
│   │   ├── services/            # FactVerificationService (กรองสแปม ตรวจสอบสเปก)
│   │   └── use_cases/           # Intent Routing, Item Querying, Comparison, Clarification
│   ├── core/
│   │   ├── config.py            # การอ่าน Environment Variables ผ่าน Pydantic Settings
│   │   ├── container.py         # Dependency Injection Container เชื่อม Port กับ Adapter
│   │   ├── exceptions.py        # Custom Domain Exceptions
│   │   └── logging.py           # Structured Logging Setup
│   ├── domain/
│   │   ├── entities/            # Pydantic Domain Models
│   │   └── interfaces/          # Protocol / ABC Interfaces
│   ├── infrastructure/
│   │   ├── cache/               # In-memory TTL Cache Service
│   │   ├── database/            # Supabase PostgREST Client Adapter
│   │   ├── llm/                 # GeminiClient, GroqClient, MultiProviderLLMService
│   │   ├── prompts/             # Prompt Templates ภาษาไทย
│   │   └── search/              # TavilyClient Adapter
│   └── interface/
│       ├── api/v1/
│       │   ├── endpoints/       # chat.py, items.py, health.py
│       │   └── router.py        # API Router Grouping
│       └── schemas/             # Pydantic Request & Response Schemas
├── tests/                       # Unit & Integration Tests (pytest, pytest-asyncio)
├── requirements.txt             # Python Package Dependencies
└── main.py                      # จุดเริ่มต้นรันเซิร์ฟเวอร์ FastAPI (Port 8000)
```

---

## 🔄 โฟลว์การทำงานสำคัญ (Core Workflows)

### 1. โฟลว์การเปรียบเทียบอุปกรณ์และตรวจสเปก (Fact-Checking & Comparison)
1. **Catalog Retrieval**: ค้นหาอุปกรณ์ที่เกี่ยวข้องจาก `item_tb`
2. **Search Query Generation**: สร้างข้อความค้นหาสเปกเชิงลึกอัตโนมัติ
3. **Web Search**: ค้นหาผลลัพธ์ผ่าน Tavily Search API
4. **Fact Verification Engine**: LLM ตรวจสอบและตัดโฆษณาแฝง สกัดสเปกจริง (เช่น เซนเซอร์, ความละเอียด, พอร์ตเชื่อมต่อ, น้ำหนัก)
5. **Grounded Synthesis**: เรียบเรียงคำตอบเป็นภาษาไทย เปรียบเทียบราคาเช่าในร้านกับความคุ้มค่า

### 2. โฟลว์ถามกลับเมื่อข้อมูลไม่ชัดเจน (Interactive Clarification)
1. ตรวจพบว่าคำถามคลุมเครือ (`ambiguity_level >= 0.5`)
2. ดึงหมวดหมู่สินค้าจริงในร้านจาก Cache
3. สังเคราะห์คำถามเจาะจง พร้อมตัวเลือก 3-4 ข้อ (`ChoiceOption` ที่มี `id`, `label`, `description`, `action_value`)
4. ฝั่ง Flutter นำตัวเลือกไปแสดงเป็นปุ่มกด Interactive Chips ให้ผู้ใช้แตะเลือกได้ทันที

---

## 📋 ข้อกำหนดเบื้องต้นและการติดตั้ง (Getting Started)

### ข้อกำหนด
- **Python**: เวอร์ชัน `3.12`
- API Key สำหรับ **Google Gemini** (Google AI Studio)
- API Key สำหรับ **Groq Cloud**
- API Key สำหรับ **Tavily Search**

### ขั้นตอนการติดตั้งและรันเซิร์ฟเวอร์

```bash
cd ai_service

# 1. สร้าง Virtual Environment
python -m venv .venv

# 2. เปิดใช้งาน Virtual Environment
# Windows:
.\.venv\Scripts\activate
# macOS / Linux:
# source .venv/bin/activate

# 3. ติดตั้ง Dependencies
pip install -r requirements.txt

# 4. เริ่มต้นรันเซิร์ฟเวอร์
python main.py
```
> เซิร์ฟเวอร์จะรันที่ `http://localhost:8000` (เข้าดูเอกสาร API ได้ที่ `http://localhost:8000/docs`)

---

## ⚙️ การตั้งค่า Environment Variables

สร้างไฟล์ `.env` ในโฟลเดอร์ `ai_service/`:

```env
# แอปพลิเคชัน
APP_NAME="Yuemnoi AI Service"
APP_ENV=production
LOG_LEVEL=INFO
CACHE_TTL_SECONDS=300
HTTP_TIMEOUT_SECONDS=30.0

# ฐานข้อมูลและการยืนยันสิทธิ์ภายในระบบ
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your-supabase-service-role-or-anon-key
INTERNAL_SERVICE_KEY=your-internal-shared-service-key-32chars

# กุญแจ API ผู้ให้บริการ AI (ฟรี 100%)
GEMINI_API_KEY=your-google-gemini-api-key
GROQ_API_KEY=your-groq-cloud-api-key
TAVILY_API_KEY=your-tavily-search-api-key

# ลำดับโมเดลสำรอง (Cascade Models)
GEMINI_PRIMARY_MODEL=gemini-3.5-flash-lite
GEMINI_FALLBACK_MODEL_1=gemini-3.1-flash-lite
GEMINI_FALLBACK_MODEL_2=gemini-flash-lite-latest

GROQ_PRIMARY_MODEL=qwen/qwen3.8-27b
GROQ_FALLBACK_MODEL_1=openai/gpt-oss-120b
GROQ_FALLBACK_MODEL_2=openai/gpt-oss-20b
```

---

## 🌐 API Endpoints Reference

### `GET /health`
ตรวจสอบสถานะของระบบย่อยทั้งหมด (Gemini, Groq, Supabase, Tavily):
```json
{
  "status": "healthy",
  "gemini": "ok",
  "groq": "ok",
  "supabase": "ok",
  "tavily": "ok"
}
```

### `GET /api/v1/items`
ดึงรายการอุปกรณ์ให้เช่าทั้งหมดที่บันทึกอยู่ใน In-Memory Cache

### `POST /api/v1/chat`
ส่งข้อความสนทนาและรับผลลัพธ์เป็น JSON สมบูรณ์ (รวมถึงข้อความตอบกลับ, รายการสินค้าที่แนะนำ และตัวเลือก Clarification)

### `POST /api/v1/chat/stream`
สตรีมคำตอบของ AI แบบ Server-Sent Events (SSE) เหมาะสำหรับแอปพลิเคชันมือถือที่ต้องการแสดงผลข้อความพิมพ์สดแบบเรียลไทม์

ทุกข้อความใช้ deadline รวม 30 วินาทีตาม runtime ที่ผู้ใช้อนุมัติ เวลาขั้น planning/evidence/review และ fallback ใช้งบเดียวกัน ไม่เริ่มนับใหม่เมื่อเปลี่ยน flow เมื่อคำตอบผ่านการตรวจครบและตรวจคลังล่าสุดแล้ว จะส่ง event `ready` พร้อม payload ฉบับเต็มก่อน `metadata`/`delta` และ `done` ที่มี payload เดียวกัน Client รุ่นเดิมยังอ่าน events เดิมได้ รุ่นใหม่วัดจาก interaction ที่ส่งคำขอถึงได้รับและ parse `ready` ครบ ไม่รวมเวลาส่งตัวอักษรหรือ render ต่อจากนั้น หากคำตอบพร้อมก่อนให้ส่งทันที โดยไม่รอขั้นต่ำ 15 วินาที

---

## 🧪 การทดสอบ (Testing)

รันชุดการทดสอบทั้งหมดผ่าน `pytest`:

```bash
# Windows
.\.venv\Scripts\python.exe -m pytest tests/ -v

# macOS / Linux
pytest tests/ -v
```

ชุดการทดสอบครอบคลุม:
- `test_use_cases.py`: ทดสอบการจำแนกเจตนา (Intent Routing), การจับคู่อุปกรณ์ และการสร้างตัวเลือก Clarification
- `test_model_cascade.py`: ทดสอบกลไกการสลับผู้ให้บริการเมื่อ Primary Provider ไม่พร้อมใช้งาน
- `test_api_endpoints.py`: ทดสอบ Integration ระดับ API Endpoint ผ่าน TestClient

## แหล่งความรู้แอปที่ตรวจอนุมัติได้ (Step 2)

ร่างเนื้อหาและหลักฐานอยู่ใน [knowledge/review.md](knowledge/review.md) ข้อมูลที่ตัวอ่านใช้จริงอยู่ใน [knowledge/app_knowledge.json](knowledge/app_knowledge.json) วิธีตั้งค่า `APP_KNOWLEDGE_PATH` และขั้นตอนอนุมัติอยู่ใน [knowledge/README.md](knowledge/README.md)

ตัวอ่านแยกจากการวิเคราะห์เจตนา โหลดข้อมูลแบบ async และส่งออกเฉพาะรายการที่มีสถานะ approved พร้อม metadata ที่ตรงกับเนื้อหา เมื่อแก้เนื้อหาหลังอนุมัติหรือไฟล์ไม่ถูกต้องจะปฏิเสธข้อมูล ไม่มี keyword routing หรือคำตอบสำเร็จรูปในตัวอ่าน

เจ้าของอนุมัติข้อเท็จจริง 12 รายการแล้ว ส่วน 10 หัวข้อที่ขาดหลักฐานคงเป็น unverified และยังไม่เชื่อมเข้าสู่การตอบแชท การอนุมัติขั้นงานไม่ใช่การอนุมัตินโยบายหรือข้อเท็จจริงโดยอัตโนมัติ ผลตรวจ Step 2 อยู่ใน [knowledge/step2_report.md](knowledge/step2_report.md)

## การวิเคราะห์เจตนาและบริบท (Step 3)

Router ใช้ RequestUnderstanding แยก request_scope, information_sufficient และ next_action เก็บประวัติทั้งข้อความ/แบบสอบถามแบบมีโครงสร้างตาม context limits ที่ตั้งค่าได้ ทั้ง JSON/SSE ใช้ action เดียวกัน ผลวัดและข้อจำกัดอยู่ใน [evaluation/step3_report.md](evaluation/step3_report.md) ฉบับแก้หลังวัดผ่าน tests ในเครื่อง แต่ยังไม่ได้วัดกับโมเดลจริงซ้ำ จึงยังยืนยัน 95% ไม่ได้

## แบบสอบถามและการเลือกสินค้า (Step 4)

สร้างคำถามเฉพาะข้อมูลที่ยังจำเป็น 1–3 ข้อ ช้อยไม่เกิน 4 ข้อ และเลือกสินค้าเชิงความหมายจากคลังจริงโดยไม่มี keyword/scoring fallback มี structured validation กับ semantic review ตรวจ ID ข้อมูลที่ทราบ งบ/หน่วยราคา และสถานะ ก่อนอ่านหลักฐานจากคลังอีกครั้งเพื่อป้องกันข้อมูลเก่า ดู configuration ผล smoke และข้อจำกัดใน [evaluation/step4_report.md](evaluation/step4_report.md) ยังไม่ประเมินผ่าน 95% และรอ Step 5 สำหรับ structured response ร่วมกับ Go/Flutter
# Structured chat and current-session context

JSON and SSE share one validated result. Optional `session_id`, `context`,
`questionnaire_answers` (`question_id` with either `option_id` or `text`), and
`questionnaire_skipped` preserve the current conversation without account memory.
Responses include optional `context` and `references`; legacy fields/events remain.
Client context cannot establish prices, stock, policies or approval.

Set `APP_KNOWLEDGE_PATH=knowledge/app_knowledge.json` from the AI service working
directory, or supply another configured document path. Missing/invalid/revoked
knowledge fails closed. Supported app-only answers and mixed clarification answers
project approved article content by ID rather than free-form app claims.
SSE emits heartbeat comments during generation and publishes text/cards after
validation. See [Step 5 report](evaluation/step5_report.md) for verification and limitations.

## การประเมินก่อนส่งมอบ (Step 6)

ผลล่าสุดและข้อจำกัดอยู่ใน [evaluation/step6_report.md](evaluation/step6_report.md)
สถานะยังเป็น incomplete ไม่รับรอง 95% และไม่อนุมัติใช้งานจริง

`evaluation/acceptance.py` รันโมเดลจริงแยก router, chat และ fairness มีชุด heldout
120 กรณี หกกลุ่ม กลุ่มละ 20 สามรอบ และ counterfactual fixture 30 กรณี ข้อคาดหวัง
และหมายเหตุผู้ตรวจไม่ส่งเข้า production prompts รายงานแยกกลุ่ม/รอบ บันทึก source hashes,
provider/model, HTTP statuses และเวลา โดยไม่เก็บ credentials หรือ private provider bodies
จำนวน token ยังไม่ทราบเพราะ adapter ปัจจุบันไม่ส่ง usage กลับมา

รันจาก `ai_service` และเลือกชื่อรายงานใหม่เสมอเพื่อเก็บหลักฐานเก่า:

```powershell
.venv/Scripts/python.exe -m evaluation.acceptance --config evaluation/step6_config.json
.venv/Scripts/python.exe -m evaluation.acceptance --config evaluation/step6_config.json --phase router --live --allow-heldout --output evaluation/reports/new-step6-router.json
.venv/Scripts/python.exe -m evaluation.acceptance --config evaluation/step6_config.json --phase chat --live --allow-heldout --output evaluation/reports/new-step6-chat.json
.venv/Scripts/python.exe -m evaluation.acceptance --config evaluation/step6_config.json --phase fairness --live --allow-heldout --output evaluation/reports/new-step6-fairness.json
.venv/Scripts/python.exe -m evaluation.assessment --config evaluation/step6_config.json --router evaluation/reports/new-step6-router.json --chat evaluation/reports/new-step6-chat.json --fairness evaluation/reports/new-step6-fairness.json --output evaluation/reports/new-step6-assessment.json
```

คำสั่งแรกตรวจ fixtures/config โดยไม่เรียก API คำสั่ง live ต้องอนุมัติขั้นประเมินแล้ว
หาก provider ใช้งานไม่ได้หรือถึงงบเวลาหรือจำนวน calls ให้ checkpoint แล้วหยุดด้วยสถานะ
incomplete ไม่ลดเกณฑ์ การรันใหม่เป็นรายงานอีกชุด ไม่รวมผลที่เลือกจากหลายรันให้ครบสามรอบ

`evaluation/assessment.py` ตรวจ hashes และคำนวณคะแนนใหม่จาก decisions กับ labels
รับ `--reviews` เป็น JSON ตาม `ReviewLedger` สำหรับการตรวจคำตอบและเหตุผลของ fairness
โดยผู้ตรวจที่ระบุชื่อ/เวลา พร้อม hash ของ output และ report ที่ตรวจ ไม่มี review หรือ label
ยังไม่อนุมัติจะไม่ให้ pass ดู [ข้อควรตรวจของ label](evaluation/step6_label_review.md)
ก่อนรับรองผล หากนำ heldout ไปปรับ production ต้องจัด heldout ใหม่สำหรับฉบับที่ปรับ

## Conversation fixes (2026-10-04)

Optional `active_question_id` identifies a displayed question from `context.questions`. It does not automatically associate the typed message with that question. Send the raw message and actual completed `questionnaire_answers`; the semantic planner resolves answers, corrections, social turns and topic changes. Legacy requests omit this field.

Rental duration uses the `rental_duration` fact/question dimension, separate from the budget billing period `budget_unit`. Catalog factual prose uses authoritative field references in the internal evidence contract. Post-fix real-provider evaluation reuses the original suite in `ai_service/evaluation/conversation_afterfix_20261004`, with distinct checkpoints and all attempts preserved.

## Reviewed responses and shared quota (2026-10-04)

The fast chat path reviews the exact final response, questionnaire, choices,
suggested replies, cards and references with a different actual model before
publishing. A valid rejection with an exact draft span withholds that response;
there is no additional rewrite loop. This model review is distinct from the
hash-bound Codex evaluation and independent human certification.

Stage routing and budget reservations are configured in `config/ai_runtime.json`.
General turns allow two logical calls within four seconds; equipment and
technical turns allow three within eight and fifteen seconds respectively.
Each logical call retains at most one backup. The current order is explicitly
pending measurements; calibration proposals do not automatically change it.

Main, UI and startup requests share `.state/llm_quota.json` through an OS lock
and atomic writes. `AI_QUOTA_LEDGER_PATH` can specify the shared location; all
processes on the same host must use the same path. Preserve this state across
restarts. Submitted requests with unknown usage remain charged conservatively.
Malformed ledgers or lock failures fail closed rather than resetting quotas.
The local state directory is excluded from Git.

Follow [evaluation/CURRENT.md](evaluation/CURRENT.md) for the active trial.
Diagnostic conversation cases and isolated role measurements retain every
attempt and use separate checkpoints. They do not contribute to qualification
scores. Changing production, runtime, policy or catalog requires a new trial;
do not update hashes to resume an old source snapshot. The original suite,
config and rubric remain unchanged, and qualification still requires actual
360/360 semantic and neutral-voice passes plus all six fresh Flutter flows.
