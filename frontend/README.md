# Yuemnoi Frontend

Flutter application สำหรับแพลตฟอร์มเช่าอุปกรณ์ Yuemnoi (ยืมหน่อย) ทำหน้าที่เป็นส่วนติดต่อผู้ใช้ เชื่อมต่อกับ Go Backend ผ่าน REST API (Dio) และเชื่อมต่อ Supabase สำหรับจัดการ Auth session, Google OAuth, และ Realtime Chat WebSockets

> **สถานะปัจจุบัน**: พัฒนาเสร็จสมบูรณ์ทั้ง 10 Feature Modules ได้แก่ Authentication & Guest Browsing, Discovery Feed, Item Detail & Management, Rental Lifecycle, Wallet & Payment, Realtime Chat, AI Chatbot พร้อม SSE Streaming และ FCM Push Notifications

---

## ฟีเจอร์หลักในระบบ

1. **Authentication & Guest Mode**:
   - สมัครสมาชิก, เข้าสู่ระบบด้วย Email/Password และ Google OAuth
   - กู้คืนรหัสผ่านด้วย OTP 6 หลัก
   - รองรับ Guest Browsing (ดูสินค้าได้โดยไม่ต้องล็อกอิน และมี Login Guard เตือนเมื่อทำธุรกรรม)
2. **Discovery & Home Feed**:
   - แนะนำอุปกรณ์ด้วยระบบ Ranking (คะแนนรีวิว, ยอดเช่า, ความใหม่, ความหลากหลายของหมวดหมู่)
   - ค้นหาสินค้า และกรองตามหมวดหมู่
3. **Item Management**:
   - ลงประกาศอุปกรณ์ให้เช่า พร้อมบีบอัดรูปภาพก่อนอัปโหลด
   - จัดการและแก้ไขข้อมูลอุปกรณ์
4. **Rental Lifecycle & Order Tracking**:
   - ส่งคำขอเช่าและคำนวณราคาอัตโนมัติตามระยะเวลา
   - หน้าต่างยืนยันการส่งมอบและรับคืนอุปกรณ์ (Handover & Return Modal)
   - แผนที่แสดงตำแหน่งและระยะทางระหว่างผู้เช่ากับผู้ให้เช่า
5. **Wallet & Payment**:
   - ยอดเงินคงเหลือในกระเป๋า (Wallet Balance) และประวัติธุรกรรม
   - ระบบเติมเงินและหักยอดเงินค่าเช่า
6. **Realtime Chat & AI Assistant**:
   - แชทสดผ่าน Supabase Realtime WebSockets พร้อมแนบรูปภาพ
   - AI Chatbot ให้คำปรึกษา แนะนำอุปกรณ์ และเปรียบเทียบสเปกผ่าน SSE Streaming พร้อมช้อยส์ตัวเลือก Interactive
7. **Push Notifications**:
   - แจ้งเตือนข้อความแชทและสถานะการจองผ่าน Firebase Cloud Messaging (FCM)

---

## เทคโนโลยีหลัก

- **Framework**: Flutter (Dart `^3.6.0` ขึ้นไป)
- **State Management**: `flutter_bloc` (BLoC / Cubit), `equatable`
- **Navigation**: `go_router`
- **Networking**: `dio` (เชื่อมต่อ Go Backend REST API), `supabase_flutter` (Auth, Realtime, Storage)
- **Push Notifications**: `firebase_messaging`, `flutter_local_notifications`
- **Maps & Geolocation**: `flutter_map`, `latlong2`, `geolocator`
- **Typography & Theme**: ฟอนต์ Prompt และ Custom Theme Tokens

---

## การตั้งค่า Environment (`frontend/.env.local`)

สร้างไฟล์ `frontend/.env.local`:

```env
SUPABASE_URL=.....
SUPABASE_PUBLISHABLE_KEY=......
API_URL=......

# Security & OAuth (Optional)
APP_SECRET_KEY=......
GOOGLE_WEB_CLIENT_ID=.......
```

| ตัวแปร                     | รายละเอียด                                     |
| -------------------------- | ---------------------------------------------- |
| `SUPABASE_URL`             | URL ของ Supabase Project                       |
| `SUPABASE_PUBLISHABLE_KEY` | Publishable (Anon) Key สำหรับไคลเอนต์          |
| `API_URL`                  | Base URL ของ Go Backend โดยไม่ต้องมี `/api/v1` |
| `APP_SECRET_KEY`           | กุญแจตรวจสอบความถูกต้องของไคลเอนต์กับ Backend  |
| `GOOGLE_WEB_CLIENT_ID`     | OAuth Client ID สำหรับ Google Sign-In          |

> [!CAUTION]
> ห้ามใส่ `SUPABASE_SERVICE_ROLE_KEY` หรือ Server Private Keys ใดๆ ใน `frontend/.env.local` เด็ดขาด เพราะไฟล์นี้จะถูก bundle ลงไปใน Client Application

---

## การเชื่อมต่อ Backend จากแต่ละอุปกรณ์

| อุปกรณ์                              | ค่า `API_URL` ที่แนะนำ            |
| ------------------------------------ | --------------------------------- |
| Flutter Web / iOS Simulator          | `http://localhost:8080`           |
| Android Emulator (มาตรฐาน)           | `http://10.0.2.2:8080`            |
| Android Emulator (Genymotion)        | `http://10.0.3.2:8080`            |
| โทรศัพท์จริง (ผ่าน Wi-Fi วงเดียวกัน) | `http://<IP-ของคอมพิวเตอร์>:8080` |

---

## วิธีรันแอปพลิเคชัน

```bash
cd frontend
flutter pub get

# รันด้วยการส่งผ่านไฟล์คอนฟิก (แนะนำ):
flutter run --dart-define-from-file=.env.local

# หรือระบุอุปกรณ์เป้าหมาย:
flutter run -d <device-id> --dart-define-from-file=.env.local
```

---

## การทดสอบ

```bash
cd frontend
flutter analyze
flutter test
```

ดูวิธีรันทั้งระบบร่วมกับ Backend และ AI Service ได้ที่ [README หลัก](../README.md)
