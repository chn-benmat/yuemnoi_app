<div align="center">

# 🤖 Yuemnoi — AI Service

รายละเอียดการจัดการบริบท การตรวจข้อมูลล่าสุด และผลทดสอบ performance:
[AI pipeline verification](PIPELINE_VERIFICATION.md)

### ระบบ AI ผู้ช่วยอัจฉริยะของแอปพลิเคชัน "ยืมหน่อย"

[![Python](https://img.shields.io/badge/Python-3.12-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.111-009688?style=for-the-badge&logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Qwen](https://img.shields.io/badge/Qwen_3-8B-7C3AED?style=for-the-badge&logo=ollama&logoColor=white)](https://ollama.com/library/qwen3)

<br/>

> **AI Agent Pipeline** ที่ใช้โมเดลภาษา Qwen 3 วิเคราะห์คำถามจากลูกค้า
> ค้นหาอุปกรณ์ในฐานข้อมูล และเสริมข้อมูลสเปคจาก Google Search  
> เพื่อตอบคำถามเรื่องการเช่า/ยืมอุปกรณ์ได้อย่างแม่นยำ

</div>

---

## 📖 ภาพรวมระบบ

AI Service ของ Yuemnoi เป็น **Agentic AI Pipeline** ที่ออกแบบมาเพื่อทำหน้าที่เป็น "ผู้ช่วยอัจฉริยะ" ช่วยลูกค้าค้นหาและเปรียบเทียบอุปกรณ์เช่าในระบบ โดยมีขั้นตอนการทำงานดังนี้:

### 🧠 ขั้นตอนการทำงานของ Pipeline

| ขั้นตอน | ชื่อ                      | รายละเอียด                                                                               |
| :-----: | :------------------------ | :--------------------------------------------------------------------------------------- |
|    ①    | **Intent** | ตีความคำถามและ history ครั้งเดียวเป็นชนิดข้อมูลภายใน; คำทักทาย/ขอบคุณ/ความสามารถที่ชัดเจนตอบทันที |
|    ②    | **Inventory** | จัด candidate จากเจตนา อ่านข้อมูลสด แล้วตรวจงบ หน่วย และสถานะ |
|    ③    | **Specifications** | เรียกค้นสเปคเฉพาะเมื่อจำเป็น แยกข้อมูลเว็บออกจากราคาเช่า |
|    ④    | **Conversation** | โมเดลเลือกสินค้าและเรียบเรียงคำตอบร่วมกัน พร้อม ID และหลักฐาน |
|    ⑤    | **Validation** | ตรวจ ID/หลักฐาน อ่านรายการที่เลือกซ้ำ แล้วสร้างราคาและการ์ดจากข้อมูลชุดเดียวกัน |

---

## 📂 โครงสร้างโปรเจ็ค

```
ai_service/
├── 📄 .env                               # ตัวแปรสภาพแวดล้อม (API Keys, Model Config)
├── 📄 .gitignore                         # ไฟล์ที่ไม่ต้อง Track ใน Git
├── 📄 requirements.txt                   # Python Dependencies
├── 📄 config.py                          # ⚙️ โหลดและจัดการ Configuration ทั้งหมด
├── 📄 main.py                            # 🚀 จุดเริ่มต้น FastAPI Server
│
└── 📁 app/
    ├── 📄 __init__.py
    │
    ├── 📁 agent/                         # 🧠 หน่วยสมองกลางของระบบ AI
    │   └── 📄 executor.py                #    AgentExecutor — ตัวควบคุม Pipeline หลัก
    │
    ├── 📁 llm/                           # 🧠 Ollama native API + structured JSON
    └── 📁 tools/                         # 🔧 เครื่องมือที่ Agent เลือกเรียก
        ├── 📄 database_tool.py           #    DatabaseTool — typed filters + Supabase PostgREST
        └── 📄 google_tool.py             #    GoogleTool — ค้นหาสเปคอุปกรณ์ผ่าน Serper API
```

---

## 🧩 รายละเอียดแต่ละส่วน

### 🚀 `main.py` — FastAPI Server

จุดเริ่มต้นของ AI Service:

- สร้าง **FastAPI** app ชื่อ `yuemnoi AI Core Service`
- ตั้งค่า **CORS** ให้ทุก Origin เข้าถึงได้
- ประกาศ **Pydantic Models** สำหรับ Request Validation:
  - `ChatMessage` — ข้อความแต่ละรายการ (role + content)
  - `ChatRequest` — คำถามใหม่ + ประวัติแชท (max 200 ตัวอักษร)
- รัน `AgentExecutor` เมื่อมี Request เข้ามาที่ `/api/ai/chat`

```python
# Endpoint หลักของ AI Service
@app.post("/api/ai/chat")
async def stream_ai_response(payload: ChatRequest):
    res = await agent_executor.run_pipeline_non_stream(
        user_query, history=chat_history_list
    )
    return res
```

---

### ⚙️ `config.py` — Configuration Manager

ใช้ **Pydantic Settings** โหลดค่าจากไฟล์ `.env` อัตโนมัติ:

| ตัวแปร                  | คำอธิบาย                                           | ค่าตั้งต้น               |
| :---------------------- | :------------------------------------------------- | :----------------------- |
| `SUPABASE_URL`          | URL ของ Supabase Project                           | — (ต้องกำหนด)            |
| `SUPABASE_KEY`          | Service Role Secret Key ของ Supabase (สำหรับจัดการ Feedback / In-Context Learning) | — (ต้องกำหนด)            |
| `SERPER_API_KEY`        | API Key สำหรับ Serper.dev (Google Search)          | — (ต้องกำหนด)            |
| `MODEL_NAME`            | ชื่อโมเดล Ollama ที่ใช้งาน                         | `qwen3:8b`               |
| `OLLAMA_ENDPOINT`       | Native endpoint ของ Ollama                         | `http://localhost:11434` |
| `OLLAMA_CONTEXT_LENGTH` | Context ที่ใช้ต่อ request เพื่อควบคุม VRAM         | `4096`                   |
| `OLLAMA_KEEP_ALIVE`     | ระยะเวลาคงโมเดลไว้ในหน่วยความจำ (`-1` = คงไว้ตลอด) | `-1`                     |
| `MAX_SEARCH_RESULTS`    | จำนวนสินค้าสูงสุดที่ค้นและส่งเข้าโมเดล             | `5`                      |
| `MAX_HISTORY_MESSAGES`  | จำนวนข้อความย้อนหลังสูงสุด                         | `6`                      |

---

### 🧠 `app/agent/executor.py` — AgentExecutor (หัวใจหลัก)

`AgentExecutor` เป็นตัวควบคุม Pipeline ทั้งหมด ภายในฟังก์ชัน `run_pipeline_non_stream()`:

- `app/agent/dialogue.py` กำหนด `Intent`, `Answer`, หลักฐาน และ prompt ร่วมกัน โดยส่งคำถามล่าสุดหลัง history เสมอ
- คำถามที่ต้องตีความเรียกโมเดลหนึ่งครั้ง; หากใช้เครื่องมือเรียกอีกหนึ่งครั้งเพื่อเลือกสินค้าและอธิบาย ไม่มี verifier ที่ตีความคำถามซ้ำ
- จำกัด history 6 ข้อความ ข้อความละ 500 ตัวอักษร, candidate 8 รายการ, คำตอบไม่เกิน 5 รายการ และ deadline รวม 45 วินาที
- Inventory ใช้ catalog cache 60 วินาทีเพื่อจัดอันดับ อ่าน candidate สดก่อนสร้างคำตอบ และอ่าน ID ที่เลือกอีกครั้งก่อนส่ง เพื่อรับราคาที่เปลี่ยนหรือหยุดแสดงสินค้าที่ไม่ว่าง
- มีเครื่องมือเชิงตรรกะสองประเภทคือ inventory และ specifications โดย inventory อาจใช้หลาย HTTP reads สำหรับตรวจความสด ไม่มี agent loop หรือ retry โมเดล
- กรองงบ/สถานะ/หน่วยด้วยโค้ด ไม่กรองความเหมาะสมจาก substring ของชื่อสินค้า; โมเดลเลือกชนิดที่เกี่ยวข้องและอธิบายข้อจำกัดของหลักฐาน
- คำตอบภายในมี `outcome`, `answer`, `item_ids`, `evidence`, `source_urls`; response ภายนอกยังคง envelope เดิม
- ราคา ชื่อ หน่วย และการ์ดมาจากข้อมูลสด ส่วนคำแนะนำเป็นข้อความโมเดล ตรวจ ID, quote หลักฐาน, URL และตัวเลขสเปคก่อนส่ง
- ไม่พบ candidate, ข้อมูลไม่พอยืนยัน และบริการล้มเหลวเป็นคนละสถานการณ์; ไม่ใช้ผลเก่าหรือสินค้าไม่เกี่ยวข้องกลบ error
- ค่าเริ่มต้น `INTERPRETATION_MAX_TOKENS=384`, `CONVERSATIONAL_MAX_TOKENS=512`, `think=False`; ไม่เปลี่ยนโมเดลหรือเพิ่ม streaming
- Log ใช้ request ID, route, จำนวน candidate, outcome, model calls, token counts และเวลารายขั้น ไม่บันทึกข้อความสนทนาปกติ

รายละเอียดผลทดสอบและข้อจำกัดอยู่ใน [PIPELINE_VERIFICATION.md](PIPELINE_VERIFICATION.md)

---

### 🔧 `app/tools/` — เครื่องมือของ Agent

#### `database_tool.py` — DatabaseTool

เครื่องมือค้นหาอุปกรณ์ในฐานข้อมูล Supabase ที่ถูกเรียกโดย Qwen:

1. **Tool Selection** — Qwen ตัดสินใจจากความหมายและประวัติสนทนาโดยไม่มี keyword router
2. **Catalog Grounding** — โหลดชื่อ คำอธิบาย category ราคา สถานะ และหน่วยเช่าจาก `item_tb`
3. **Semantic Matching** — Qwen เทียบความหมายและข้อจำกัดโดยตรง จึงรองรับ category ภาษาไทยและคำพูดหลายรูปแบบโดยไม่ใช้ keyword mapping
4. **Validated IDs** — Pydantic ตรวจโครงสร้างผลลัพธ์และระบบตัด ID ที่ไม่มีอยู่จริงออก
5. **Safe Query** — AI ไม่สามารถส่ง SQL หรือสร้างข้อมูลสินค้าใหม่เองได้

```
คำถาม: "เช่ากล้องราคาไม่เกิน 2,000 บาท"
    ↓ Qwen calls search_inventory
Catalog: [{ id: 9, category: "กล้อง", price: 1500, ... }, ...]
    ↓ Qwen selects only matching catalog IDs
ผลลัพธ์: [{ id: 9, item_name: "กล้อง Sony A7 IV พร้อมเลนส์ 24-70mm", price: 1500, ... }]
```

#### `google_tool.py` — GoogleTool

ค้นหาข้อมูลสเปคและรีวิวจาก Google ผ่าน **Serper.dev API**:

- โฟกัสผลลัพธ์ในประเทศไทย (`gl: th`, `hl: th`)
- ดึง Organic Search Snippets สูงสุด 5 อันดับแรก
- ส่งข้อมูลเป็นบริบทเสริมให้ AI ตอบเรื่องสเปคได้ถูกต้อง

---

## ⚙️ ตัวแปรสภาพแวดล้อม (Environment Variables)

สร้างไฟล์ `.env` ในโฟลเดอร์ `ai_service/` :

```env
# Supabase (ใช้ Service Role Key เพื่อจัดการ Feedback และ In-Context Learning)
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_KEY=eyJhbGciOi... (Service Role Key)

# Google Search (Serper.dev)
SERPER_API_KEY=your_serper_api_key

# Local LLM ผ่าน Ollama
MODEL_NAME=qwen3:8b
OLLAMA_ENDPOINT=http://localhost:11434
OLLAMA_CONTEXT_LENGTH=4096
OLLAMA_KEEP_ALIVE=-1
```

---

## 🚀 วิธีรันโปรเจ็ค

### ข้อกำหนดเบื้องต้น

- [Python](https://www.python.org/downloads/) เวอร์ชัน 3.10 ขึ้นไป
- [Ollama](https://ollama.com/download) สำหรับรันโมเดล Qwen 3 8B ภายในเครื่อง
- API Key จาก [Serper.dev](https://serper.dev/) สำหรับ Google Search

### ติดตั้ง Dependencies

```bash
cd ai_service
python -m venv .venv

# Windows
.venv\Scripts\activate

# macOS / Linux
source .venv/bin/activate

pip install -r requirements.txt
```

### ดาวน์โหลดและรันโมเดล Local ด้วย Ollama

```powershell
ollama pull qwen3:8b
ollama run qwen3:8b --think=false
```

Ollama เปิด API ที่ `http://localhost:11434` โดยค่าเริ่มต้น

### รัน AI Service

```bash
cd ai_service
python main.py
```

เซิร์ฟเวอร์จะรันที่ `http://localhost:8000`

### ทดสอบ API ด้วย cURL

```bash
curl -X POST http://localhost:8000/api/ai/chat \
  -H "Content-Type: application/json" \
  -d '{
    "query": "มีกล้องถ่ายรูปให้เช่าไหม",
    "history": []
  }'
```

---

## 📚 เทคโนโลยีที่ใช้

| เทคโนโลยี             | เวอร์ชัน | วัตถุประสงค์                                              |
| :-------------------- | :------- | :-------------------------------------------------------- |
| **Python**            | 3.10+    | ภาษาหลักในการพัฒนา                                        |
| **FastAPI**           | 0.111.0  | Web Framework สำหรับ API                                  |
| **Uvicorn**           | 0.30.1   | ASGI Server สำหรับรัน FastAPI                             |
| **Pydantic Settings** | 2.2.1    | จัดการ Configuration & Environment Variables              |
| **HTTPX**             | 0.27.0   | HTTP Client แบบ Async/Sync                                |
| **Qwen 3**            | 8B       | โมเดลภาษาสำหรับสร้างคำตอบและ structured filter JSON       |
| **Ollama**            | —        | รัน Qwen 3 8B ภายในเครื่องและให้บริการ API ที่พอร์ต 11434 |
| **Serper.dev**        | —        | Google Search API สำหรับดึงข้อมูลสเปค                     |
| **Supabase**          | —        | ฐานข้อมูล PostgreSQL (ผ่าน REST API)                      |

---

## 🔐 ระบบความปลอดภัย

AI Service มีระบบป้องกันหลายชั้น:

| ชั้น | การป้องกัน            | รายละเอียด                                                       |
| :--: | :-------------------- | :--------------------------------------------------------------- |
|  🛡️  | **Input Validation**  | จำกัดความยาว Query ไม่เกิน 200 ตัวอักษร                          |
|  🛡️  | **Agent Tool Policy** | Qwen ตอบบทสนทนาเองและต้องเรียก tool ก่อนอ้างข้อมูลปัจจุบัน        |
|  🛡️  | **Typed Tools**       | โมเดลส่งได้เฉพาะ arguments ตาม schema และไม่สามารถส่ง SQL มารันได้ |
|  🛡️  | **Bounded Query**     | backend เลือกคอลัมน์และจำกัดผลลัพธ์สูงสุด 5 รายการ               |
|  🛡️  | **Structured Output** | บังคับและตรวจสอบ routing กับคำตอบด้วย Pydantic JSON Schema       |

---
