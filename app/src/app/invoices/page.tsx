import Link from "next/link";
import { view, one } from "@/lib/db";
import { money, int } from "@/lib/format";
import { Chip } from "@/components/Chip";

export const dynamic = "force-dynamic";
const PAGE = 12;
const day = (d: string) => new Date(d + "T12:00:00Z").toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" });

export default async function Register({ searchParams }: { searchParams: Promise<{ q?: string; t?: string; scope?: string; page?: string; invoice?: string }> }) {
  const { q = "", t = "all", scope = "oct", page = "1", invoice } = await searchParams;
  const [rows, sum]: any = await Promise.all([view("ui_invoices", "select=*&order=customer,issued,invoice_number"), one("ui_invoices_summary")]);
  let list = rows.filter((r: any) => (scope === "all" || r.covers_october) && (t === "all" || r.stream === t) && (!q || `${r.invoice_number} ${r.customer}`.toLowerCase().includes(q.toLowerCase())));
  const pages = Math.max(1, Math.ceil(list.length / PAGE)); const p = Math.min(Math.max(1, Number(page) || 1), pages);
  const shown = list.slice((p - 1) * PAGE, p * PAGE);
  // default selection: the listed invoice carrying the lowest-numbered finding (F-01 first), else the first row
  const rank = (r: any) => Math.min(...String(r.finding_ids ?? "").split(", ").filter(Boolean).map((f) => Number(f.replace("F-", ""))), 999);
  const sel = rows.find((r: any) => r.invoice_number === invoice) ?? [...shown].sort((a: any, b: any) => rank(a) - rank(b))[0];
  const d: any = sel ? await one("ui_invoice_detail", `select=*&invoice_id=eq.${encodeURIComponent(sel.invoice_id)}`) : undefined;
  const href = (o: Record<string, string>) => `/invoices?${new URLSearchParams({ q, t, scope, page: "1", ...(invoice ? { invoice } : {}), ...o }).toString()}`;
  return (
    <div style={{ padding: "16px 32px 32px", display: "flex", flexDirection: "column", gap: 16 }}>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
        <Chip tone="gray">{sum?.invoices} invoices</Chip><Chip tone="ok">{sum?.paid} paid</Chip><Chip tone="gray">{sum?.open} open</Chip>
        <Chip tone="info">{sum?.credit_notes} credit notes: {sum?.credit_notes_issued} issued, {sum?.credit_notes_void} void</Chip>
      </div>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 12, alignItems: "center", justifyContent: "space-between" }}>
        <form method="get" action="/invoices" style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
          <input type="hidden" name="t" value={t} /><input type="hidden" name="scope" value={scope} />
          <input name="q" defaultValue={q} placeholder="Invoice or customer" aria-label="Search invoices" style={{ padding: "8px 10px", border: "1px solid #C9CFD8", borderRadius: 6, fontFamily: "inherit", fontSize: 13, minWidth: 200 }} />
          <button className="btn" type="submit">Search</button>
          {[["all", "All"], ["platform", "Platform"], ["usage", "Usage"]].map(([k, l]) => <Link key={k} href={href({ t: k })} className={`btn${t === k ? " btn-p" : ""}`}>{l}</Link>)}
        </form>
        <div style={{ display: "flex", gap: 8 }}>
          <Link href={href({ scope: "oct" })} className={`btn${scope === "oct" ? " btn-p" : ""}`}>Covers October</Link>
          <Link href={href({ scope: "all" })} className={`btn${scope === "all" ? " btn-p" : ""}`}>All periods</Link>
        </div>
      </div>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 16, alignItems: "flex-start" }}>
        <section className="card" style={{ flex: "3 1 640px", minWidth: 0 }}>
          <div style={{ overflowX: "auto" }}>
            <table className="t">
              <thead><tr><th>Invoice</th><th>Customer</th><th>Type</th><th>Issued</th><th>Service period</th><th className="num">Amount</th><th>Status</th><th>Role in October review</th></tr></thead>
              <tbody>
                {shown.map((r: any) => (
                  <tr key={r.invoice_id} style={r.invoice_id === sel?.invoice_id ? { background: "#F1F5FE" } : undefined}>
                    <td><Link href={href({ invoice: r.invoice_number, page: String(p) })}>{r.invoice_number}</Link></td><td>{r.customer}</td><td>{r.type}</td><td>{day(r.issued)}</td><td>{r.service_period}</td>
                    <td className="num">{money(r.amount)}</td><td><Chip tone={r.status === "Paid" ? "ok" : "gray"}>{r.status}</Chip></td>
                    <td>{r.role_in_review}{r.finding_ids && r.finding_ids.split(", ").map((f: string) => <span key={f}> <Link href={`/findings/${f}`}><span className="chip c-blue">{f}</span></Link></span>)}
                      {r.credit_note_text && <div className="muted" style={{ fontSize: 11 }}>{r.credit_note_text}</div>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div style={{ padding: "12px 16px", display: "flex", flexWrap: "wrap", justifyContent: "space-between", alignItems: "center", gap: 8, borderTop: "1px solid #EEF0F3" }}>
            <span className="muted" style={{ fontSize: 12 }}>Showing {shown.length} of {list.length} invoices{scope === "oct" ? " that cover October" : ""}. Amounts are invoice totals, not October revenue.</span>
            <div style={{ display: "flex", gap: 8 }}>
              {p > 1 ? <Link className="btn" href={href({ page: String(p - 1) })}>Previous</Link> : <span className="btn" style={{ opacity: 0.5 }}>Previous</span>}
              {p < pages ? <Link className="btn" href={href({ page: String(p + 1) })}>Next</Link> : <span className="btn" style={{ opacity: 0.5 }}>Next</span>}
              <a className="btn" href="/api/export/invoices">Export CSV</a>
            </div>
          </div>
        </section>

        {d && (
          <section className="card" style={{ flex: "1 1 340px", padding: 20, display: "flex", flexDirection: "column", gap: 12 }}>
            <div className="lbl">Invoice detail</div>
            <div><div style={{ fontSize: 18, fontWeight: 700 }}>{d.invoice_number}</div><div className="muted">{d.customer} · Stripe {d.invoice_id}</div></div>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
              <Chip tone={d.status === "Paid" ? "ok" : "gray"}>{d.status}</Chip><Chip tone="gray">{d.type}</Chip>
              {d.finding_ids && d.finding_ids.split(", ").map((f: string) => <Link key={f} href={`/findings/${f}`}><span className="chip c-blue">Finding {f}</span></Link>)}
            </div>
            <table className="t"><tbody>
              <tr><td className="muted">Issued</td><td>{String(d.issued_label).replace("Issued ", "")}</td></tr>
              <tr><td className="muted">Service period</td><td>{d.service_period_label}</td></tr>
              <tr><td className="muted">Line</td><td>{d.line_description}</td></tr>
              <tr><td className="muted">Quantity</td><td>{d.stream === "usage" ? `${int(d.quantity)} runs` : d.quantity}</td></tr>
              <tr><td className="muted">Unit price</td><td>{money(d.unit_price)}</td></tr>
              <tr><td className="muted">Discount</td><td>{money(d.discount)}</td></tr>
              <tr><td style={{ fontWeight: 600 }}>Invoice total</td><td style={{ fontWeight: 700 }}>{money(d.invoice_total)}</td></tr>
            </tbody></table>
            <div style={Number(d.over_billed) > 0 || Number(d.under_billed) > 0 ? { background: "#FFF3EE", border: "1px solid #F0B8A4", borderRadius: 8, padding: 10 } : undefined}>
              <div className="lbl" style={Number(d.over_billed) > 0 || Number(d.under_billed) > 0 ? { color: "#8F2D0F" } : undefined}>Expected vs billed</div>
              <div style={{ marginTop: 4 }}>{d.expected_label} <b>{money(d.expected_amount)}</b></div>
              {Number(d.over_billed) > 0 && <div style={{ color: "#8F2D0F", fontWeight: 600 }}>Over-billed {money(d.over_billed)}</div>}
              {Number(d.under_billed) > 0 && <div style={{ color: "#6B4A00", fontWeight: 600 }}>Under-billed {money(d.under_billed)}</div>}
              {d.expected_amount !== null && Number(d.over_billed) === 0 && Number(d.under_billed) === 0 && Number(d.expected_amount) === Number(d.invoice_total) && <div className="muted">Matches the contract.</div>}
            </div>
            <div style={{ borderTop: "1px solid #EEF0F3", paddingTop: 10 }}>
              <div className="lbl">NetSuite posting</div>
              {d.outside_gl_extract ? <div className="muted" style={{ marginTop: 4 }}>Posted in September, before the GL extract period (supported by the opening balances).</div> : (
                <div style={{ marginTop: 4 }}><div>{d.journal} · {day(d.posting_date)}</div><div className="mono">{d.dr_text} / {d.cr_text}</div><div className="muted">{d.posting_note}</div></div>
              )}
            </div>
            <div style={{ borderTop: "1px solid #EEF0F3", paddingTop: 10 }}>
              <div className="lbl">Credit notes</div>
              <div style={{ marginTop: 4 }}>{d.credit_note_text ?? <span className="muted">None issued against this invoice.</span>}</div>
            </div>
            {d.correction_ref && (
              <div style={{ borderTop: "1px solid #EEF0F3", paddingTop: 10 }}>
                <div className="lbl">Proposed correction</div>
                <div style={{ marginTop: 4 }}>{d.correction_ref} · {d.correction_document} <b>{money(d.correction_amount)}</b></div>
                <div className="muted" style={{ fontSize: 12 }}>November issue date. The finalized invoice is not edited.</div>
                <div style={{ marginTop: 4 }}><Chip tone={d.correction_decision === "approved" ? "ok" : "info"}>{d.correction_decision === "approved" ? "Approved" : "Awaiting Controller approval"}</Chip></div>
              </div>
            )}
            <div style={{ display: "flex", flexWrap: "wrap", gap: 12 }}>
              {d.finding_ids && <Link href={`/findings/${d.finding_ids.split(", ")[0]}`}>Open finding {d.finding_ids.split(", ")[0]}</Link>}
              <Link href={`/reconciliation/customer?id=${d.salesforce_account_id}`}>Customer detail</Link>
            </div>
          </section>
        )}
      </div>
    </div>
  );
}
