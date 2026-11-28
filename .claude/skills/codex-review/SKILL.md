---
name: codex-review
description: ขอให้ Codex CLI รีวิว diff แบบอ่านอย่างเดียว (sandbox read-only) เป็นความเห็นที่สองที่เป็นอิสระ ใช้เมื่อผู้ใช้สั่ง /codex-review หรือขอให้ Codex รีวิว ก่อนเสนอ commit งานที่แตะหลายไฟล์
---

# Codex review (read-only)

ใช้ Codex CLI (`codex review`) เป็น reviewer อิสระ Codex อ่านได้อย่างเดียว ห้ามแก้ไฟล์

> หมายเหตุ: Codex CLI 0.172 ไม่มีคำสั่ง `codex mcp-server` แล้ว จึงเรียกผ่าน CLI แทนการลงทะเบียน MCP

## ขั้นตอน

1. เลือกขอบเขต (ถามผู้ใช้ถ้าไม่ชัด):
   - งานที่ยังไม่ commit: `--uncommitted`
   - เทียบกับ branch: `--base main`
   - commit เดียว: `--commit <sha>`
2. รันจาก root ของ repo (หรือ worktree ที่ต้องการรีวิว) ใน background เพราะอาจใช้หลายนาที:

   ```bash
   codex review --uncommitted \
     -c sandbox_mode='"read-only"' \
     -c approval_policy='"never"' \
     "รีวิวตามกฎใน AGENTS.md และ AGENTS.md ของโฟลเดอร์ที่ถูกแก้ เน้น bug, contract ข้ามส่วน, ความปลอดภัย และ test ที่ขาด รายงานเป็นรายการ ไฟล์:บรรทัด + ความรุนแรง (สูง/กลาง/ต่ำ) ห้ามแก้ไฟล์" \
     < /dev/null > "$SCRATCH/codex-review.md" 2>&1
   ```

   ถ้าไม่เจอคำสั่ง `codex` ให้ใช้ `~/AppData/Roaming/npm/codex`
3. อ่านผล แล้ว **ตรวจทุกข้อกับโค้ดจริง** ก่อนเชื่อ (ใช้ skill `superpowers:receiving-code-review`) แยกเป็น: ยืนยันแล้ว / ไม่จริง / ต้องให้ผู้ใช้ตัดสิน
4. สรุปให้ผู้ใช้ แล้วแก้เฉพาะข้อที่ยืนยันเมื่อผู้ใช้เห็นด้วย นับเป็น 1 รอบ review → fix (เพดาน 2 รอบ)
5. บันทึกแถวใหม่ใน `docs/agents/experiment-log.md`

## เมื่อล้มเหลว

- `usage limit`: แจ้งผู้ใช้พร้อมเวลารีเซ็ตที่ Codex บอก แล้วหยุด อย่าวนลองใหม่
- ไม่ได้ล็อกอิน: ให้ผู้ใช้รัน `codex login` เอง
