# แนวทางสำหรับ agent: admin

ใช้กับทุกไฟล์ภายใต้ `admin/` รันคำสั่งจากโฟลเดอร์นี้ อ่าน `README.md` และ `../backend/README.md` เมื่อแก้การตั้งค่า สิทธิ์เจ้าหน้าที่ หรือการยืนยันตัวตน ตรวจเวอร์ชันและ scripts จาก `package.json`

## โครงสร้างและ UI

- ใช้ Next.js App Router: `src/app/` เป็น routes/route handlers, `src/components/` เป็น UI และ `src/lib/` เป็น API helpers, catalog และ export utilities
- รักษา Server/Client Component boundary; เพิ่ม client component เฉพาะส่วนที่ต้องใช้ state, events หรือ browser API
- ใช้ components ใน `src/components/primitives.tsx`, styles ใน `src/app/globals.css` และ Prompt font เดิม ปรับดีไซน์เมื่ออยู่ในขอบเขตคำขอ
- เพิ่ม section ผ่าน `src/lib/catalog.ts` พร้อมตรวจ route, UI และ endpoint ที่เกี่ยวข้อง
- คอมเมนต์ที่เพิ่มหรือแก้ให้ใช้ภาษาไทยที่อธิบายเหตุผลหรือข้อจำกัด

## Backend และข้อมูลส่วนตัว

- Browser เรียก `/api/ops/*` ผ่าน `src/lib/api.ts`; server proxy ติดต่อ Go `/api/admin/*` ผ่าน `src/lib/server.ts` ซึ่งต้องคง `server-only`
- เก็บ `BACKEND_URL`, `BACKEND_APP_SECRET` และ staff token ฝั่ง server; รักษา HttpOnly session cookie, same-origin validation และการตรวจสิทธิ์จาก Go
- เมื่อเพิ่ม module/action ให้ปรับ proxy allowlists ใน `src/app/api/ops/[...path]/route.ts` คู่กับ route และ authorization ฝั่ง Go
- รักษา `private, no-store` สำหรับข้อมูลเจ้าหน้าที่และหลักฐาน ส่ง evidence ผ่าน proxy ที่ตรวจสิทธิ์; browser ต้องไม่อ่าน Supabase หรือเก็บ service-role key โดยตรง
- Export CSV ผ่าน `src/lib/export.ts` เพื่อคงการตัดข้อมูลตัวตน/หลักฐานและการป้องกัน spreadsheet formula injection
- Preview ใช้ได้เมื่อเป็น development และ `ADMIN_PREVIEW=true` เท่านั้น รักษาข้อมูลตัวอย่างและการปิด action จริงใน preview
- การตรวจตัวตนเป็น manual review สำหรับทุกวัย การอนุมัติต้องยืนยันหลักฐาน โดยไม่บังคับเหตุผลหรืออายุบัตร; การปฏิเสธ/ขอข้อมูลเพิ่มและคำสั่งอื่นยังต้องระบุเหตุผลตาม backend contract

## ตรวจงาน

```powershell
npm ci
npm run dev -- --port 3000
```

เมื่อแก้ TypeScript/React ให้ตรวจ:

```powershell
npm run check
npm run build
```

- วาง tests ใน `tests/` แยกตามส่วนของ `src/` ตาม `tests/README.md`; `npm test` รองรับโฟลเดอร์ย่อยแล้ว แต่ยังไม่มี test cases ให้รายงานว่าขาดชุดทดสอบแทนการอ้างว่าผ่าน
- เมื่อต้องแก้ UI ให้ตรวจหน้าที่เกี่ยวข้องใน browser รวม loading/error/empty states; ใช้ preview สำหรับตรวจหน้าตาโดยไม่มีข้อมูลจริง
- ตัวอย่าง env และภาพใน `design/` ที่ README อ้างยังไม่มีใน checkout นี้ ให้ตรวจไฟล์ที่มีจริงก่อนใช้อ้างอิง

<!-- BEGIN:nextjs-agent-rules -->

## This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->
