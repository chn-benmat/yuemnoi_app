"use client";
import { useState } from "react";
import { FileSearch, ShieldCheck, LockKeyhole } from "lucide-react";
import { useAdminData } from "@/lib/api";
import { date, display, type Row } from "@/lib/catalog";
import { Badge, Empty, type Operation } from "./primitives";
type Detail = {
  request?: Row;
  evidence?: { id: string; kind: string; deleted: boolean }[];
  sensitive?: Row;
};
export default function Identity({
  rows,
  preview,
  onOperation,
}: {
  rows: Row[];
  preview: boolean;
  onOperation: (op: Operation) => void;
}) {
  const [selected, setSelected] = useState("");
  const result = useAdminData<Detail>(
    "identity-detail?id=" + selected,
    preview || !selected,
  );
  const r = result.data?.request;
  return (
    <div className="review-grid">
      <section className="panel queue">
        <div className="panel-heading">
          <h2>รายการคำขอ</h2>
          <span className="muted text-sm">ล่าสุดก่อน</span>
        </div>
        {rows.length ? (
          rows.map((row) => (
            <button
              key={String(row.id)}
              className={"queue-row " + (selected === row.id ? "selected" : "")}
              onClick={() => setSelected(String(row.id))}
            >
              <div>
                <strong>
                  {display(row.display_name ?? row.id)}
                </strong>
                <Badge value={row.status} />
              </div>
              <small>
                {date(row.created_at)} ·{" "}
                {display(row.masked_id)}
              </small>
            </button>
          ))
        ) : (
          <Empty
            title="ยังไม่มีคำขอ"
            detail="เมื่อมีผู้ส่งคำขอ รายการจะแสดงที่นี่"
          />
        )}
      </section>
      <section className="panel review-detail">
        {!selected ? (
          <div className="selection-empty">
            <FileSearch />
            <h2>เลือกคำขอเพื่อเริ่มตรวจสอบ</h2>
            <p className="muted">
              เลือกรายการจากฝั่งซ้ายเพื่อดูข้อมูลและหลักฐาน
            </p>
          </div>
        ) : result.loading ? (
          <p className="muted">กำลังโหลดหลักฐาน…</p>
        ) : result.error ? (
          <p className="error">{result.error}</p>
        ) : !r ? (
          <Empty title="ไม่พบคำขอ" />
        ) : (
          <>
            <div className="panel-heading">
              <h2>ตรวจคำขอยืนยันตัวตน</h2>
              <Badge value={r.status} />
            </div>
            <p className="notice">
              <ShieldCheck size={18} />
              ตรวจข้อมูลที่ผู้ใช้กรอก เทียบภาพบัตรและใบหน้าด้วยตนเองก่อนตัดสินใจ
            </p>
            <dl className="details">
              {Object.entries({
                ชื่อบนบัตร: r.legal_name,
                เลขบัตร: r.masked_id,
              }).map(([k, v]) => (
                <div key={k}>
                  <dt>{k}</dt>
                  <dd>{display(v)}</dd>
                </div>
              ))}
            </dl>
            <div className="evidence-grid">
              {result.data?.evidence?.map((e) => (
                <div key={e.id}>
                  <h3>
                    {e.kind === "card"
                      ? "ภาพบัตรประชาชน"
                      : e.kind === "selfie"
                        ? "ภาพใบหน้า"
                        : "หลักฐานยืนยันตัวตน"}
                  </h3>
                  {e.deleted ? (
                    <div className="evidence-expired">
                      <LockKeyhole />
                      หลักฐานถูกลบตามกำหนดแล้ว
                    </div>
                  ) : (
                    <a
                      href={"/api/ops/evidence/" + e.id}
                      target="_blank"
                      rel="noreferrer"
                    >
                      <img
                        src={"/api/ops/evidence/" + e.id}
                        alt={
                          e.kind === "card"
                            ? "ภาพบัตร"
                            : e.kind === "selfie"
                              ? "ภาพใบหน้า"
                              : "หลักฐานยืนยันตัวตน"
                        }
                      />
                    </a>
                  )}
                </div>
              ))}
            </div>
            {result.data?.sensitive && (
              <details>
                <summary>ข้อมูลที่ผู้ใช้กรอก</summary>
                <p className="muted">
                  ตรวจเทียบกับภาพต้นฉบับ ข้อมูลส่วนนี้จะถูกลบตามกำหนด
                </p>
                <dl className="details">
                  {Object.entries(result.data.sensitive)
                    .filter(([k]) => k !== "ocr_text")
                    .map(([k, v]) => (
                      <div key={k}>
                        <dt>
                          {{
                            name_prefix: "คำนำหน้าชื่อ",
                            first_name: "ชื่อ",
                            last_name: "นามสกุล",
                            address_detail:
                              "รายละเอียดที่อยู่ตามบัตรประชาชน",
                            postal_code: "รหัสไปรษณีย์",
                            province: "จังหวัด",
                            district: "อำเภอ/เขต",
                            subdistrict: "ตำบล/แขวง",
                            citizen_id: "เลขบัตรที่กรอก",
                            birth_date: "วันเกิดที่กรอก",
                          }[k] ?? k}
                        </dt>
                        <dd className="pre-wrap">{display(v)}</dd>
                      </div>
                    ))}
                </dl>
              </details>
            )}
            {r.reason && <p className="notice">{display(r.reason)}</p>}
            {r.status === "pending" && (
              <div className="review-actions">
                {["corrections", "rejected", "approved"].map((decision) => (
                  <button
                    key={decision}
                    className={
                      decision === "approved"
                        ? "primary"
                        : decision === "rejected"
                          ? "danger-button"
                          : ""
                    }
                    disabled={preview}
                    onClick={() =>
                      onOperation({
                        action: "identity-review",
                        target: String(r.id),
                        title:
                          decision === "approved"
                            ? "อนุมัติคำขอ"
                            : decision === "rejected"
                              ? "ปฏิเสธคำขอ"
                              : "ขอข้อมูลเพิ่ม",
                        review: true,
                        data: { decision },
                        detail:
                          "ตรวจชื่อ ข้อมูลบัตร และเทียบรูปใบหน้ากับรูปบนบัตรด้วยตนเองก่อนบันทึก",
                      })
                    }
                  >
                    {decision === "approved"
                      ? "อนุมัติ"
                      : decision === "rejected"
                        ? "ปฏิเสธ"
                        : "ขอข้อมูลเพิ่ม"}
                  </button>
                ))}
              </div>
            )}
          </>
        )}
      </section>
    </div>
  );
}
