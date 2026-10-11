import { test, mock } from "node:test";
import assert from "node:assert/strict";
import { registerHooks } from "node:module";

const backendModule =
  "data:text/javascript," +
  encodeURIComponent(`
  let failure;
  export function failWith(error){failure=error}
  export function backend(){throw failure}
  export function sameOrigin(){return true}
  export function requestOrigin(){return 'https://admin.example.com'}
  export const sessionCookie='yuemnoi_staff';
`);
const cookiesModule =
  "data:text/javascript," +
  encodeURIComponent(
    'export function cookies(){throw new Error("unexpected_cookie_access")}',
  );
const hooks = registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier === "@/lib/server")
      return { url: backendModule, shortCircuit: true };
    if (specifier === "next/headers")
      return { url: cookiesModule, shortCircuit: true };
    if (specifier === "@/lib/session-diagnostics")
      return {
        url: new URL("../src/lib/session-diagnostics.ts", import.meta.url).href,
        shortCircuit: true,
      };
    return nextResolve(specifier, context);
  },
});
const { failWith } = await import(backendModule);
const { POST } = await import("../src/app/api/session/route.ts");
hooks.deregister();

test("real login handler records a safe failure stage and preserves the public 503 response", async () => {
  const sensitive = "private-email-password-token";
  failWith(
    new TypeError(sensitive, {
      cause: Object.assign(new Error(sensitive), { code: "ENOTFOUND" }),
    }),
  );
  const logs: unknown[][] = [];
  const logger = mock.method(console, "error", (...args: unknown[]) => {
    logs.push(args);
  });
  try {
    const response = await POST(
      new Request("https://admin.example.com/api/session", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: sensitive, password: sensitive }),
      }),
    );
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), {
      error: "ระบบเข้าสู่ระบบยังไม่พร้อม กรุณาลองใหม่",
    });
    assert.deepEqual(logs, [
      [
        "admin_session_failed",
        {
          stage: "backend_login",
          reason: "backend_request_failed",
          codes: ["ENOTFOUND"],
        },
      ],
    ]);
    assert.equal(JSON.stringify(logs).includes(sensitive), false);
  } finally {
    logger.mock.restore();
  }
});
