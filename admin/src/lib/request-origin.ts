// Next.js อาจใช้ localhost เป็น URL ภายใน จึงตรวจ Origin กับ Host ที่รับจริง
// เมื่อมี reverse proxy ให้กำหนด ADMIN_ORIGIN แทนการเชื่อ forwarded headers
export function resolveRequestOrigin(
  request: Request,
  configuredOrigin?: string,
): string | null {
  try {
    if (configuredOrigin) {
      const configured = new URL(configuredOrigin);
      if (
        !["http:", "https:"].includes(configured.protocol) ||
        configured.username ||
        configured.password ||
        configured.pathname !== "/" ||
        configured.search ||
        configured.hash
      )
        return null;
      return configured.origin;
    }
    const url = new URL(request.url);
    const host = request.headers.get("host");
    if (
      !["http:", "https:"].includes(url.protocol) ||
      !host ||
      /[\s/?#@\\]/.test(host)
    )
      return null;
    return new URL(`${url.protocol}//${host}`).origin;
  } catch {
    return null;
  }
}

export function isSameOrigin(
  request: Request,
  configuredOrigin?: string,
): boolean {
  const expected = resolveRequestOrigin(request, configuredOrigin);
  return expected !== null && request.headers.get("origin") === expected;
}
