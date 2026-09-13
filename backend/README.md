<div align="center">

# 🛠️ Yuemnoi — Backend API Server

### ระบบ API หลังบ้านของแอปพลิเคชัน "ยืมหน่อย"

[![Go](https://img.shields.io/badge/Go-1.26-00ADD8?style=for-the-badge&logo=go&logoColor=white)](https://go.dev)
[![Gin](https://img.shields.io/badge/Gin-1.12-00897B?style=for-the-badge&logo=go&logoColor=white)](https://gin-gonic.com)
[![Supabase](https://img.shields.io/badge/Supabase-Database-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)](https://supabase.com)

<br/>

> **Backend API** ที่เป็นตัวกลางเชื่อมต่อระหว่าง Flutter Frontend กับฐานข้อมูล Supabase

</div>

---

## 📖 ภาพรวมระบบ

Backend ของ Yuemnoi ถูกพัฒนาด้วยภาษา **Go** โดยใช้ **Gin** เป็น HTTP Framework หลัก และออกแบบตาม **Hexagonal Architecture (Ports & Adapters)** เพื่อให้สามารถแยกส่วนของ Business Logic ออกจาก Infrastructure ได้อย่างสะอาด สามารถเปลี่ยนฐานข้อมูลหรือ External Service ได้โดยไม่กระทบ Core Logic

---

## 🧩 รายละเอียดแต่ละส่วน

### 🚀 `cmd/server/main.go` — จุดเริ่มต้น (Composition Root)

ไฟล์นี้ทำหน้าที่:

- อ่านค่า **Environment Variables** (`PORT`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `FIREBASE_SERVICE_ACCOUNT_PATH`, `APP_SECRET_KEY`)
- สร้าง **Supabase Client** และ **Adapters** ทั้งหมด (`ItemRepo`, `AuthGateway`, `ContactRepo`, `RentalRepo`, `FCMSender`)
- ฉีด Dependencies ทั้งหมดเข้า `ports.SetupRouter` (Dependency Injection)
- ตั้งค่า **HTTP Server** พร้อม Read/Write Timeout
- รัน Server แบบ **Non-blocking** ด้วย Goroutine
- รองรับ **Graceful Shutdown** (รอ Request ที่ค้างอยู่จบก่อนปิดเซิร์ฟเวอร์)

---

### 💎 `internal/domain/` — Business Entities & Ports

ชั้น Domain เป็นหัวใจหลักของระบบ เป็น Pure Go ไม่พึ่งพา Framework หรือ Database ใดๆ

| ไฟล์              | Struct & Interface หลัก                                  | คำอธิบาย                                                       |
| :---------------- | :------------------------------------------------------- | :------------------------------------------------------------- |
| `contact.go`      | `ConversationContactRepository`                          | สัญญาสิทธิ์การเข้าถึงข้อมูลติดต่อของผู้เข้าร่วมห้องสนทนา       |
| `item.go`         | `Item`, `RankedItem`, `ItemImage`, `ItemRepository`      | ข้อมูลอุปกรณ์เช่า, รูปภาพ, สถิติการจัดอันดับ และฟังก์ชันจัดการ |
| `notification.go` | `ChatPushNotification`, `PushNotificationSender`         | สัญญาการส่ง Push Notification สำหรับข้อความแชท                 |
| `rental.go`       | `RentalOrder`, `CreateRentalRequest`, `RentalRepository` | ข้อมูลคำขอและรายการเช่าอุปกรณ์                                 |
| `user.go`         | `UserProfile`, `AuthRepository`, `TokenVerifier`         | ข้อมูลโปรไฟล์, การเข้าสู่ระบบ และการตรวจสอบ Token              |

---

### 🔌 `internal/adapters/` — Infrastructure Layer

#### `fcm/fcm_sender.go`

Implement `domain.PushNotificationSender` ผ่าน FCM HTTP v1:

- จัดการ Service Account และแลกเปลี่ยน Google OAuth2 Access Token ด้วยการเซ็น JWT (RSA SHA256)
- ส่ง Chat Push Notification แบบมีเสียงและ Payload รองรับทั้ง iOS (APNs) และ Android
- แคช Token อัตโนมัติและล้าง Token ที่หมดอายุ (`UNREGISTERED`) ออกจากระบบ

#### `supabase/`

- **`client.go`** — สร้างและตรวจสอบ Supabase Client
- **`item_repository.go`** — จัดการ CRUD อุปกรณ์และดึงฟีดจาก `home_feed_ranked_v`
- **`user_repository.go`** — จัดการ Supabase Auth, Storage รูปโปรไฟล์, และข้อมูลใน `profile_tb`
- **`rental_repository.go`** — เรียก Database Function ตรวจสอบช่วงเวลาและคำนวณราคาเช่า
- **`contact_repository.go`** — ตรวจสอบสิทธิ์ผู้สนทนาและดึงเบอร์ติดต่อ

---

### 🌐 `internal/ports/` — Inbound HTTP Layer (Gin)

- **`auth_helper.go`** — รวมศูนย์ฟังก์ชันถอด Bearer Token และตรวจสอบความถูกต้องของสิทธิ์ผู้ใช้
- **`response_logging_middleware.go`** — ตรวจสอบและปิดบังข้อมูลส่วนบุคคล (PII/Tokens/Passwords) ใน Log ของ Response อัตโนมัติ
- **`router.go`** — จัดเส้นทาง API ทั้งหมดภายใต้ prefix `/api/v1` และเปิดใช้งาน CORS, Security Scanner Blocker, Response Redaction Logger

#### API Endpoints

| Method   | Endpoint                 | Handler                                     | คำอธิบาย                               |
| :------- | :----------------------- | :------------------------------------------ | :------------------------------------- |
| `GET`    | `/api/v1/items`          | `ItemHandler.GetAllItems`                   | ดึงฟีดอุปกรณ์พร้อมเช่าที่จัดอันดับแล้ว |
| `GET`    | `/api/v1/items/:id`      | `ItemHandler.GetItemByID`                   | ดึงข้อมูลอุปกรณ์ตาม ID                 |
| `POST`   | `/api/v1/items`          | `ItemHandler.CreateItem`                    | เพิ่มอุปกรณ์ของผู้ใช้ที่เข้าสู่ระบบ    |
| `PUT`    | `/api/v1/items/:id`      | `ItemHandler.UpdateItem`                    | แก้ไขอุปกรณ์ของเจ้าของรายการ           |
| `DELETE` | `/api/v1/items/:id`      | `ItemHandler.DeleteItem`                    | ลบอุปกรณ์ของเจ้าของรายการ              |
| `POST`   | `/api/v1/rentals`        | `RentalHandler.CreateRentalOrder`           | สร้างใบจองเช่าอุปกรณ์                  |
| `POST`   | `/api/v1/chat/contact`   | `ChatContactHandler.GetConversationContact` | ดึงเบอร์คู่สนทนาสำหรับสมาชิกในห้อง     |
| `POST`   | `/api/v1/chat-ai`        | `ChatbotHandler.SendMessage`                | สนทนากับ AI Chatbot แบบ Non-Streaming  |
| `POST`   | `/api/v1/chat-ai/stream` | `ChatbotHandler.SendMessageStream`          | สนทนากับ AI Chatbot แบบ SSE Streaming  |

คำสั่ง `POST`, `PUT` และ `DELETE` ของ Items ต้องส่ง Supabase access token:

```http
Authorization: Bearer <SUPABASE_ACCESS_TOKEN>
```

`GET /api/v1/items` เรียงฟีดจากยอดเช่าที่ชำระแล้ว คะแนนรีวิว ความใหม่
และความหลากหลายของหมวดหมู่/เจ้าของ โดยคืน `rating`, `review_count` และ
`paid_booking_count` เพิ่มเติม แต่ไม่เปิดเผยคะแนนจัดอันดับภายใน

`POST /api/v1/chat/contact` ต้องส่ง access token เช่นกัน และจะคืนข้อมูลติดต่อ
เฉพาะเมื่อผู้ใช้เป็นผู้เช่าหรือเจ้าของในห้องสนทนาที่ระบุเท่านั้น

การเพิ่มอุปกรณ์ใช้ `multipart/form-data` และแนบรูปด้วยชื่อฟิลด์ `images` ได้สูงสุด 5 รูป
(JPEG, PNG หรือ WebP รูปละไม่เกิน 5 MB):

```bash
curl -X POST http://localhost:8080/api/v1/items \
  -H "Authorization: Bearer <SUPABASE_ACCESS_TOKEN>" \
  -F "item_name=กล้องถ่ายวิดีโอ 4K" \
  -F "description=กล้องพร้อมแบตเตอรี่และกระเป๋า" \
  -F "category=กล้อง" \
  -F "price=2500" \
  -F "type=รายวัน" \
  -F "images=@camera-front.jpg" \
  -F "images=@camera-back.jpg"
```

Backend จะสร้างรายการด้วยสถานะ `pending` อัตโนมัติ อัปโหลดรูปไปที่ bucket
`item_bk` ภายใต้ path `{item_id}/...` และบันทึก public URL ลง `item_tb.item_image_url`

ตัวอย่างแก้ไขเฉพาะบางฟิลด์:

```json
{
  "price": 2200,
  "status": "available"
}
```

`user_id` จะถูกอ่านจาก access token โดย Backend และไม่รับค่าจาก request body

---

## ⚙️ ตัวแปรสภาพแวดล้อม (Environment Variables)

สร้างไฟล์ `.env` ในโฟลเดอร์ `backend/` :

```env
GIN_MODE=debug
PORT=.......
SUPABASE_URL=......
SUPABASE_SERVICE_ROLE_KEY=.......
FIREBASE_SERVICE_ACCOUNT_PATH=......
APP_SECRET_KEY=......
INTERNAL_SERVICE_KEY=......
```

---

## 🚀 วิธีรันโปรเจ็ค

### ข้อกำหนดเบื้องต้น

- [Go](https://go.dev/dl/) เวอร์ชัน 1.26 ขึ้นไป
- [Air](https://github.com/air-verse/air) (สำหรับ Hot Reload ขณะพัฒนา)

### ติดตั้ง Dependencies

หลังจาก clone โปรเจกต์ ให้เข้าไปที่โฟลเดอร์ `backend` และติดตั้ง package ที่ระบุไว้ใน `go.mod` ด้วยคำสั่ง:

```bash
cd backend
go mod tidy
```

### รันด้วย Air (แนะนำสำหรับการพัฒนา)

```bash
cd backend
go install github.com/air-verse/air@latest
air
```

Air จะคอยดูไฟล์ `.go`, `.tpl`, `.tmpl`, `.html` และ Build ใหม่อัตโนมัติเมื่อมีการแก้ไข

### รันด้วย Go ตรงๆ

```bash
cd backend
go run ./cmd/server/main.go
```

### Build สำหรับ Production

```bash
cd backend
go build -o ./tmp/main ./cmd/server/main.go
./tmp/main
```

เซิร์ฟเวอร์จะรันที่ `http://localhost:8080` (หรือพอร์ตที่กำหนดใน `.env`)

---

## 📚 เทคโนโลยีที่ใช้

| เทคโนโลยี        | เวอร์ชัน | วัตถุประสงค์                                        |
| :--------------- | :------- | :-------------------------------------------------- |
| **Go**           | 1.26     | ภาษาหลักในการพัฒนา                                  |
| **Gin**          | 1.12     | HTTP Web Framework                                  |
| **Supabase Go**  | 0.5.0    | SDK เชื่อมต่อฐานข้อมูล Supabase (PostgreSQL)        |
| **caarlos0/env** | 11.4     | อ่านและ Parse Environment Variables เป็น Go Struct  |
| **godotenv**     | 1.5.1    | โหลดตัวแปรสภาพแวดล้อมจากไฟล์ `.env`                 |
| **log/slog**     | Go std   | Structured Logging พร้อมฟังก์ชัน Redact ข้อมูลสำคัญ |
| **testify**      | 1.12     | Unit Test Assertions & Test Suites                  |
| **Air**          | —        | Hot Reload สำหรับ Development                       |

---
