// Server-side reads of the read-only public.ui_* views. No number is computed here; values are formatted for display only.
const URL = process.env.SUPABASE_URL ?? "https://pejthvjkkyiuwcleywbf.supabase.co";
// Publishable key is public by design; it can only read the ui_* views (raw/calc/ref/stg/ops are not exposed to it).
const KEY = process.env.SUPABASE_PUBLISHABLE_KEY ?? "sb_publishable_OcgIf8C4Ge2gndql31db8g__kK7u7oL";

export async function view<T = Record<string, any>>(name: string, query = "select=*"): Promise<T[]> {
  const res = await fetch(`${URL}/rest/v1/${name}?${query}`, { headers: { apikey: KEY, Authorization: `Bearer ${KEY}` }, cache: "no-store" });
  if (!res.ok) throw new Error(`${name}: ${res.status} ${await res.text()}`);
  return (await res.json()) as T[];
}
export async function one<T = Record<string, any>>(name: string, query = "select=*"): Promise<T | undefined> {
  return (await view<T>(name, `${query}&limit=1`))[0];
}
