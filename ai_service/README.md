# 🤖 AI Rental Chatbot Service

ระบบ AI Chatbot สำหรับบริการเช่าสินค้า (Rental Service) พัฒนาด้วย **Python 3.12**, รันบนเครื่อง Local ผ่าน **Ollama** โดยใช้โมเดล **`llama3.1-typhoon2-8b-instruct:latest`**, เชื่อมต่อฐานข้อมูล **Supabase** (`item_tb`), ค้นหาและเปรียบเทียบสเปกสินค้าด้วย **Tavily Search API** พร้อม **Fact-Checking Engine** เพื่อกลั่นกรองข้อมูล และรองรับระบบถามกลับพร้อมช้อยส์ (**Interactive Clarification**) เมื่อคำถามไม่ละเอียด ภายใต้ข้อกำหนดเคร่งครัด:

> ⚡ **Zero-Regex, Zero-Keyword, Zero-Hardcode Policy**:
> ทุกการตัดสินใจ (Intent Routing, Entity Extraction, Catalog Ranking, Fact Checking) ขับเคลื่อนด้วย **AI-Native Structured Reasoning (Pydantic Schema + JSON Mode)** ไม่มีการใช้คำสั่ง `if keyword in text` หรือ regex pattern แม้แต่จุดเดียว!

---

## ⚙️ การตั้งค่า Environment (`.env`)

```env
SUPABASE_URL=.....
SUPABASE_KEY=.....

TAVILY_API_KEY=......

OLLAMA_MODEL=.....

INTERNAL_SERVICE_KEY=.....
```

---

## 🚀 วิธีการรันระบบ (Running the Service)

### 1. เปิด Ollama

ตรวจสอบว่าโมเดล `llama3.1-typhoon2-8b-instruct:latest` ติดตั้งและพร้อมใช้งาน:

```bash
ollama list
```

### 2. รัน FastAPI Server

```bash
# Windows PowerShell
.\.venv\Scripts\python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Swagger UI Documentation จะพร้อมใช้งานที่:
👉 **`http://localhost:8000/docs`**

---

## 📡 การเรียกใช้งาน API (Endpoints)

### 1. `POST /api/v1/chat` (Full Response Mode)

เหมาะสำหรับการสนทนาทั่วไป, การถามหาสินค้า, การเปรียบเทียบสินค้า, หรือการรับคำถามพร้อมช้อยส์ตัวเลือก

**Request Body:**

```json
{
  "message": "อยากได้คอมไปทำงานสักเครื่อง",
  "session_id": "session-123"
}
```

**Response ตัวอย่าง (เมื่อคำถามไม่ละเอียด - ระบบสร้างช้อยส์ให้อัตโนมัติ):**

```json
{
  "response": "คุณลูกค้าสนใจนำคอมพิวเตอร์ไปใช้งานลักษณะใดเป็นหลักครับ เพื่อที่จะได้แนะนำรุ่นที่เหมาะสมให้ครับ",
  "intent": "CLARIFICATION_NEEDED",
  "confidence": 0.95,
  "ambiguity_level": 0.85,
  "clarification": {
    "question": "คุณลูกค้าสนใจนำคอมพิวเตอร์ไปใช้งานลักษณะใดเป็นหลักครับ เพื่อที่จะได้แนะนำรุ่นที่เหมาะสมให้ครับ",
    "missing_dimension": "intended_use",
    "options": [
      {
        "id": "opt_1",
        "label": "งานเอกสารและทั่วไป",
        "description": "เน้นพกพาง่าย แบตอึด",
        "action_value": "ต้องการคอมพิวเตอร์สำหรับงานเอกสารและการเรียนทั่วไป"
      },
      {
        "id": "opt_2",
        "label": "งานกราฟิกและตัดต่อวิดีโอ",
        "description": "เน้นประสิทธิภาพสูง เช่น MacBook Air M2",
        "action_value": "ต้องการคอมพิวเตอร์ประสิทธิภาพสูงสำหรับงานตัดต่อวิดีโอและกราฟิก"
      }
    ]
  },
  "items": [],
  "comparison": null
}
```

---

### 2. `POST /api/v1/chat/stream` (SSE Streaming Mode)

สำหรับสร้างประสบการณ์การพิมพ์แบบสด (Typewriter effect) ใน Mobile App

**Request Body:**

```json
{
  "message": "กล้อง Canon EOS R50 เช่าวันละเท่าไหร่ และมีฟีเจอร์เด่นอะไรบ้าง"
}
```

**Response Format:** `text/event-stream`

```
data: {"token": "กล้อง"}
data: {"token": " Canon"}
data: {"token": " EOS"}
data: {"token": " R50"}
...
data: [DONE]
```

---

### 3. `GET /api/v1/items`

ดึงรายการสินค้าทั้งหมดในร้านเช่า (ดึงจาก Supabase `item_tb` พร้อม In-memory Cache)

---

### 4. `GET /health`

ตรวจสอบสถานะการเชื่อมต่อของ Ollama Local, Supabase Database, และ Tavily API Key

---

## 📱 แนวทางการนำไปเชื่อมต่อกับ Flutter Mobile App

1. **การแสดงผล Quick Reply / Choices**: เมื่อ `response.clarification` ไม่เป็น `null` ให้นำ `clarification.options` ไป Render เป็น `ChoiceChip` หรือ `ElevatedButton` แนวนอน
2. **เมื่อผู้ใช้กดเลือกช้อยส์**: ให้นำค่า `option.action_value` ส่งกลับมาที่ `POST /api/v1/chat` เป็นข้อความถัดไป
3. **การแสดงผลสินค้า (`items`)**: เมื่อ `response.items` มีข้อมูล สามารถนำไปแสดงผลเป็น Product Card พร้อมรูปภาพและปุ่มกดจอง/เช่าได้ทันที
