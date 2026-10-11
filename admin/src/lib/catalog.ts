export const sections = [
  {
    id: "overview",
    label: "ภาพรวม",
    title: "ภาพรวมแอป",
    description: "ติดตามการใช้งานและงานที่ต้องดูแล",
  },
  {
    id: "identity",
    label: "ยืนยันตัวตน",
    title: "ยืนยันตัวตน",
    description: "ตรวจหลักฐานและพิจารณาคำขอ",
  },
  {
    id: "users",
    label: "ผู้ใช้",
    title: "ผู้ใช้งาน",
    description: "ดูแลบัญชีและสถานะการยืนยันตัวตน",
  },
  {
    id: "items",
    label: "สินค้า",
    title: "สินค้า",
    description: "ดูแลประกาศและสินค้าที่ผิดกฎ",
  },
  {
    id: "bookings",
    label: "การเช่า",
    title: "การเช่า",
    description: "ติดตามคำขอเช่าและการส่งคืน",
  },
  {
    id: "reviews",
    label: "รีวิว",
    title: "รีวิว",
    description: "ติดตามความคิดเห็นและคุณภาพการใช้งาน",
  },
  {
    id: "complaints",
    label: "ร้องเรียน",
    title: "เรื่องร้องเรียน",
    description: "รับเรื่อง ติดตาม และบันทึกผลการดำเนินงาน",
  },
  {
    id: "reports",
    label: "รายงาน",
    title: "รายงาน",
    description: "สำรวจข้อมูลและส่งออกรายงาน",
  },
  {
    id: "staff",
    label: "เจ้าหน้าที่",
    title: "เจ้าหน้าที่",
    description: "ทุกบัญชีเจ้าหน้าที่ใช้สิทธิ์ระดับเดียวกัน",
  },
  {
    id: "audit",
    label: "ประวัติการทำงาน",
    title: "ประวัติการทำงาน",
    description: "ตรวจสอบการเข้าถึงหลักฐานและการดำเนินงาน",
  },
  {
    id: "settings",
    label: "ตั้งค่า",
    title: "ตั้งค่า",
    description: "จัดการการเปิดใช้งานระบบยืนยันตัวตน",
  },
  {
    id: "health",
    label: "สถานะระบบ",
    title: "สถานะระบบ",
    description: "ตรวจสอบความพร้อมของบริการ",
  },
] as const;
export type Row = Record<string, unknown>;
export type Overview = {
  users?: number;
  items?: number;
  bookings?: number;
  pending_identity?: number;
  open_complaints?: number;
  hidden_items?: number;
  booking_value?: number;
  series?: Row[];
  registrations?: Row[];
  categories?: Row[];
  statuses?: Row[];
  recent?: Row[];
};
export const statusNames: Record<string, string> = {
  approved: "อนุมัติแล้ว",
  unverified: "ยังไม่ยืนยัน",
  revoked: "เพิกถอน",
  pending: "รอพิจารณา",
  capture: "รอส่งหลักฐาน",
  rejected: "ปฏิเสธ",
  corrections: "ขอข้อมูลเพิ่ม",
  expired: "หมดอายุ",
  available: "พร้อมให้เช่า",
  confirmed: "ยืนยันแล้ว",
  active: "กำลังเช่า",
  completed: "เสร็จสิ้น",
  finished: "เสร็จสิ้น",
  cancelled: "ยกเลิก",
  awaiting_return: "รอส่งคืน",
  open: "เปิดเรื่อง",
  in_progress: "กำลังดำเนินการ",
  resolved: "ปิดเรื่อง",
  suspended: "ระงับบัญชี",
};
export function display(value: unknown): string {
  if (value === null || value === undefined || value === "") return "—";
  if (typeof value === "boolean") return value ? "ใช่" : "ไม่";
  return String(value);
}
export function date(value: unknown) {
  if (!value) return "—";
  const d = new Date(String(value));
  return Number.isNaN(d.valueOf())
    ? String(value)
    : d.toLocaleDateString("th-TH", {
        day: "numeric",
        month: "short",
        year: "numeric",
        timeZone: "Asia/Bangkok",
      });
}
