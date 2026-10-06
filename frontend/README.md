# 📱 Frontend: ยืมหน่อย (Yuemnoi Mobile App)

ค่าการทำงานของ AI chat อยู่ใน `../ai_service/config/chat_client_runtime.json` ใช้ `flutter run --dart-define-from-file=../ai_service/config/chat_client_runtime.json` ร่วมกับไฟล์ configuration ของแอปตามสภาพแวดล้อม โดยไม่ใส่ server-only key ใน Flutter ค่า compile-time เป็น configuration ของ build; แก้ JSON แล้วต้อง build ใหม่

คำตอบแบบมีโครงสร้างเก็บ scope/sufficiency/action/flow และบริบทเฉพาะแชต ส่งคำตอบแบบสอบถามด้วย ID เส้นทางใหม่แสดงข้อความและการ์ดทันทีเมื่อข้อมูลพร้อม การวัดผ่าน `ChatbotBloc.onTimingMeasured` แยก first text, transport complete และ post-frame render โดยไม่ log ข้อความหรือ credentials อัตโนมัติ กรณี error/cancelled/ไม่เห็นเฟรมครบไม่มี success render sample

`test/features/chatbot/live_gateway_render_test.dart` เป็น smoke ที่ต้อง opt-in และใช้ HTTP จริงผ่าน Go/Python ใน Flutter Live Test Binding ไม่ใช่ physical device/profile mode และไม่ใช้รับรอง p95

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.11+-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Supabase](https://img.shields.io/badge/Supabase-Auth%20%26%20Realtime-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)](https://supabase.com)
[![BLoC](https://img.shields.io/badge/State-flutter__bloc-blueviolet?style=for-the-badge)](https://bloclibrary.dev)

แอปพลิเคชันมือถือสำหรับแพลตฟอร์ม **ยืมหน่อย (Yuemnoi)** พัฒนาด้วย **Flutter** รองรับทั้งระบบปฏิบัติการ **Android** และ **iOS** ออกแบบสถาปัตยกรรมตามหลัก **Clean Architecture** ร่วมกับ **BLoC Pattern** เพื่อการจัดการสถานะ (State Management) ที่มีประสิทธิภาพและดูแลรักษาง่าย

---

## 📑 สารบัญ (Table of Contents)

1. [ภาพรวมสถาปัตยกรรม (Architecture Overview)](#-ภาพรวมสถาปัตยกรรม-architecture-overview)
2. [โครงสร้างไดเรกทอรี (Directory Structure)](#-โครงสร้างไดเรกทอรี-directory-structure)
3. [ฟีเจอร์ภายในแอปพลิเคชัน (Features)](#-ฟีเจอร์ภายในแอปพลิเคชัน-features)
4. [ข้อกำหนดเบื้องต้น (Prerequisites)](#-ข้อกำหนดเบื้องต้น-prerequisites)
5. [การตั้งค่า Environment Variables](#-การตั้งค่า-environment-variables)
6. [ขั้นตอนการติดตั้งและรันแอปพลิเคชัน (Getting Started)](#-ขั้นตอนการติดตั้งและรันแอปพลิเคชัน-getting-started)
7. [วิธีการคอมไพล์และสร้างไฟล์ติดตั้ง (Build APK / App Bundle)](#-วิธีการคอมไพล์และสร้างไฟล์ติดตั้ง-build-apk--app-bundle)
8. [การทดสอบ (Testing)](#-การทดสอบ-testing)
9. [แนวทางการพัฒนา (Development Rules)](#-แนวทางการพัฒนา-development-rules)

---

## 🏛️ ภาพรวมสถาปัตยกรรม (Architecture Overview)

โครงสร้างโค้ดภายในโฟลเดอร์ `lib/features/` ถูกจัดแบ่งตามหลัก **Clean Architecture** แยกหน้าที่ของแต่ละ Layer ชัดเจน:

```text
features/<feature_name>/
├── data/
│   ├── datasources/     # เชื่อมต่อ REST API (Dio), Supabase หรือ Local Storage
│   ├── models/          # Data Transfer Objects (DTO) และ JSON Serialization
│   └── repositories/    # Implementation ของ Domain Repositories
├── domain/
│   ├── entities/        # โครงสร้างข้อมูลเชิงธุรกิจ (Pure Dart Models)
│   ├── repositories/    # Interface สัญญาการทำงานของ Repository
│   └── usecases/        # Business Logic Use Cases
└── presentation/
    ├── bloc/            # BLoC / Cubit จัดการ State, Event และ State Transitions
    ├── pages/           # หน้าจอแสดงผล (Screens / Views)
    └── widgets/         # Widget ย่อยที่ใช้เฉพาะภายใน Feature นี้
```

### การเชื่อมต่อเครือข่ายและบริการภายนอก (Hybrid Integration):

- **Core Business Logic (REST API via Dio)**: การจอง, ดึงฟีดอุปกรณ์, อัปเดตโปรไฟล์, ธุรกรรม Wallet จะเรียกไปยัง **Go Backend** (`/api/v1/...`)
- **Realtime Chat & Auth (Supabase SDK)**: การรับส่งข้อความสดในห้องแชท (`chat_room:*`), Presence Tracking และ Google OAuth เชื่อมต่อผ่าน `supabase_flutter` โดยตรงเพื่อความรวดเร็ว
- **AI Chatbot Streaming (SSE)**: รับข้อมูลการตอบสดของ AI ทีละโทเค็นผ่าน Backend Gateway (`/api/v1/chat-ai/stream`)

Chatbot ใช้ `AI_CHAT_RESPONSE_READY_TIMEOUT_SECONDS=30` นับจาก interaction ที่ส่งคำขอถึงได้รับคำตอบครบที่ผ่านการตรวจใน SSE `ready` หากครบเวลาให้ยกเลิก HTTP แม้ยังรอ headers ค่า `AI_CHAT_REQUEST_TIMEOUT_SECONDS=45` เป็นขอบเขต transport ส่วน idle timeout 20s ใช้ตรวจ stream ขาดการติดต่อและมี heartbeat จาก AI แยกกัน `response_ready_microseconds` และเวลาตอบที่แสดงไม่ถูกทับด้วยเวลาส่งตัวอักษร/วาดหน้าจอ ค่า build ใช้ `--dart-define-from-file=../ai_service/config/chat_client_runtime.json`; คำตอบที่พร้อมก่อนส่งทันที

---

## 📁 โครงสร้างไดเรกทอรี (Directory Structure)

```text
frontend/
├── assets/
│   ├── fonts/           # ฟอนต์ Prompt สำหรับแสดงผลภาษาไทยและอังกฤษ
│   ├── icons/           # ไอคอนของระบบ
│   ├── images/          # โลโก้และภาพประกอบ
│   └── sounds/          # ไฟล์เสียงแจ้งเตือน
├── lib/
│   ├── core/            # โมดูลกลางที่ใช้งานร่วมกันทั้งแอปพลิเคชัน
│   │   ├── config/      # การอ่านค่าคอนฟิกสภาพแวดล้อม (AppConfig)
│   │   ├── constants/   # ค่าคงที่ สี ดีไซน์โทเค็น (AppColors)
│   │   ├── errors/      # Failure & Exception classes
│   │   ├── navigation/  # การตั้งค่า GoRouter และ Deep Links
│   │   ├── network/     # Dio Client และ Supabase Auth Interceptor
│   │   ├── services/    # FCM Push Notification, Location, Presence Tracker
│   │   ├── theme/       # AppTheme & Typography
│   │   ├── utils/       # Image Compression, Date Formatters
│   │   └── widgets/     # Common Shared Widgets (ปุ่ม, ฟอร์ม, Dialog)
│   ├── features/        # โมดูลตามฟังก์ชันการทำงาน (Feature Modules)
│   │   ├── auth/        # ระบบยืนยันตัวตน (Email, Password, Google, OTP)
│   │   ├── booking/     # การส่งคำขอจองเช่าและจัดการคำขอ
│   │   ├── chat/        # แชทสนทนาระหว่างผู้เช่า-ผู้ให้เช่าแบบ Realtime
│   │   ├── chatbot/     # ระบบสนทนากับ AI Rental Consultant
│   │   ├── home/        # ฟีดรายการอุปกรณ์แนะนำ ค้นหา และกรองหมวดหมู่
│   │   ├── item_detail/ # รายละเอียดอุปกรณ์ สเปก และเงื่อนไขการเช่า
│   │   ├── profile/     # จัดการโปรไฟล์ ยืนยันตัวตน และเบอร์ติดต่อ
│   │   ├── rental_item/ # การลงประกาศปล่อยเช่าอุปกรณ์และการแก้ไข
│   │   ├── rental_return/# การส่งมอบ (Handover) และส่งคืน (Return) อุปกรณ์
│   │   ├── review/      # การเขียนรีวิวและประเมินคะแนน
│   │   └── wallet/      # กระเป๋าเงินดิจิทัล เติมเงิน และประวัติการทำรายการ
│   ├── app.dart         # รูทวิดเจ็ตของแอปพลิเคชัน
│   └── main.dart        # จุดเริ่มต้นการทำงาน (Entry Point)
├── test/                # ชุดทดสอบ Unit Tests และ Widget Tests
└── pubspec.yaml         # รายการ Package Dependencies
```

---

## ✨ ฟีเจอร์ภายในแอปพลิเคชัน (Features)

- **Authentication & Guest Mode**:
  - รองรับการเข้าสู่ระบบด้วย Email/Password และ Google Sign-In (OAuth PKCE)
  - รองรับโหมด Guest Browsing (สามารถดูรายการสินค้าได้ แต่จะติด Login Guard เมื่อกดจองหรือแชท)
- **Discovery Feed & Catalog**:
  - หน้าฟีดเรียงลำดับอุปกรณ์ตามความนิยม (Popularity) และความสดใหม่ (Recency)
  - กรองตามหมวดหมู่ เช่น กล้อง, เลนส์, โน้ตบุ๊ก, แท็บเล็ต, อุปกรณ์สตูดิโอ
  - แสดงผลด้วย Shimmer Skeleton Loading ระหว่างรอข้อมูล
- **Rental Lifecycle Management**:
  - สร้างคำขอเช่า ระบุวันที่ต้องการเช่า คำนวณราคาอัตโนมัติ
  - ระบบตัดเงินค่าเช่าและเงินประกันผ่าน Wallet
  - ยืนยันการส่งมอบแบบพบหน้าด้วย OTP / QR Code
  - ติดตามพิกัดจุดนัดพบผ่านแผนที่ OpenStreetMap (`flutter_map`)
  - ยืนยันการส่งคืนและปลดล็อกเงินประกัน
  - ให้คะแนนและเขียนรีวิวผู้ให้เช่า
- **Real-time Messaging**:
  - ส่งข้อความและรูปภาพสภาพสินค้าแบบสดผ่าน WebSocket
  - แสดงจำนวนข้อความที่ยังไม่ได้อ่าน
- **AI Chatbot Interface**:
  - สตรีมคำตอบแบบพิมพ์สด (SSE)
  - แสดงชิปตัวเลือก (Interactive Choice Chips) เพื่อตอบคำถามเจาะจงของ AI
  - ปุ่มแก้ไขข้อความ และปุ่มส่ง Feedback ความพึงพอใจ
- **Push Notifications**:
  - แจ้งเตือนข้อความแชทใหม่และสถานะการเช่าผ่าน Firebase Cloud Messaging (FCM)

---

## 📋 ข้อกำหนดเบื้องต้น (Prerequisites)

- **Flutter SDK**: `^3.11.5` (หรือเวอร์ชัน 3.29+)
- **Dart SDK**: `^3.11.5`
- **Android Studio** (สำหรับรัน Android Emulator หรือเชื่อมต่ออุปกรณ์จริง) หรือ **Xcode** (สำหรับ iOS Simulator บน macOS)
- ติดตั้ง `build_runner` เพื่อคอมไพล์โค้ด Serialization

---

## ⚙️ การตั้งค่า Environment Variables

สร้างไฟล์ `.env.local` ภายในโฟลเดอร์ `frontend/`:

```env
# URL สำหรับเชื่อมต่อไปยัง Go Backend REST API
# สำหรับ Android Emulator ใช้ 10.0.2.2
# สำหรับ iOS Simulator หรือ Web ใช้ localhost
# สำหรับ Physical Device ให้ใช้ IP เครื่อง Host ในเครือข่าย หรือ Tailscale URL
API_URL=http://10.0.2.2:8080/api/v1

# ข้อมูลเชื่อมต่อ Supabase
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_PUBLISHABLE_KEY=your-supabase-anon-key

# กุญแจความปลอดภัยสำหรับยืนยันว่าเป็นแอปที่ถูกต้อง
APP_SECRET_KEY=your-super-secure-app-secret-key-32chars

# Google OAuth Web Client ID (สำหรับการยืนยันตัวตนผ่าน Google Sign-In)
GOOGLE_WEB_CLIENT_ID=your-google-client-id.apps.googleusercontent.com
```

---

## 🚀 ขั้นตอนการติดตั้งและรันแอปพลิเคชัน (Getting Started)

### 1. ดาวน์โหลดแพ็กเกจ

```bash
cd frontend
flutter pub get
```

### 2. รันแอปพลิเคชัน

รันโดยระบุไฟล์คอนฟิกผ่าน `--dart-define-from-file`:

```bash
flutter run --dart-define-from-file=.env.local
```

หรือระบุ Device เจาะจง:

```bash
# รันบน Android
flutter run -d android --dart-define-from-file=.env.local

# รันบน iOS
flutter run -d ios --dart-define-from-file=.env.local

# รันบน Chrome (Web)
flutter run -d chrome --dart-define-from-file=.env.local
```

---

## 📦 วิธีการคอมไพล์และสร้างไฟล์ติดตั้ง (Build APK / App Bundle)

ก่อนเริ่มคอมไพล์ กรุณาตรวจสอบ Checklist ดังนี้:
1. ดึง Dependencies ให้ครบถ้วน: `flutter pub get`
2. คอมไพล์โค้ด Model Serialization: `dart run build_runner build --delete-conflicting-outputs`
3. **ตรวจสอบ `API_URL` ใน `.env.local`**: หากนำ APK ไปติดตั้งบนสมาร์ตโฟนเครื่องจริง ให้เปลี่ยนจาก `10.0.2.2` หรือ `localhost` เป็น IP เครื่องคอมพิวเตอร์ในวง LAN เดียวกัน (เช่น `http://192.168.1.XX:8080/api/v1`) หรือใช้ Cloud/Tailscale URL ที่เครื่องภายนอกเข้าถึงได้

### 1. คอมไพล์แบบ Universal Release APK (รวมทุก CPU Architecture)
เหมาะสำหรับการนำไฟล์ไปส่งต่อหรือแชร์ให้ผู้อื่นติดตั้งได้ทันทีบนทุกเครื่อง:
```bash
flutter build apk --release --dart-define-from-file=.env.local
```
- 📁 **ไฟล์ผลลัพธ์**: `build/app/outputs/flutter-apk/app-release.apk`

---

### 2. คอมไพล์แบบแยกสถาปัตยกรรม CPU (Split per ABI - แนะนำ)
ช่วยลดขนาดไฟล์ APK ลงได้มากกว่า 50% เหมาะสำหรับการติดตั้งเฉพาะเครื่อง:
```bash
flutter build apk --release --split-per-abi --dart-define-from-file=.env.local
```
- 📁 **ไฟล์ผลลัพธ์** (อยู่ในโฟลเดอร์ `build/app/outputs/flutter-apk/`):
  - `app-arm64-v8a-release.apk` : สำหรับสมาร์ตโฟน Android 64-bit รุ่นใหม่เกือบทั้งหมด (**แนะนำสำหรับเครื่องปัจจุบัน**)
  - `app-armeabi-v7a-release.apk` : สำหรับสมาร์ตโฟน Android 32-bit รุ่นเก่า
  - `app-x86_64-release.apk` : สำหรับอุปกรณ์ x86_64 หรือ Android Emulator

---

### 3. คอมไพล์ Debug APK (สำหรับทดสอบด่วน)
หากต้องการติดตั้งเพื่อทดสอบระบบอย่างรวดเร็วโดยไม่ต้องตรวจ Signing Key:
```bash
flutter build apk --debug --dart-define-from-file=.env.local
```
- 📁 **ไฟล์ผลลัพธ์**: `build/app/outputs/flutter-apk/app-debug.apk`

---

### 4. คอมไพล์ Android App Bundle (.aab สำหรับ Google Play Store)
สำหรับการเตรียมไฟล์นำขึ้นเผยแพร่บน Google Play Console:
```bash
flutter build appbundle --release --dart-define-from-file=.env.local
```
- 📁 **ไฟล์ผลลัพธ์**: `build/app/outputs/bundle/release/app-release.aab`

---

### 5. วิธีการติดตั้งไฟล์ APK ลงสมาร์ตโฟนผ่าน ADB
หากเปิดโหมด **USB Debugging** บนสมาร์ตโฟนไว้ สามารถสั่งติดตั้งได้โดยตรงผ่านคำสั่ง:
```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

---

## 🧪 การทดสอบ (Testing)

รันชุดทดสอบทั้งหมดในโปรเจกต์:

```bash
flutter test
```

รันการทดสอบเฉพาะส่วน:

```bash
# ทดสอบ Core Logic
flutter test test/core/

# ทดสอบ Feature Bloc & Repositories
flutter test test/features/
```

---

## 📝 แนวทางการพัฒนา (Development Rules)

1. **Clean Architecture Strictness**: ห้ามเรียกใช้ Database/API โดยตรงจาก UI Presentation Layer ทุกอย่างต้องผ่าน Use Case และ Repository
2. **UI Stability**: ห้ามปรับเปลี่ยน Layout หรือ Styling เดิมโดยไม่ได้รับมอบหมาย ให้คงดีไซน์ Tokens และสีเดิมใน `core/constants/colors.dart`
3. **No Direct Sensitive DB Joins**: ห้าม Query ข้อมูลส่วนบุคคล (เบอร์โทร, ข้อมูล KYC) ข้ามผู้ใช้ผ่าน Supabase Client โดยตรง ให้เรียกผ่าน Go Backend เสมอ
4. **Code Comments**: เขียนคอมเมนต์อธิบายโค้ดด้วยภาษาไทยที่กระชับและเข้าใจง่าย

## Conversation fixes (2026-10-04)

Optional `active_question_id` identifies a displayed question from `context.questions`. It does not automatically associate the typed message with that question. Send the raw message and actual completed `questionnaire_answers`; the semantic planner resolves answers, corrections, social turns and topic changes. Legacy requests omit this field.

Rental duration uses the `rental_duration` fact/question dimension, separate from the budget billing period `budget_unit`. Catalog factual prose uses authoritative field references in the internal evidence contract. Post-fix real-provider evaluation reuses the original suite in `ai_service/evaluation/conversation_afterfix_20261004`, with distinct checkpoints and all attempts preserved.
