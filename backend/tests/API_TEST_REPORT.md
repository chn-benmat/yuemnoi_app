# ผลทดสอบ API หลังย้ายเป็น Fiber v3 และปรับ dependencies

ตรวจล่าสุดเมื่อ 10 ตุลาคม 2026 ด้วย Go 1.26.2, Fiber v3.5.0, Firebase Admin SDK v4.22.0 และ golang.org/x/time v0.16.0

## ผลที่ยืนยันได้

- ทดสอบครบ **23 endpoint** รวม `GET /health` ผ่าน router และ middleware จริง ตารางทดสอบเทียบกับรายการ routes เพื่อจับ endpoint ที่ตกหล่น
- ทดสอบกรณีสำเร็จของทั้ง 23 endpoint ผ่าน **adapter จริง** ของ Supabase, Python AI และ FCM โดยใช้ HTTP server จำลองบน loopback
- ทั้ง backend ผ่าน **657 กรณีทดสอบปลายทาง** ไม่นับ test แม่ซ้ำกับ subtests: ล้มเหลว 0, ข้าม 1 (`TestAILiveEvaluationGateway` ซึ่งต้องเปิดใช้เอง)
- รอบย้าย Fiber เพิ่ม 22 test functions รวม 492 กรณีปลายทาง และรอบปรับ dependencies เพิ่ม 14 test functions รวม 40 กรณีปลายทาง
- Statement coverage ของ `internal/ports` รวม handlers, router, middleware และ transport: **96.7%** รวม coverage ของ source block เดียวกันจากทุก test package โดยไม่นับซ้ำ ตัวเลขนี้ไม่ใช่เปอร์เซ็นต์รับประกันว่าปลอด bug
- `go vet ./...`, `go build ./...`, `go mod verify` และ `git diff --check` ผ่าน

## รายการ API

ทุก API ใต้ `/api` ถูกทดสอบ app key ขาด/ผิดเป็น 401, preflight เป็น 204 และ method ที่ไม่ได้รองรับเป็น 404 ด้วย

| Method | Endpoint | สำเร็จ | กรณีผิดพลาดหรือเงื่อนไขที่ตรวจเพิ่ม |
| --- | --- | --- | --- |
| GET | `/health` | 200 | ไม่ต้องใช้ app key, ไม่มีการเรียกบริการภายนอก |
| POST | `/api/auth/register` | 201 | ข้อมูลผิด 400, อีเมลซ้ำ 409, rate limit 429, บริการล้มเหลว 500, multipart/รูป/ยืนยันรหัสผ่าน |
| POST | `/api/auth/login` | 200 | ข้อมูลผิด 400, เข้าสู่ระบบไม่ได้ 401, rate limit 429, token response |
| POST | `/api/auth/google-profile` | 200 | token ผิด 401, ไม่มีรูป/โปรไฟล์ 422, rate limit 429, บริการล้มเหลว 500 |
| POST | `/api/auth/change-password` | 200 | ข้อมูลผิด 400, token ผิด 401, rate limit 429, บริการล้มเหลว 500 |
| POST | `/api/auth/send-otp` | 200 | อีเมลผิด 400, ไม่พบอีเมล 404 และต้องไม่ส่ง OTP, rate limit 429, lookup/send ล้มเหลว 500 |
| POST | `/api/auth/verify-otp` | 200 | รูปแบบ/รหัส OTP ผิดหรือหมดอายุ 400, rate limit 429, token response |
| GET | `/api/user/profile` | 200 | ไม่มีสิทธิ์ 401, โหลดข้อมูลล้มเหลว 500 |
| PUT | `/api/user/profile` | 200 | ข้อมูล/รูปผิด 400, ไม่มีสิทธิ์ 401, บันทึกล้มเหลว 500, pointer fields และ multipart |
| PUT | `/api/user/contact` | 200 | เบอร์ผิด 400, ไม่มีสิทธิ์ 401, บันทึกล้มเหลว 500, แปลงเบอร์ไทยเป็น +66 |
| POST | `/api/user/fcm-token` | 200 | token ว่างหรือมีแต่ช่องว่าง 400, ไม่มีสิทธิ์ 401, บันทึกล้มเหลว 500 |
| GET | `/api/items` | 200 | บริการล้มเหลว 500, search/category, ไม่พบผลเป็น `[]`, ลำดับและคะแนนรีวิว |
| POST | `/api/items` | 201 | ข้อมูล/รูปผิด 400, ไม่มีสิทธิ์ 401, บริการล้มเหลว 500, ไม่รับ user ID/status ที่ปลอมมา |
| GET | `/api/items/:id` | 200 | ID ผิด 400, ไม่พบ 404, บริการล้มเหลว 500 |
| PUT | `/api/items/:id` | 200 | ID/ข้อมูลผิดหรือไม่มี field 400, ไม่มีสิทธิ์ 401, ไม่พบ/ไม่ใช่เจ้าของ 404, บริการล้มเหลว 500, ทุก field ที่แก้ได้ |
| DELETE | `/api/items/:id` | 204 | ID ผิด 400, ไม่มีสิทธิ์ 401, ไม่พบ/ไม่ใช่เจ้าของ 404, มีข้อมูลอ้างอิง 409, บริการล้มเหลว 500, response ไม่มี body |
| POST | `/api/rentals` | 201 | เวลา/ข้อมูลผิด 400, ไม่มีสิทธิ์ 401, ไม่พบ 404, ช่วงเวลาไม่ว่าง 409, บริการล้มเหลว 500, ใช้ราคาจาก server |
| POST | `/api/rentals/:id/handover` | 200 | ID ผิด 400, ไม่มีสิทธิ์ 401, ไม่ใช่คู่สัญญา 403, ไม่พบ 404, สถานะไม่ถูกต้อง 409, บริการล้มเหลว 500 |
| POST | `/api/rentals/:id/return` | 200 | ID ผิด 400, ไม่มีสิทธิ์ 401, ไม่ใช่คู่สัญญา 403, ไม่พบ 404, สถานะไม่ถูกต้อง 409, บริการล้มเหลว 500 |
| POST | `/api/push/chat` | 200 queued | ข้อมูลผิด/ส่งหาตัวเอง 400, ไม่มีสิทธิ์ 401, ป้องกันปลอมชื่อ/รูปผู้ส่ง, fallback โปรไฟล์, background delivery failure |
| POST | `/api/chat/contact` | 200 | ข้อมูลผิด 400, ไม่มีสิทธิ์ 401, ไม่อยู่ในห้อง 403, ไม่พบห้อง/เบอร์ 404, บริการล้มเหลว 500 |
| POST | `/api/chat-ai` | 200 | ข้อมูล/ข้อความผิด 400, rate limit 429, upstream ล้มเหลว 502/503, error code และ Retry-After |
| POST | `/api/chat-ai/stream` | 200 SSE | ข้อมูลผิด 400, rate limit 429, ก่อนเปิด stream เป็น JSON 502/503, SSE error/flush/heartbeat/timeout/disconnect/shutdown |

ตรวจเพิ่มทั้ง bearer ที่ขาด ผิดรูปแบบ หมดอายุ และ verifier คืน user ID ว่าง รวมถึงการปลอม user ID ใน payload ของทุก endpoint ที่เกี่ยวข้อง

อัปโหลดตรวจไฟล์ว่าง, ไฟล์ข้อความปลอมเป็นรูป, GIF ที่ไม่รองรับ, ไฟล์เกิน 5 MiB, รูปอุปกรณ์เกิน 5 รูป, รูปอุปกรณ์ 5 รูปขนาดรูปละ 5 MiB, multipart ที่เสียรูป และการส่งไฟล์ผ่าน Storage adapter จริงไปยัง server จำลอง

## ข้อผิดพลาดที่พบและแก้แล้ว

1. API เปลี่ยนรหัสผ่านตอบ 500 เมื่อ Supabase ปฏิเสธ token: เพิ่ม domain error และแปลงเป็น 401 โดยทดสอบทั้ง fake gateway และ HTTP adapter จริง
2. API ผู้ใช้หลายจุดส่งข้อความภายในจาก adapter กลับไป: เปลี่ยนเป็นข้อความปลอดภัย และตรวจไม่ให้รายละเอียดภายในหลุดใน error response
3. ตัวช่วย authentication ไม่ตรวจ bearer ว่างและ user ID ว่าง: ปฏิเสธก่อนเรียกงานข้อมูล
4. ข้อมูลที่มีแต่ช่องว่างผ่าน validation ของอุปกรณ์ สถานที่รับของ FCM token และข้อมูลผู้รับ push: ตอบ 400 ก่อนบันทึกหรือส่งงาน background
5. CORS ตรวจแค่ prefix/suffix ของข้อความ จึงรับ host เลียนแบบและชื่อโดเมนใน path: เปลี่ยนเป็นตรวจ scheme และ hostname จริง
6. Fiber parse multipart ก่อน middleware ทำให้ body เสียรูปคืน transport error: เลื่อน parsing ไปที่ handler และยืนยัน 400 ทั้งผ่าน `app.Test` และ TCP จริง

## Regression tests สำหรับ dependencies และ Supabase transport

- Firebase Admin SDK ส่ง payload ผ่าน HTTP server จำลองจริง: ตรวจ notification / data / Android channel / เสียง / APNs badge และ fallback ข้อความ รวมการโหลด credentials จากไฟล์และใช้ OAuth token ซ้ำ
- ตรวจ typed `UNREGISTERED` ให้ลบ device token แต่เก็บ token เมื่อเป็น HTTP 404 ทั่วไป, ข้อความ UNREGISTERED ที่ไม่มีชนิด error, invalid payload หรือ permission denied
- ยกเลิกคำขอระหว่าง OAuth และระหว่างรอ FCM ตอบได้; credentials ผิดทำให้ adapter คืน error โดยไม่ panic และ server ยังเริ่มได้ตาม flow ใน `main.go`
- Token Bucket คง burst และการแยก IP เดิม เติม token กลับได้ และคำขอพร้อมกัน 100 รายการผ่านได้ไม่เกิน burst รวมทดสอบ 429 ของทุก Auth / AI route
- รูปโปรไฟล์และรูปอุปกรณ์: ตรวจ HTTP 401 / 403 / 503, JSON เสียรูป, key หาย, HTTP client timeout ก่อน headers และระหว่างอ่าน body รวม caller cancellation
- ตรวจการลบไฟล์ที่อัปโหลดแล้วเมื่อบันทึก URL ลงฐานข้อมูลล้มเหลว, ไม่พบ row หรือ caller ถูกยกเลิก และตรวจ rollback รายการอุปกรณ์
- เก็บรูปโปรไฟล์ไว้ถ้าฐานข้อมูลยังอ้างอิงอยู่หรือตรวจอ้างอิงไม่สำเร็จ และเก็บรูปอุปกรณ์ไว้ถ้า rollback แถวข้อมูลไม่สำเร็จ เพื่อไม่ลบไฟล์ที่ยังใช้งานอยู่
- Supabase Auth และ PostgREST ยังคง cancellation ก่อน headers และระหว่างอ่าน body; Auth client มี timeout 60s และ PostgREST ใช้ transport ที่จำกัดเวลา response body เช่นกัน
- รัน `go run main.go` จาก root backend ด้วยคอนฟิกบริการจำลองและ Firebase credentials ที่ไม่ครบ: server เริ่มพร้อม warning, `GET /health` ตอบ 200 และปิดด้วย Ctrl+C ได้ตามปกติ

## ข้อจำกัดและสิ่งที่ยังไม่ได้ยืนยัน

- **ยังไม่ได้ทดสอบ E2E กับ Supabase, FCM, ผู้ให้บริการ AI หรือ Flutter ที่ใช้งานจริง** ไม่มีการสร้างผู้ใช้ ส่งอีเมล OTP หรือ push notification จริงในรอบนี้ บริการจำลองยืนยันรูปแบบ HTTP, mapping และการจัดการข้อผิดพลาด แต่ไม่ยืนยัน schema/RLS, bucket, credentials หรือ quota ของระบบที่ deploy
- SSE: หลัง upstream ส่ง headers แล้ว ทดสอบ flush, client disconnect, timeout และ shutdown ผ่าน TCP จริงแล้ว แต่ถ้า client ตัดการเชื่อมต่อ **ก่อน upstream ส่ง headers** backend อาจตรวจไม่พบทันที และยังรอจน upstream/transport timeout ตามค่าที่ตั้งไว้ (ค่า AI ปกติ 45 วินาที)
- Body เกิน 32 MiB: เมื่อใช้ `Expect: 100-continue` ทดสอบผ่าน TCP ได้ 413 ถูกต้อง แต่การส่ง body ขนาดเกินเพดานโดยไม่ใช้ header นี้บนเครื่อง Windows ที่ทดสอบพบ **connection reset แทน HTTP response** ข้อนี้ยังเป็นข้อจำกัดของเส้นทาง transport ที่ใช้อยู่; payload รูปที่รองรับสูงสุด 5 × 5 MiB ผ่านแล้ว
- ไม่ได้ยืนยันด้วย race detector: เครื่องนี้ตั้ง `CGO_ENABLED=0` และไม่มี C compiler สำหรับรัน `go test -race`
- ไม่ใช่ load/soak test และไม่สามารถรับรองว่าไม่มีข้อผิดพลาดในทุก input หรือสภาพ production ได้

## รันทดสอบซ้ำ

จาก `backend/`:

```powershell
go test ./... -count=1 -timeout 60s
go vet ./...
go build ./...
go mod verify
```

ตรวจ coverage ของ HTTP layer ใน PowerShell:

```powershell
$apiCoveragePath = Join-Path $env:TEMP 'yuemnoi-api-coverage.out'
go test ./... -count=1 -timeout 60s '-coverpkg=github.com/chn-benmat/yuemnoi_app/backend/internal/ports' "-coverprofile=$apiCoveragePath"
go tool cover "-func=$apiCoveragePath"
```

หลักฐานเป็นผลของชุดทดสอบที่รันใน workspace นี้ หากโค้ดหรือ dependencies เปลี่ยนต้องรันใหม่
