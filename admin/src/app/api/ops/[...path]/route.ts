import { cookies } from "next/headers";
import { backend, sameOrigin, sessionCookie } from "@/lib/server";
const modules = new Set([
  "me",
  "overview",
  "reports",
  "users",
  "items",
  "bookings",
  "reviews",
  "complaints",
  "identity",
  "identity-detail",
  "staff",
  "audit",
  "settings",
  "health",
]);
const actions = new Set([
  "identity-review",
  "suspend-user",
  "hide-item",
  "review-item",
  "hide-review",
  "staff",
  "revoke-identity",
  "complaint",
]);
type Context = { params: Promise<{ path: string[] }> };
async function proxy(request: Request, context: Context) {
  const { path } = await context.params;
  if (request.method === "GET") {
    if (
      !(path.length === 1 && modules.has(path[0])) &&
      !(
        path.length === 2 &&
        path[0] === "evidence" &&
        /^[a-f0-9-]{36}$/.test(path[1])
      )
    )
      return new Response(null, { status: 404 });
  } else {
    if (!sameOrigin(request)) return new Response(null, { status: 403 });
    if (
      path.length !== 3 ||
      path[0] !== "actions" ||
      !actions.has(path[1]) ||
      !/^[a-zA-Z0-9-]{1,64}$/.test(path[2])
    )
      return new Response(null, { status: 404 });
  }
  const token = (await cookies()).get(sessionCookie)?.value;
  if (!token)
    return Response.json({ error: "กรุณาเข้าสู่ระบบ" }, { status: 401 });
  try {
    const body = request.method === "POST" ? await request.text() : undefined;
    if (body && body.length > 8000) return new Response(null, { status: 413 });
    const res = await backend(
      "/api/admin/" +
        path.map(encodeURIComponent).join("/") +
        new URL(request.url).search,
      { method: request.method, body },
      token,
    );
    return new Response(await res.arrayBuffer(), {
      status: res.status,
      headers: {
        "Content-Type": res.headers.get("Content-Type") ?? "application/json",
        "Cache-Control": "private, no-store",
        "X-Content-Type-Options": "nosniff",
      },
    });
  } catch {
    return Response.json(
      { error: "เชื่อมต่อระบบไม่สำเร็จ กรุณาลองใหม่" },
      { status: 503 },
    );
  }
}
export const GET = proxy;
export const POST = proxy;
