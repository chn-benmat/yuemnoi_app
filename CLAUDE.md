@AGENTS.md

## เฉพาะ Claude Code

- กฎหลักทั้งหมดอยู่ใน `AGENTS.md` (import ด้านบน) และ `AGENTS.md` ของแต่ละโฟลเดอร์ ให้แก้กฎที่นั่น ไม่ใช่ที่ไฟล์นี้ เพื่อให้ Codex อ่านกฎชุดเดียวกัน
- เมื่อแก้ไฟล์ในโฟลเดอร์ใด ให้อ่าน `<โฟลเดอร์>/AGENTS.md` ก่อน (Claude Code ไม่โหลดไฟล์เหล่านี้ให้เองเหมือน `CLAUDE.md`)
- Claude Code เป็นผู้คุมงาน: วางแผน แตกงาน รวมผล ส่งงานที่ขอบเขตชัดให้ Codex ใน worktree แยก ตาม `docs/agents/multi-agent-workflow.md`
- ขอความเห็นอิสระจาก Codex ด้วย skill `/codex-review` (read-only) ก่อนเสนอ commit งานที่แตะหลายไฟล์หรือ contract ข้ามส่วน; รับฟีดแบ็กด้วยการตรวจจริง ไม่ทำตามทุกข้อโดยอัตโนมัติ
- รอบ review → fix ไม่เกิน 2 รอบต่องาน แล้วบันทึกผลใน `docs/agents/experiment-log.md`
