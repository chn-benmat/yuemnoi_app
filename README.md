# Yuemnoi (ยืมหน่อย)

Yuemnoi คือแอปพลิเคชันสำหรับค้นหาและจัดการการเช่าอุปกรณ์ โดยประกอบด้วยแอป Flutter, Backend API และ AI Service สำหรับช่วยค้นหาและแนะนำอุปกรณ์จากข้อมูลในระบบ

> สถานะปัจจุบัน: ฝั่ง Flutter รองรับขั้นตอน Authentication แล้ว ส่วนหน้าหลักและฟีเจอร์เช่าอุปกรณ์ยังอยู่ระหว่างพัฒนา ขณะที่ Backend มี API สำหรับผู้ใช้ อุปกรณ์ การเช่า และ AI Chat

## สถาปัตยกรรมระบบ

```mermaid
flowchart LR
    App["Flutter App"] -->|REST API| API["Go + Gin Backend"]
    App -->|Auth session / OAuth| Supabase["Supabase"]
    API -->|Data & Auth| Supabase
    API -->|AI request| AI["Python + FastAPI"]
    AI -->|Inventory search| Supabase
    AI -->|Local LLM| Ollama["Ollama / Typhoon 2 8B"]
    AI -->|Product information| Serper["Serper.dev"]
```

## โครงสร้างโปรเจกต์

| โฟลเดอร์ | รายละเอียด | เอกสาร |
| --- | --- | --- |
| `frontend/` | Mobile/Web client พัฒนาด้วย Flutter | [Frontend README](frontend/README.md) |
| `backend/` | REST API พัฒนาด้วย Go และ Gin | [Backend README](backend/README.md) |
| `ai_service/` | AI pipeline พัฒนาด้วย FastAPI และใช้ Typhoon 2 8B ผ่าน Ollama | [AI Service README](ai_service/README.md) |

## เทคโนโลยีหลัก

- Flutter และ Dart สำหรับแอปพลิเคชันฝั่งผู้ใช้
- Go และ Gin สำหรับ Backend API
- Python และ FastAPI สำหรับ AI Service
- Supabase สำหรับ Authentication, PostgreSQL และ Storage
- Ollama + Typhoon 2 8B สำหรับโมเดลภาษาที่รันภายในเครื่อง
- Serper.dev สำหรับค้นหาข้อมูลผลิตภัณฑ์ภายนอก

## สิ่งที่ต้องติดตั้ง

- [Flutter SDK](https://docs.flutter.dev/get-started/install) ที่รองรับ Dart `^3.11.5`
- [Go](https://go.dev/dl/) `1.26.2` ขึ้นไป
- [Python](https://www.python.org/downloads/) `3.10` ขึ้นไป
- [Ollama](https://ollama.com/download)
- Supabase project และ Serper.dev API key

ตรวจสอบเครื่องมือเบื้องต้น:

```bash
flutter doctor
go version
python --version
ollama --version
```

## การตั้งค่า Environment Variables

ไฟล์ environment ทุกไฟล์ถูก ignore จาก Git ให้สร้างไฟล์ต่อไปนี้ในเครื่องของผู้พัฒนา

### 1. Frontend — `frontend/.env.local`

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_PUBLISHABLE_KEY=your_publishable_key
API_URL=http://localhost:8080
```

`API_URL` ต้องเป็น URL ที่อุปกรณ์เข้าถึง Backend ได้ ดูตัวอย่างสำหรับ Emulator และเครื่องจริงใน [Frontend README](frontend/README.md#การเชื่อมต่อ-backend-จากแต่ละอุปกรณ์)

> ห้ามใส่ `SUPABASE_SERVICE_ROLE_KEY` หรือ secret ใด ๆ ใน `frontend/.env.local` เพราะไฟล์นี้ถูก bundle ไปกับแอป

### 2. Backend — `backend/.env`

```env
GIN_MODE=debug
PORT=8080
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
AI_SERVICE_URL=http://localhost:8000
```

Backend อ่านค่าจาก environment ของ process จึงต้อง export ค่าจากไฟล์ก่อนรัน ตัวอย่างสำหรับ PowerShell:

```powershell
cd backend
Get-Content .env | ForEach-Object {
  if ($_ -match '^\s*([^#][^=]*)=(.*)$') {
    [Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), 'Process')
  }
}
go run ./cmd/server/main.go
```

### 3. AI Service — `ai_service/.env`

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your_supabase_key
SERPER_API_KEY=your_serper_api_key
MODEL_NAME=scb10x/llama3.1-typhoon2-8b-instruct:latest
OLLAMA_ENDPOINT=http://localhost:11434
OLLAMA_CONTEXT_LENGTH=4096
OLLAMA_KEEP_ALIVE=-1
```

## วิธีรันระบบสำหรับพัฒนา

เปิด Terminal แยกสำหรับแต่ละ service และรันตามลำดับต่อไปนี้

### 1. เตรียมโมเดล Ollama

```bash
ollama pull scb10x/llama3.1-typhoon2-8b-instruct:latest
ollama serve
```

หาก Ollama ทำงานเป็น background service อยู่แล้ว ไม่ต้องรัน `ollama serve` ซ้ำ

### 2. รัน AI Service

```bash
cd ai_service
python -m venv .venv
```

Windows PowerShell:

```powershell
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python main.py
```

macOS/Linux:

```bash
source .venv/bin/activate
pip install -r requirements.txt
python main.py
```

AI Service จะเปิดที่ `http://localhost:8000` และตรวจสอบได้ที่ `GET /health`

### 3. รัน Backend

โหลดค่า `backend/.env` เข้า process ตามตัวอย่างด้านบน แล้วรัน:

```bash
cd backend
go mod download
go run ./cmd/server/main.go
```

Backend จะเปิดที่ `http://localhost:8080` และตรวจสอบได้ที่ `GET /health`

การส่งคำขอเช่าใช้ `POST /api/v1/rentals` โดย Backend และฐานข้อมูลเป็นผู้ตรวจสอบช่วงเวลาและคำนวณราคาจากข้อมูลอุปกรณ์ปัจจุบัน ใบจองใหม่จะอยู่ในสถานะ `pending` จนกว่าเจ้าของอุปกรณ์จะยืนยัน

### 4. รัน Flutter App

```bash
cd frontend
flutter pub get
flutter run
```

ดูรายละเอียดการตั้งค่า Supabase OAuth, การเลือกอุปกรณ์ และคำสั่งทดสอบได้ที่ [Frontend README](frontend/README.md)

## การทดสอบ

```bash
# Flutter
cd frontend
flutter analyze
flutter test

# Go
cd backend
go test ./...
```

ตรวจสอบ service ขณะระบบทำงาน:

```bash
curl http://localhost:8000/health
curl http://localhost:8080/health
```

## ข้อควรระวังด้านความปลอดภัย

- อย่า commit ไฟล์ `.env`, `.env.local`, API key หรือ token ลง Git
- ใช้ Supabase publishable key ใน Frontend เท่านั้น
- เก็บ service role key และ JWT secret ไว้เฉพาะฝั่ง Backend/Server
- ก่อน deploy ให้จำกัด CORS และตรวจสอบนโยบาย Supabase Row Level Security (RLS) ให้เหมาะสม
