export type SessionStage =
  | "request"
  | "backend_login"
  | "backend_staff"
  | "session_cookie";

const reasons = new Set([
  "backend_unconfigured",
  "invalid_response",
  "expired_token",
]);
const networkCodes = new Set([
  "ENOTFOUND",
  "EAI_AGAIN",
  "ECONNREFUSED",
  "ECONNRESET",
  "ENETUNREACH",
  "EHOSTUNREACH",
  "ETIMEDOUT",
  "UND_ERR_CONNECT_TIMEOUT",
  "UND_ERR_SOCKET",
  "ERR_INVALID_CHAR",
  "ERR_INVALID_URL",
  "ERR_SSL_WRONG_VERSION_NUMBER",
  "CERT_HAS_EXPIRED",
  "UNABLE_TO_VERIFY_LEAF_SIGNATURE",
  "UNABLE_TO_GET_ISSUER_CERT_LOCALLY",
  "DEPTH_ZERO_SELF_SIGNED_CERT",
  "ERR_TLS_CERT_ALTNAME_INVALID",
]);

// เก็บเฉพาะรหัสที่รู้จัก ห้ามส่งข้อความ error, URL, headers หรือข้อมูลบัญชีลง log
export function sessionFailure(error: unknown, stage: SessionStage) {
  const codes = new Set<string>();
  function collect(current: unknown, depth: number) {
    if (!(current instanceof Error) || depth > 3) return;
    if (
      "code" in current &&
      typeof current.code === "string" &&
      networkCodes.has(current.code)
    )
      codes.add(current.code);
    if (current instanceof AggregateError)
      for (const nested of current.errors) collect(nested, depth + 1);
    collect(current.cause, depth + 1);
  }
  collect(error, 0);
  return {
    stage,
    reason:
      error instanceof Error && reasons.has(error.message)
        ? error.message
        : "backend_request_failed",
    codes: [...codes],
  };
}
