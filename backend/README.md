<div align="center">

# 🛠️ Yuemnoi — Backend API Server

### ระบบ API หลังบ้านของแอปพลิเคชัน "ยืมหน่อย"

[![Go](https://img.shields.io/badge/Go-1.26-00ADD8?style=for-the-badge&logo=go&logoColor=white)](https://go.dev)
[![Gin](https://img.shields.io/badge/Gin-1.12-00897B?style=for-the-badge&logo=go&logoColor=white)](https://gin-gonic.com)
[![Supabase](https://img.shields.io/badge/Supabase-Database-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)](https://supabase.com)

<br/>

> **Backend API** ที่เป็นตัวกลางเชื่อมต่อระหว่าง Flutter Frontend กับฐานข้อมูล Supabase  
> และ AI Service ที่ประมวลผลด้วยโมเดลภาษา Qwen

</div>

---

## 📖 ภาพรวมระบบ

Backend ของ Yuemnoi ถูกพัฒนาด้วยภาษา **Go** โดยใช้ **Gin** เป็น HTTP Framework หลัก และออกแบบตาม **Hexagonal Architecture (Ports & Adapters)** เพื่อให้สามารถแยกส่วนของ Business Logic ออกจาก Infrastructure ได้อย่างสะอาด สามารถเปลี่ยนฐานข้อมูลหรือ External Service ได้โดยไม่กระทบ Core Logic

---

## 📂 โครงสร้างโปรเจ็ค

```
backend/
├── 📄 .air.toml                          # ตั้งค่า Air (Hot Reload ขณะพัฒนา)
├── 📄 .env                               # ตัวแปรสภาพแวดล้อม (Environment Variables)
├── 📄 go.mod                             # Go Module Dependencies
├── 📄 go.sum                             # Checksum ของ Dependencies
│
├── 📁 cmd/
│   └── 📁 server/
│       └── 📄 main.go                    # 🚀 จุดเริ่มต้นของแอปพลิเคชัน (Entry Point)
│
├── 📁 internal/
│   ├── 📁 domain/                        # 💎 Business Entities & Repository Interfaces
│   │   ├── 📄 item.go                    #    โครงสร้างข้อมูลอุปกรณ์เช่า (Item, Review)
│   │   ├── 📄 transaction.go            #    โครงสร้างข้อมูลกระเป๋าเงิน & ธุรกรรม (Wallet, Transaction)
│   │   └── 📄 user.go                    #    โครงสร้างข้อมูลผู้ใช้ & การยืนยันตัวตน (Profile, Verification)
│   │
│   ├── 📁 adapters/                      # 🔌 การเชื่อมต่อกับระบบภายนอก (Infrastructure Layer)
│   │   ├── 📁 supabase/
│   │   │   ├── 📄 client.go              #    สร้างและตรวจสอบ Supabase Client
│   │   │   └── 📄 item_repository.go    #    อ่าน/เขียนข้อมูลตาราง item_tb บน Supabase
│   │   └── 📁 service/
│   │       └── 📄 ai_service.go          #    Adapter สื่อสารกับ AI Service (Python FastAPI)
│   │
│   └── 📁 ports/                         # 🌐 HTTP Handlers & Router (Application Layer)
│       ├── 📄 router.go                  #    จัดเส้นทาง API ทั้งหมด + CORS Middleware
│       ├── 📄 item_handler.go            #    Handler จัดการข้อมูลอุปกรณ์เช่า
│       ├── 📄 rental_handler.go          #    Handler จัดการการจอง/เช่าอุปกรณ์
│       └── 📄 ai_handler.go              #    Handler รับข้อความแชทและส่งต่อไปยัง AI Service
```

---

## 🧩 รายละเอียดแต่ละส่วน

### 🚀 `cmd/server/main.go` — จุดเริ่มต้น

ไฟล์นี้ทำหน้าที่:

- อ่านค่า **Environment Variables** (`PORT`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `AI_SERVICE_URL`)
- สร้าง **Supabase Client** และ **AI Service Adapter**
- ตั้งค่า **HTTP Server** พร้อม Timeout ที่ปรับให้รองรับ LLM Pipeline (Write Timeout 90 วินาที)
- รัน Server แบบ **Non-blocking** ด้วย Goroutine
- รองรับ **Graceful Shutdown** (รอ Request ที่ค้างอยู่จบก่อนปิดเซิร์ฟเวอร์)

---

### 💎 `internal/domain/` — Business Entities

ชั้น Domain เป็นหัวใจหลักของระบบ ไม่พึ่งพา Framework หรือ Database ใดๆ

| ไฟล์             | Struct หลัก               | คำอธิบาย                                                                    |
| :--------------- | :------------------------ | :-------------------------------------------------------------------------- |
| `item.go`        | `Item`, `Review`          | โครงสร้างข้อมูลอุปกรณ์เช่า (ชื่อ, รูปภาพ, หมวดหมู่, สถานะ, ประเภท) และรีวิว |
| `transaction.go` | `Wallet`, `Transaction`   | กระเป๋าเงินของผู้ใช้และธุรกรรมการชำระเงิน (ฝาก/ถอน/จ่ายค่าเช่า)             |
| `user.go`        | `Profile`, `Verification` | โปรไฟล์ผู้ใช้ (พิกัด GPS) และข้อมูลการยืนยันตัวตน KYC (NDID/ThaiD)          |

แต่ละไฟล์ประกาศ **Repository Interface** ไว้ด้วย เพื่อให้ชั้น Adapter ไปเขียน Implementation จริง:

```go
// ตัวอย่างจาก item.go
type ItemRepository interface {
    Insert(ctx context.Context, item *Item) error
    FindAll(ctx context.Context) ([]Item, error)
}
```

---

### 🔌 `internal/adapters/` — Infrastructure Layer

#### `supabase/client.go`

สร้างและตรวจสอบ **Supabase Client** ถ้า URL หรือ Key ว่างจะ **Fatal** ทันทีเพื่อป้องกันไม่ให้ระบบรันโดยไม่มีฐานข้อมูล

#### `supabase/item_repository.go`

Implement `domain.ItemRepository` โดยใช้ Supabase Go SDK:

- **`Insert()`** — เพิ่มข้อมูลอุปกรณ์ใหม่ลงตาราง `item_tb`
- **`FindAll()`** — ดึงข้อมูลอุปกรณ์เช่าทั้งหมด
- **`FindByID()`** — ดึงข้อมูลอุปกรณ์ตาม ID
- **`Update()`** — แก้ไขข้อมูลโดยตรวจทั้ง ID และเจ้าของรายการ
- **`Delete()`** — ลบข้อมูลโดยตรวจทั้ง ID และเจ้าของรายการ

#### `service/ai_service.go`

Adapter สำหรับติดต่อกับ **AI Service** (Python FastAPI):

- ส่ง HTTP POST ไปยัง `/api/ai/chat` พร้อม Query และ Chat History
- ตั้งค่า Connection Pool (MaxIdleConns: 100, Timeout: 60 วินาที)
- Decode JSON Response และส่งกลับให้ Handler

---

### 🌐 `internal/ports/` — HTTP Handlers

#### `router.go`

จัดเส้นทาง API ทั้งหมดภายใต้ prefix `/api/v1`:

- ตั้งค่า **CORS** ให้ Flutter เรียกใช้งานได้
- ใช้ **Logger** และ **Recovery** Middleware

#### API Endpoints

| Method   | Endpoint            | Handler                           | คำอธิบาย                            |
| :------- | :------------------ | :-------------------------------- | :---------------------------------- |
| `GET`    | `/api/v1/items`     | `ItemHandler.GetAllItems`         | ดึงรายการอุปกรณ์เช่าทั้งหมด         |
| `GET`    | `/api/v1/items/:id` | `ItemHandler.GetItemByID`         | ดึงข้อมูลอุปกรณ์ตาม ID              |
| `POST`   | `/api/v1/items`     | `ItemHandler.CreateItem`          | เพิ่มอุปกรณ์ของผู้ใช้ที่เข้าสู่ระบบ |
| `PUT`    | `/api/v1/items/:id` | `ItemHandler.UpdateItem`          | แก้ไขอุปกรณ์ของเจ้าของรายการ        |
| `DELETE` | `/api/v1/items/:id` | `ItemHandler.DeleteItem`          | ลบอุปกรณ์ของเจ้าของรายการ           |
| `POST`   | `/api/v1/rentals`   | `RentalHandler.CreateRentalOrder` | สร้างใบจองเช่าอุปกรณ์               |
| `POST`   | `/api/v1/chat-ai`   | `AIHandler.HandleChat`            | ส่งข้อความแชทไปยัง AI และรับคำตอบ   |
| `POST`   | `/api/v1/chat/contact` | `ChatContactHandler.GetConversationContact` | ดึงเบอร์คู่สนทนาสำหรับสมาชิกในห้อง |

คำสั่ง `POST`, `PUT` และ `DELETE` ของ Items ต้องส่ง Supabase access token:

```http
Authorization: Bearer <SUPABASE_ACCESS_TOKEN>
```

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
GIN_MODE=debug                          # โหมด Gin (debug / release)
PORT=8080                               # พอร์ตที่เซิร์ฟเวอร์จะรัน
SUPABASE_URL=https://xxxxx.supabase.co  # URL ของ Supabase Project
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOi... # Service Role Key (ใช้เฉพาะ Backend ห้ามใส่ใน Flutter)
AI_SERVICE_URL=http://localhost:8000     # URL ของ AI Service (Python)
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

| เทคโนโลยี       | เวอร์ชัน | วัตถุประสงค์                                 |
| :-------------- | :------- | :------------------------------------------- |
| **Go**          | 1.26     | ภาษาหลักในการพัฒนา                           |
| **Gin**         | 1.12     | HTTP Web Framework                           |
| **Supabase Go** | 0.5.0    | SDK เชื่อมต่อฐานข้อมูล Supabase (PostgreSQL) |
| **godotenv**    | 1.5.1    | โหลดตัวแปรสภาพแวดล้อมจากไฟล์ `.env`          |
| **Air**         | —        | Hot Reload สำหรับ Development                |
| **JWT v5**      | 5.3.1    | จัดการ JSON Web Token                        |
| **Zap**         | 1.28.0   | Structured Logging                           |
| **gRPC**        | 1.81.1   | รองรับการสื่อสารแบบ gRPC (สำรอง)             |

---
