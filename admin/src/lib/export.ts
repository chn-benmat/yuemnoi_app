// ป้องกัน spreadsheet formula injection และไม่ให้ export หลักฐานหรือข้อมูลเลขบัตร
const forbidden = new Set([
  "citizen_id",
  "birth_date",
  "ocr_text",
  "raw_encrypted",
  "citizen_hmac",
  "analysis",
  "evidence",
  "object_path",
  "legal_name",
  "masked_id",
]);
export function csvCell(value: unknown) {
  let s = value == null ? "" : String(value);
  if (/^[\s]*[=+\-@]/.test(s)) s = "'" + s;
  return '"' + s.replaceAll('"', '""') + '"';
}
export function toCSV(rows: Record<string, unknown>[]) {
  const keys = [...new Set(rows.flatMap(Object.keys))].filter(
    (k) => !forbidden.has(k),
  );
  return (
    "\ufeff" +
    [
      keys.map(csvCell).join(","),
      ...rows.map((row) => keys.map((k) => csvCell(row[k])).join(",")),
    ].join("\r\n")
  );
}
