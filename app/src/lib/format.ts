// Display formatting only (string operations on SQL-computed values; nothing is calculated).
function group(int: string): string { return int.replace(/\B(?=(\d{3})+(?!\d))/g, ","); }
export function money(v: string | number | null | undefined, opts: { sign?: boolean } = {}): string {
  if (v === null || v === undefined || v === "") return "";
  let s = String(v); let neg = false;
  if (s.startsWith("-")) { neg = true; s = s.slice(1); }
  const [i, d = ""] = s.split(".");
  const out = `$${group(i)}.${(d + "00").slice(0, 2)}`;
  if (neg) return `−${out}`;
  return opts.sign ? `+${out}` : out;
}
export function int(v: string | number | null | undefined): string { return v === null || v === undefined ? "" : group(String(v).split(".")[0]); }
const MT = "America/Denver";
export function cutoffLabel(iso: string): string {
  const d = new Date(iso);
  const date = d.toLocaleDateString("en-US", { timeZone: MT, month: "short", day: "numeric", year: "numeric" });
  const time = d.toLocaleTimeString("en-US", { timeZone: MT, hour: "numeric", minute: "2-digit" });
  return `${date}, ${time} MT`;
}
export function runLabel(iso: string): string { return cutoffLabel(iso); }
