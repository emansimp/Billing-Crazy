import { view } from "@/lib/db";

// CSV export of the Customers table (read-only; values come straight from the ui_customers snapshot).
export async function GET(req: Request) {
  const basis = new URL(req.url).searchParams.get("basis") === "inv" ? "inv" : "alloc";
  const rows: any[] = await view("ui_customers", "select=*&order=customer");
  const esc = (v: unknown) => { const s = v === null || v === undefined ? "" : String(v); return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; };
  const cols = ["customer", "ns_id", `plat_exp_${basis}`, `plat_bill_${basis}`, `plat_under_${basis}`, `plat_over_${basis}`, "usage_exp", "usage_bill", "usage_under", "usage_over", "flags"];
  const head = ["Customer", "NetSuite ID", "Platform expected", "Platform billed", "Platform under-billed", "Platform over-billed", "Usage expected", "Usage billed", "Usage under-billed", "Usage over-billed", "Flags"];
  const money = (v: unknown) => (v === null || v === undefined || v === "" ? "" : String(v).replace(/^(-?\d+)(\.\d+)?$/, (_m, i, d) => `${i}.${((d ?? ".").slice(1) + "00").slice(0, 2)}`));
  const body = rows.map((r) => cols.map((c) => esc(["customer", "ns_id", "flags"].includes(c) ? r[c] : money(r[c]))).join(",")).join("\r\n");
  return new Response(`${head.join(",")}\r\n${body}\r\n`, { headers: { "Content-Type": "text/csv; charset=utf-8", "Content-Disposition": `attachment; filename="october_2026_customers_${basis}.csv"` } });
}
