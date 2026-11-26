"use client";

import { useEffect, useRef, useState, type FormEvent } from "react";
import { X } from "lucide-react";
import { api, useAdminData } from "@/lib/api";
import { date, display, type Row } from "@/lib/catalog";
import { Badge } from "./primitives";

export const complaintOutcomes = {
  confirmed: "ยืนยันว่าเป็นจริง",
  dismissed: "ไม่พบมูล",
  duplicate: "ซ้ำกับเหตุการณ์เดิม",
};

type Outcome = keyof typeof complaintOutcomes;
type ComplaintContext = {
  can_confirm: boolean;
  item_hidden: boolean;
  strike_count: number;
  incidents: {
    id: string;
    strike_number: number;
    confirmed_at: string;
    summary: string | null;
  }[];
};
type SavedComplaint = { strike_count?: number; item_hidden?: boolean };

export function ComplaintDialog({
  row,
  onClose,
  onSaved,
}: {
  row: Row;
  onClose: () => void;
  onSaved: (message: string) => void;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const [outcome, setOutcome] = useState<Outcome>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const id = encodeURIComponent(String(row.id));
  const closed = row.status === "resolved";
  const context = useAdminData<ComplaintContext>("complaints?id=" + id, closed);
  const data = Array.isArray(context.data?.incidents)
    ? context.data
    : undefined;
  const confirmed = outcome === "confirmed";
  const duplicate = outcome === "duplicate";
  const strikeCount = data?.strike_count ?? 0;
  const canSubmit = outcome && data && (!confirmed || data.can_confirm);

  useEffect(() => {
    const dialog = ref.current;
    dialog?.showModal();
    return () => dialog?.close();
  }, []);

  async function save(
    status: "in_progress" | "open" | "resolved",
    fields: Row = {},
  ) {
    if (busy) return;
    setBusy(true);
    setError("");
    try {
      const result = await api<SavedComplaint>("actions/complaint/" + id, {
        method: "POST",
        body: JSON.stringify({ status, ...fields }),
      });
      if (status === "in_progress") onSaved("รับเรื่องไว้ตรวจสอบแล้ว");
      else if (status === "open") onSaved("เปิดเรื่องอีกครั้งแล้ว");
      else if (fields.outcome === "confirmed" && result.strike_count) {
        onSaved(
          result.strike_count >= 3
            ? "ปิดเรื่องและนำประกาศออกแล้ว ระบบจะแจ้งเจ้าของประกาศ"
            : `ปิดเรื่องแล้ว ระบบจะแจ้งเตือนเจ้าของประกาศ (${result.strike_count}/3 ครั้ง)`,
        );
      } else onSaved("บันทึกผลและปิดเรื่องแล้ว");
    } catch (e) {
      setError(e instanceof Error ? e.message : "ไม่สามารถบันทึกได้");
    } finally {
      setBusy(false);
    }
  }

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (closed || !canSubmit) return;
    const form = new FormData(event.currentTarget);
    if (duplicate) {
      void save("resolved", { outcome, incident_id: form.get("incident_id") });
      return;
    }
    const reason = String(form.get("reason") ?? "").trim();
    if (reason.length < 3) {
      setError("กรุณากรอกข้อความอย่างน้อย 3 ตัวอักษร");
      return;
    }
    void save("resolved", { outcome, reason });
  }

  return (
    <dialog
      className="complaint-dialog"
      ref={ref}
      aria-labelledby="complaint-dialog-title"
      onCancel={(event) => {
        event.preventDefault();
        if (!busy) onClose();
      }}
    >
      <form onSubmit={submit}>
        <div className="dialog-heading">
          <h2 id="complaint-dialog-title">
            {closed ? "ผลเรื่องร้องเรียน" : "จัดการเรื่องร้องเรียน"}
          </h2>
          <button
            type="button"
            className="icon-button"
            aria-label="ปิด"
            disabled={busy}
            onClick={onClose}
          >
            <X size={20} />
          </button>
        </div>
        <div className="complaint-details">
          <div>
            <strong>{display(row.item_name)}</strong>
            <Badge value={row.status} />
          </div>
          <p>{display(row.description)}</p>
          {data?.can_confirm && (
            <small>
              ยืนยันแล้ว {strikeCount} ครั้ง
              {data.item_hidden ? " · ประกาศถูกซ่อน" : ""}
            </small>
          )}
        </div>
        {Boolean(row.resolution) && (
          <p className="complaint-summary">
            <strong>ผลที่บันทึกไว้</strong>
            <br />
            {display(row.resolution)}
          </p>
        )}
        {!closed && (
          <>
            {context.loading && (
              <p role="status" className="muted">
                กำลังโหลดยอดยืนยัน…
              </p>
            )}
            {!context.loading && !data && (
              <p className="error" role="alert">
                {context.error || "ข้อมูลการตรวจสอบยังไม่พร้อม"}{" "}
                <button type="button" onClick={context.reload}>
                  ลองใหม่
                </button>
              </p>
            )}
            <fieldset className="complaint-outcomes" disabled={busy || !data}>
              <legend>ผลตรวจสอบ</legend>
              {(Object.keys(complaintOutcomes) as Outcome[]).map((value) => (
                <label key={value}>
                  <input
                    type="radio"
                    name="outcome"
                    value={value}
                    checked={outcome === value}
                    disabled={
                      (value === "confirmed" && !data?.can_confirm) ||
                      (value === "duplicate" && !data?.incidents.length)
                    }
                    onChange={() => setOutcome(value)}
                  />
                  {complaintOutcomes[value]}
                </label>
              ))}
            </fieldset>
            {duplicate && (
              <label className="complaint-field">
                เหตุการณ์เดิม
                <select
                  name="incident_id"
                  defaultValue=""
                  required
                  disabled={busy}
                >
                  <option value="" disabled>
                    เลือกเหตุการณ์ที่แจ้งซ้ำ
                  </option>
                  {data?.incidents.map((incident) => (
                    <option key={incident.id} value={incident.id}>
                      ครั้งที่ {incident.strike_number} ·{" "}
                      {date(incident.confirmed_at)}
                      {incident.summary && ` · ${incident.summary}`}
                    </option>
                  ))}
                </select>
              </label>
            )}
            {outcome && !duplicate && (
              <label className="complaint-field" key={outcome}>
                {confirmed ? "ข้อความถึงเจ้าของ" : "สรุปผลตรวจสอบ"}
                <textarea
                  name="reason"
                  rows={3}
                  required
                  minLength={3}
                  maxLength={confirmed ? 150 : 500}
                  disabled={busy}
                  placeholder={
                    confirmed
                      ? "ระบุปัญหาและสิ่งที่ต้องแก้ โดยเว้นข้อมูลผู้ร้องเรียน"
                      : "ระบุสิ่งที่ตรวจสอบและข้อสรุป"
                  }
                  aria-describedby={confirmed ? "complaint-notice" : undefined}
                />
              </label>
            )}
            {confirmed && (
              <p
                id="complaint-notice"
                className={strikeCount >= 2 ? "complaint-warning" : "muted"}
              >
                {strikeCount >= 3
                  ? "ประกาศถูกนำออกแล้ว ระบบจะแจ้งผลตรวจครั้งนี้ให้เจ้าของทราบ"
                  : strikeCount === 2
                    ? "ครั้งนี้จะครบ 3 ครั้ง ระบบจะนำประกาศออก หยุดรับจองใหม่ และแจ้งเจ้าของ"
                    : `ระบบจะแจ้งเจ้าของและนับเป็นครั้งที่ ${strikeCount + 1} จาก 3 ครั้ง`}
              </p>
            )}
          </>
        )}
        {error && (
          <p className="error" role="alert">
            {error}
          </p>
        )}
        <div className="dialog-actions complaint-actions">
          {closed && row.review_outcome !== "confirmed" && (
            <button
              type="button"
              onClick={() => void save("open")}
              disabled={busy}
            >
              เปิดเรื่องอีกครั้ง
            </button>
          )}
          {!closed && row.status === "open" && (
            <button
              type="button"
              onClick={() => void save("in_progress")}
              disabled={busy}
            >
              รับเรื่องไว้ตรวจสอบ
            </button>
          )}
          {!closed && (
            <button className="primary" disabled={busy || !canSubmit}>
              {busy ? "กำลังบันทึก…" : "บันทึกและปิดเรื่อง"}
            </button>
          )}
        </div>
      </form>
    </dialog>
  );
}
