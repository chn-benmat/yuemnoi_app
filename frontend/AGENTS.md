# แนวทางสำหรับ agent: frontend

ใช้กับทุกไฟล์ภายใต้ `frontend/` รันคำสั่งจากโฟลเดอร์นี้ อ่าน `README.md` เมื่อทำงานเกี่ยวกับการตั้งค่า การเชื่อมต่อระบบ หรือ flow ยืนยันตัวตน และตรวจเวอร์ชันจาก `pubspec.yaml` กับ `pubspec.lock`

## โครงสร้างและการแก้โค้ด

- ใช้ BLoC/Cubit และโครงสร้างเดิมของแต่ละ feature ใน `lib/features/` ส่วนที่แยก `data/`, `domain/`, `presentation/` ให้รักษาขอบเขตนั้น; บาง feature มีโครงสร้างย่อยกว่า
- ให้ datasource ติดต่อระบบภายนอก, repository แปลงข้อมูล, use case จัดการกฎงาน และ BLoC/Cubit จัดการ state; widget รับ state และส่ง action
- ค้นหา widget ใน feature และ `lib/core/widgets/` รวมถึง style ใน `lib/core/theme/` ก่อนสร้างใหม่ วาง UI เฉพาะ feature ไว้ใน feature และย้ายเข้า core เมื่อใช้ร่วมกันจริง
- เมื่องานเป็น logic หรือการเชื่อมต่อ API ให้รักษา layout และรูปแบบ UI เดิม ปรับดีไซน์เมื่ออยู่ในขอบเขตคำขอ
- คอมเมนต์ที่เพิ่มหรือแก้ให้ใช้ภาษาไทยที่อธิบายเหตุผลหรือข้อจำกัด สั้นและเข้าใจ
- แก้ route ผ่าน `lib/core/navigation/app_routes.dart` และตรวจ deep link, auth guard และการกลับหน้าที่เกี่ยวข้อง

## API, auth และข้อมูล

- ใช้ `lib/core/network/api_client.dart` สำหรับ Go API; `X-App-Secret` จัดการส่วนกลาง แต่ Bearer token ต้องส่งตามรูปแบบของ caller ผ่าน `AuthSession` อย่าสมมติว่า Dio เติมให้เอง
- อ่านค่าตั้งจาก `lib/core/config/app_config.dart`; compile-time defines มีลำดับก่อน `.env.local` และ `API_URL` เป็น origin ที่ไม่มี `/api` ต่อท้าย
- frontend ยังมีทั้ง Go API และ Supabase โดยตรง ให้ตรวจ datasource ของ feature ก่อนแก้ การย้ายทั้งระบบไปใช้ backend เป็นงานแยกจากการแก้เฉพาะจุด
- งานใหม่ที่แตะข้อมูลส่วนตัว สิทธิ์เจ้าหน้าที่ หรือธุรกรรมสำคัญให้ผ่าน Go ที่ตรวจสิทธิ์ฝั่ง server; การใช้ Supabase จาก client ต้องอยู่ภายใต้สิทธิ์ผู้ใช้และ RLS
- ส่งคำขอ AI ผ่าน Go `/api/chat-ai` และ `/api/chat-ai/stream` รักษา JSON/SSE contract ร่วมกับ `../backend/` และ `../ai_service/` โดยเฉพาะสถานะ ความผิดพลาด และการยกเลิกคำขอ
- รักษา guest browsing และใช้ auth guard ก่อน action ที่ต้องล็อกอิน คีย์ใน `.env.local` ถูก bundle เป็น asset จึงเก็บได้เฉพาะค่าที่เปิดเผยกับ client ได้; service-role key และ secret ฝั่ง server ต้องอยู่บน server
- หน้าชำระเงินบางส่วนยังเป็น mock ให้ตรวจ implementation ก่อนอ้างว่ามีการตัดเงินจริง

## ตรวจงาน

```powershell
flutter pub get
flutter analyze
flutter test test/features/<feature>
```

- แทน `<feature>` ด้วย feature ที่แก้ หรือเลือกไฟล์ทดสอบเฉพาะ; งาน core ใช้ `flutter test test/core` วาง tests ตามโครงสร้าง `test/features/` หรือ `test/core/`
- ใช้ `dart format` กับไฟล์ Dart ที่แก้ หากเพิ่มหรือเปลี่ยน model ที่ใช้ code generation จึงรัน `dart run build_runner build --delete-conflicting-outputs` และตรวจ diff ที่สร้าง
- ก่อนรัน `flutter test` ทั้งชุด ให้ตรวจ live dependencies: `test/features/home/home_supabase_live_search_test.dart` เรียก Supabase จริง ส่วน chatbot live tests มี opt-in ของตัวเอง
- เมื่องานเปลี่ยน API หรือ SSE ให้ตรวจ caller และ contract ของบริการที่เกี่ยวข้อง รายงานคำสั่งที่รัน ผล และสิ่งที่ยังไม่ได้ทดสอบ
