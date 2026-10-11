import "server-only";
import { cookies } from "next/headers";
import { isSameOrigin, resolveRequestOrigin } from "./request-origin";
export const sessionCookie = "yuemnoi_staff";
export async function backend(
  path: string,
  options: RequestInit = {},
  token?: string,
) {
  const base = process.env.BACKEND_URL;
  if (!base) throw new Error("backend_unconfigured");
  const url = new URL(base);
  if (!["http:", "https:"].includes(url.protocol))
    throw new Error("backend_unconfigured");
  const headers = new Headers(options.headers);
  if (options.body) headers.set("Content-Type", "application/json");
  if (token) headers.set("Authorization", "Bearer " + token);
  if (process.env.BACKEND_APP_SECRET)
    headers.set("X-App-Secret", process.env.BACKEND_APP_SECRET);
  return fetch(new URL(path, url), {
    ...options,
    headers,
    cache: "no-store",
    signal: AbortSignal.timeout(35000),
  });
}
export async function staffToken() {
  const token = (await cookies()).get(sessionCookie)?.value;
  if (!token) return null;
  try {
    return (await backend("/api/admin/me", {}, token)).ok ? token : null;
  } catch {
    return null;
  }
}
export function requestOrigin(request: Request) {
  return resolveRequestOrigin(request, process.env.ADMIN_ORIGIN);
}
export function sameOrigin(request: Request) {
  return isSameOrigin(request, process.env.ADMIN_ORIGIN);
}
