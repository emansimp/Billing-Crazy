// Server-only writes. Calls narrow SECURITY DEFINER functions (public.ui_*) with the service-role key; the browser key cannot execute them.
const URL = process.env.SUPABASE_URL ?? "https://pejthvjkkyiuwcleywbf.supabase.co";

export class NoKeyError extends Error {}

export async function rpc<T = unknown>(name: string, args: Record<string, unknown> = {}): Promise<T> {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) throw new NoKeyError("Saving needs the server key (SUPABASE_SERVICE_ROLE_KEY), which is not configured on this deployment.");
  // Legacy service_role keys are JWTs (apikey + Bearer); new sb_secret_ keys are not JWTs and go in apikey only.
  const headers: Record<string, string> = { apikey: key, "Content-Type": "application/json" };
  if (!key.startsWith("sb_secret_")) headers.Authorization = `Bearer ${key}`;
  const res = await fetch(`${URL}/rest/v1/rpc/${name}`, { method: "POST", headers, body: JSON.stringify(args), cache: "no-store" });
  const text = await res.text();
  if (!res.ok) {
    let msg = text; try { msg = JSON.parse(text).message ?? text; } catch { /* keep raw */ }
    throw new Error(msg);
  }
  return (text ? JSON.parse(text) : null) as T;
}

export function fail(e: unknown): Response {
  const noKey = e instanceof NoKeyError;
  return Response.json({ error: e instanceof Error ? e.message : "Unexpected error" }, { status: noKey ? 503 : 400 });
}
