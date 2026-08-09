# Yuemnoi Frontend

Flutter application สำหรับแพลตฟอร์มเช่าอุปกรณ์ Yuemnoi (ยืมหน่อย) ทำหน้าที่เป็นส่วนติดต่อผู้ใช้ เชื่อมต่อกับ Go Backend ผ่าน REST API และใช้ Supabase สำหรับจัดการ session และ Google OAuth

> สถานะปัจจุบัน: ขั้นตอน Authentication พร้อมใช้งานแล้ว ส่วน `HomeScreen` และฟีเจอร์เช่าอุปกรณ์ยังอยู่ระหว่างพัฒนา

## ฟีเจอร์ที่มีในปัจจุบัน

- สมัครสมาชิกพร้อมอัปโหลดรูปโปรไฟล์
- เข้าสู่ระบบด้วยอีเมลและรหัสผ่าน
- เข้าสู่ระบบด้วย Google OAuth
- กู้คืนรหัสผ่านด้วย OTP 6 หลักและตั้งรหัสผ่านใหม่
- กู้คืน Supabase session เมื่อเปิดแอปอีกครั้ง
- Responsive layout สำหรับหน้าจอมือถือหลายขนาด
- Theme และชุด component กลาง เช่น ปุ่ม ช่องกรอกข้อมูล และ page body

## เทคโนโลยี

- Flutter / Dart
- `supabase_flutter` สำหรับ Auth session และ OAuth
- `http` สำหรับเรียก Backend REST API
- `flutter_dotenv` สำหรับอ่านค่าตั้งค่าฝั่ง client
- `image_picker` สำหรับเลือกรูปโปรไฟล์
- Prompt และ Google Fonts สำหรับ Typography

## โครงสร้างสำคัญ

```text
frontend/
├── assets/
│   ├── fonts/                 # ฟอนต์ Prompt
│   ├── icons/                 # ไอคอน Social login
│   └── images/                # รูปภาพและ App icon
├── lib/
│   ├── core/
│   │   ├── constants/         # ค่าคงที่ของแอป
│   │   ├── errors/            # Exception และ Failure
│   │   ├── navigation/        # Route และ navigation helper
│   │   ├── network/           # Supabase client และ auth session
│   │   ├── theme/             # Theme และ text styles
│   │   └── widgets/           # Widget ที่ใช้ร่วมกัน
│   ├── features/
│   │   ├── auth/              # Data source, pages และ widgets ของ Auth
│   │   └── home/              # หน้าหลัก (อยู่ระหว่างพัฒนา)
│   ├── app.dart               # MaterialApp และ Theme
│   └── main.dart              # โหลด config และเริ่มแอป
└── test/                      # Widget, routing และ data source tests
```

## สิ่งที่ต้องติดตั้ง

- [Flutter SDK](https://docs.flutter.dev/get-started/install) ที่รองรับ Dart `^3.11.5`
- Android Studio/Android SDK สำหรับ Android หรือ Xcode สำหรับ iOS
- Backend ของ Yuemnoi ที่กำลังทำงาน
- Supabase project ที่เปิด Email Auth และ Google Provider ตามฟีเจอร์ที่ต้องการทดสอบ

ตรวจสอบสภาพแวดล้อมก่อนเริ่ม:

```bash
flutter doctor
```

## การตั้งค่า

สร้างไฟล์ `frontend/.env.local`:

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_PUBLISHABLE_KEY=your_publishable_key
API_URL=http://localhost:8080
```

| ตัวแปร | รายละเอียด |
| --- | --- |
| `SUPABASE_URL` | URL ของ Supabase project |
| `SUPABASE_PUBLISHABLE_KEY` | Publishable/anon key สำหรับ client |
| `API_URL` | Base URL ของ Go Backend โดยไม่ต้องใส่ `/api/v1` ต่อท้าย |

> `.env.local` ถูกประกาศเป็น Flutter asset และจะอยู่ใน app bundle จึงห้ามใส่ Supabase service role key, JWT secret หรือค่าความลับฝั่ง server ทุกชนิด

### ตั้งค่า Google OAuth

1. เปิดใช้งาน Google provider ใน Supabase Authentication
2. สำหรับ Android/iOS ให้เพิ่ม redirect URL `yuemnoi://login-callback/` ในรายการ Redirect URLs ของ Supabase
3. สำหรับ Web ให้ตั้งค่า Site URL และ Allowed Redirect URLs ให้ตรงกับ URL ที่ใช้รัน
4. ตั้งค่า Google OAuth client ตามแพลตฟอร์มที่ต้องการรัน

Android และ iOS ของโปรเจกต์ตั้งค่า custom URL scheme `yuemnoi` ไว้แล้ว

## การเชื่อมต่อ Backend จากแต่ละอุปกรณ์

ค่า `localhost` ภายใน Emulator หรือเครื่องจริงอาจไม่ได้หมายถึงคอมพิวเตอร์ที่รัน Backend

| อุปกรณ์ | ตัวอย่าง `API_URL` |
| --- | --- |
| Flutter Web / iOS Simulator | `http://localhost:8080` |
| Android Emulator | `http://10.0.2.2:8080` |
| Android Emulator (Genymotion) | `http://10.0.3.2:8080` |
| โทรศัพท์จริง | `http://<LAN-IP-ของคอมพิวเตอร์>:8080` |

เมื่อใช้โทรศัพท์จริง โทรศัพท์และคอมพิวเตอร์ต้องอยู่ในเครือข่ายเดียวกัน และ Firewall ต้องอนุญาตการเชื่อมต่อเข้าพอร์ต `8080`

## วิธีรัน

```bash
cd frontend
flutter pub get
flutter devices
flutter run
```

เลือกอุปกรณ์โดยระบุ device ID:

```bash
flutter run -d <device-id>
```

ตัวอย่างสำหรับ Chrome:

```bash
flutter run -d chrome
```

## Routes

| Route | หน้าจอ |
| --- | --- |
| `/login` | เข้าสู่ระบบ |
| `/register` | สมัครสมาชิก |
| `/forgot-password` | ขอ OTP สำหรับตั้งรหัสผ่านใหม่ |
| `/otp-verification` | ยืนยัน OTP |
| `/change-password` | ตั้งรหัสผ่านใหม่ |
| `/home` | หน้าหลัก (อยู่ระหว่างพัฒนา) |

เมื่อเปิดแอป ระบบจะตรวจสอบ Supabase session และเลือก `/home` หรือ `/login` เป็น initial route โดยอัตโนมัติ

## การตรวจสอบคุณภาพและทดสอบ

```bash
flutter analyze
flutter test
```

ชุดทดสอบปัจจุบันครอบคลุม responsive layout ของหน้า Auth, การลงทะเบียน route, การจัดการ OTP, การเปลี่ยนรหัสผ่าน และการ sync รูปโปรไฟล์จาก Google

## สร้าง App Icon ใหม่

ไฟล์ต้นฉบับอยู่ที่ `assets/images/yuemnoi.png` และตั้งค่าไว้ใน `pubspec.yaml` แล้ว:

```bash
dart run flutter_launcher_icons
```

## แก้ปัญหาเบื้องต้น

- `API_URL is not configured`: ตรวจสอบว่ามี `.env.local` และรัน `flutter pub get` หลังแก้ `pubspec.yaml`
- เชื่อมต่อ Backend ไม่ได้จาก Android Emulator: เปลี่ยน `localhost` เป็น `10.0.2.2`
- Google Login กลับเข้าแอปไม่ได้: ตรวจสอบ Supabase Redirect URL และ custom URL scheme `yuemnoi`
- แอปข้ามไปหน้า Login ทั้งที่เคยเข้าสู่ระบบ: ตรวจสอบว่า Supabase URL/key ถูกต้องและ refresh token ยังใช้งานได้

ดูวิธีรันทั้งระบบได้ที่ [README หลัก](../README.md)
