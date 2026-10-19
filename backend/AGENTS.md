# แนวทางสำหรับ agent: backend

ใช้กับทุกไฟล์ภายใต้ `backend/` รันคำสั่งจากโฟลเดอร์นี้ อ่าน `README.md` เมื่อแก้ API, auth, AI gateway หรือระบบยืนยันตัวตน และตรวจเวอร์ชัน Go/Fiber จาก `go.mod`

## สถาปัตยกรรมและ HTTP

- รักษา Hexagonal Architecture: `internal/domain/` เป็น entities และ interfaces, `internal/adapters/` เชื่อมระบบภายนอก, `internal/ports/` เป็น Fiber handlers/middleware และ root `main.go` ประกอบ dependencies
- เพิ่ม dependency ผ่าน domain interface และฉีด adapter จาก `main.go`; domain ต้องไม่ผูกกับ Fiber, HTTP client หรือฐานข้อมูล
- ใช้ native Fiber v3 handlers และสร้าง app ผ่าน `ports.NewHTTPApp` หรือ router constructor เดิม เพื่อให้ validation, body limit, error mapping และ lifecycle ใช้กฎเดียวกัน
- ลงทะเบียน routes ใน `internal/ports/router.go`; API อยู่ใต้ `/api` และ health check คือ `/health` ตรวจ caller ใน `../frontend/` และ `../admin/` เมื่อเปลี่ยน contract
- ใช้ `validate` tags ใน request DTO ตรวจข้อความหลัง trim และแยกค่าที่ไม่ส่งออกจากค่าที่ส่งเป็นค่าว่างสำหรับ partial update
- ใช้ `fiber.Ctx` ภายในอายุ handler เท่านั้น คัดลอกค่าที่งาน background ต้องใช้ และส่ง `context.Context` ผ่าน ports/adapters เพื่อรักษา timeout กับ cancellation
- เมื่อแก้ SSE ให้รักษา upstream error mapping ก่อนเปิด stream, event boundaries, heartbeat และการปิด body/ยกเลิก upstream เมื่อ client disconnect
- คอมเมนต์ที่เพิ่มหรือแก้ให้ใช้ภาษาไทยที่อธิบายเหตุผลหรือข้อจำกัด

## สิทธิ์และ configuration

- กำหนด env ผ่าน typed config ใน `internal/config/config.go` และ `config.Load()` แทนการอ่าน env กระจายใน packages
- ใช้ตัวตนจาก bearer token ที่ตรวจแล้วในการอนุญาตงาน ตรวจ ownership และสิทธิ์เจ้าหน้าที่ฝั่ง server แยกจาก app secret
- เก็บ `SUPABASE_SERVICE_ROLE_KEY`, internal service key และ identity encryption/HMAC keys เฉพาะ server; ปกปิด token, รหัสผ่าน, OTP และข้อมูลส่วนบุคคลใน response/log
- Go กับ Python ต้องใช้ internal service key ที่ตรงกัน ตรวจการเลือก key และการหมุน key ทั้งสองฝั่งก่อนเปลี่ยน configuration
- ใช้ `log/slog` และ error ที่มีบริบทสำหรับผู้ดูแล โดยไม่เปิดเผยข้อมูลลับให้ client
- เมื่อแก้ identity/admin ให้รักษา audit, evidence access, retention และการตรวจโดยเจ้าหน้าที่ อ้างกติกาปัจจุบันใน README และโค้ดแทนการเพิ่มเงื่อนไขอายุเอง

## ตรวจงาน

```powershell
go run main.go
```

เมื่อแก้ Go code ให้จัดรูปแบบไฟล์ที่แก้ด้วย `gofmt` แล้วตรวจ:

```powershell
go test ./...
go vet ./...
go build ./...
```

- วางไฟล์ทดสอบทั้งหมดใน `tests/` แยกโฟลเดอร์ตาม package ต้นทาง เช่น `tests/adapters/fcm`, `tests/domain`, `tests/ports` ใช้ package ภายนอก (`fcm_test`, `domain_test`, `ports_test`) และทดสอบผ่าน API ของ package; ฉีด client/cache ผ่าน constructor เมื่อจำเป็นต้องควบคุม dependency
- ใช้ fake services และ `httptest` สำหรับการตรวจแบบ offline และ opt-in เมื่อต้องเรียกบริการจริง วัด coverage ของโค้ดต้นทางด้วย `go test '-coverpkg=github.com/chn-benmat/yuemnoi_app/backend/internal/...' ./tests/...`
- เมื่อเปลี่ยน AI gateway ให้ตรวจ JSON/SSE และ configuration ร่วมกับ `../ai_service/` รายงานผลตรวจและข้อจำกัดโดยแยก local tests จาก live end-to-end
