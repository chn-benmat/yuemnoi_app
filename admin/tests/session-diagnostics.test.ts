import { test } from "node:test";
import assert from "node:assert/strict";
import { sessionFailure } from "../src/lib/session-diagnostics.ts";

test("identifies missing backend configuration separately from network failures", () => {
  assert.deepEqual(
    sessionFailure(new Error("backend_unconfigured"), "backend_login"),
    {
      stage: "backend_login",
      reason: "backend_unconfigured",
      codes: [],
    },
  );
  const failure = new TypeError("fetch failed", {
    cause: Object.assign(new Error("private host"), { code: "ENOTFOUND" }),
  });
  assert.deepEqual(sessionFailure(failure, "backend_login"), {
    stage: "backend_login",
    reason: "backend_request_failed",
    codes: ["ENOTFOUND"],
  });
});

test("retains socket error codes inside Node aggregate connection failures", () => {
  const failure = new TypeError("fetch failed", {
    cause: new AggregateError([
      Object.assign(new Error("private address"), { code: "ENETUNREACH" }),
      Object.assign(new Error("private address"), { code: "ETIMEDOUT" }),
    ]),
  });
  assert.deepEqual(sessionFailure(failure, "backend_staff").codes, [
    "ENETUNREACH",
    "ETIMEDOUT",
  ]);
});

test("never serializes arbitrary error messages, headers, credentials or codes", () => {
  const sensitive = "password-token-personal-email";
  const failure = Object.assign(new Error(sensitive), {
    code: sensitive,
    headers: { Authorization: sensitive },
    cause: new Error(sensitive),
  });
  assert.equal(
    JSON.stringify(sessionFailure(failure, "session_cookie")).includes(
      sensitive,
    ),
    false,
  );
  assert.deepEqual(sessionFailure(sensitive, "request"), {
    stage: "request",
    reason: "backend_request_failed",
    codes: [],
  });
});
