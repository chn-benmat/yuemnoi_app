# แนวทางสำหรับ agent: ai_service

ใช้กับทุกไฟล์ภายใต้ `ai_service/` รันคำสั่งจากโฟลเดอร์นี้ ใช้ Python 3.12 และ venv ของโปรเจ็กต์ อ่าน `README.md` เมื่อแก้ pipeline, runtime, knowledge หรือ JSON/SSE contract

## สถาปัตยกรรม

- รักษาทิศทาง dependency เข้าสู่ domain: `app/domain/` เป็น entities/ports, `app/application/` เป็น use cases/services, `app/infrastructure/` เป็น adapters และ `app/interface/` เป็น FastAPI/API schemas
- ประกอบ dependencies ที่ `app/core/container.py`; domain ใช้ Pydantic ได้ตามโค้ดเดิม แต่ต้องไม่ขึ้นกับ FastAPI, HTTP client หรือ DB adapter
- ใช้ async I/O สำหรับ network calls และรักษา cancellation/deadline; ใช้ Pydantic v2 API เช่น `model_validate`, `model_dump` และ `model_json_schema`
- คอมเมนต์ที่เพิ่มหรือแก้ให้ใช้ภาษาไทยที่อธิบายเหตุผลหรือข้อจำกัด

## การตีความและความน่าเชื่อถือ

- ให้ structured reasoning ตีความเจตนาและข้อมูลจากข้อความ โดยนิยาม intent ตามเป้าหมายการสื่อสารและข้อมูลที่ยังขาด ห้ามใช้ keyword/regex routing หรือชุดวลีตายตัวแทนการตีความความหมาย
- ดึงสินค้า ประเภท ราคา และสถานะจาก catalog จริงผ่าน repository/cache; ห้ามฝังรายการสินค้า จำนวนสินค้า หรือราคาไว้ใน production logic หรือ prompt
- สร้างคำตอบ คำถามชี้แจง และตัวเลือกจากบริบทกับหลักฐานจริง ห้ามใช้บทสนทนาหรือคำตอบธุรกิจสำเร็จรูปแทน reasoning และห้ามส่งข้อมูล mock ทดแทน dependency ที่ล้มเหลว
- ข้อห้ามข้างต้นใช้กับการตีความและข้อมูลธุรกิจ; ใช้เงื่อนไขปกติ, regex, constants และ config defaults สำหรับ validation, protocol, serialization และ deterministic safety checks ได้
- แนะนำจากความต้องการ งบประมาณ สเปกที่ตรวจได้ และความพร้อมของสินค้า อธิบายข้อจำกัดตามหลักฐานโดยไม่ให้คะแนนพิเศษแก่แบรนด์ เจ้าของ หรือผลประโยชน์ทางการค้า
- ใช้ app knowledge ที่ผ่านการอนุมัติสำหรับข้อเท็จจริงของแอป; ประเด็นที่ยังไม่ยืนยันต้องแสดงข้อจำกัด ไม่แต่งนโยบายเงินมัดจำ คืนเงิน หรือค่าปรับ

## Runtime และ response contract

- อ่านค่าตั้งผ่าน `app/core/config.py`; provider/model order, review, repair, deadline และ quota อยู่ใน `config/ai_runtime.json` ตรวจ schema ใน `config/schemas/` เมื่อแก้ config
- รักษา Groq provider และ writer/reviewer ที่เป็นอิสระตาม runtime ปัจจุบัน อ้าง configuration แทนการฝังชื่อโมเดล ค่าใช้จ่าย หรือสิทธิ์ใช้จ่ายจากการอนุมัติในอดีต
- `knowledge/interpretation_policy.json` และ `knowledge/app_knowledge.json` มีการตรวจ schema/digest ให้ใช้ workflow ในโค้ดที่เกี่ยวข้องและตรวจความถูกต้องก่อน restart; การแก้ runtime/policy ต้อง restart จึงนำค่ามาใช้
- รักษาประวัติ quota ใน `.state/` ระหว่างการตรวจงาน การล้าง ledger ทำให้การนับการใช้งานคลาดเคลื่อน
- เผยแพร่คำตอบหลัง validation และ independent review สำเร็จเท่านั้น SSE ส่ง progress/status ก่อน แล้วส่งคำตอบที่ผ่านตรวจเป็น `ready` ตามด้วย `metadata`, `delta`, `done`; ตรวจ implementation จริงก่อนเปลี่ยน event contract
- เมื่อแก้ API/SSE หรือ `config/chat_client_runtime.json` ให้ตรวจผลต่อ `../backend/` และ `../frontend/` รวมถึง error, timeout และการยกเลิกคำขอ
- เก็บ API keys และ internal service key ใน env ฝั่ง server ปกปิด credentials และข้อความ/ข้อมูลส่วนบุคคลใน diagnostics

## ตรวจงาน

```powershell
.\.venv\Scripts\python.exe main.py
```

- เมื่อต้องติดตั้ง dependencies ใช้ Python ของ venv กับ `-m pip install -r requirements.txt`
- วาง Python tests ใน `tests/` และรันเฉพาะชุดที่มีจริงด้วย `.\.venv\Scripts\python.exe -m pytest tests/<test_file>.py -q`
- checkout นี้ยังไม่มี test files ใน `tests/` และไม่มี `evaluation/`; ตัวอย่าง pytest หลายคำสั่งใน README จึงใช้ไม่ได้ทันที ให้รายงานว่าขาดชุดทดสอบแทนการอ้างว่าผ่าน
- สำหรับ syntax check ใช้ `.\.venv\Scripts\python.exe -m compileall -q app main.py`; ผลนี้ตรวจ syntax เท่านั้น ไม่ยืนยัน runtime, response quality หรือ latency
- ใช้ fake adapters สำหรับการตรวจ offline ตรวจ prerequisites ก่อน live calls ที่ใช้ quota และรายงานคำสั่ง ผลตรวจ กับข้อจำกัดตามจริง
