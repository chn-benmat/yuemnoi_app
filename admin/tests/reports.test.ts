import { test } from "node:test";
import assert from "node:assert/strict";
import { groupSeries } from "../src/lib/reports.ts";
test("report weeks start Monday and preserve totals", () => {
  const rows = [
    { day: "2026-10-04", bookings: 2 },
    { day: "2026-10-05", bookings: 3 },
    { day: "2026-10-06", bookings: 4 },
  ];
  assert.deepEqual(
    groupSeries(rows, "week").map((r) => [r.day, r.bookings]),
    [
      ["2026-09-28", 2],
      ["2026-10-05", 7],
    ],
  );
  assert.equal(groupSeries(rows, "month")[0].bookings, 9);
});
