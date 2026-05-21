<div align="center">

# 🤖 Yuemnoi — AI Service

### ระบบ AI ผู้ช่วยอัจฉริยะของแอปพลิเคชัน "ยืมหน่อย"

[![Python](https://img.shields.io/badge/Python-3.12-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.111-009688?style=for-the-badge&logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Qwen](https://img.shields.io/badge/Qwen_2.5-7B-7C3AED?style=for-the-badge&logo=huggingface&logoColor=white)](https://huggingface.co/Qwen)

<br/>

> **AI Agent Pipeline** ที่ใช้โมเดลภาษา Qwen 2.5 วิเคราะห์คำถามจากลูกค้า  
> ค้นหาอุปกรณ์ในฐานข้อมูล และเสริมข้อมูลสเปคจาก Google Search  
> เพื่อตอบคำถามเรื่องการเช่า/ยืมอุปกรณ์ได้อย่างแม่นยำ

</div>

---

## 📖 ภาพรวมระบบ

AI Service ของ Yuemnoi เป็น **Agentic AI Pipeline** ที่ออกแบบมาเพื่อทำหน้าที่เป็น "ผู้ช่วยอัจฉริยะ" ช่วยลูกค้าค้นหาและเปรียบเทียบอุปกรณ์เช่าในระบบ โดยมีขั้นตอนการทำงานดังนี้:


### 🧠 ขั้นตอนการทำงานของ Pipeline

| ขั้นตอน | ชื่อ | รายละเอียด |
|:-------:|:-----|:-----------|
| ① | **Guard & Filter** | ตรวจสอบความยาว, กรองคำถามทั่วไป/นอกเรื่องธุรกิจออก |
| ② | **Database Query** | ใช้ Qwen แปลงภาษาคนเป็น SQL แล้วค้นข้อมูลอุปกรณ์จาก Supabase |
| ③ | **Google Verification** | ถ้าคำถามเกี่ยวกับสเปคทางเทคนิค จะดึงข้อมูลเสริมจาก Google |
| ④ | **LLM Response** | รวมข้อมูลทั้งหมด + Chat History ส่งให้ Qwen สร้างคำตอบ JSON |
| ⑤ | **Item Selection** | กรองเฉพาะอุปกรณ์ที่ AI เลือกส่งกลับไปแสดงผลเป็นการ์ด |

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
    │   ├── 📄 executor.py                #    AgentExecutor — ตัวควบคุม Pipeline หลัก
    │   └── 📄 router.py                  #    IntentRouter — วิเคราะห์ความตั้งใจของผู้ใช้
    │
    └── 📁 tools/                         # 🔧 เครื่องมือที่ Agent ใช้ในการดึงข้อมูล
        ├── 📄 database_tool.py           #    DatabaseTool — แปลงภาษาคนเป็น SQL + ค้นฐานข้อมูล
        └── 📄 google_tool.py             #    GoogleTool — ค้นหาสเปคอุปกรณ์จาก Google (Serper API)
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

| ตัวแปร | คำอธิบาย | ค่าตั้งต้น |
|:-------|:---------|:----------|
| `SUPABASE_URL` | URL ของ Supabase Project | — (ต้องกำหนด) |
| `SUPABASE_KEY` | API Key ของ Supabase | — (ต้องกำหนด) |
| `SERPER_API_KEY` | API Key สำหรับ Serper.dev (Google Search) | — (ต้องกำหนด) |
| `HF_TOKEN` | Token สำหรับดาวน์โหลดโมเดลจาก Hugging Face | — (ต้องกำหนด) |
| `MODEL_NAME` | ชื่อโมเดล LLM ที่ใช้งาน | `Qwen/Qwen2.5-7B-Instruct` |
| `VLLM_ENDPOINT` | Endpoint ของ vLLM Server | `http://localhost:8000/v1` |

---

### 🧠 `app/agent/executor.py` — AgentExecutor (หัวใจหลัก)

`AgentExecutor` เป็นตัวควบคุม Pipeline ทั้งหมด ภายในฟังก์ชัน `run_pipeline_non_stream()`:

#### 1. 🛡️ Guard & Filter (การกรองข้อความ)
```
คำถามจากผู้ใช้
    ├── ยาวเกิน 200 ตัวอักษร? → ปฏิเสธ
    ├── เป็นคำถามทั่วไป? (เช่น "สวัสดี", "คุณคือใคร") → แนะนำให้ถามเรื่องอุปกรณ์
    └── ไม่มีคีย์เวิร์ดธุรกิจ + สั้นกว่า 3 ตัวอักษร? → แนะนำให้ถามเรื่องอุปกรณ์
```

#### 2. 🗄️ Database Query
- เรียก `DatabaseTool.query_items()` เพื่อค้นหาอุปกรณ์จากฐานข้อมูล Supabase
- LLM จะแปลงคำถามเป็น SQL อัตโนมัติ (Text-to-SQL)

#### 3. 🔍 Google Verification
- ใช้ `IntentRouter` ตรวจสอบว่าคำถามต้องการข้อมูลสเปคทางเทคนิคหรือไม่
- ถ้าต้องการ → เรียก `GoogleTool.search_spec()` ดึงข้อมูลสเปคเสริมจากเว็บ

#### 4. 💬 LLM Response Generation
- รวม **ประวัติแชท** + **ข้อมูลจาก DB** + **ข้อมูลจาก Google** + **คำถามใหม่**
- ส่ง Prompt ไปยัง **Qwen 2.5** ผ่าน vLLM Endpoint
- บังคับให้โมเดลตอบเป็น **JSON** รูปแบบ:
  ```json
  {
    "answer": "ข้อความคำตอบสุภาพ ลงท้ายด้วย ค่ะ/คะ",
    "selected_item_id": 42
  }
  ```

#### 5. 📦 Item Selection & Response
- กรองอุปกรณ์ตาม `selected_item_id` ที่ AI เลือก
- จัดรูปแบบข้อมูลรูปภาพ, ราคา, หน่วย (วัน/สัปดาห์)
- ส่ง Response กลับ:
  ```json
  {
    "status": "success",
    "search_status": "checked_google",
    "items_found": 1,
    "answer": "กล้อง Sony RX100 IV ตัวนี้ถ่าย 4K ได้ค่ะ ราคาเช่าวันละ 500 บาทเท่านั้น",
    "recommended_items": [{ ... }]
  }
  ```

---

### 🔀 `app/agent/router.py` — IntentRouter

ทำหน้าที่ **วิเคราะห์ความตั้งใจของผู้ใช้** ว่าคำถามนั้นต้องการข้อมูลสเปคจาก Google หรือไม่ โดยสแกนคีย์เวิร์ดที่บ่งบอกความต้องการเชิงเทคนิค:

```python
keywords_requiring_verification = [
    "สเปค", "spec", "ถ่าย 4k", "กันน้ำ", "เล่นเกม",
    "ไหวไหม", "รองรับ", "ของแท้ไหม", "เวอร์ชันไหน"
]
```

ถ้าพบคีย์เวิร์ดเหล่านี้ → ระบบจะดึงข้อมูลจาก Google มาเป็นบริบทเสริมให้ AI ตอบได้แม่นยำขึ้น

---

### 🔧 `app/tools/` — เครื่องมือของ Agent

#### `database_tool.py` — DatabaseTool

เครื่องมือค้นหาอุปกรณ์ในฐานข้อมูล Supabase ด้วยเทคนิค **Text-to-SQL**:

1. **SQL Generation** — ส่ง Table Schema + คำถามผู้ใช้ไปให้ Qwen แปลงเป็นคำสั่ง SQL
2. **Security Guardrail** — สแกนคีย์เวิร์ดอันตราย (`INSERT`, `UPDATE`, `DELETE`, `DROP`) เพื่อป้องกัน SQL Injection
3. **Execution** — ยิง SQL ผ่าน Supabase RPC (`execute_sql`) และส่งผลลัพธ์กลับ

```
คำถาม: "มีกล้อง Sony ราคาไม่เกิน 500 บาทไหม?"
    ↓ Qwen Text-to-SQL
SQL: SELECT * FROM public.item_tb WHERE item_name ILIKE '%sony%' AND price <= 500
    ↓ Security Check ✅
    ↓ Execute via Supabase RPC
ผลลัพธ์: [{ id: 42, item_name: "กล้อง Sony RX100 IV", price: 450, ... }]
```

#### `google_tool.py` — GoogleTool

ค้นหาข้อมูลสเปคและรีวิวจาก Google ผ่าน **Serper.dev API**:
- โฟกัสผลลัพธ์ในประเทศไทย (`gl: th`, `hl: th`)
- ดึง Organic Search Snippets 3 อันดับแรก
- ส่งข้อมูลเป็นบริบทเสริมให้ AI ตอบเรื่องสเปคได้ถูกต้อง

---

## ⚙️ ตัวแปรสภาพแวดล้อม (Environment Variables)

สร้างไฟล์ `.env` ในโฟลเดอร์ `ai_service/` :

```env
# Supabase
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_KEY=eyJhbGciOi...

# Google Search (Serper.dev)
SERPER_API_KEY=your_serper_api_key

# Hugging Face
HF_TOKEN=hf_xxxxx

# LLM Model Configuration
MODEL_NAME=Qwen/Qwen2.5-7B-Instruct
VLLM_ENDPOINT=http://localhost:8000/v1
```

---

## 🚀 วิธีรันโปรเจ็ค

### ข้อกำหนดเบื้องต้น
- [Python](https://www.python.org/downloads/) เวอร์ชัน 3.10 ขึ้นไป
- [vLLM](https://docs.vllm.ai/) หรือ Ollama สำหรับรันโมเดล Qwen 2.5 ในเครื่อง
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

### รัน vLLM Server (ต้องรันก่อน)

```bash
vllm serve Qwen/Qwen2.5-7B-Instruct --port 8000
```

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

| เทคโนโลยี | เวอร์ชัน | วัตถุประสงค์ |
|:-----------|:---------|:------------|
| **Python** | 3.10+ | ภาษาหลักในการพัฒนา |
| **FastAPI** | 0.111.0 | Web Framework สำหรับ API |
| **Uvicorn** | 0.30.1 | ASGI Server สำหรับรัน FastAPI |
| **Pydantic Settings** | 2.2.1 | จัดการ Configuration & Environment Variables |
| **HTTPX** | 0.27.0 | HTTP Client แบบ Async/Sync |
| **Qwen 2.5** | 7B-Instruct | โมเดลภาษาสำหรับสร้างคำตอบและแปลง Text-to-SQL |
| **vLLM** | — | Inference Engine สำหรับเร่งความเร็วโมเดล |
| **Serper.dev** | — | Google Search API สำหรับดึงข้อมูลสเปค |
| **Supabase** | — | ฐานข้อมูล PostgreSQL (ผ่าน REST API) |

---

## 🔐 ระบบความปลอดภัย

AI Service มีระบบป้องกันหลายชั้น:

| ชั้น | การป้องกัน | รายละเอียด |
|:----:|:-----------|:-----------|
| 🛡️ | **Input Validation** | จำกัดความยาว Query ไม่เกิน 200 ตัวอักษร |
| 🛡️ | **Intent Filter** | กรองคำถามนอกเรื่องธุรกิจออก |
| 🛡️ | **SQL Guardrail** | บล็อกคำสั่ง SQL อันตราย (INSERT/UPDATE/DELETE/DROP/ALTER/TRUNCATE) |
| 🛡️ | **SELECT Only** | อนุญาตเฉพาะคำสั่ง SELECT เท่านั้น |
| 🛡️ | **Response Parsing** | จัดการกรณี LLM ส่ง JSON ผิดรูปแบบ + Fallback |

---
