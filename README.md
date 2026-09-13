# Yuemnoi (ยืมหน่อย)

Yuemnoi คือแพลตฟอร์ม C2C สำหรับค้นหา ให้เช่า และจัดการการเช่าอุปกรณ์และเครื่องมือ (Equipment Rental Platform) ครบวงจร โดยประกอบด้วย Mobile App (Flutter), REST API Server (Go + Gin ตามสถาปัตยกรรม Hexagonal) และ AI Chatbot Assistant Service (Python + FastAPI ตามสถาปัตยกรรม Clean Architecture) ที่ทำงานร่วมกับ Local LLM และระบบค้นหาข้อมูลภายนอกเพื่อช่วยแนะนำและตรวจสอบสเปกอุปกรณ์

> **สถานะปัจจุบัน**: ระบบพัฒนาครบถ้วนตาม Hybrid Architecture ครอบคลุมทั้งระบบยืนยันตัวตน (Authentication & Guest Browsing), ฟีดแนะนำอุปกรณ์ (Discovery & Ranking Feed), ระบบจัดการรายการอุปกรณ์ (Item Management), วงจรการเช่าและส่งมอบคืน (Rental Lifecycle & Handover/Return), กระเป๋าเงินดิจิทัล (Wallet & Payment), แชทแบบเรียลไทม์ (Supabase Realtime Chat), ระบบแจ้งเตือน (FCM Push Notifications) และที่ปรึกษาการเช่าอัจฉริยะ (AI Rental Consultant with SSE Streaming & Fact Verification)

---

## 🏛️ สถาปัตยกรรมระบบ (System Architecture)

ระบบใช้สถาปัตยกรรม **Hybrid Architecture** โดยแบ่งหน้าที่ระหว่าง Backend, AI Service และ Supabase ไคลเอนต์เพื่อความปลอดภัยและประสิทธิภาพสูงสุด

---

## 📂 โครงสร้างโปรเจกต์ (Project Structure)

| โฟลเดอร์      | รายละเอียด                                         | สถาปัตยกรรม / เทคโนโลยี                          | เอกสารเพิ่มเติม                           |
| :------------ | :------------------------------------------------- | :----------------------------------------------- | :---------------------------------------- |
| `frontend/`   | แอปพลิเคชันมือถือสำหรับผู้เช่าและผู้ให้เช่า        | Flutter, Dart, BLoC/Cubit, Dio, Supabase SDK     | [Frontend README](frontend/README.md)     |
| `backend/`    | เซิร์ฟเวอร์หลักจัดการข้อมูล ธุรกรรม และความปลอดภัย | Go 1.26+, Gin, Hexagonal Architecture, FCM v1    | [Backend README](backend/README.md)       |
| `ai_service/` | บริการ AI ให้คำปรึกษาและเปรียบเทียบสเปกอุปกรณ์     | Python 3.12, FastAPI, Clean Architecture, Ollama | [AI Service README](ai_service/README.md) |

---

## 🛠️ เทคโนโลยีหลัก (Tech Stack)

- **Frontend**: Flutter, Dart, `flutter_bloc`, `dio`, `go_router`, `supabase_flutter`, `firebase_messaging`, `flutter_map`
- **Core Backend**: Go, Gin, Hexagonal Architecture (Ports & Adapters), Supabase Go Client, Google FCM HTTP v1, `caarlos0/env/v11`, `log/slog`
- **AI Microservice**: Python 3.12, FastAPI, Pydantic v2, Clean Architecture, HTTPX (Async), SSE Streaming
- **Database & Auth**: Supabase (PostgreSQL, Row Level Security, Realtime WebSockets, Storage)
- **Local AI / LLM**: Ollama พร้อมโมเดล `llama3.1-typhoon2-8b-instruct:latest` (รองรับ Structured Output JSON Mode)
- **Search Provider**: Tavily Search API สำหรับ Fact-checking สเปกอุปกรณ์และราคาตลาด

---

## 📋 สิ่งที่ต้องติดตั้ง (Prerequisites)

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart `^3.6.0` ขึ้นไป)
- [Go](https://go.dev/dl/) `1.26` ขึ้นไป
- [Python](https://www.python.org/downloads/) `3.12`
- [Ollama](https://ollama.com/download)
- บัญชี [Supabase](https://supabase.com) (Database, Auth, Storage)
- บัญชี [Firebase Console](https://console.firebase.google.com) (สำหรับ FCM Push Notifications)
- [Tavily Search API Key](https://tavily.com) (สำหรับค้นหาสเปกและตรวจสอบข้อเท็จจริง)

ตรวจสอบความพร้อมของเครื่องมือในเครื่อง:

```bash
flutter doctor
go version
python --version
ollama --version
```

---

## 🚀 วิธีการรันระบบเพื่อการพัฒนา (Getting Started)

เปิด Terminal แยก 4 หน้าต่างตามลำดับดังนี้:

### ขั้นตอนที่ 1: เตรียมโมเดล Local LLM (Ollama)

```bash
ollama pull llama3.1-typhoon2-8b-instruct:latest
ollama serve
```

_(หาก Ollama เปิดเป็น background process ประจำเครื่องอยู่แล้ว ข้ามคำสั่ง `ollama serve` ได้)_

### ขั้นตอนที่ 2: รัน AI Service (FastAPI)

```bash
cd ai_service

# สร้างและเปิดใช้งาน Virtual Environment (Python 3.12)
python -m venv .venv

# บน Windows PowerShell:
.\.venv\Scripts\Activate.ps1

# บน macOS/Linux:
# source .venv/bin/activate

pip install -r requirements.txt
python main.py
```

- ทดสอบสุขภาพของระบบ: `GET http://localhost:8000/health`
- ดูเอกสาร API Interactive Docs: `http://localhost:8000/docs`

### ขั้นตอนที่ 3: รัน Backend (Go)

```bash
cd backend
go mod tidy

# รันแบบ Hot Reload ด้วย Air (แนะนำ):
air

# หรือรันตรงด้วย Go:
go run ./cmd/server/main.go
```

- ทดสอบสุขภาพของเซิร์ฟเวอร์: `GET http://localhost:8080/health`

### ขั้นตอนที่ 4: รัน Flutter Application

```bash
cd frontend
flutter pub get

# รันแอปพร้อม inject คอนฟิกจาก .env.local
flutter run --dart-define-from-file=.env.local
```

---

## 🧪 การทดสอบระบบ (Testing)

```bash
# 1. ทดสอบ Frontend (Flutter Unit & Widget Tests)
cd frontend
flutter analyze
flutter test

# 2. ทดสอบ Backend (Go Unit & Mock Tests)
cd backend
go test ./tests/...

# 3. ทดสอบ AI Service (Pytest)
cd ai_service
.\.venv\Scripts\pytest tests/ -v
```

---

## 🛡️ แนวทางความปลอดภัยและสิทธิการเข้าถึง (Security & Privacy)

1. **สถาปัตยกรรมแบบไฮบริด (Hybrid Security)**:
   - การเปลี่ยนแปลงข้อมูลสำคัญ (Mutation) เช่น การสร้าง/แก้ไขรายการอุปกรณ์, การสร้างคำขอเช่า, การหักยอดเงิน, การสืบค้นเบอร์โทรศัพท์คู่สนทนา ต้องผ่าน Go Backend เสมอเพื่อตรวจสอบ JWT และสิทธิ์ของผู้ใช้
   - อนุญาตให้ Flutter ไคลเอนต์ต่อตรงกับ Supabase เฉพาะงานที่ต้องการ Low-latency เท่านั้น เช่น Supabase Realtime WebSocket สำหรับการรับส่งข้อความในห้องแชท
2. **การรักษาความลับของกุญแจ (Secret Isolation)**:
   - `SUPABASE_SERVICE_ROLE_KEY` และ Google Service Account (`service-account.json`) จะต้องไม่ปรากฏในโค้ดฝั่ง Client
   - มีการสื่อสารระหว่าง Backend และ AI Service ด้วย `INTERNAL_SERVICE_KEY` เพื่อป้องกันการเรียกใช้งานจากภายนอก
3. **การป้องกันข้อมูลรั่วไหล (PII Redaction & Audit Logging)**:
   - Backend มี `response_logging_middleware` ที่คอยกรองและ Redact ข้อมูลส่วนบุคคล (รหัสผ่าน, เบอร์โทรศัพท์, Token) ก่อนบันทึกลง Structured Log เสมอ
4. **ความเที่ยงธรรมและไร้อคติของ AI (Strict Neutrality)**:
   - ระบบ AI ทำงานตาม **Zero-Regex, Zero-Keyword, Zero-Hardcode** และ **Zero-Bias Policy** โดยแนะนำสินค้าตามความต้องการของผู้ใช้และความจริงจากฐานข้อมูล ไม่มีการเอนเอียงตามผลประโยชน์ทางการค้าหรือตราสินค้า
