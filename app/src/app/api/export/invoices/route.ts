import { view } from "@/lib/db";

// CSV export of the invoice register (read-only; straight from the ui_invoices snapshot).
export async function GET() {
  const rows: any[] = await view("ui_invoices", "select=*&order=customer,issued,invoice_number");
  const esc = (v: unknown) => { const s = v === null || v === undefined ? "" : String(v); return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; };
  const money = (v: unknown) => String(v).replace(/^(-?\d+)(\.\d+)?$/, (_m, i, d) => `${i}.${((d ?? ".").slice(1) + "00").slice(0, 2)}`);
  const head = ["Invoice", "Customer", "NetSuite ID", "Type", "Issued", "Service period", "Amount", "Status", "Covers October", "Role in October review", "Findings", "Credit notes"];
  const body = rows.map((r) => [r.invoice_number, r.customer, r.ns_id, r.type, r.issued, r.service_period, money(r.amount), r.status, r.covers_october ? "Yes" : "No", r.role_in_review, r.finding_ids, r.credit_note_text].map(esc).join(",")).join("\r\n");
  return new Response(`${head.join(",")}\r\n${body}\r\n`, { headers: { "Content-Type": "text/csv; charset=utf-8", "Content-Disposition": 'attachment; filename="october_2026_invoice_register.csv"' } });
}
