# ยืมหน่อย · ศูนย์เจ้าหน้าที่

Next.js 16.4, TypeScript 7, Tailwind CSS 4.3.3 และ Prompt font ใช้ Go API เป็นขอบเขตสิทธิ์ ข้อมูลตัวตนไม่เข้าถึง Supabase ตรงจาก browser

อ่านการเปิดยืนยันตัวตนทุกบัญชี การตั้งค่า และข้อจำกัดใน [คู่มือเปิดใช้งาน](../docs/IDENTITY_PUBLIC_ROLLOUT.md)

```powershell
npm ci
# เตรียม .env.local ตาม .env.example
npm run dev -- --port 3000
```

`npm run check`, `npm test`, `npm run build` ใช้ตรวจ TypeScript, export privacy และ production build ตามลำดับ Preview เปิดเฉพาะ dev และไม่มีข้อมูลจริงหรือปุ่มทำรายการ

ภาพออกแบบก่อนสร้างอยู่ใน `design/overview.png` และ `design/identity.png` ใช้โครงร่าง สี และสัดส่วนจากภาพ พร้อมโลโก้จริงของแอป
