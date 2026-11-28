"use client";
import Link from "next/link";
import { useEffect, useState } from "react";
import {
  Home,
  ShieldCheck,
  Users,
  Package,
  CalendarDays,
  Star,
  MessageSquareWarning,
  UserRoundCog,
  Settings,
  Activity,
  History,
  Search,
  Sun,
  Moon,
  Menu,
  LogOut,
  ChevronLeft,
  ChevronRight,
  Download,
  RefreshCw,
  Printer,
  Info,
  X,
} from "lucide-react";
import {
  sections,
  display,
  date,
  type Row,
  type Overview as Summary,
} from "@/lib/catalog";
import { api, useAdminData } from "@/lib/api";
import { toCSV } from "@/lib/export";
import { groupSeries, type Group } from "@/lib/reports";
import Overview from "./overview";
import Identity from "./identity";
import { ComplaintDialog, complaintOutcomes } from "./complaint-dialog";
import {
  DataTable,
  Badge,
  ActionDialog,
  type Operation,
  type Column,
} from "./primitives";
const icons = [
  Home,
  ShieldCheck,
  Users,
  Package,
  CalendarDays,
  Star,
  MessageSquareWarning,
  UserRoundCog,
  History,
  Settings,
  Activity,
];
const dateColumn: Column = {
  key: "created_at",
  label: "วันที่",
  render: (r) => date(r.created_at),
};
function ImagePreview({ value, label }: { value: unknown; label: string }) {
  let images: string[] = [];
  if (Array.isArray(value)) {
    images = value.filter((url): url is string => typeof url === "string");
  } else if (typeof value === "string" && value.trim()) {
    const trimmed = value.trim();
    try {
      const parsed: unknown = JSON.parse(trimmed);
      images = Array.isArray(parsed)
        ? parsed.filter((url): url is string => typeof url === "string")
        : [trimmed];
    } catch {
      images = trimmed.split(",").map((url) => url.trim()).filter(Boolean);
    }
  }
  if (images.length === 0) return <span className="muted">ไม่มีรูปภาพ</span>;
  return (
    <div style={{ display: "flex", gap: 6 }}>
      {images.slice(0, 4).map((url, index) => (
        <a key={url + index} href={url} target="_blank" rel="noreferrer">
          <img
            src={url}
            alt={`${label} ${index + 1}`}
            loading="lazy"
            style={{ width: 48, height: 48, objectFit: "cover", borderRadius: 8 }}
            onError={(event) => {
              event.currentTarget.style.visibility = "hidden";
            }}
          />
        </a>
      ))}
    </div>
  );
}
const columns: Record<string, Column[]> = {
  users: [
    { key: "display_name", label: "ชื่อผู้ใช้" },
    { key: "email", label: "อีเมล" },
    {
      key: "identity_status",
      label: "ยืนยันตัวตน",
      render: (r) => <Badge value={r.identity_status} />,
    },
    {
      key: "suspended",
      label: "บัญชี",
      render: (r) => <Badge value={r.suspended ? "suspended" : "active"} />,
    },
    dateColumn,
  ],
  items: [
    { key: "item_name", label: "สินค้า" },
    { key: "owner_name", label: "เจ้าของ" },
    { key: "category", label: "หมวดหมู่" },
    { key: "description", label: "รายละเอียด" },
    {
      key: "item_image_url",
      label: "รูปภาพ",
      render: (r) => <ImagePreview value={r.item_image_url} label="รูปสินค้า" />,
    },
    { key: "hourly_rate", label: "ราคา/ชั่วโมง" },
    { key: "daily_rate", label: "ราคา/วัน" },
    {
      key: "status",
      label: "สถานะ",
      render: (r) => (
        <Badge
          value={
            r.status === "pending_review" || r.status === "rejected"
              ? r.status
              : r.moderation_hidden
                ? "ซ่อน"
                : r.status
          }
        />
      ),
    },
    dateColumn,
  ],
  bookings: [
    { key: "id", label: "เลขรายการ" },
    {
      key: "item_image_url",
      label: "รูปสินค้า",
      render: (r) => <ImagePreview value={r.item_image_url} label="รูปสินค้าเช่า" />,
    },
    { key: "item_name", label: "สินค้า" },
    { key: "display_name", label: "ผู้เช่า" },
    { key: "start_at", label: "เริ่มเช่า", render: (r) => date(r.start_at) },
    {
      key: "end_at",
      label: "ครบกำหนด",
      render: (r) => (
        <>
          {date(r.end_at)}
          {r.overdue === true && <Badge value="เลยกำหนด" />}
        </>
      ),
    },
    { key: "total_price", label: "มูลค่าการจอง" },
    {
      key: "status",
      label: "สถานะ",
      render: (r) => <Badge value={r.status} />,
    },
  ],
  reviews: [
    { key: "item_name", label: "สินค้า" },
    { key: "rating", label: "คะแนน" },
    { key: "description", label: "ความคิดเห็น" },
    { key: "moderation_hidden", label: "ซ่อน" },
    dateColumn,
  ],
  complaints: [
    { key: "item_name", label: "สินค้า" },
    { key: "description", label: "รายละเอียด" },
    {
      key: "status",
      label: "สถานะ",
      render: (r) => <Badge value={r.status} />,
    },
    {
      key: "review_outcome",
      label: "ผลตรวจสอบ",
      render: (r) => {
        const outcome = r.review_outcome as keyof typeof complaintOutcomes;
        return complaintOutcomes[outcome] ?? display(r.resolution);
      },
    },
    dateColumn,
  ],
  staff: [
    { key: "display_name", label: "ชื่อ" },
    { key: "email", label: "อีเมล" },
    { key: "user_id", label: "รหัสบัญชี" },
    { key: "active", label: "เปิดใช้งาน" },
    dateColumn,
  ],
  audit: [
    { key: "actor_id", label: "เจ้าหน้าที่" },
    { key: "action", label: "การดำเนินงาน" },
    { key: "target", label: "รายการ" },
    { key: "reason", label: "เหตุผล" },
    dateColumn,
  ],
};
function rangeQuery(days: string, from: string, to: string) {
  const q = new URLSearchParams();
  const now = new Date();
  const start =
    days === "custom" && from
      ? new Date(from + "T00:00:00+07:00")
      : new Date(
          now.valueOf() - Number(days === "custom" ? 30 : days) * 86400000,
        );
  const end =
    days === "custom" && to
      ? new Date(new Date(to + "T00:00:00+07:00").valueOf() + 86400000)
      : now;
  q.set("from", start.toISOString());
  q.set("to", end.toISOString());
  return q;
}
export default function Dashboard({
  section,
  preview = false,
}: {
  section: string;
  preview?: boolean;
}) {
  const meta = sections.find((s) => s.id === section)!;
  const isOverview = section === "overview";
  const [dark, setDark] = useState(false);
  const [mobile, setMobile] = useState(false);
  const [search, setSearch] = useState("");
  const [term, setTerm] = useState("");
  const [status, setStatus] = useState("");
  const [page, setPage] = useState(0);
  const [days, setDays] = useState("30");
  const [group, setGroup] = useState<Group>("day");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");
  const [operation, setOperation] = useState<Operation | null>(null);
  const [complaint, setComplaint] = useState<Row | null>(null);
  const [message, setMessage] = useState("");
  const [approvingItemId, setApprovingItemId] = useState<string | null>(null);
  useEffect(() => {
    const saved = localStorage.getItem("yuemnoi-theme") === "dark";
    setDark(saved);
    document.documentElement.dataset.theme = saved ? "dark" : "light";
    const q = new URLSearchParams(window.location.search).get("search");
    if (q) {
      setSearch(q);
      setTerm(q);
    }
  }, []);
  const [range, setRange] = useState(() => rangeQuery("30", "", "").toString());
  useEffect(
    () => setRange(rangeQuery(days, from, to).toString()),
    [days, from, to],
  );
  const query = new URLSearchParams(range);
  query.set("search", term);
  query.set("status", status);
  query.set("page", String(page));
  const module = section;
  const result = useAdminData<Row & Summary>(
    module + "?" + query.toString(),
    preview,
  );
  const reportData =
    isOverview && result.data
      ? {
          ...result.data,
          series: groupSeries(result.data.series ?? [], group),
          registrations: groupSeries(result.data.registrations ?? [], group),
        }
      : undefined;
  const showRangeFilter = section === "bookings" || section === "audit";
  const rows = Array.isArray(result.data?.rows)
    ? (result.data.rows as Row[])
    : [];
  const base = preview ? "/preview" : "";
  function theme() {
    setDark(!dark);
    document.documentElement.dataset.theme = dark ? "light" : "dark";
    localStorage.setItem("yuemnoi-theme", dark ? "light" : "dark");
  }
  function download() {
    const data = result.data;
    if (!data) return;
    const exportRows =
      isOverview
        ? [
            {
              report: "summary",
              from: query.get("from"),
              to: query.get("to"),
              users: data.users,
              items: data.items,
              bookings: data.bookings,
              booking_value: data.booking_value,
              payment_revenue: "ยังไม่มีข้อมูลรับชำระเงินจริง",
            },
            ...(data.series ?? []).map((r) => ({
              report: "daily_bookings",
              ...r,
            })),
            ...(data.registrations ?? []).map((r) => ({
              report: "registrations",
              ...r,
            })),
            ...(data.categories ?? []).map((r) => ({
              report: "categories",
              ...r,
            })),
            ...(data.statuses ?? []).map((r) => ({
              report: "booking_statuses",
              ...r,
            })),
          ]
        : rows;
    const url = URL.createObjectURL(
      new Blob([toCSV(exportRows)], { type: "text/csv;charset=utf-8" }),
    );
    const a = document.createElement("a");
    a.href = url;
    a.download =
      "yuemnoi-" +
      section +
      "-" +
      new Date().toISOString().slice(0, 10) +
      ".csv";
    a.click();
    URL.revokeObjectURL(url);
  }
  function action(r: Row, a: string, title: string, data: Row = {}) {
    setOperation({
      action: a,
      target: display(r.user_id ?? r.id),
      title,
      data,
    });
  }
  async function approveItem(r: Row) {
    const itemId = String(r.id ?? "");
    if (!itemId || approvingItemId) return;
    setApprovingItemId(itemId);
    setMessage("");
    try {
      await api(`actions/review-item/${encodeURIComponent(itemId)}`, {
        method: "POST",
        body: JSON.stringify({
          decision: "approved",
          reason: "อนุมัติและโพสต์ประกาศ",
        }),
      });
      setMessage("อนุมัติและโพสต์ประกาศเรียบร้อยแล้ว");
      result.reload();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "อนุมัติประกาศไม่สำเร็จ");
    } finally {
      setApprovingItemId(null);
    }
  }
  function rowActions(r: Row) {
    if (section === "users")
      return (
        <>
          <button
            disabled={preview}
            onClick={() =>
              action(
                r,
                "suspend-user",
                r.suspended ? "คืนสิทธิ์บัญชี" : "ระงับบัญชี",
                { enabled: !r.suspended },
              )
            }
          >
            {r.suspended ? "คืนสิทธิ์" : "ระงับ"}
          </button>
          {r.identity_status === "approved" && (
            <button
              disabled={preview}
              onClick={() =>
                action(r, "revoke-identity", "เพิกถอนการยืนยันตัวตน")
              }
            >
              เพิกถอน
            </button>
          )}
        </>
      );
    if (section === "items" && r.status === "pending_review")
      return (
        <>
          <button
            disabled={preview || approvingItemId !== null}
            onClick={() => void approveItem(r)}
          >
            {approvingItemId === String(r.id) ? "กำลังอนุมัติ…" : "อนุมัติและโพสต์"}
          </button>
          <button
            disabled={preview}
            onClick={() =>
              action(r, "review-item", "ปฏิเสธประกาศ", {
                decision: "rejected",
              })
            }
          >
            ปฏิเสธ
          </button>
        </>
      );
    if (section === "items" && r.status === "rejected") return null;
    if (section === "items" || section === "reviews")
      return (
        <button
          disabled={preview}
          onClick={() =>
            action(
              r,
              section === "items" ? "hide-item" : "hide-review",
              r.moderation_hidden ? "แสดงรายการอีกครั้ง" : "ซ่อนรายการ",
              { enabled: !r.moderation_hidden },
            )
          }
        >
          {r.moderation_hidden ? "แสดงอีกครั้ง" : "ซ่อน"}
        </button>
      );
    if (section === "complaints")
      return (
        <button disabled={preview} onClick={() => setComplaint(r)}>
          {r.status === "resolved" ? "ดูผลตรวจ" : "จัดการ"}
        </button>
      );
    if (section === "staff")
      return (
        <button
          disabled={preview}
          onClick={() =>
            action(
              r,
              "staff",
              r.active ? "เพิกถอนสิทธิ์เจ้าหน้าที่" : "เปิดสิทธิ์เจ้าหน้าที่",
              { enabled: !r.active },
            )
          }
        >
          {r.active ? "เพิกถอน" : "เปิดสิทธิ์"}
        </button>
      );
    return null;
  }
  return (
    <div className="app-shell">
      <a className="skip-link" href="#main">
        ข้ามไปเนื้อหา
      </a>
      {mobile && (
        <button
          className="sidebar-backdrop"
          aria-label="ปิดเมนู"
          onClick={() => setMobile(false)}
        />
      )}
      <aside className={"sidebar " + (mobile ? "open" : "")}>
        <Link className="brand" href={base + "/overview"}>
          <img src="/brand.png" alt="" />
          <span>ยืมหน่อย</span>
        </Link>
        <nav aria-label="เมนูหลัก">
          {sections.map((s, i) => {
            const Icon = icons[i];
            return (
              <Link
                key={s.id}
                href={base + "/" + s.id}
                className={s.id === section ? "active" : ""}
                aria-current={s.id === section ? "page" : undefined}
                onClick={() => setMobile(false)}
              >
                <Icon size={21} />
                <span>{s.label}</span>
              </Link>
            );
          })}
        </nav>
        <div className="sidebar-bottom">
          <div className="staff-summary">
            <span className="avatar">
              <Users size={21} />
            </span>
            <div>
              <strong>เจ้าหน้าที่</strong>
              <small>ศูนย์จัดการยืมหน่อย</small>
            </div>
          </div>
          <button
            onClick={async () => {
              if (preview) {
                window.location.assign("/login");
                return;
              }
              await fetch("/api/session", { method: "DELETE" });
              window.location.assign("/login");
            }}
          >
            <LogOut size={20} />
            ออกจากระบบ
          </button>
        </div>
      </aside>
      <div className="workspace">
        <header className="topbar">
          <button
            className="icon-button mobile-menu"
            onClick={() => setMobile(true)}
            aria-label="เปิดเมนู"
          >
            <Menu />
          </button>
          <form className="global-search" action={base + "/users"}>
            <Search size={20} />
            <input
              name="search"
              aria-label="ค้นหาผู้ใช้"
              placeholder="ค้นหาผู้ใช้ด้วยชื่อหรืออีเมล…"
            />
          </form>
          <div className="top-actions">
            <button
              className="icon-button theme-toggle"
              onClick={theme}
              aria-label={dark ? "เปลี่ยนเป็นโหมดสว่าง" : "เปลี่ยนเป็นโหมดมืด"}
            >
              {dark ? <Sun /> : <Moon />}
            </button>
            <span className="staff-chip">
              <span className="avatar">
                <Users size={18} />
              </span>
              เจ้าหน้าที่
            </span>
          </div>
        </header>
        <main id="main">
          {preview && (
            <p className="preview-banner">
              <Info size={16} />
              ตัวอย่างหน้าตา · ยังไม่เชื่อมบัญชีเจ้าหน้าที่
            </p>
          )}
          <div className="page-heading">
            <div>
              <h1>{meta.title}</h1>
              <p>{meta.description}</p>
            </div>
            <div className="heading-actions">
              {showRangeFilter && (
                <>
                  <label className="sr-only" htmlFor="range">
                    ช่วงเวลา
                  </label>
                  <select
                    id="range"
                    value={days}
                    onChange={(e) => {
                      setDays(e.target.value);
                      setPage(0);
                    }}
                  >
                    <option value="7">7 วัน</option>
                    <option value="30">30 วัน</option>
                    <option value="90">90 วัน</option>
                    <option value="custom">กำหนดเอง</option>
                  </select>
                </>
              )}
              {isOverview && (
                <button
                  className="primary"
                  disabled={preview || !result.data}
                  onClick={download}
                >
                  <Download size={18} />
                  ส่งออกรายงาน
                </button>
              )}
              <button
                className="icon-button"
                disabled={preview || result.loading}
                onClick={result.reload}
                aria-label="โหลดใหม่"
              >
                <RefreshCw size={19} className={result.loading ? "spin" : ""} />
              </button>
            </div>
          </div>
          {showRangeFilter && days === "custom" && (
            <div className="date-filter">
              <label>
                ตั้งแต่
                <input
                  type="date"
                  value={from}
                  onChange={(e) => setFrom(e.target.value)}
                />
              </label>
              <label>
                ถึง
                <input
                  type="date"
                  value={to}
                  min={from}
                  onChange={(e) => setTo(e.target.value)}
                />
              </label>
            </div>
          )}
          {message && (
            <p className="notice" role="status">
              {message}
              <button
                className="icon-button"
                onClick={() => setMessage("")}
                aria-label="ปิดข้อความ"
              >
                <X size={16} />
              </button>
            </p>
          )}
          {result.error && (
            <div className="error" role="alert">
              {result.error}
              <button onClick={result.reload}>ลองใหม่</button>
            </div>
          )}
          {result.loading && (
            <p className="muted" role="status">
              กำลังโหลดข้อมูล…
            </p>
          )}
          {isOverview && (
            <>
              <div className="report-controls">
                <select
                  aria-label="การรวมรายงาน"
                  value={group}
                  onChange={(e) => setGroup(e.target.value as Group)}
                >
                  <option value="day">รายวัน</option>
                  <option value="week">รายสัปดาห์</option>
                  <option value="month">รายเดือน</option>
                </select>
                <button
                  disabled={preview || !result.data}
                  onClick={() => window.print()}
                >
                  <Printer size={18} />
                  PDF สรุป / พิมพ์
                </button>
                <p className="muted">บันทึกเป็น PDF จากหน้าต่างพิมพ์</p>
              </div>
              <div className="print-summary">
                <h2>รายงานการใช้งานยืมหน่อย</h2>
                <p>
                  {date(query.get("from"))} – {date(query.get("to"))}
                </p>
              </div>
              <Overview data={reportData} base={base} group={group} />
            </>
          )}
          {section === "identity" && (
            <>
              <Filter
                search={search}
                setSearch={setSearch}
                submit={() => {
                  setTerm(search);
                  setPage(0);
                }}
                status={status}
                setStatus={(s) => {
                  setStatus(s);
                  setPage(0);
                }}
                options={[
                  "pending",
                  "approved",
                  "rejected",
                  "corrections",
                  "expired",
                  "capture",
                ]}
              />
              <Identity
                key={
                  module +
                  JSON.stringify(rows.map((r) => [r.id, r.status, r.reason]))
                }
                rows={rows}
                preview={preview}
                onOperation={setOperation}
              />
            </>
          )}
          {columns[section] && (
            <section className="panel">
              <div className="panel-heading">
                <h2>{meta.title}</h2>
                {section === "staff" && (
                  <button
                    disabled={preview}
                    onClick={() => {
                      setOperation({
                        action: "staff",
                        target: "",
                        targetInput: true,
                        title: "แต่งตั้งเจ้าหน้าที่",
                        data: { enabled: true },
                        detail:
                          "เจ้าหน้าที่ทุกคนมีสิทธิ์เท่ากัน ตรวจรหัสบัญชีให้ตรงกับผู้ที่ต้องการแต่งตั้ง",
                      });
                    }}
                  >
                    <UserRoundCog size={18} />
                    เพิ่มเจ้าหน้าที่
                  </button>
                )}
                {!["staff", "audit"].includes(section) && (
                  <button disabled={preview || !rows.length} onClick={download}>
                    CSV หน้านี้
                  </button>
                )}
              </div>
              <Filter
                search={search}
                setSearch={setSearch}
                submit={() => {
                  setTerm(search);
                  setPage(0);
                }}
                status={status}
                setStatus={(s) => {
                  setStatus(s);
                  setPage(0);
                }}
                options={
                  section === "users"
                    ? ["approved", "unverified", "suspended"]
                    : section === "complaints"
                      ? ["open", "in_progress", "resolved"]
                      : section === "bookings"
                        ? [
                            "pending",
                            "confirmed",
                            "active",
                            "completed",
                            "cancelled",
                            "awaiting_return",
                          ]
                        : section === "items"
                          ? ["pending_review", "available", "rejected", "hidden"]
                          : []
                }
              />
              <DataTable
                rows={rows}
                columns={columns[section]}
                actions={
                  ["users", "items", "reviews", "complaints", "staff"].includes(
                    section,
                  )
                    ? rowActions
                    : undefined
                }
              />
            </section>
          )}
          {section === "settings" && (
            <section className="panel settings-panel">
              <span className="icon-tile">
                <ShieldCheck />
              </span>
              <h2>ข้อกำหนดยืนยันตัวตน</h2>
              <p className="muted">
                ทั้งผู้ลงประกาศ ผู้ส่งคำขอเช่า และเจ้าของที่รับการจองใหม่
                ต้องผ่านการตรวจบัตรและบันทึกเบอร์โทรเสมอ ข้อกำหนดนี้ปิดไม่ได้
              </p>
              <p>
                สถานะ: <Badge value="บังคับเสมอ" />
              </p>
              <hr />
              <h3>นโยบายหลักฐาน</h3>
              <p className="muted">
                คำขอค้างหมดอายุใน 7 วัน รูปคู่บัตรและหลักฐานอื่นหมดอายุ 7 วันหลังผลพิจารณา
                รูปหน้าบัตรล่าสุดที่อนุมัติภายใต้เงื่อนไขการเก็บรักษาฉบับใหม่
                เก็บกับบัญชีจนกว่าจะมีรูปที่อนุมัติมาแทนหรือมีการลบบัญชี
              </p>
              <p className="muted">
                ผลอนุมัติไม่ผูกกับวันหมดอายุบัตร และรองรับผู้ใช้ทุกวัย
              </p>
            </section>
          )}
          {section === "health" && (
            <div className="metrics">
              {["backend", "database", "cleanup"].map((k) => (
                <section className="panel" key={k}>
                  <span className="icon-tile">
                    <Activity />
                  </span>
                  <h2>
                    {
                      {
                        backend: "Backend",
                        database: "ฐานข้อมูล",
                        cleanup: "งานลบหลักฐาน",
                      }[k]
                    }
                  </h2>
                  <p>
                    <Badge value={result.data?.[k] ?? "ยังไม่ได้ตรวจสอบ"} />
                  </p>
                </section>
              ))}
            </div>
          )}
          {columns[section] || section === "identity" ? (
            <div className="pagination">
              <button
                disabled={page === 0 || result.loading}
                onClick={() => setPage((p) => p - 1)}
              >
                <ChevronLeft size={18} />
                ก่อนหน้า
              </button>
              <span>หน้า {page + 1} · สูงสุด 50 รายการต่อหน้า</span>
              <button
                disabled={rows.length < 50 || result.loading}
                onClick={() => setPage((p) => p + 1)}
              >
                ถัดไป
                <ChevronRight size={18} />
              </button>
            </div>
          ) : null}
        </main>
        <footer>
          ยืมหน่อย · ศูนย์จัดการแอป<span>เวลารายงาน Asia/Bangkok</span>
        </footer>
      </div>
      <ActionDialog
        operation={operation}
        onClose={() => setOperation(null)}
        onSuccess={() => {
          result.reload();
          setMessage("บันทึกการดำเนินงานเรียบร้อยแล้ว");
        }}
      />
      {complaint && (
        <ComplaintDialog
          row={complaint}
          onClose={() => setComplaint(null)}
          onSaved={(text) => {
            setComplaint(null);
            setMessage(text);
            result.reload();
          }}
        />
      )}
    </div>
  );
}
function Filter({
  search,
  setSearch,
  submit,
  status,
  setStatus,
  options,
}: {
  search: string;
  setSearch: (v: string) => void;
  submit: () => void;
  status: string;
  setStatus: (v: string) => void;
  options: string[];
}) {
  return (
    <form
      className="filters"
      onSubmit={(e) => {
        e.preventDefault();
        submit();
      }}
    >
      <div className="filter-search">
        <Search size={18} />
        <input
          aria-label="ค้นหารายการ"
          placeholder="ค้นหารายการ…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <button type="submit">ค้นหา</button>
      </div>
      {options.length > 0 && (
        <select
          aria-label="สถานะ"
          value={status}
          onChange={(e) => setStatus(e.target.value)}
        >
          <option value="">ทุกสถานะ</option>
          {options.map((s) => (
            <option value={s} key={s}>
              {(
                {
                  pending: "รอพิจารณา",
                  approved: "อนุมัติแล้ว",
                  rejected: "ปฏิเสธ",
                  corrections: "ขอข้อมูลเพิ่ม",
                  expired: "หมดอายุ",
                  unverified: "ยังไม่ยืนยัน",
                  suspended: "ระงับ",
                  open: "เปิดเรื่อง",
                  in_progress: "กำลังดำเนินการ",
                  resolved: "ปิดเรื่อง",
                  available: "พร้อมให้เช่า",
                  pending_review: "รอตรวจสอบประกาศ",
                  hidden: "ซ่อน",
                  confirmed: "ยืนยันแล้ว",
                  active: "กำลังเช่า",
                  completed: "เสร็จสิ้น",
                  cancelled: "ยกเลิก",
                  awaiting_return: "รอส่งคืน",
                  capture: "รอส่งหลักฐาน",
                } as Record<string, string>
              )[s] ?? s}
            </option>
          ))}
        </select>
      )}
    </form>
  );
}
