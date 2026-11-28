import { view } from "@/lib/db";

// Generates the journal CSV from the live journal lines. Gated like the mockup: blocked on any failing check and until every entry is approved.
// Layout follows the NetSuite journal entry import: External ID repeated on every row, one debit-or-credit per line, no total row.
export async function GET(req: Request) {
  const fmt = new URL(req.url).searchParams.get("format") === "generic" ? "generic" : "netsuite";
  const [checks, lines]: any = await Promise.all([view("ui_export_checks"), view("ui_export_lines", "select=*&order=external_id,line_order,side_order")]);
  const failed = checks.find((c: any) => c.status === "fail");
  if (failed) return Response.json({ error: `Export blocked: ${failed.check_name}. ${failed.detail}` }, { status: 409 });
  const pending = checks.find((c: any) => c.check_name === "Controller approval" && c.status !== "pass");
  if (pending) return Response.json({ error: `Export is locked until the Controller approves the entries (${pending.detail}).` }, { status: 403 });
  const esc = (v: unknown) => { const s = v === null || v === undefined ? "" : String(v); return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; };
  const amt = (v: unknown) => (v === null || v === undefined ? "" : String(v).replace(/^(-?\d+)(\.\d+)?$/, (_m, i, d) => `${i}.${((d ?? ".").slice(1) + "00").slice(0, 2)}`));
  const head = fmt === "netsuite"
    ? ["External ID", "Date", "Posting Period", "Journal Entry - Line: Account", "Journal Entry - Line: Debit", "Journal Entry - Line: Credit", "Journal Entry - Line: Memo", "Name"]
    : ["External ID", "Date", "Posting Period", "Account", "Debit", "Credit", "Memo", "Name"];
  const body = lines.map((l: any) => [l.external_id, l.date, l.posting_period, l.account_label, amt(l.debit), amt(l.credit), l.memo, l.name].map(esc).join(",")).join("\r\n");
  return new Response(`${head.join(",")}\r\n${body}\r\n`, { headers: { "Content-Type": "text/csv; charset=utf-8", "Content-Disposition": 'attachment; filename="relaycloud_oct2026_adjustments_netsuite.csv"' } });
}
