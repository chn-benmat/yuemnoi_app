<div align="center">

<img src="../frontend/assets/images/yuemnoi.png" width="88" alt="Yuemnoi logo">

# ยืมหน่อย · Backend API

**จัดการข้อมูล การเช่า และเชื่อมแอปกับบริการภายนอก**

![Go](https://img.shields.io/badge/Go-1.26.2-00ADD8?style=flat-square&logo=go&logoColor=white)
![Fiber](https://img.shields.io/badge/Fiber-3.5.0-00ACD7?style=flat-square)
![Supabase](https://img.shields.io/badge/Data-Supabase-3ECF8E?style=flat-square&logo=supabase&logoColor=white)
![Architecture](https://img.shields.io/badge/Architecture-Hexagonal-9251D0?style=flat-square)

[ภาพรวม](#overview) · [Tech stack](#stack) · [ตั้งค่า](#setup) · [เริ่มรัน](#run) · [API](#api) · [ตรวจงาน](#development) · [แก้ปัญหา](#troubleshooting)

[Project](../README.md) / [Frontend](../frontend/README.md) / **Backend** / [AI Service](../ai_service/README.md)

</div>

---

<a id="overview"></a>

## ✨ ส่วนนี้ทำอะไร

Go Backend เป็น REST API หลักของ **Yuemnoi** เชื่อม Flutter กับ Supabase, Firebase และ Python AI ใช้ **Hexagonal Architecture** แยก business entities / interfaces ออกจาก HTTP และบริการภายนอก

| ความสามารถ      | หน้าที่ของ Backend                                                         |
| --------------- | -------------------------------------------------------------------------- |
| 🔑 Auth         | สมัครสมาชิก, login, email OTP, เปลี่ยนรหัสผ่าน และซิงค์รูปจาก Google OAuth |
| 👤 Profile      | อ่าน / แก้ไขโปรไฟล์, contact และ FCM token ของผู้ใช้                       |
| 📸 Items        | ฟีดจาก ranked view, ค้นหา / กรองหมวดหมู่, CRUD และจัดการรูป                |
| 📅 Rental       | สร้างคำขอผ่าน Supabase RPC, ตรวจผู้มีสิทธิ์และเปลี่ยนสถานะส่งมอบ / รับคืน  |
| 💬 Chat contact | ตรวจสิทธิ์คู่สนทนาก่อนอ่านข้อมูลติดต่อ                                     |
| 🔔 Push         | ส่งแจ้งเตือนแชตผ่าน FCM HTTP v1 และจัดการ device token ที่หมดอายุ          |
| 🤖 AI Gateway   | ส่งคำขอ JSON / SSE ไป Python พร้อม internal service key                    |

การสร้างคำขอเช่าเรียก RPC `create_rental_request` และส่งมอบเป็น `active` ขั้นตอนคืนใช้ `return-evidence` (ผู้เช่าส่งรูป 3 รูปและ checklist) -> `return-inspection` (เจ้าของตรวจและสร้าง QR/OTP) -> `return` (ผู้เช่าส่ง `token_or_otp` ให้ server ตรวจ) สถานะผ่าน `awaiting_return` และ `return_ready` ก่อน `completed`; รหัสหมดอายุใน 5 นาที จำกัด 5 ครั้งและใช้ซ้ำไม่ได้ การยกเลิกก่อนส่งมอบใช้ `cancel` พร้อมเหตุผลและหลักฐาน ไม่มีการหัก Wallet หรือคืนเงินจริงใน flow นี้

แจ้งเตือนแชต การเช่า และระบบเก็บใน `notification_tb` พร้อม outbox จาก transaction ของเหตุการณ์ Worker ส่ง FCM ไปยังทุกอุปกรณ์ใน `notification_device_tb`; ไม่ใช้ `profile_tb.fcm_token` เป็นแหล่งส่งอีกแล้ว API ประวัติ/อ่าน/ลงทะเบียนเครื่องอยู่ที่ `/api/notifications` รายละเอียดและ SQL tests อยู่ใน [ข้อตกลงระบบแจ้งเตือน](../docs/notifications.md)

การยืนยันข้อเสนอจากแชทมีสองขั้นตอน: `POST /api/rentals` พร้อม `offer_message_id` สร้างหรือเรียกใช้ booking เดิมเป็น `pending` และผูก `bookingId` / `status` ในข้อความเดิม จากนั้นเมื่อผู้เช่ากดปุ่ม “ยืนยันการเช่า” ในหน้าสรุป จึงเรียก `POST /api/rentals/:id/confirm` พร้อม `offer_message_id` เพื่อเปลี่ยนเป็น `confirmed` และเผยแพร่สถานะให้ทั้งสองเครื่อง Backend ตรวจผู้เช่า เจ้าของสินค้าจริง คู่สนทนา เงื่อนไขข้อเสนอ และเลข booking ที่ผูกกับข้อความซ้ำก่อนยืนยัน การเปิดหรือปิดหน้าสรุปไม่เปลี่ยนสถานะ การลองใหม่ใช้เลขรายการเดิมโดยไม่สร้างซ้ำ รายการ `pending` ยังไม่แสดงในหน้าสถานะการเช่า

เงื่อนไขเทียบข้อความก่อนบันทึกใช้ PostgREST `eq` กับข้อความเดิมตรงตัว โดยเข้ารหัส URL เพื่อชดเชย SDK ที่ถอด encoding ก่อนส่ง ห้ามเติมอัญประกาศหรือ escape JSON ซ้ำ เพราะจะค้นได้ 0 แถวและทำให้ข้อเสนอที่ถูกต้องถูกปฏิเสธเป็น `invalid rental` กรณีทดสอบใน `rental_offer_test.go` ตรวจ filter จริงหลังถอด URL รวมข้อความไทย บรรทัดใหม่ และ JSON

### ภาพรวมการเชื่อมต่อ

```mermaid
flowchart LR
    App["Flutter"] -->|"REST / SSE"| API["Fiber API :8080"]
    API --> SB["Supabase Auth / Database / Storage"]
    API --> FCM["Firebase FCM HTTP v1"]
    API -->|"X-Internal-Service-Key"| AI["Python AI :8000"]
```

Frontend ยังใช้ Supabase โดยตรงในบางฟีเจอร์ รายละเอียดอยู่ใน [Frontend README](../frontend/README.md)

บัญชีที่มี `app_metadata.dashboard_only = true` ใช้ได้เฉพาะ dashboard: `POST /api/auth/login`, OTP และ API ส่วนตัวของแอปตอบ HTTP 403 พร้อม `code: dashboard_only` โดยตรวจ metadata ปัจจุบันจาก Supabase Auth ทุกครั้ง `GET /api/auth/session` ใช้ตรวจ OAuth และ session ที่กู้คืน ส่วน dashboard ใช้ `POST /api/admin/login` และตรวจสิทธิ์เจ้าหน้าที่ก่อนคืน token ใช้ [migration](../supabase/migrations/20261017094213_restrict_dashboard_only_accounts.sql) เพื่อกำหนดบัญชี `admin_yuemnoi@gmail.com` และบังคับ RLS สำหรับการเข้าถึง Supabase โดยตรงด้วย JWT เดิม ทดสอบฐานข้อมูลแบบ rollback ได้ด้วย [dashboard_only_access.sql](../supabase/tests/dashboard_only_access.sql)

<a id="stack"></a>

## 🧰 Tech stack & versions

เวอร์ชันอ้างอิง [go.mod](go.mod) และ checksums อยู่ใน [go.sum](go.sum)

| เครื่องมือ / module                      | เวอร์ชัน                                                    | ใช้ทำอะไร                                                          |
| ---------------------------------------- | ----------------------------------------------------------- | ------------------------------------------------------------------ |
| Go                                       | **1.26.2** ตาม go directive; ใช้ toolchain ที่ตรงหรือรองรับ | ภาษา, HTTP client/server และ concurrency                           |
| `github.com/gofiber/fiber/v3`            | v3.5.0                                                      | Router, handlers และ middleware                                    |
| `github.com/caarlos0/env/v11`            | v11.4.1                                                     | อ่าน env ลง typed configuration                                    |
| `github.com/go-playground/validator/v10` | v10.30.1                                                    | ตรวจ `validate` tags ของ request DTOs ผ่าน Fiber `StructValidator` |
| `github.com/joho/godotenv`               | v1.5.1                                                      | โหลดไฟล์ `.env`                                                    |
| `github.com/nedpals/supabase-go`         | v0.5.0                                                      | Supabase Auth / PostgREST                                          |
| `firebase.google.com/go/v4`              | v4.22.0                                                     | Firebase Admin SDK สำหรับ FCM                                      |
| `cloud.google.com/go/auth`               | v0.20.0                                                     | Credentials, OAuth และ HTTP transport ของ Google                   |
| `google.golang.org/api`                  | v0.279.0                                                    | Client options สำหรับ Firebase SDK                                 |
| `golang.org/x/time`                      | v0.16.0                                                     | Token Bucket ผ่าน package `rate`                                   |
| `github.com/jellydator/ttlcache/v3`      | v3.4.1                                                      | Cache อายุข้อมูลตาม TTL สำหรับ IP buckets และ FCM device tokens    |
| `github.com/lmittmann/tint`              | v1.2.1                                                      | Console handler สำหรับ `log/slog` ในโหมด debug                     |
| `github.com/stretchr/testify`            | v1.12.1                                                     | Assertions และ mocks ใน tests                                      |
| Go standard library                      | ตาม Go toolchain                                            | `net/http`, `log/slog` และ Supabase Storage adapter                |

FCM adapter ใช้ Firebase Admin SDK ส่ง HTTP v1 และใช้ Google Auth จัดการ credentials / OAuth โดยคง data, Android channel และเสียงแจ้งเตือนเดิม ส่วน Supabase Storage ใช้ HTTP adapter ที่ส่ง context และคืน error แทนการเรียก Upload / Remove ของ SDK เดิม Supabase / Firebase / AI เป็นบริการภายนอก จึงไม่มีเวอร์ชัน server ที่ pin ไว้ใน go.mod

<a id="setup"></a>

## ⚙️ เตรียมเครื่อง & configuration

### 1. เครื่องมือและบริการที่ต้องมี

- Git และ [Go toolchain](https://go.dev/doc/install) ที่รองรับ `go 1.26.2`
- Supabase project พร้อม Auth และ schema ของแอปตามรายการด้านล่าง
- Python AI Service เมื่อต้องใช้ Chatbot
- Firebase service account เมื่อต้องส่ง push notifications จริง

ควรเก็บ checkout ของ `backend/`, `frontend/` และ `ai_service/` ไว้ในโครงสร้าง repository เดียวกัน เพราะ configuration และ tests บางส่วนอ้างอิงไฟล์ข้ามส่วน

### 2. เตรียม Supabase ให้ตรงกับโค้ด

**สร้าง project เปล่าอย่างเดียวยังไม่พอ**: checkout นี้ไม่มี SQL migrations / schema bootstrap สำหรับสร้างฐานข้อมูลครบทั้งระบบ ให้ใช้ schema ที่ทีมดูแลสำหรับ environment นั้น แล้วตรวจรายการสำคัญต่อไปนี้

| ประเภท         | สิ่งที่ Backend ใช้                                                                                   |
| -------------- | ----------------------------------------------------------------------------------------------------- |
| Tables         | `public.item_tb`, `public.booking_tb`, `profiles.profile_tb`, `messaging.conversation_tb`, `messaging.chat_message_tb` |
| View           | `public.home_feed_ranked_v` สำหรับฟีด และ `profiles.public_profile_v` สำหรับโปรไฟล์ที่เปิดอ่านได้ |
| RPC            | `check_email_exists(search_email)` → boolean                                                          |
| RPC            | `create_rental_request(p_user_id, p_item_id, p_start_at, p_end_at, p_rental_type, p_pickup_location)` |
| Storage        | `item_bk` และ `profile_bk` รองรับรูปแบบ URL ที่ adapters ใช้                                          |
| Auth → Profile | Trigger สร้างแถว `profiles.profile_tb` เมื่อสร้าง Auth user เพราะ registration flow ปัจจุบันอัปเดตแถวที่มีอยู่ |
| Permissions    | grants / RLS / Storage policies ให้ตรงกับทั้ง Backend และ Flutter ที่เข้าถึงโดยตรง                    |

ใช้ [migration แยก schema ตามโมดูล](../supabase/README.md) พร้อม Backend และ Flutter รุ่นนี้ โดย notification tables อยู่ใน `notifications` และ RPC คงชื่อเดิมใน `public`

Backend ใช้ตัวแปรชื่อ `SUPABASE_SERVICE_ROLE_KEY` และ SDK / adapters ตามเวอร์ชันในตาราง ให้ใช้ server credential ที่ตรงกับ integration นี้และเก็บไว้ฝั่งเซิร์ฟเวอร์ ดู [Supabase API keys](https://supabase.com/docs/guides/getting-started/api-keys) ก่อนเลือกหรือเปลี่ยนชนิดคีย์; README นี้ไม่ได้เปลี่ยน implementation ให้รองรับการย้ายคีย์แบบใหม่

OTP flow ปัจจุบันใช้ Supabase email OTP ผ่าน Magic Link template หากต้องการให้ผู้ใช้กรอกรหัสหกหลัก ต้องตั้ง template ให้แสดง `{{ .Token }}` ตาม flow ที่แอปใช้ Google login เริ่มจาก Supabase OAuth ใน Flutter ส่วน Backend ซิงค์รูปของผู้ใช้ที่ login แล้ว

### 3. สร้างไฟล์ `.env`

สร้างในโฟลเดอร์ `backend/` แล้วแทนค่า `replace-with-...` ด้วยค่าของ environment จริง ไม่มีไฟล์ `.env.example` ให้ copy ใน checkout นี้

```dotenv
PORT=8080
APP_ENV=debug

SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=replace-with-backend-service-role-key

APP_SECRET_KEY=replace-with-client-app-key
INTERNAL_SERVICE_KEY=replace-with-shared-internal-key-at-least-32-chars

AI_SERVICE_URL=http://localhost:8000
AI_CLIENT_RUNTIME_PATH=../ai_service/config/chat_client_runtime.json

READ_TIMEOUT=15s
WRITE_TIMEOUT=90s
SHUTDOWN_TIMEOUT=5s

# ใส่เมื่อใช้ push notifications
# FIREBASE_SERVICE_ACCOUNT_PATH=service-account.json
```

`APP_SECRET_KEY` ใน Flutter ต้องตรงกับหนึ่งใน app keys ของ Backend และ `INTERNAL_SERVICE_KEY` ใน Python ต้องตรงกับคีย์ internal ที่ Backend ส่ง ทั้งสองคีย์มีหน้าที่ต่างกัน

### ตัวแปรทั้งหมดที่รองรับ

| ตัวแปร                          | Default                 | ต้องตั้งเมื่อ / ความหมาย                                    |
| ------------------------------- | ----------------------- | ----------------------------------------------------------- |
| `PORT`                          | `8080`                  | พอร์ต HTTP                                                  |
| `APP_ENV`                       | `debug`                 | ใช้ `release` เพื่อตรวจคอนฟิก production และใช้ JSON slog   |
| `SUPABASE_URL`                  | ไม่มี                   | **จำเป็นทุกโหมด**                                           |
| `SUPABASE_SERVICE_ROLE_KEY`     | ไม่มี                   | **จำเป็นทุกโหมด**, server-only                              |
| `FIREBASE_SERVICE_ACCOUNT_PATH` | ไม่มี                   | path ของ service account สำหรับ FCM                         |
| `FIREBASE_SERVICE_ACCOUNT_KEY`  | ไม่มี                   | service account JSON แบบ inline; มีลำดับก่อน path           |
| `APP_SECRET_KEY`                | ไม่มี                   | app key เดี่ยวหรือคั่น comma; ต้องมีคีย์ใน release          |
| `APP_SECRET_KEYS`               | ไม่มี                   | app keys เพิ่มเติมคั่น comma; รวมกับตัวแปรด้านบน            |
| `INTERNAL_SERVICE_KEY`          | ไม่มี                   | ต้องมีใน release; primary key ยาวอย่างน้อย **16 ตัวอักษร**  |
| `AI_SERVICE_URL`                | `http://localhost:8000` | **Base URL** ของ Python ไม่ต่อ `/api/chat`                  |
| `AI_SERVICE_TIMEOUT`            | `45s`                   | Go duration ที่มากกว่า 0; env ที่ระบุชัดเจนชนะ runtime JSON |
| `AI_CLIENT_RUNTIME_PATH`        | ไม่มี                   | อ่าน gateway timeout จาก shared JSON เมื่อกำหนด path        |
| `READ_TIMEOUT`                  | `15s`                   | HTTP server read timeout                                    |
| `WRITE_TIMEOUT`                 | `90s`                   | HTTP server write timeout                                   |
| `SHUTDOWN_TIMEOUT`              | `5s`                    | เวลา graceful shutdown                                      |

[Config loader](internal/config/config.go) โหลด `.env` จาก working directory ก่อน และลอง `../../.env` หากไฟล์แรกโหลดไม่สำเร็จ แนะนำให้รันจาก `backend/` เพื่อให้ paths ของ Firebase และ shared runtime ชัดเจน Process environment ที่มีอยู่มีลำดับก่อนค่าจาก dotenv

`APP_ENV` เป็นชื่อคอนฟิกหลักของ runtime; deployment เดิมยังใช้ `GIN_MODE` เป็น fallback ได้ เมื่อกำหนด `APP_ENV` ไว้จะมีสิทธิ์สูงกว่า โดยคงการตรวจ app key / internal key ในโหมด `release` เหมือนเดิม

**Release configuration:** ตั้ง `APP_ENV=release` พร้อม app key อย่างน้อยหนึ่งตัวจาก `APP_SECRET_KEY` / `APP_SECRET_KEYS` และ internal primary key อย่างน้อย 16 ตัวอักษร โค้ดไม่ได้บังคับความยาวขั้นต่ำของ app key ส่วน credential ของ Firebase เป็นเงื่อนไขสำหรับ push; ขาดแล้ว server ยังเริ่มได้พร้อม warning

<details>
<summary>ตั้งค่า Firebase และการหมุนคีย์</summary>

วาง service account นอก source control แล้วตั้ง `FIREBASE_SERVICE_ACCOUNT_PATH` ให้ชัดเจน หรือส่ง JSON ผ่าน `FIREBASE_SERVICE_ACCOUNT_KEY` ในระบบจัดการ secrets ฝั่ง server Firebase project ต้องตรงกับแอปที่สร้าง FCM device token

Backend รวม app keys จากสองตัวแปรและรับค่าใดค่าหนึ่งผ่าน `X-App-Secret` สำหรับ internal key Backend ส่ง **ตัวแรกที่ไม่ว่าง** ของรายการคั่น comma แต่ Python ตรวจ **ทั้ง string แบบตรงตัว** จึงแนะนำให้ใช้ **คีย์เดียวที่เหมือนกัน** ใน Backend และ AI หากหมุนคีย์ ต้องให้ Python รับค่าเดียวกับ primary ที่ Backend ส่ง

</details>

<a id="run"></a>

## 🚀 ติดตั้ง & เริ่มรัน

จาก root ของ repository คำสั่งนี้ใช้ได้ทั้ง Windows PowerShell และ macOS / Linux:

```sh
cd backend
go version
go mod download
go run main.go หรือ go run .
```

`main.go` เปิด HTTP server ด้วย Fiber `Listen` โดยตรง เมื่อแก้โค้ด ให้หยุดด้วย `Ctrl+C` แล้วรัน `go run main.go` ใหม่

ในโหมด debug ใช้รูปแบบและสีมาตรฐานของ `tint` เมื่อแสดง log ใน terminal รองรับ Windows console ด้วย เมื่อ redirect ไปไฟล์หรือ pipe จะเป็นข้อความไม่มีสี ส่วน `APP_ENV=release` ใช้ JSON log ระดับ Info ตามเดิม Access log เก็บเฉพาะ method, path, status และ latency โดยไม่เก็บ headers, query หรือ body

CORS ใช้ Fiber middleware ร่วมกับการตรวจ origin ตาม hostname เดิม: `http`/`https` ของ `localhost`, `127.0.0.1`, `yuemnoi.com`, subdomains ของ `yuemnoi.com` และ `.ts.net` อนุญาต credentials เฉพาะ origin ที่ผ่านการตรวจ คำขอ native ที่ไม่มี Origin ใช้ `*` โดยไม่มี credentials และ OPTIONS ยังคงตอบ 204 ก่อนตรวจ app key เพิ่ม `Vary: Origin` เพื่อให้ HTTP cache แยก response ตาม origin

Rate limiter ยังคงเป็น token bucket ของ `x/time/rate`: auth และ admin login แชร์ burst 5 เติม 1 token ทุก 12 วินาที, AI JSON/SSE แชร์ burst 15 เติม 1 token ทุก 4 วินาที และ identity/complaints แชร์ burst 5 อีกชุดหนึ่ง ทุกชุดแยกตาม client IP และเก็บ bucket ใน `ttlcache` จนไม่ได้ใช้งาน 10 นาที รวมคำขอที่ถูกปฏิเสธในการต่ออายุ idle TTL คำขอที่ถูกปฏิเสธไม่หัก token และคง JSON 429 กับข้อความเดิม ไม่เปลี่ยนเป็น fixed/sliding window

Push ใช้ durable outbox และ token ของอุปกรณ์ที่ยังผูกกับผู้รับใน `notification_device_tb` ตรวจการสลับบัญชี การอ่าน และวันหมดอายุก่อน claim งาน Worker ทำงานทุก 10 วินาทีพร้อม lease และ retry แบบจำกัด; token ที่ FCM ยืนยันว่า unregistered จะถูกปิดเฉพาะค่าที่ส่งจริง Adapter cache ของเส้นทางเก่ายังคงอยู่เพื่อ compatibility แต่เส้นทางแจ้งเตือนใหม่ไม่อ่าน cache นั้น

เปิด terminal อีกหน้าตรวจ HTTP server:

**Windows PowerShell**

```powershell
Invoke-RestMethod http://localhost:8080/health
```

**macOS / Linux**

```bash
curl http://localhost:8080/health
```

ผลที่คาดหวัง:

```json
{ "status": "ok" }
```

`/health` ตรวจว่า handler ของ server ตอบได้ เป็นผลคงที่ จึงยังต้องลองรายการสินค้า, Auth, AI และ push แยกเพื่อยืนยัน dependencies

ตัวอย่างเรียกรายการสินค้า เมื่อใช้ app key จาก env ตัวอย่าง ให้แทน placeholder ใน header ด้วยค่าที่ตั้งไว้:

```powershell
Invoke-RestMethod 'http://localhost:8080/api/items' -Headers @{
  'X-App-Secret' = 'replace-with-client-app-key'
}
```

```bash
curl http://localhost:8080/api/items \
  -H 'X-App-Secret: replace-with-client-app-key'
```

Go เปิด HTTP server ที่ `:8080` ตามค่า default มือถือ Android ในโปรเจกต์นี้บล็อก cleartext HTTP จึงต้องมี HTTPS endpoint หรือ native debug network policy ก่อนเชื่อมจากแอป ดูรายละเอียด URL ใน Frontend README

<a id="api"></a>

## 🌐 API & authentication

Base path คือ `/api` เส้นทางทั้งหมดอยู่ใน [router.go](internal/ports/router.go)

**App key:** เมื่อกำหนด app keys ไว้ ต้องส่ง `X-App-Secret` แม้อยู่ใน debug mode ยกเว้น `/health` และ OPTIONS หากไม่มี app keys ใน debug middleware นี้จะข้ามการตรวจ

**User identity:** routes ที่ต้อง login ใช้ `Authorization: Bearer <Supabase access token>` แยกจาก app key และตรวจสิทธิ์เจ้าของ / คู่สัญญาตาม handler

| Method / route                                            | หน้าที่                            | User Bearer                           |
| --------------------------------------------------------- | ---------------------------------- | ------------------------------------- |
| `GET /health`                                             | HTTP liveness                      | ไม่ต้อง                               |
| `POST /auth/register`, `POST /auth/login`                 | สมัคร / login                      | ไม่ต้อง                               |
| `POST /auth/send-otp`, `POST /auth/verify-otp`            | ส่ง / ตรวจ email OTP               | ไม่ต้อง                               |
| `POST /auth/google-profile`, `POST /auth/change-password` | ซิงค์รูป / เปลี่ยนรหัสผ่าน         | ต้องมี                                |
| `GET /user/profile`, `PUT /user/profile`                  | อ่าน / แก้โปรไฟล์                  | ต้องมี                                |
| `PUT /user/contact`, `POST /user/fcm-token`               | Contact / device token             | ต้องมี                                |
| `GET /items`, `GET /items/:id`                            | ฟีด / รายละเอียด                   | ไม่ต้อง                               |
| `POST /items`, `PUT /items/:id`, `DELETE /items/:id`      | จัดการอุปกรณ์                      | ต้องมี; ตรวจเจ้าของ                   |
| `GET /items/:id/auto-reply`, `PUT /items/:id/auto-reply` | อ่าน / บันทึกข้อความตอบกลับอัตโนมัติ | ต้องมี; ตรวจเจ้าของ                   |
| `POST /rentals`                                           | สร้างคำขอเช่า                      | ต้องมี                                |
| `POST /rentals/:id/confirm`                               | ผู้เช่ายืนยันข้อเสนอเป็น confirmed | ต้องมี; ตรวจผู้เช่าและข้อความข้อเสนอ  |
| `POST /rentals/:id/handover`, `POST /rentals/:id/return`  | เปลี่ยนสถานะ                       | ต้องมี; ตรวจผู้มีสิทธิ์               |
| `POST /chat/contact`, `POST /push/chat`                   | Contact / push                     | ต้องมี                                |
| `POST /chat-ai`, `POST /chat-ai/stream`                   | AI JSON / SSE                      | handler ปัจจุบันไม่บังคับ user Bearer |

ทุก route ในตารางยกเว้น `/health` ต้องเติม `/api` ด้านหน้า เช่น `/items` → `/api/items` เส้นทาง AI ยังผ่าน app-key middleware และ rate limiter แม้ handler จะไม่ตรวจ user Bearer

การตอบกลับอัตโนมัติรับ JSON `{ "enabled": true, "message": "ข้อความตอบกลับ" }` จำกัดข้อความหลัง trim ไม่เกิน 500 Unicode code points และเปิดใช้ได้เมื่อข้อความไม่ว่าง ค่าเริ่มต้นปิดไว้ เจ้าของต้องกดบันทึกก่อนมีผล โดยใช้ตารางตั้งค่าส่วนตัวแยกจาก item สาธารณะ ต้องติดตั้ง migrations `item_auto_reply` และ `item_auto_reply_actor_guard` ใน `../supabase/migrations/` ร่วมกับ API รุ่นนี้

เมื่อผู้เช่าส่งการ์ด `[ITEM_INQUIRY:{...}]` ฐานข้อมูลตรวจคู่สนทนาและเจ้าของอุปกรณ์จริง แล้วส่งข้อความเพียงครั้งเดียวต่อผู้เช่า–อุปกรณ์–เจ้าของ แม้ห้องเดิมจะเปลี่ยนไปคุยอุปกรณ์อื่นหรือเจ้าของไม่ได้เปิดแอป การแก้ข้อความ/ปิด–เปิดใหม่ไม่ reset ประวัติและไม่ส่งย้อนหลัง สินค้าที่เจ้าของซ่อนยังตอบการสอบถามในแชทเดิมได้ ข้อความเข้าสตรีม Realtime และประวัติแชทปกติ; ยังไม่ได้เพิ่ม OS push สำหรับข้อความตอบกลับอัตโนมัติ

Migration ย้ายการรักษา `conversation_tb.last_message` มาอยู่ฝั่งฐานข้อมูลพร้อมข้อความตอบกลับ และป้องกัน client รุ่นเดิมเขียนทับด้วยข้อความขาเข้า ตรวจแบบ rollback ด้วย `../supabase/tests/item_auto_reply.sql` โดยไม่มีข้อความทดสอบค้างในห้องจริง

- รายการสินค้าใช้ query `search` และ `category`; ยังไม่มี pagination แบบ `limit` / `offset` ใน handler ปัจจุบัน
- สร้าง item รองรับ JSON หรือ multipart; field รูปชื่อ `images` ไม่เกิน **5 รูป**, รูปละ **5 MiB**, JPEG / PNG / WebP
- รูปโปรไฟล์ใช้ multipart field `image` ไม่เกิน **5 MiB**
- รูปสินค้าใหม่เก็บที่ `item_bk/<owner_user_id>/<item_id>/<filename>` หลังสร้างไอดีสินค้า ส่วนรูปโปรไฟล์ทั้งตอนสมัครและแก้ไขเก็บที่ `profile_bk/<user_id>/<filename>`; URL และการลบรูปเดิมยังอ้างอิง path ที่บันทึกไว้
- Rate limiter ใช้ `golang.org/x/time/rate` เป็น token bucket **ต่อ client IP ใน memory**: Auth เติม 5/minute, burst 5; AI เติม 15/minute, burst 15 และตอบ 429 เมื่อเกิน กวาด IP ที่ไม่ได้ใช้งานระหว่างรับคำขอโดยไม่สร้าง background goroutine; หลาย server instance ยังไม่แชร์ตัวนับ
- Supabase Auth / PostgREST / Storage จำกัดเวลาคำขอไว้ **60s** รวมการอ่าน response body และเคารพ context ที่หมดเวลาก่อน ส่วนการชดเชยไฟล์ / รายการหลังบันทึกล้มเหลวใช้ context แยกไม่เกิน **5s** เพื่อทำความสะอาดได้แม้คำขอหลักถูกยกเลิก การล้างข้อมูลเป็น best effort และมี warning หากไม่สำเร็จ รูปโปรไฟล์ที่ยังมีการอ้างอิงหรือตรวจสอบไม่ได้จะถูกเก็บไว้ และ rollback อุปกรณ์จะลบแถวสำเร็จก่อนล้างไฟล์
- FCM จำกัดเวลางานส่งรวม **10s** รองรับ cancellation ทั้ง OAuth และ delivery SDK อาจ retry ข้อผิดพลาดชั่วคราวภายในเวลานี้ ลบ device token เฉพาะ error `UNREGISTERED` ที่ SDK ระบุชนิดได้; HTTP 404 ทั่วไปไม่ทำให้ token ถูกลบ

### AI contract

Go ส่ง `/chat-ai` ไป `/api/chat` ของ Python และ `/chat-ai/stream` ไป `/api/chat/stream` พร้อม `X-Internal-Service-Key`

Gateway ส่ง SSE `status` (`step` และ `message`) ต่อทันทีตามข้อมูลจาก Python รวมถึงขั้นเตรียมข้อมูล วิเคราะห์คำถาม สร้างคำตอบ ตรวจคำตอบ และปรับปรุงคำตอบ โดยไม่จำลองความคืบหน้าหรือกำหนดเวลาเปลี่ยนสถานะเอง

Fiber ใช้ native handlers (`func(fiber.Ctx) error`), `c.Bind()` พร้อม struct validation และ `SendStreamWriter` โดยคง URL, JSON, HTTP status, auth และ error / `Retry-After` เดิม ก่อนเปิด SSE จะตรวจผลจาก upstream ก่อนเสมอ เมื่อเปิดแล้วจะส่ง bytes ต่อทันทีและแทรก SSE heartbeat comments เฉพาะรอยต่อ event เพื่อจับการตัดการเชื่อมต่อระหว่างรอข้อมูล โดยไม่แทรก comment กลาง event และไม่สร้างสถานะ AI เพิ่ม

การปิดสตรีม, `WRITE_TIMEOUT` และ server shutdown จะยกเลิก context และปิด upstream body สำหรับ Fiber การตัดการเชื่อมต่อก่อน upstream ตอบ headers ครั้งแรกยังไม่แจ้งผ่าน request context อัตโนมัติ ช่วงนี้จึงมี `AI_SERVICE_TIMEOUT` และ `WRITE_TIMEOUT` เป็นขอบเขตเวลา เมื่อเริ่มสตรีมแล้วตรวจ disconnect จาก write/flush errors ได้

HTTP transport กำหนด request body limit รวม **32 MiB** เพื่อรองรับ multipart รูปสินค้า 5 รูป รูปละ 5 MiB พร้อม overhead และยังตรวจจำนวน / ขนาด / MIME ของแต่ละรูปใน handler เช่นเดิม `net/http` ยังคงใช้กับ outbound clients ของ Supabase, FCM และ AI service

คำขอรองรับ `query` / `message` และ optional `session_id`, `history`, `context`, `questionnaire_answers`, `questionnaire_skipped`, `active_question_id` ผลตอบกลับมีข้อความ, การ์ด, แบบสอบถาม, references และข้อมูล scope / action / response kind / session context

`active_question_id` ระบุคำถามที่แสดงอยู่ แต่ไม่ถือว่าข้อความที่พิมพ์เป็นคำตอบของคำถามนั้นโดยอัตโนมัติ ให้ส่งข้อความเดิมและคำตอบแบบสอบถามที่ผู้ใช้เลือกจริง ส่วน `rental_duration` แยกจากหน่วยงบ `budget_unit`

คำถามรองรับ `branch_question_id`, `branch_choices` และ `branch_titles` ที่อ้างคำถามก่อนหน้าด้วย question ID และจับคู่ด้วย option ID Backend ส่งข้อมูลนี้พร้อมรหัสช้อยและหน่วยราคาเดิมในคำตอบ JSON, SSE และ context รอบถัดไป ข้อความที่ผู้ใช้กด “พิมพ์ตอบเอง” ส่งเป็น `questionnaire_answers[].text` ของข้อนั้น

Runtime ปัจจุบันให้ Go transport timeout **45s** และ Flutter response-ready timeout **30s** ตาม [chat_client_runtime.json](../ai_service/config/chat_client_runtime.json) ส่วน Python validated-answer deadline **30s** มาจาก [ai_runtime.json](../ai_service/config/ai_runtime.json) Backend ส่ง error code และ `Retry-After` ที่ปลอดภัยกลับให้ client โดยไม่มี retry loop อัตโนมัติ

รหัส `quota_temporarily_unavailable` ระบุเพดานการใช้ช่วงเวลาสั้น / cooldown ภายใน, `quota_exhausted` ระบุโควต้ารายวันภายใน, `providers_rate_limited` ระบุ HTTP 429 จาก provider, `providers_busy` ระบุการรอช่องประมวลผลจนหมดเวลา และ `review_unavailable` ระบุว่าไม่มีโมเดลตรวจคำตอบอิสระพร้อมใช้ Backend ส่งรหัสเหล่านี้โดยไม่รวมคิวกับโควต้า เวลารอใช้ `Retry-After` สำหรับ JSON และ `retry_after_seconds` สำหรับ SSE; HTTP 200 ที่เปิด SSE แล้วอาจมี `event: error` ตามมา

`structured_output_invalid` ระบุว่าการสร้างหรืออ่านข้อมูลคำตอบตามโครงสร้างไม่สำเร็จ ส่วน `response_quality_rejected` ระบุว่าคำตอบยังไม่ผ่านการตรวจคุณภาพ ทั้งสองรหัสส่งผ่านได้ทั้ง JSON ก่อนเปิด stream และ SSE โดยไม่ส่ง draft, assessment, validation path หรือรายละเอียด provider ไปยัง client

<a id="development"></a>

## 🧪 ตรวจงาน & build

จาก `backend/`:

```sh
go test ./...
go vet ./...
```

ไฟล์ทดสอบทั้งหมดอยู่ใน `tests/` แยกเป็น `adapters/fcm`, `adapters/supabase`, `domain` และ `ports` ใช้ package ภายนอกที่ import โค้ดจาก `internal/` พร้อม mocks และ `httptest` จึงไม่ต้องมี credentials หรือบริการจริง HTTP middleware tests ครอบคลุม CORS allowlist/preflight/native, Vary header, token-bucket refill และ burst แบบ concurrent, การแชร์ quota ข้าม routes และ proxy IP ส่วน FCM tests ตรวจ cache hit/miss/expiry/invalidation และ fixed TTL ที่ไม่ต่ออายุเมื่ออ่าน การทดสอบภาพหลักฐานและพิกัดเรียกผ่าน HTTP handler จริง

รันเฉพาะชุดทดสอบด้วย `go test ./tests/...` หรือเลือกโฟลเดอร์ เช่น `go test ./tests/ports` และวัด coverage ของโค้ดต้นทางด้วย `go test '-coverpkg=github.com/chn-benmat/yuemnoi_app/backend/internal/...' ./tests/...` คำสั่ง `go test ./...` ด้านบนยังครอบคลุมทุกชุดตามเดิม

**Build บน Windows PowerShell**

```powershell
New-Item -ItemType Directory -Force bin | Out-Null
go build -o ./bin/yuemnoi-api.exe .
.\bin\yuemnoi-api.exe
```

**Build บน macOS / Linux**

```bash
mkdir -p bin
go build -o ./bin/yuemnoi-api .
./bin/yuemnoi-api
```

รัน binary จาก `backend/` เช่นเดียวกับ development เพื่อให้ env และ relative paths ตรงกัน

### โครงสร้างที่ควรรู้

```text
backend/
├── main.go                  # Config, dependency injection, HTTP startup
├── internal/
│   ├── config/              # Typed env configuration
│   ├── domain/              # Entities และ interfaces
│   ├── adapters/
│   │   ├── supabase/        # Auth, data, storage
│   │   ├── fcm/             # FCM HTTP v1
│   │   └── aiservice/       # Python JSON / SSE client
│   └── ports/               # Fiber handlers, router, middleware
├── tests/                   # External tests แยก adapters/, domain/, ports/
├── .env                     # Server configuration — สร้างเอง
├── go.mod
└── go.sum
```

Domain ไม่ควร import Fiber หรือ infrastructure ส่วน composition อยู่ที่ root `main.go` กติกาเพิ่มเติมอยู่ใน [AGENTS.md](AGENTS.md)

ระบบเจ้าหน้าที่และตัวตนเปิดผ่าน `OPERATIONS_ENABLED` พร้อม `IDENTITY_ENCRYPTION_KEY` (base64 ของคีย์ 32 bytes), `IDENTITY_HMAC_KEY` (base64 ของคีย์อย่างน้อย 32 bytes) และ `IDENTITY_CLEANUP_INTERVAL` (ค่าเริ่มต้น 15m) โดยไม่ต้องมี AI Service สำหรับขั้นตอนยืนยันตัวตน

`POST /api/identity/sessions` รับ `consent_version: "identity-v1"` และวันเกิด `birth_date` แบบ ค.ศ. YYYY-MM-DD เมื่อส่งวันเกิดมาต้องเป็นวันที่จริงและไม่อยู่ในอนาคต ใช้คำขอทุกวัยแบบเดียวกัน ไม่มีเงื่อนไขผู้ปกครองหรืออายุขั้นต่ำ ยังรับ `is_minor` จากแอปรุ่นเก่าและส่ง `p_minor` เป็นข้อมูลประกอบใน schema เดิมเท่านั้น ไม่ใช้กำหนดสิทธิ์ ค่าอายุที่ขาดหรือ null ไม่ขัดขวาง Begin แต่ Submit ยังต้องมีวันเกิดตามบัตร แอปเก็บภาพชั่วคราวและเริ่มคำขอเมื่อกดส่ง จึงถ่ายภาพก่อนกรอกวันเกิดได้

`POST /api/identity/sessions/:id/submit` รับ multipart `legal_name`, `citizen_id`, `birth_date` และภาพ `card`/`selfie` แบบฟอร์มเพิ่ม `name_prefix` (นาย / นางสาว / นาง), `first_name`, `last_name`, `address_detail`, `postal_code` (ตัวเลข ASCII 5 หลัก ไม่ขึ้นต้นด้วย 0), `province`, `district`, `subdistrict` เมื่อส่งช่องใหม่อย่างน้อยหนึ่งช่องต้องกรอกครบทุกช่อง ระบบตัดช่องว่างหัวท้ายและประกอบชื่อรวม ชื่อแต่ละช่องจำกัด 150 ตัวอักษร ที่อยู่ 500 ตัวอักษร จังหวัด/อำเภอ/ตำบลช่องละ 100 ตัวอักษร และชื่อรวมไม่เกิน 450 bytes ข้อมูลเก็บใน `raw_encrypted` ร่วมกับเลขบัตรและวันเกิด เปิดอ่านได้ผ่าน `identity-detail` ที่ตรวจสิทธิ์เจ้าหน้าที่ ยังรองรับแอปรุ่นเดิมที่ส่งเฉพาะชื่อรวม

ผู้ใช้กรอกข้อมูลตามบัตรเองและส่งรูปบัตรกับใบหน้าเพื่อรอพนักงานตรวจ แอปและ Go ตรวจเลขบัตรเฉพาะตัวเลข ASCII ครบ 13 หลักโดยไม่ตรวจ checksum และให้เจ้าหน้าที่ตรวจความถูกต้องจากหลักฐาน Go ยังตรวจวันเกิด รูปแบบ/ขนาดภาพ ก่อนส่งสถานะ `pending` ไม่มี OCR หรือการส่งภาพเข้าบริการ AI และลบ route `read-card` แล้ว

แบบฟอร์มและหน้าสรุปของผู้ใช้ไม่มีช่องบัตรตลอดชีพหรือวันหมดอายุ Go ไม่รับค่าอายุบัตรจาก client โดยคำขอรอตรวจมี `expires_on = null`, `lifetime = false`, `analysis = {"review_mode":"manual"}` หน้าพนักงานอนุมัติผ่าน `identity-review` ด้วย `decision: "approved"`, `checked: true` โดยไม่ต้องส่งเหตุผลหรืออายุบัตร การปฏิเสธ/ขอข้อมูลเพิ่มยังต้องส่ง `reason` 3–500 ตัวอักษรและ `checked: true` คำสั่งอื่นยังบังคับเหตุผลตามเดิม

ติดตั้ง [migration สำหรับฟอร์มอนุมัติ](../supabase/migrations/20261017083657_simplify_identity_approval.sql) และ [migration ยกเลิกอายุบัตร](../supabase/migrations/20261017132150_remove_identity_card_expiry.sql) เพื่อให้ฐานข้อมูลรองรับ contract นี้ ผลอนุมัติและสิทธิ์ปล่อยเช่าไม่ตรวจวันหมดอายุบัตร รวมถึงวันที่เดิมและค่าจาก client รุ่นเก่า คำขอที่อนุมัติใหม่เก็บ `expires_on = null`, `lifetime = false` เพื่อรองรับ schema เดิม การอนุมัติยังตรวจสิทธิ์เจ้าหน้าที่ ห้ามตรวจคำขอตนเอง ตรวจข้อมูลซ้ำ บันทึก audit และกำหนดเวลาลบหลักฐานตามเดิม ทดสอบ contract แบบ rollback ได้ด้วย [ชุดทดสอบ SQL](../supabase/tests/identity_approval.sql)

ติดตั้ง [migration สำหรับทุกวัย](../supabase/migrations/20261011162207_remove_guardian_age_restrictions.sql) ก่อนใช้งาน Backend และ Admin รุ่นนี้ การอนุมัติยังตรวจสิทธิ์พนักงาน ห้ามตรวจคำขอตนเอง ตรวจข้อมูลซ้ำ พร้อมบันทึก audit

การส่งคำขอยืนยันลงทะเบียนหลักฐานก่อนอัปโหลดภาพบัตรและใบหน้าพร้อมกัน โดยใช้คนละ object path รอทั้งสองงานจบก่อนเรียก `identity_submit` หรือ rollback หากอัปโหลดงานหนึ่งล้มเหลวจะรออีกงานจบก่อนลบทั้งสอง path เพื่อไม่ให้ cleanup แข่งกับ worker ที่ยังอัปโหลดอยู่ คง context และ timeout ของ Storage เดิม รวมถึงงาน cleanup ตามกำหนดเผื่อ remote upload ที่หมดเวลาฝั่ง client การตรวจสิทธิ์ การเข้ารหัส และการอนุมัติโดยเจ้าหน้าที่คงเดิม ฝั่ง Flutter แสดงรับคำขอเมื่อ submit สำเร็จและโหลดสถานะล่าสุดต่อเบื้องหลัง

ตารางภายในแยกเป็น `identity_private` และ `ops_private` โดย Go ยังเรียก RPC ชื่อเดิมใน `public` ด้วย service role ดู [migration และการตรวจสอบฐานข้อมูล](../supabase/README.md)

`GET /api/identity/status` ส่ง `available` เพื่อบอกสิทธิ์เริ่มยืนยัน โดย `pilot` ยังคงหมายถึงสมาชิกกลุ่มทดลองเท่านั้น `POST /api/admin/actions/settings/identity` รับ `identity_open_to_all` และ/หรือ `enforce_identity` เป็น boolean พร้อม `reason` และคงค่าที่ไม่ได้ส่งมา หากส่งชนิดข้อมูลไม่ถูกต้องจะได้ HTTP 400 พร้อม `code: invalid_settings`

<a id="troubleshooting"></a>

## 🛠️ ติดตรงไหน ลองเช็กตรงนี้

| อาการ                          | เช็กอะไร                                                              |
| ------------------------------ | --------------------------------------------------------------------- |
| Config validation ไม่ผ่าน      | Working directory, Supabase values, Go duration และ release keys      |
| 401 ก่อนถึง handler            | `X-App-Secret` ไม่ตรงกับ app keys                                     |
| 401 ใน flow ส่วนตัว            | Supabase access token / session หมดอายุหรือไม่ถูกต้อง                 |
| ฟีด / register ใช้งานไม่ได้    | ตรวจ `home_feed_ranked_v`, `check_email_exists` และ schema            |
| อัปโหลด avatar ตอนสมัครล้มเหลว | ตรวจกลไกสร้าง profile row และ `profile_bk`                            |
| อีเมล OTP มีแต่ลิงก์           | ตั้ง Magic Link template ให้มี `{{ .Token }}`                         |
| Health ผ่านแต่ส่ง push ไม่ได้  | ตรวจ service account, Firebase project และ receiver FCM token         |
| AI 502 / 503                   | ตรวจ base URL, Python, internal key, provider error และ `Retry-After` |
| 429                            | รอ rate limiter คืนโควตา; อุปกรณ์ที่ใช้ IP เดียวกันแชร์ bucket        |
| Rental 409                     | ตรวจสถานะ / ช่วงเวลา / ผู้มีสิทธิ์ตาม booking                         |

---

นโยบายทุกวัยใช้ migration `supabase/migrations/20261011162207_remove_guardian_age_restrictions.sql` ยกเลิกการใช้ `is_minor` จำกัดลงประกาศ/จอง/อนุมัติตัวตนทั้ง Go guard และ database triggers รวมถึงถอด API `/api/identity/guardians`, คิวและคำสั่งผู้ปกครองจากระบบเจ้าหน้าที่ ข้อมูลประวัติผู้ปกครองและหลักฐานเก่ายังเก็บตามรอบลบเดิม การตรวจตัวตนโดยเจ้าหน้าที่และการระงับบัญชียังทำงานทุกวัย

### ข้อมูลบัตรประชาชนในตั้งค่าบัญชี

ติดตั้ง `supabase/migrations/20261021065036_identity_account_details.sql` ก่อนเปิด Backend รุ่นนี้ `GET /api/identity/account` อ่านเฉพาะข้อมูลของเจ้าของ Bearer token ส่ง `fields`, `status`, `has_identity`, `selfie_with_card` และรายการ `evidence` (ID/kind) โดยไม่ส่ง ciphertext, HMAC หรือ object path; `GET /api/identity/account/evidence/:id` ตรวจเจ้าของและกำหนดลบก่อนส่งภาพ base64 ใน `data` ทั้งสอง route ใช้ `Cache-Control: private, no-store` และไม่บันทึกข้อมูลตัวตนใน response log

การแก้ไขใช้ session/submit เดิม ส่งข้อมูลส่วนบุคคลและที่อยู่ครบ พร้อม `selfie_with_card: true` และแนบเฉพาะภาพที่เปลี่ยน ระบบคัดลอกภาพเดิมที่ยังไม่หมดอายุเข้าสู่คำขอใหม่ได้ รูปเดิมที่ยังอ่านได้สามารถใช้ต่อได้แม้ไม่มีธง selfie_with_card ของรุ่นใหม่ โดยคง metadata เดิม ไม่ใช้ธงดังกล่าวแทนผลตรวจของเจ้าหน้าที่ การส่งซ้ำถูกป้องกันระหว่าง pending เลขบัตรเทียบกับ HMAC เดิมทั้ง Go และ database trigger หากต่างจะได้ `409 citizen_id_locked` และต้องติดต่อเจ้าหน้าที่ กรณีข้อมูลเก่าถูก purge แล้วจะแสดงเลขที่ปกปิดไว้และให้กรอกช่องอื่นใหม่ โดยคง HMAC เลขบัตรเดิม

ข้อมูลที่อนุมัติล่าสุดเก็บเป็น ciphertext ใน `identity_profiles.raw_encrypted` จนกว่าข้อมูลบัญชีนั้นถูกแทนที่หรือลบบัญชี ใช้คีย์และการเข้ารหัสเดิม แยกจากข้อมูลคำขอและรูปหลักฐานที่ยังลบตาม retention เดิม ข้อมูล pending/corrections/rejected ไม่ทับ snapshot หรือสิทธิ์เดิม เมื่อเจ้าหน้าที่อนุมัติผ่าน workflow เดิมจึงแทนที่ snapshot โดยอัตโนมัติ หากอัปโหลดล้มเหลวจะยกเลิกรอบ capture ก่อน rollback รูป และจะไม่ลบรูปของคำขอที่เปลี่ยนเป็น pending แล้ว

ตรวจด้วย `go test ./...`, `go vet ./...`, `go build ./...` และ `supabase/tests/identity_account_details.sql` ซึ่งสร้าง fixture แล้ว rollback ครอบคลุม ownership, สิทธิ์ RPC, เลขบัตรคงเดิม, pending/corrections/approval และการหมดอายุหลักฐาน
