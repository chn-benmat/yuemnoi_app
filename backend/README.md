# ⚡ Backend: ยืมหน่อย REST API (Go)

[![Go](https://img.shields.io/badge/Go-1.26+-00ADD8?style=for-the-badge&logo=go&logoColor=white)](https://golang.org)
[![Gin Framework](https://img.shields.io/badge/Gin-v1.12-008ECF?style=for-the-badge&logo=gin&logoColor=white)](https://gin-gonic.com)
[![Supabase](https://img.shields.io/badge/Supabase-Backend%20Adapter-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)](https://supabase.com)
[![Firebase](https://img.shields.io/badge/Firebase-Admin%20FCM-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)](https://firebase.google.com)

บริการ Core REST API และ Gateway ของระบบ **ยืมหน่อย (Yuemnoi)** พัฒนาด้วยภาษา **Go (Golang)** และ **Gin Framework** โดยยึดหลัก **Hexagonal Architecture (Ports and Adapters)** เพื่อแยก Business Rules ออกจาก Infrastructure และ Frameworks อย่างเด็ดขาด

---

## 📑 สารบัญ (Table of Contents)

1. [สถาปัตยกรรม (Hexagonal Architecture)](#-สถาปัตยกรรม-hexagonal-architecture)
2. [โครงสร้างไดเรกทอรี (Directory Structure)](#-โครงสร้างไดเรกทอรี-directory-structure)
3. [ขอบเขตหน้าที่ของระบบ (Responsibilities)](#-ขอบเขตหน้าที่ของระบบ-responsibilities)
4. [ข้อกำหนดเบื้องต้น (Prerequisites)](#-ข้อกำหนดเบื้องต้น-prerequisites)
5. [การตั้งค่า Environment Variables](#-การตั้งค่า-environment-variables)
6. [ขั้นตอนการติดตั้งและรันเซิร์ฟเวอร์ (Getting Started)](#-ขั้นตอนการติดตั้งและรันเซิร์ฟเวอร์-getting-started)
7. [รายการ API Endpoints (API Routes)](#-รายการ-api-endpoints-api-routes)
8. [ความปลอดภัยและการควบคุมสิทธิ์ (Security & Hardening)](#-ความปลอดภัยและการควบคุมสิทธิ์-security--hardening)
9. [การทดสอบ (Testing)](#-การทดสอบ-testing)

---

## 🏛️ สถาปัตยกรรม (Hexagonal Architecture)

ระบบออกแบบตามแนวคิด **Hexagonal Architecture (Ports and Adapters)** โดยมีแกนหลักอยู่ที่ `internal/domain/` ซึ่งไม่มีการผูกติดกับเฟรมเวิร์กหรือฐานข้อมูลใดๆ:

```text
       ┌────────────────────────────────────────────────────────┐
       │                       HTTP Inbound                     │
       │     (Mobile App / Web via Gin Router & Middlewares)    │
       └───────────────────────────┬────────────────────────────┘
                                   │
                                   ▼
             ┌───────────────────────────────────────────┐
             │       Inbound Ports (HTTP Handlers)       │
             │   ItemHandler, RentalHandler, UserHandler │
             └─────────────────────┬─────────────────────┘
                                   │
                                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        Core Domain (Business)                          │
│   Entities, Models, Business Rules, Inbound/Outbound Port Interfaces   │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
                                   ▼
             ┌───────────────────────────────────────────┐
             │      Outbound Adapters (Infrastructure)   │
             ├─────────────────────┬─────────────────────┤
             │      Supabase       │      Firebase       │      AI Service     │
             │   (PostgreSQL DB)   │     (Admin SDK)     │    (FastAPI Proxy)  │
             └─────────────────────┴─────────────────────┴─────────────────────┘
```

### รายละเอียดในแต่ละ Layer:
- `cmd/server/`: จัดการโหลดคอนฟิก, ทำ Dependency Injection และรัน HTTP Server พร้อมระบบ Graceful Shutdown
- `internal/domain/`: บรรจุ Pure Business Entities และ Interface Ports สำหรับเชื่อมต่อภายนอก (ห้าม Import `gin` หรือ Database Libraries)
- `internal/adapters/`: ดำเนินการตาม Interface ของ Domain เพื่อคุยกับ Third-party Services:
  - `supabase/`: จัดการ Table `item_tb`, `booking_tb`, `profile_tb`, `conversation_tb`
  - `fcm/`: ส่ง Push Notifications ผ่าน Firebase Admin SDK
  - `aiservice/`: เชื่อมต่อไปยัง Python FastAPI AI Service
- `internal/ports/`: ควบคุมการรับ Request ของ Gin, การแปลง DTO, Validation, Rate Limiter, และ Security Middlewares

---

## 📁 โครงสร้างไดเรกทอรี (Directory Structure)

```text
backend/
├── cmd/
│   └── server/
│       └── main.go              # Application Entry Point & Dependency Wiring
├── internal/
│   ├── adapters/
│   │   ├── aiservice/           # AI Gateway Client (HTTP Proxy & Streaming)
│   │   ├── fcm/                 # Firebase Cloud Messaging Adapter
│   │   └── supabase/            # Supabase Repositories (Item, Rental, Profile, Contact)
│   ├── config/
│   │   └── config.go            # Centralized Config with caarlos0/env & godotenv
│   ├── domain/
│   │   ├── errors.go            # Domain Errors
│   │   └── *.go                 # Domain Interfaces & Core Entities
│   └── ports/
│       ├── *_handler.go         # Gin Controllers (Auth, Item, Rental, Chatbot, Push)
│       ├── rate_limiter_middleware.go # In-memory Rate Limiting
│       ├── response_logging_middleware.go # Slog Structured Logging
│       └── router.go            # Route Grouping, CORS, AppSecret Check
├── tests/                       # Unit & Integration Tests (Testify)
├── go.mod                       # Go Module Dependencies
└── go.sum                       # Dependency Checksums
```

---

## 🎯 ขอบเขตหน้าที่ของระบบ (Responsibilities)

1. **Core CRUD & Business Logic**: บริหารจัดการข้อมูลอุปกรณ์, การสร้างคำขอเช่า, คำนวณยอดเงิน และจัดการสถานะการส่งมอบ/ส่งคืน
2. **AI Chatbot Gateway**: ทำหน้าที่เป็น Gateway เชื่อมต่อไปยัง Python AI Service ตรวจสอบ Rate Limit ป้องกัน DoS และถ่ายทอด SSE Stream กลับไปยัง Mobile App
3. **Sensitive Data Protection**: ให้บริการตรวจสอบข้อมูลส่วนตัวและหมายเลขติดต่อ (`/api/v1/chat/contact`) หลังผ่านการยืนยันสิทธิ์ ป้องกัน Client ทำ Direct Query สู่ Database
4. **Push Notification Dispatcher**: แปลงเหตุการณ์ของระบบเป็นข้อความแจ้งเตือนผ่าน Firebase Cloud Messaging (FCM)
5. **Session Verification**: ตรวจสอบ Supabase JWT Bearer Token และระบุตัวตนของผู้ใช้จาก Token เท่านั้น (ไม่รับ User ID ผ่าน Request Body)

---

## 📋 ข้อกำหนดเบื้องต้น (Prerequisites)

- **Go**: เวอร์ชัน `1.26` หรือใหม่กว่า
- บัญชีและโครงการ **Supabase** (ต้องมี `SUPABASE_URL` และ `SUPABASE_SERVICE_ROLE_KEY`)
- ไฟล์ Service Account ของ **Firebase** (สำหรับระบบ Push Notifications)

---

## ⚙️ การตั้งค่า Environment Variables

สร้างไฟล์ `.env` ไว้ในโฟลเดอร์ `backend/`:

```env
# ตั้งค่าโหมดการทำงานและพอร์ตเซิร์ฟเวอร์
PORT=8080
GIN_MODE=debug                           # ใช้ 'debug' ขณะพัฒนา และ 'release' บน Production

# Supabase Configurations (ห้ามเปิดเผย Service Role Key ออกไปภายนอก)
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-supabase-service-role-key

# Firebase Cloud Messaging Credentials
FIREBASE_SERVICE_ACCOUNT_PATH=service-account.json
# หรือสามารถระบุเป็น JSON String ใน FIREBASE_SERVICE_ACCOUNT_KEY แทนได้

# กุญแจความปลอดภัย (รองรับ Multi-Key Rotation ด้วยการคั่นด้วยเครื่องหมายจุลภาค ,)
APP_SECRET_KEY=your-super-secure-app-secret-key-32chars
INTERNAL_SERVICE_KEY=your-internal-shared-service-key-32chars

# การเชื่อมต่อกับ Python AI Service
AI_SERVICE_URL=http://localhost:8000
AI_SERVICE_TIMEOUT=60s

# Timeouts สำหรับ Network I/O
READ_TIMEOUT=15s
WRITE_TIMEOUT=90s
SHUTDOWN_TIMEOUT=5s
```

---

## 🚀 ขั้นตอนการติดตั้งและรันเซิร์ฟเวอร์ (Getting Started)

### 1. ติดตั้ง Go Modules
```bash
cd backend
go mod download
```

### 2. รันเซิร์ฟเวอร์
```bash
go run cmd/server/main.go
```
> เซิร์ฟเวอร์จะเริ่มทำงานที่ `http://localhost:8080`

### 3. ตรวจสอบสถานะการทำงาน (Healthcheck)
```bash
curl http://localhost:8080/health
```
Response:
```json
{"status":"ok"}
```

---

## 🌐 รายการ API Endpoints (API Routes)

ทุกเส้นทางขึ้นต้นด้วย `/api/v1` และจำเป็นต้องมี Header `X-App-Secret`:

### Authentication & Profiles
- `POST /api/v1/auth/register` - สมัครสมาชิกใหม่
- `POST /api/v1/auth/login` - เข้าสู่ระบบด้วย Email/Password
- `POST /api/v1/auth/google-profile` - ซิงค์ข้อมูลรูปโปรไฟล์จาก Google OAuth
- `POST /api/v1/auth/change-password` - เปลี่ยนรหัสผ่าน
- `POST /api/v1/auth/send-otp` - ส่ง OTP สำหรับรีเซ็ตรหัสผ่าน
- `POST /api/v1/auth/verify-otp` - ตรวจสอบรหัส OTP
- `GET /api/v1/user/profile` - ดึงข้อมูลโปรไฟล์ผู้ใช้งาน
- `PUT /api/v1/user/profile` - อัปเดตข้อมูลโปรไฟล์
- `PUT /api/v1/user/contact` - บันทึกเบอร์โทรศัพท์ติดต่อ
- `POST /api/v1/user/fcm-token` - บันทึกหรืออัปเดต FCM Device Token

### Items Management
- `GET /api/v1/items` - รายการอุปกรณ์ (รองรับ Query Params: `category`, `search`, `limit`, `offset`)
- `POST /api/v1/items` - ลงประกาศอุปกรณ์ให้เช่าใหม่
- `GET /api/v1/items/:id` - ดูรายละเอียดอุปกรณ์ตาม ID
- `PUT /api/v1/items/:id` - อัปเดตข้อมูลอุปกรณ์ (เฉพาะเจ้าของ)
- `DELETE /api/v1/items/:id` - ลบรายการอุปกรณ์ (เฉพาะเจ้าของ)

### Rental Orders & Handover
- `POST /api/v1/rentals` - สร้างคำขอเช่าอุปกรณ์และหักเงิน Wallet
- `POST /api/v1/rentals/:id/handover` - ยืนยันการส่งมอบอุปกรณ์ (OTP/QR)
- `POST /api/v1/rentals/:id/return` - ยืนยันการรับคืนอุปกรณ์และปลดล็อกเงินมัดจำ

### Chat & Notifications
- `POST /api/v1/chat/contact` - ดึงข้อมูลคู่สนทนาแบบปลอดภัย
- `POST /api/v1/push/chat` - ส่งการแจ้งเตือน Push Notification เมื่อมีข้อความใหม่

### AI Chatbot Gateway
- `POST /api/v1/chat-ai` - สนทนากับ AI (Full JSON Response)
- `POST /api/v1/chat-ai/stream` - สนทนากับ AI แบบถ่ายทอดสด (Server-Sent Events)

---

## 🔒 ความปลอดภัยและการควบคุมสิทธิ์ (Security & Hardening)

1. **X-App-Secret Verification**: ป้องกัน Direct Endpoint Abuse โดยบังคับให้คำขอส่งมาจาก Mobile Client ที่มีกุญแจลับที่ถูกต้อง รองรับการทำ Zero-Downtime Secret Rotation
2. **In-Memory Token Bucket Rate Limiting**:
   - Authentication Group: จำกัด 5 ครั้งต่อนาที ป้องกัน Brute-force โจมตีรหัสผ่าน
   - AI Chatbot Group: จำกัด 15 ครั้งต่อนาที ป้องกันการใช้ทรัพยากร AI เกินขนาด
3. **Automated Scanner Path Blocking**: ตัดการเชื่อมต่อและตอบกลับ 404 ทันทีหากพบลักษณะ URL สแกนช่องโหว่ เช่น `.env`, `.git`, `.php`
4. **Structured Logging (log/slog)**: จัดเก็บ Log เป็น JSON Format ในโหมด Release พร้อมเซนเซอร์ข้อมูลที่เป็นความลับ เช่น รหัสผ่านและ Bearer Token

---

## 🧪 การทดสอบ (Testing)

โปรเจกต์ใช้ `testify` สำหรับการทำ Mocking และ Unit Testing โดยไม่ต้องเชื่อมต่อฐานข้อมูลภายนอกจริง:

```bash
cd backend
go test -v ./tests/...
```

รันการทดสอบพร้อมตรวจสอบ Code Coverage:
```bash
go test -cover ./...
```
