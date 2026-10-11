import { test } from "node:test";
import assert from "node:assert/strict";
import { toCSV } from "../src/lib/export.ts";
test("CSV excludes identity and face evidence", () => {
  const csv = toCSV([
    {
      id: "sample",
      citizen_id: "private",
      birth_date: "private",
      raw_encrypted: "private",
      ocr_text: "private",
      analysis: { live_score: 1 },
      object_path: "private",
      legal_name: "private",
      value: 3,
    },
  ]);
  assert(!csv.includes("private"));
  assert(csv.includes("value"));
});
test("CSV neutralizes spreadsheet formulas and escapes quotes", () => {
  const csv = toCSV([
    { name: '=HYPERLINK("https://example.test")', other: "a,b" },
  ]);
  assert(csv.includes("'=HYPERLINK"));
  assert(csv.includes('""https://example.test""'));
  assert(csv.includes('"a,b"'));
});
