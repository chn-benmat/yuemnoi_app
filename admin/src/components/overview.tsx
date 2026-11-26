"use client";
import Link from "next/link";
import {
  Users,
  Package,
  CalendarDays,
  ShieldCheck,
  ChevronRight,
  MessageSquareWarning,
  Flag,
  ChartColumn,
  Info,
} from "lucide-react";
import type { Overview as Summary, Row } from "@/lib/catalog";
import { date, display } from "@/lib/catalog";
import { Badge, DataTable, Empty } from "./primitives";
export function BookingChart({ rows = [] }: { rows?: Row[] }) {
  const max = Math.max(1, ...rows.map((r) => Number(r.bookings) || 0));
  return (
    <div className="chart">
      {rows.length === 0 ? (
        <div className="chart-empty">
          <ChartColumn />
          <span>ยังไม่มีข้อมูลในช่วงเวลานี้</span>
        </div>
      ) : (
        <div className="bars">
          {rows.map((r, i) => (
            <div
              className="bar-column"
              key={i}
              title={date(r.day) + " · " + display(r.bookings) + " การจอง"}
            >
              <strong>{display(r.bookings)}</strong>
              <div
                className="bar"
                style={{
                  height: Math.max(4, (Number(r.bookings) / max) * 160) + "px",
                }}
              />
              <small>{date(r.day)}</small>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
export default function Overview({
  data,
  base = "",
  group = "day",
}: {
  data?: Summary;
  base?: string;
  group?: "day" | "week" | "month";
}) {
  const metrics = [
    { label: "ผู้ใช้งาน", value: data?.users, icon: Users },
    { label: "สินค้าทั้งหมด", value: data?.items, icon: Package },
    { label: "การจอง", value: data?.bookings, icon: CalendarDays },
    { label: "รอตรวจตัวตน", value: data?.pending_identity, icon: ShieldCheck },
  ];
  const tasks = [
    {
      label: "ยืนยันตัวตน",
      detail: "คำขอที่รอการพิจารณา",
      value: data?.pending_identity,
      href: "identity",
      icon: ShieldCheck,
      tone: "purple",
    },
    {
      label: "เรื่องร้องเรียน",
      detail: "เรื่องที่ยังดำเนินการไม่เสร็จ",
      value: data?.open_complaints,
      href: "complaints",
      icon: MessageSquareWarning,
      tone: "pink",
    },
    {
      label: "สินค้าที่ถูกซ่อน",
      detail: "ประกาศที่อยู่ระหว่างจัดการ",
      value: data?.hidden_items,
      href: "items",
      icon: Flag,
      tone: "orange",
    },
  ];
  return (
    <>
      <div className="metrics">
        {metrics.map((m) => (
          <section className="metric" key={m.label}>
            <div>
              <span className="icon-tile">
                <m.icon />
              </span>
              <span>{m.label}</span>
            </div>
            <strong>
              {typeof m.value === "number"
                ? m.value.toLocaleString("th-TH")
                : "—"}
            </strong>
            <m.icon className="metric-watermark" />
          </section>
        ))}
      </div>
      <p className="footnote">
        ผู้ใช้และสินค้าเป็นยอดสะสม · การจองตามช่วงเวลาที่เลือก
      </p>
      <div className="overview-grid">
        <section className="panel">
          <div className="panel-heading">
            <h2>แนวโน้มการจอง</h2>
            <span className="muted text-sm">
              {
                {
                  day: "รายวัน",
                  week: "รายสัปดาห์ · เริ่มวันจันทร์",
                  month: "รายเดือน",
                }[group]
              }
            </span>
          </div>
          <BookingChart rows={data?.series} />
        </section>
        <section className="panel">
          <div className="panel-heading">
            <h2>งานที่ต้องดูแล</h2>
          </div>
          <div className="task-list">
            {tasks.map((t) => (
              <Link href={base + "/" + t.href} className="task" key={t.label}>
                <span className={"icon-tile " + t.tone}>
                  <t.icon />
                </span>
                <div>
                  <strong>{t.label}</strong>
                  <small>{t.detail}</small>
                </div>
                <b>{display(t.value)}</b>
                <ChevronRight size={18} />
              </Link>
            ))}
          </div>
        </section>
      </div>
      <section className="panel">
        <div className="panel-heading">
          <h2>การจองล่าสุด</h2>
          <Link className="button subtle" href={base + "/bookings"}>
            ดูทั้งหมด
            <ChevronRight size={16} />
          </Link>
        </div>
        <DataTable
          rows={data?.recent ?? []}
          columns={[
            { key: "item_name", label: "รายการ" },
            { key: "display_name", label: "ผู้เช่า" },
            {
              key: "start_at",
              label: "ช่วงเวลา",
              render: (r) => (
                <>
                  {date(r.start_at)} – {date(r.end_at)}
                </>
              ),
            },
            {
              key: "total_price",
              label: "มูลค่าการจอง",
              render: (r) => (
                <>฿{Number(r.total_price ?? 0).toLocaleString("th-TH")}</>
              ),
            },
            {
              key: "status",
              label: "สถานะ",
              render: (r) => <Badge value={r.status} />,
            },
          ]}
        />
        <p className="footnote">
          <Info size={16} />
          มูลค่าการจองไม่ใช่ยอดรับชำระเงินจริง
        </p>
      </section>
      <section className="panel">
        <div className="panel-heading">
          <h2>มูลค่าการจองในช่วงเวลา</h2>
          <strong>฿{display(data?.booking_value)}</strong>
        </div>
        <p className="footnote">ยังไม่มีข้อมูลยอดรับชำระเงินจริง</p>
      </section>
      <div className="overview-grid">
        <Breakdown
          rows={data?.categories ?? []}
          title="สินค้าตามหมวดหมู่"
          value="items"
        />
        <Breakdown
          rows={data?.statuses ?? []}
          title="สถานะการจอง"
          value="bookings"
        />
      </div>
    </>
  );
}
function Breakdown({
  rows,
  title,
  value,
}: {
  rows: Row[];
  title: string;
  value: string;
}) {
  return (
    <section className="panel">
      <div className="panel-heading">
        <h2>{title}</h2>
      </div>
      {rows.length ? (
        <div className="breakdown">
          {rows.map((r, i) => (
            <div key={i}>
              <span>{display(r.category ?? r.status ?? r.day)}</span>
              <strong>{display(r[value])}</strong>
            </div>
          ))}
        </div>
      ) : (
        <Empty />
      )}
    </section>
  );
}
