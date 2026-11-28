# แนวทางสำหรับ agent: ทั้ง repo

ไฟล์นี้คือแหล่งกติกากลางของทุก agent (Claude Code, Codex และตัวอื่น) ใน repo นี้ กฎเฉพาะของแต่ละส่วนอยู่ใน `AGENTS.md` ของโฟลเดอร์นั้น ให้อ่านไฟล์ของโฟลเดอร์ที่จะแก้ก่อนเริ่มงานเสมอ ถ้ากฎในโฟลเดอร์ขัดกับไฟล์นี้ ให้กฎในโฟลเดอร์ชนะเฉพาะเรื่องภายในโฟลเดอร์นั้น

## ขอบเขตโฟลเดอร์

| โฟลเดอร์ | เนื้อหา | กฎเฉพาะ |
| --- | --- | --- |
| `frontend/` | แอป Flutter (BLoC/Cubit) | `frontend/AGENTS.md` |
| `backend/` | Go API (Fiber v3, Hexagonal) | `backend/AGENTS.md` |
| `ai_service/` | Python FastAPI สำหรับยืมหน่อย AI | `ai_service/AGENTS.md` |
| `admin/` | Next.js หน้าเจ้าหน้าที่ | `admin/AGENTS.md` |
| `supabase/` | migrations และ SQL tests | ส่วนนี้ (ด้านล่าง) |
| `docs/` | เอกสารออกแบบ แผน และผล audit | — |

- งานหนึ่งชิ้นควรแตะโฟลเดอร์น้อยที่สุด ถ้าเปลี่ยน contract ข้ามส่วน (API, JSON/SSE, schema) ให้ตรวจ caller ทุกฝั่งที่ระบุใน AGENTS.md ของโฟลเดอร์นั้น
- `supabase/migrations/` ตั้งชื่อ `YYYYMMDDHHMMSS_<snake_case>.sql` ห้ามแก้ migration ที่ apply ไปแล้ว ให้เพิ่มไฟล์ใหม่แทน; SQL tests อยู่ใน `supabase/tests/` ทั้งสองโฟลเดอร์ (และ `docs/`) เก็บเฉพาะเครื่อง ไม่อยู่ใน git

## ไฟล์ที่ห้ามแตะหรือห้าม commit

- ไฟล์ความลับและค่าตั้งเฉพาะเครื่องตาม `.gitignore`: `.env*` (ยกเว้น `*.example`), `service-account*.json`, `google-services.json`, `GoogleService-Info.plist`, keystore/คีย์ทุกชนิด ห้ามอ่านค่ามาแสดงหรือคัดลอกไปที่อื่น
- `.qa/` เป็นที่เก็บ log/หลักฐานการตรวจในเครื่อง ใช้เขียนผลตรวจได้ แต่ห้าม commit
- ไฟล์ที่ generate (`frontend/build/`, `admin/node_modules/`, `*.g.dart`, `*.freezed.dart`) ห้ามแก้ด้วยมือ ให้สร้างใหม่ด้วยคำสั่งของโฟลเดอร์นั้น
- `ai_service/.state/` เก็บ quota ledger ห้ามล้าง

## คำสั่งตรวจงาน (สรุป รายละเอียดดูในโฟลเดอร์)

| ส่วน | รันจาก | คำสั่ง |
| --- | --- | --- |
| frontend | `frontend/` | `flutter analyze` แล้ว `flutter test test/features/<feature>` |
| backend | `backend/` | `gofmt` ไฟล์ที่แก้, `go test ./...`, `go vet ./...`, `go build ./...` |
| ai_service | `ai_service/` | `.\.venv\Scripts\python.exe -m pytest tests/<layer>/<file>.py -q` |
| admin | `admin/` | `npm run check` แล้ว `npm run build` |

- ห้ามรัน live tests ที่เรียก Supabase จริงหรือใช้ quota AI โดยไม่ได้ตั้งใจ ดูรายชื่อในแต่ละโฟลเดอร์
- รายงานผลตามจริง: คำสั่งที่รัน ผล และสิ่งที่ยังไม่ได้ทดสอบ ถ้าไม่มีชุดทดสอบให้บอกว่าขาด อย่าอ้างว่าผ่าน

## Branch, commit และ worktree

- `main` คือ branch หลัก; `M`, `Fon`, `elle` เป็น branch ส่วนตัวของสมาชิก ห้าม agent push หรือ force-push branch เหล่านี้เอง
- งานของ agent ใช้ branch `<type>/<หัวข้อสั้น>` เช่น `feat/chat-rental-queue`, `fix/profile-phone` โดย `<type>` ตรงกับ commit type
- commit message ใช้ Conventional Commits แบบ `<type>(<scope>): <สรุปภาษาไทย>` เช่น `fix(profile): ใช้ profile_tb.phone เป็นเบอร์ติดต่อเพียงแหล่งเดียว`; type ที่ใช้: `feat`, `fix`, `refactor`, `test`, `chore`, `docs`
- commit หรือ push เฉพาะเมื่อผู้ใช้สั่ง
- เมื่อหลาย agent ทำงานขนานกัน แต่ละตัวใช้ git worktree และ branch ของตัวเอง ดู `docs/agents/multi-agent-workflow.md`

## การทำงานร่วมกันของหลาย agent

- **ห้ามสอง agent แก้ไฟล์เดียวกันใน branch เดียวกัน** แบ่งงานตามขอบเขตโฟลเดอร์/ไฟล์ ไม่ใช่ตามความเชื่อว่าตัวไหนเก่งอะไร
- ผู้คุมงาน (ปกติคือ Claude Code) วางแผน แตกงาน และรวมผล; agent ที่รับงานย่อยทำเฉพาะขอบเขตที่ได้รับใน worktree ของตัวเอง
- agent ที่ทำหน้าที่ reviewer อ่านอย่างเดียว ไม่แก้ไฟล์ รายงานปัญหาพร้อมไฟล์:บรรทัด และระดับความรุนแรง
- รอบ plan → review → fix ต่องานหนึ่งชิ้น **ไม่เกิน 2 รอบ** ถ้ายังไม่ผ่านให้หยุดและสรุปให้ผู้ใช้ตัดสินใจ
- คอมเมนต์ในโค้ดที่เพิ่มหรือแก้ใช้ภาษาไทยที่อธิบายเหตุผลหรือข้อจำกัด
