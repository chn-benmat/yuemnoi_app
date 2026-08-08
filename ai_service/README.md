<div align="center">

# 🤖 Yuemnoi — AI Service

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
|    ①    | **Conversational Agent**  | Qwen อ่านคำถามและประวัติแชททุกครั้ง แล้วตอบบทสนทนาทั่วไปเองโดยไม่มี keyword router       |
|    ②    | **Inventory Tool Call**   | Qwen เรียก typed tool เมื่อต้องใช้ข้อมูลสินค้า ราคา หรือคำแนะนำจาก Supabase               |
|    ③    | **Specification Tool**    | Qwen เลือกค้นแหล่งข้อมูลสเปกภายนอกเมื่อคำถามต้องใช้ข้อมูลอ้างอิง                          |
|    ④    | **Grounded Response**     | Qwen อ่านผลจาก tool แล้วเรียบเรียง structured JSON แบบปิด thinking                       |
|    ⑤    | **Item Selection**        | กรองเฉพาะอุปกรณ์ที่ AI เลือกส่งกลับไปแสดงผลเป็นการ์ด                                     |

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
| `SUPABASE_KEY`          | API Key ของ Supabase                               | — (ต้องกำหนด)            |
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

#### 1. 🛡️ Guard & Filter (การกรองข้อความ)

```
คำถามจากผู้ใช้
    ├── ยาวเกิน 200 ตัวอักษร? → ขอให้พิมพ์ใหม่แบบกระชับ
    └── ส่งคำถาม + history ให้ Qwen ตีความอย่างอิสระ
```

#### 2. 🗄️ Database Query

- Qwen เลือกเรียก `search_inventory` เองเมื่อคำถามต้องใช้ข้อมูลสินค้าปัจจุบัน
- tool รับ typed arguments เช่น category, search_text, min_price และ max_price
- backend ตรวจสอบ arguments ด้วย Pydantic ก่อนค้น Supabase ผ่าน PostgREST
- จำกัดผลลัพธ์ไม่เกิน 5 รายการและเลือกเฉพาะคอลัมน์ที่จำเป็น

#### 3. 🔍 Google Verification

- Qwen เลือกเรียก `search_web_specs` เมื่อคำถามต้องใช้ข้อมูลสเปกภายนอก
- ไม่ใช้ web tool สำหรับราคา สถานะ หรือสินค้าในคลัง Yuemnoi
- ส่งชื่อแหล่งข้อมูล URL และข้อมูลสรุปสูงสุด 5 แหล่งให้ AI ตรวจสอบก่อนตอบ

#### 4. 💬 LLM Response Generation

- รอบแรกส่งประวัติแชทล่าสุดไม่เกิน 6 ข้อความให้ Qwen ตัดสินใจด้วย structured semantic routing เพียงครั้งเดียว
- บทสนทนาทั่วไปใช้คำตอบจาก routing ได้ทันที ส่วนคำถามสินค้า/สเปกจึงค่อยส่งผลจริงให้ Qwen เรียบเรียงรอบสุดท้าย
- ปิด thinking, จำกัด output และบังคับคำตอบหลัง tool ด้วย JSON schema รูปแบบ:
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

ค่า `search_status` ที่เป็นไปได้:

- `using_supabase` — พบข้อมูลใน Supabase และไม่ได้เรียก Google
- `inventory_no_results` — Qwen เรียก inventory tool แต่ไม่พบสินค้าตรงเงื่อนไข
- `direct_response` — Qwen ตอบบทสนทนาโดยตรงและไม่จำเป็นต้องเรียก tool
- `checked_google` — ค้นสำเร็จและมีแหล่งข้อมูลส่งให้ AI ตรวจสอบ
- `google_no_results` — Google ไม่พบผลลัพธ์ที่ใช้เป็นบริบทได้
- `google_search_failed` — เรียกบริการค้นหาไม่สำเร็จ
- `input_too_long` — คำถามยาวเกิน 200 ตัวอักษร
- `llm_failed` — Ollama/Qwen ไม่พร้อมใช้งานชั่วคราว

---

### 🔧 `app/tools/` — เครื่องมือของ Agent

#### `database_tool.py` — DatabaseTool

เครื่องมือค้นหาอุปกรณ์ในฐานข้อมูล Supabase ที่ถูกเรียกโดย Qwen:

1. **Tool Selection** — Qwen ตัดสินใจจากความหมายและประวัติสนทนาโดยไม่มี keyword router
2. **Semantic Filters** — Qwen แปลงคำพ้อง คำอธิบายการใช้งาน และบริบทจากข้อความก่อนหน้าเป็นหมวดมาตรฐาน เช่น “จะไปนอนป่า” → `camping` โดยไม่บังคับให้ผู้ใช้พิมพ์คำตายตัว
3. **Typed Arguments** — Pydantic ตรวจสอบชื่อสินค้า หมวดหมู่ และช่วงราคา
4. **Flexible Text Search** — คำค้นหลายคำถูกค้นแยกเป็นคำสำคัญ ไม่ต้องตรงกับวลีในฐานข้อมูลทั้งประโยค
5. **Safe Query** — backend สร้าง PostgREST filters เองและไม่รับ SQL ดิบจากโมเดล

```
คำถาม: "มีกล้อง Sony ราคาไม่เกิน 500 บาทไหม?"
    ↓ Qwen calls search_inventory
Filters: category=camera, search_text=sony, max_price=500, limit=5
    ↓ Execute via Supabase PostgREST
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
