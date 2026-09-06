# Yuemnoi conversational pipeline — 5 กันยายน 2026

รายงานนี้แทนผลของ pipeline แบบกฎในรอบก่อน ไม่ใช่การรับรองว่าความสามารถเทียบเท่า ChatGPT

## การเปลี่ยนแปลงรอบนี้

- `app/agent/dialogue.py` (ใหม่): สัญญา Intent/Answer, การตีความคำผิดและบริบทครั้งเดียว, schema แยกคำตอบตรงจากคำสั่งค้นหา, candidate ranking และตรวจ ID/หลักฐาน/URL/ตัวเลขสเปค
- `app/agent/executor.py`: production ใช้ตีความ → เครื่องมือ → เลือกและตอบร่วมกัน; ไม่ผ่าน rule router หรือ matcher/verifier เดิม ข้อความล่าสุดอยู่ท้าย history เสมอ
- คำทักทาย ขอบคุณ และความสามารถที่ชัดเจนใช้ fast path; คำถามกว้างใช้โมเดลถามกิจกรรม; คำถามต่อเนื่องสืบทอดหัวข้อ ส่วนการเปลี่ยนประเภทไม่สืบทอดงบเก่า
- ใช้แค็ตตาล็อก cache เพื่อจัดอันดับ candidate สูงสุด 8 รายการ อ่านสดก่อนกรองงบ/หน่วย/สถานะ และอ่านสินค้าที่เลือกซ้ำหลังสร้างคำตอบ ถ้าราคาเปลี่ยนใช้ราคาสด ถ้าผิดงบ/ไม่ว่าง/รายละเอียดเปลี่ยนให้หยุดแสดงการ์ด
- ไม่ส่งราคาให้โมเดลสร้างข้อความราคาเอง ชื่อ ราคา หน่วย และการ์ดประกอบจากรายการสดเดียวกัน
- ถ้าขาดหลักฐานความเหมาะสม ให้เสนอเป็นตัวเลือกพร้อมข้อจำกัด ไม่แปลว่าไม่มีสินค้า; no_match จำกัดข้อความไว้ที่รายการที่ตรวจสอบด้วยโค้ด
- `config.py`: output budget ตีความ 384 / ตอบ 512 tokens ใช้ scb10x/llama3.1-typhoon2-8b-instruct:latest (Typhoon 2 8B), think=False, shared client, keep-alive และ deadline รวม 45 วินาที ไม่มี retry หรือ streaming
- `README.md`: อธิบายเส้นทางและข้อจำกัดปัจจุบัน

API/UI เดิม ไม่มี dependency, migration หรือการแก้ env/lockfiles ส่วนไฟล์ cache, telemetry, main และ inventory_grounding ที่แก้ค้างมาจากรอบก่อนยังคงอยู่ ไม่ได้แก้ backend/frontend เพิ่มในรอบนี้

เครื่องมือเชิงตรรกะมี inventory และ specifications เรียกแต่ละประเภทได้ไม่เกินหนึ่งรอบ ไม่มี agent loop โดย inventory มีหลาย HTTP reads ภายในเพื่อรักษาความสด; จำนวน HTTP requests จึงอาจมากกว่าสอง

## วิธีตรวจสอบ

คำสั่งจาก `ai_service`:

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests
.\.venv\Scripts\python.exe -X utf8 -m tests.evaluate_dialogue --baseline --output tests/dialogue_before.json
.\.venv\Scripts\python.exe -X utf8 -m tests.evaluate_dialogue --output tests/dialogue_release.json
```

รัน `git diff --check` จาก root repository ผล unit tests และ benchmark อยู่ด้านล่าง

Baseline เป็น snapshot โค้ดใน workspace ก่อนการเปลี่ยนบทสนทนารอบนี้ (`tests/_dialogue_baseline`) ไม่ใช่ git HEAD และไม่ใช่ log 34.86 วินาทีเดิม

Benchmark ใช้ Ollama จริงบนเครื่องเดิม กับฐานข้อมูล fixture 3 รายการ ไม่มี latency Supabase/Go/Flutter หรือเว็บจริง ชุดเดียวกัน 30 คำถาม ทำซ้ำ 3 รอบ แยกพร้อมกัน 1 และ 3 คำขอ รวม 180 คำตอบต่อเวอร์ชัน โมเดลอยู่ในหน่วยความจำแล้ว จึงเป็น warm benchmark

ตัวชี้วัดผ่านอัตโนมัติคือ status success และ ID ตรงที่คาด ไม่ใช่คะแนนคุณภาพเหตุผลหรือภาษาอย่างครบถ้วน ต้องอ่านตัวอย่างคำตอบประกอบ ไม่ให้ error ที่ตอบเร็วถือว่าผ่าน

## ผลตรวจสอบ

- Unit tests: **61 tests ผ่าน** ใน 14.880 วินาที (`tests/dialogue_tests.txt`)
- `git diff --check`: ผ่าน มีเพียงคำเตือน LF/CRLF ของ working copy
- โมเดลจริง: หลังปรับ **180/180** ผ่านเกณฑ์ status/ID ไม่มี response failed ในชุดนี้ เทียบก่อนปรับ 171/180

| เวอร์ชัน | พร้อมกัน | ผ่าน status/ID | p50 | p95 |
|---|---:|---:|---:|---:|
| ก่อนปรับบทสนทนา | 1 | 86/90 | <0.001 s | 2.642 s |
| หลังปรับบทสนทนา | 1 | 90/90 | 3.937 s | 5.088 s |
| ก่อนปรับบทสนทนา | 3 | 85/90 | <0.001 s | 6.237 s |
| หลังปรับบทสนทนา | 3 | 90/90 | 10.572 s | 12.118 s |

**เป้าหมาย warm p95 ≤5 วินาทียังไม่ผ่าน** และยังไม่รวม latency ฐานข้อมูลจริง ค่าใกล้ศูนย์ของ baseline เกิดจาก rule fast path หลายกรณี ไม่ใช่โมเดลตอบได้ทันที รุ่นใหม่ให้โมเดลตีความและเขียนคำตอบสองครั้ง จึงช้ากว่า baseline นี้เพื่อเปลี่ยนพฤติกรรมบทสนทนา ไม่อ้างว่าเร็วขึ้น

ตรวจข้อความตัวอย่างครบ 30 กรณีในรอบแรก และตรวจข้อความที่แตกต่างในกรณีสำคัญเพิ่มเติม: คำผิดคอนเสิร์ตเลือกกล้องพร้อมบอกว่าไม่มีข้อมูลยืนยันความเหมาะสมเฉพาะกิจกรรม, คำถามกว้างถามกิจกรรม, เปลี่ยนเป็นเต็นท์คืนเต็นท์, ถูกกว่านี้ไม่เสนอไมค์แทนกล้อง

ระหว่าง process benchmark ทำงาน มีการเสริม validator ตัวเลขให้ตรวจเฉพาะสินค้าที่เลือก, log เหตุผล และ renderer ของ no_match ในโค้ดปลายทาง จึงใช้ unit tests และ smoke บนโค้ดสุดท้ายยืนยันส่วนนี้ ไม่ได้รัน performance 180 คำตอบซ้ำหลังการเสริมดังกล่าว; prompt และเส้นทางเรียกโมเดลเหมือนกัน

Smoke บนโค้ดสุดท้าย:

```powershell
.\.venv\Scripts\python.exe -X utf8 -m tests.smoke_dialogue_live
```

- คำถาม `แนะนำกล้องถ่ายคอนเสิตหน่อย` กับ Supabase จริง: success / using_supabase, ID 31, เวลา **5.684 s** คำตอบเสนอ Canon EOS R50 และบอกว่าไม่มีข้อมูลการใช้งานจริงเฉพาะคอนเสิร์ต ไม่รับรองประสิทธิภาพที่ไม่มีหลักฐาน
- เวลา interpretation 2.310 s, answer 2.948 s, catalog + freshness + final_freshness รวม 0.425 s
- Ollama สองครั้งรวม load 0.284 s, อ่าน prompt 0.345 s, สร้าง output 4.228 s (76 + 97 tokens) คอขวดตัวอย่างนี้อยู่ที่การสร้างข้อความ ไม่ใช่ฐานข้อมูล ตัวอย่างเดียวไม่ใช่ p95 และไม่พิสูจน์สาเหตุ log 34.86 s ในอดีต
- ลำดับห้าคำถามต่อเนื่องกับโมเดลจริงและ fixture ผ่าน **5/5**: กล้อง → แนะนำอุปกรณ์หน่อย → ทำไรได้บ้าง → ออกแคม → ถูกกว่านี้ (`tests/dialogue_sequence.json`)
- รอบ smoke แรกพบตัวตรวจราคาปฏิเสธข้อความ no_match ของคำถามถูกกว่านี้ จึงแก้ให้ไม่ตรวจ prose ที่จะถูก renderer ทิ้งอยู่แล้ว แต่ยังตรวจ ID/หลักฐานก่อนเสมอ เพิ่ม regression และรันลำดับเดิมซ้ำผ่านครบ
- ผลจริง/เวลา: `tests/dialogue_live.json`, `tests/dialogue_live_metrics.txt`

ผลดิบ: `tests/dialogue_before.json`, `tests/dialogue_release.json`; คำตอบและ timing ทุกกรณีอยู่ใน JSON ส่วนผลรวมอยู่ในไฟล์ชื่อเดียวกันลงท้าย `_summary.txt`

Tests ที่เพิ่ม/ปรับ: `tests/test_executor_grounding.py`, `tests/test_pipeline_context.py`, `tests/test_recommendation_and_consultative.py`, `tests/test_agent_regressions.py`, `tests/evaluate_dialogue.py`, `tests/smoke_dialogue_live.py` โดยนำ tests เส้นทาง rule เก่าที่ถูกแทนที่ออกและทดสอบเส้นทาง production ใหม่ ไม่ตรวจชนิด mock เพื่อเปลี่ยนพฤติกรรม

## ขอบเขตและข้อจำกัด

- Unit tests mock external boundaries; การทดสอบกับโมเดลจริงยืนยันเพิ่มเฉพาะชุด 30 กรณี ไม่ครอบคลุมสำนวนไทยทั้งหมด
- ชุดทดสอบมีคำผิดที่ไม่ได้อยู่ในตัวอย่าง prompt เช่น ก้อง/ถ่ายรูบ/ไมโคโฟน/เต้นท์, อังกฤษ, เปลี่ยนหัวข้อ, งบใหม่, ถูกกว่านี้, คำอ้างถึงสินค้า และคำถามกว้าง
- ราคาสดและ ID ตรวจด้วยโค้ด แต่ความเกี่ยวข้องเชิงภาษาและข้ออ้างเชิงคุณภาพยังพึ่งโมเดล การตรวจ quote/URL ไม่ใช่เครื่องพิสูจน์ทุกประโยค
- พบการตอบไทยในคำถามอังกฤษบางกรณี แม้ตีความและเลือกสินค้าได้ถูกต้อง และบางคำตอบยังสั้นหรือไม่ได้ถามต่ออย่างมีประโยชน์ทุกครั้ง
- ผลค้นหาเพียง candidate 8 รายการจาก catalog จำกัดจำนวน อาจพลาดสินค้าที่ชื่อ/คำอธิบายไม่ช่วยจัดอันดับ โดยเฉพาะข้ามภาษา ไม่อ้างว่าไม่พบทั้งระบบ
- เว็บใช้ snippets จากเครื่องมือเดิม ยังไม่ดาวน์โหลดและตรวจเนื้อหาเต็มของหน้าอ้างอิง; benchmark นี้ไม่ได้วัดคุณภาพเว็บจริง
- Tests และผล benchmark ถูก ignore ตามกฎ Git เดิม อยู่ในเครื่อง ต้องรวมไฟล์เหล่านี้ในการส่งต่อแยกต่างหากหากต้องการรันใน checkout อื่น ไม่เปลี่ยนกฎ ignore หรือ stage อัตโนมัติ
- ไม่ได้รัน Go/Flutter tests เพราะไม่ได้แก้สองส่วนนี้ในรอบนี้ ยังไม่ได้ทดสอบผ่านแอปบนอุปกรณ์หรือ restart/deploy production

เริ่มใช้โดย restart AI service และติดตาม request ID, interpretation, answer, freshness, final_freshness, จำนวน model calls และ outcome ควบคู่ latency
