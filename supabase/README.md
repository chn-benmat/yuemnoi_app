# ฐานข้อมูลของแอป

ใช้ schema ตามโมดูล โดยเก็บข้อมูลเดิมในตารางเดิมและเปลี่ยนเฉพาะ schema:

| Schema | Relations |
| --- | --- |
| `messaging` | `conversation_tb`, `chat_message_tb` |
| `notifications` | `notification_tb`, `notification_device_tb`, `notification_outbox_tb` |
| `profiles` | `profile_tb`, `public_profile_v` (View) |

`item_tb`, `booking_tb`, `review_tb`, `home_feed_ranked_v` และ RPC เดิมยังอยู่ใน `public` ส่วน RPC และ Trigger ที่อ่านข้อมูลข้ามโมดูลระบุ schema ใหม่ภายในฟังก์ชัน ฟังก์ชันช่วยงานยังอยู่ใน `app_private`; ข้อมูลยืนยันตัวตนและงานเจ้าหน้าที่ยังคงใช้ `identity_private` และ `ops_private`

## การย้ายและเปิดใช้งาน

Migration `20261020081520_move_app_data_to_domain_schemas.sql` ใช้ `ALTER TABLE/VIEW SET SCHEMA` จึงรักษา OID, ข้อมูล, foreign keys, indexes, policies, grants และสมาชิก Realtime publication เดิม ใช้กับฐานข้อมูลของแอปที่ติดตั้งระบบเดิมครบแล้ว ไม่ใช่ bootstrap สำหรับ project เปล่า

ต้องเปิดใช้ migration, Go Backend และ Flutter รุ่นนี้พร้อมกัน แอปรุ่นเดิมที่ยังเรียกตารางใน `public` และฟัง Realtime ด้วย schema เดิมใช้งานต่อไม่ได้ ไม่มี compatibility view ใน `public`

Go แยก PostgREST headers ต่อคำขอและใช้ transport/timeout เดิม Flutter ใช้ `.schema('messaging')` และ `.schema('profiles')`; `.stream()` ใช้ schema ที่เลือกทั้งการโหลดครั้งแรกและ Realtime

Migration เปิด Data API สำหรับ `public, graphql_public, messaging, notifications, profiles` ผ่าน `authenticator.pgrst.db_schemas` รายการนี้มีผลเหนือค่า Exposed schemas ใน Dashboard หากเพิ่ม schema ภายหลังให้ปรับรายการผ่าน migration หรือจัดการรายชื่อให้ครบใน Dashboard แล้ว `ALTER ROLE authenticator RESET pgrst.db_schemas` พร้อม reload config ตาม [เอกสาร Supabase](https://supabase.com/docs/guides/troubleshooting/pgrst106-the-schema-must-be-one-of-the-following-error-when-querying-an-exposed-schema)

การเปิด schema ไม่เพิ่มสิทธิ์ตาราง: RLS และ grants เดิมยังมีผล ตาราง device token และ outbox ยังคงให้เฉพาะ server ใช้งาน View `profiles.public_profile_v` คง `security_invoker` และแหล่งข้อมูลเดิมที่ไม่เปิดเผยอีเมล/โทรศัพท์แก่ผู้อื่น

## การตรวจสอบ

รันไฟล์ใน `tests/` ผ่าน SQL client ที่รองรับหลาย statements ทุกไฟล์ใช้ transaction แล้ว rollback fixture ทั้งหมด จึงไม่เหลือประวัติแชตหรือ outbox ให้ worker ส่งจริง:

- `domain_schemas.sql`: ตำแหน่งตาราง/View, signup trigger, guest view, own profile/presence, chat participant isolation และ Realtime publication
- `item_auto_reply.sql`, `item_pickup_locations.sql`: ข้อความตอบกลับและข้อมูลจุดรับของในข้อความเสนอเช่า
- `notifications.sql`, `notification_reminders.sql`: inbox, read state, device ownership, outbox และการเตือน
- `rental_lifecycle_evidence.sql`: การส่งมอบ การคืน และการอ่านโปรไฟล์ข้าม schema

ชุดทดสอบที่ใช้ conversation หรือผู้ใช้เดิมต้องรันกับ environment ที่มีข้อมูลทดสอบพร้อม คำสั่ง rollback ไม่ย้อนค่า sequence ที่ถูกใช้ระหว่างทดสอบ

## ผลตรวจ 20 ตุลาคม 2026

ติดตั้ง migration บน `yuemnoi_db` แล้ว จำนวนแถวทั้งหกตารางตรงกับก่อนย้าย และตรวจว่า OID, table grants, RLS และตัวเลือกของ View ตรงกับเดิมทั้งเจ็ด relations สมาชิก Realtime ย้ายตามตารางไปที่ `messaging` ไม่มีฟังก์ชันค้างอ้างชื่อ relation เดิมใน `public`

- Go: `go test ./...`, `go vet ./...`, `go build ./...` ผ่าน
- Flutter: `flutter analyze`, ชุดทดสอบ chat/profile data, notification, core services/network 73 tests และ `flutter build apk --debug` ผ่าน
- ชุด SQL ทั้งหกไฟล์ผ่านบน schema จริงโดย rollback fixtures
- ทดสอบ Auth/REST/Realtime จริงด้วยผู้ใช้ชั่วคราวสองบัญชี: signup, own profile, guest View, การปิดข้อมูลส่วนตัวข้ามบัญชี, presence, ส่งแชต, รับ Realtime และ notification read sync ผ่าน ลบผู้ใช้และข้อมูลทดสอบแล้ว จำนวนแถวกลับมาเท่าก่อนทดสอบ
- ชุด Flutter ที่รวม core navigation พบ timeout สองรายการใน `app_routes_test.dart` (เปิด login และเปิดหน้าลงประกาศจาก home); ไม่ได้แก้ flow navigation ในงานนี้

Security advisor ไม่มี WARN/ERROR เพิ่มจากก่อนย้าย คำเตือนเดิมคือ `check_email_exists` ([search path](https://supabase.com/docs/guides/database/database-linter?lint=0011_function_search_path_mutable), [anon execute](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable), [authenticated execute](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)), extension [vector ใน public](https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public) และ [leaked password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)
