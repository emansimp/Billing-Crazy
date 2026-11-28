import Link from "next/link";
import { view, one } from "@/lib/db";
import { money, int } from "@/lib/format";
import { Chip } from "@/components/Chip";

export const dynamic = "force-dynamic";
const when = (d: string) => new Date(d + "T12:00:00Z").toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" });

export default async function CustomerDetail({ searchParams }: { searchParams: Promise<{ id?: string }> }) {
  const { id } = await searchParams;
  const all: any[] = await view("ui_customers", "select=salesforce_account_id,customer,flags,has_variance,has_needs_info&order=customer");
  const featured = all.filter((c) => c.flags && /error|info/.test(c.flags)).slice(0, 8);
  const sel = id ?? featured[0]?.salesforce_account_id ?? all[0]?.salesforce_account_id;
  const q = `salesforce_account_id=eq.${encodeURIComponent(sel)}`;
  const [h, k, uv] = await Promise.all([one("ui_customer_header", `select=*&${q}`), one("ui_customer_kpis", `select=*&${q}`), one("ui_customer_usage_validation", `select=*&${q}`)]);
  const [versions, allowance, invoices, notes, gl, roll] = await Promise.all([
    view("ui_customer_versions", `select=*&${q}&order=version_no`), view("ui_customer_allowance", `select=*&${q}&order=ord,label`),
    view("ui_customer_invoices", `select=*&${q}&order=issued,invoice`), view("ui_customer_credit_notes", `select=*&${q}&order=created`),
    view("ui_customer_gl_trail", `select=*&${q}&order=posting_date,created`), view("ui_customer_rollforward", `select=*&${q}&order=ord`),
  ]);
  if (!h || !k) return <div style={{ padding: 32 }}>Customer not found.</div>;
  const usageVar = Number(k.usage_over_billed) > 0 ? `over-billed ${money(k.usage_over_billed)}` : Number(k.usage_under_billed) > 0 ? `under-billed ${money(k.usage_under_billed)}` : "variance $0.00";
  const platVar = Number(k.platform_over_billed) > 0 ? `over-billed ${money(k.platform_over_billed)}` : Number(k.platform_under_billed) > 0 ? `under-billed ${money(k.platform_under_billed)}` : "variance $0.00";
  return (
    <div style={{ padding: "16px 32px 32px", display: "flex", flexDirection: "column", gap: 16 }}>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 12, justifyContent: "space-between", alignItems: "flex-end" }}>
        <div>
          <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
            <h2 style={{ margin: 0, fontSize: 22 }}>{h.account_name}</h2>
            {Number(h.error_findings) > 0 ? <Chip tone="err">{h.error_findings} error finding{Number(h.error_findings) > 1 ? "s" : ""}</Chip> : <Chip tone="gray">No error findings</Chip>}
          </div>
          <div className="muted" style={{ marginTop: 4 }}>Salesforce {h.salesforce_account_id} · Stripe {h.stripe_customer_id} · NetSuite {h.ns_id} · Contract {h.contract_ids} · Product account {h.product_accounts}</div>
        </div>
        <form method="get" action="/reconciliation/customer" style={{ display: "flex", gap: 8, alignItems: "center" }}>
          <span className="lbl">Customer</span>
          <select name="id" defaultValue={sel} style={{ padding: "8px 10px", border: "1px solid #C9CFD8", borderRadius: 6, fontFamily: "inherit", fontSize: 13 }}>
            {all.map((c) => <option key={c.salesforce_account_id} value={c.salesforce_account_id}>{c.customer}</option>)}
          </select>
          <button className="btn" type="submit">Show</button>
        </form>
      </div>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
        {featured.map((c) => <Link key={c.salesforce_account_id} href={`/reconciliation/customer?id=${c.salesforce_account_id}`} className={`btn${c.salesforce_account_id === sel ? " btn-p" : ""}`}>{c.customer}</Link>)}
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(240px,1fr))", gap: 12 }}>
        {[["Platform billed vs expected", money(k.plat_billed), `Expected ${money(k.plat_expected)} · ${platVar}`],
          ["Usage billed vs expected", money(k.usage_billed), `Expected ${money(k.usage_expected)} · ${usageVar}`],
          ["Platform revenue, October", money(k.plat_revenue_posted), `Posted equals ${money(k.plat_fee_for_posted).replace(/\.00$/, "")} × ${k.plat_days} ÷ 365. Billing is ${money(k.plat_invoice_amount)}.`],
          ["Usage accrual, October", money(k.usage_accrual_posted), `Expected ${money(k.usage_accrual_expected)} · accrual ${Number(k.usage_accrual_diff) === 0 ? "matches" : `${money(String(k.usage_accrual_diff).replace("-", ""))} ${Number(k.usage_accrual_diff) > 0 ? "high" : "low"}`}`]]
          .map(([t, v, s]) => <div key={t} className="card" style={{ padding: 16, ...(/over-billed|under-billed|high|low/.test(s) ? { borderColor: "#F0B8A4" } : {}) }}><div className="lbl">{t}</div><div style={{ fontSize: 24, fontWeight: 700, margin: "4px 0" }}>{v}</div><div className="muted" style={{ fontSize: 12 }}>{s}</div></div>)}
      </div>

      <div style={{ display: "flex", flexWrap: "wrap", gap: 16, alignItems: "flex-start" }}>
        <section className="card" style={{ flex: "1 1 420px", padding: 20 }}>
          <h3 style={{ margin: "0 0 8px", fontSize: 16 }}>Contract versions</h3>
          {versions.map((v: any) => (
            <div key={v.doc} style={{ padding: "10px 0", borderTop: "1px solid #EEF0F3" }}>
              <div style={{ fontWeight: 600 }}>{v.doc} · {v.type_label} {v.billing_load_missing && <Chip tone="err">Billing load not recorded</Chip>}</div>
              <div className="muted">{v.summary}</div>
            </div>
          ))}
          <h3 style={{ margin: "14px 0 8px", fontSize: 16 }}>October allowance by day</h3>
          {allowance.map((a: any, i: number) => <div key={i} className="mono" style={{ padding: "3px 0", fontWeight: a.ord === 2 ? 700 : 400 }}>{a.label}</div>)}
        </section>
        <section className="card" style={{ flex: "1 1 360px", padding: 20 }}>
          <h3 style={{ margin: "0 0 8px", fontSize: 16 }}>October usage validation</h3>
          <table className="t"><tbody>
            <tr><td>Verified product accounts</td><td className="num">{uv?.accounts_total === 0 ? "None verified" : `${uv?.accounts_verified} of ${uv?.accounts_total}`}</td></tr>
            <tr><td>Daily records, unique and active</td><td className="num">{uv?.accounts_total === 0 ? "No verified usage" : `${uv?.days_with_records} of ${uv?.days_in_period} days`}</td></tr>
            <tr><td>Duplicate or replaced records</td><td className="num">{uv?.duplicate_records}</td></tr>
            <tr><td>Total workflow runs</td><td className="num">{uv?.no_verified_usage ? "Unknown" : int(uv?.total_runs)}</td></tr>
            <tr><td>Allowance applied (weighted)</td><td className="num">{int(uv?.allowance_runs)}</td></tr>
            <tr><td>Overage runs × rate</td><td className="num">{uv?.no_verified_usage ? "Not computable" : `${int(uv?.overage_units)} × $${(() => { const [a, b = ""] = String(uv?.overage_rate_per_run).split("."); return `${a}.${(b + "00").slice(0, 2)}`; })()} = ${money(uv?.expected_usage_gross)}`}</td></tr>
          </tbody></table>
          <div className="muted" style={{ fontSize: 12, marginTop: 8 }}>Source: product_usage.csv. Tie-out to usage_batch_controls.csv for all dates is on the <Link href="/reconciliation/controls">Controls</Link> tab.</div>
          {h.finding_ids && <div style={{ marginTop: 10 }}>Open finding {h.finding_ids.split(", ").map((f: string, i: number) => <span key={f}>{i ? ", " : ""}<Link href={`/findings/${f}`}>{f}</Link></span>)}</div>}
        </section>
      </div>

      <section className="card"><div style={{ padding: "16px 20px", borderBottom: "1px solid #E2E5EA" }}><h3 style={{ margin: 0, fontSize: 16 }}>Invoices and credit notes</h3></div>
        <div style={{ overflowX: "auto" }}><table className="t">
          <thead><tr><th>Invoice</th><th>Type</th><th>Issued</th><th>Service period</th><th className="num">Amount</th><th>Status</th><th>Use in October review</th></tr></thead>
          <tbody>{invoices.map((i: any) => <tr key={i.invoice}><td>{i.invoice}</td><td>{i.type}</td><td>{when(i.issued)}</td><td>{i.service_period}</td><td className="num">{money(i.amount)}</td><td><Chip tone={i.status === "Paid" ? "ok" : "gray"}>{i.status}</Chip></td><td>{i.use_in_review}</td></tr>)}</tbody>
        </table></div>
        <div style={{ padding: "12px 20px" }}>
          {notes.length === 0 ? <span className="muted">No credit notes exist for this customer.</span> : notes.map((n: any) => <div key={n.number}>{n.number} · {n.status} · {money(n.amount)} · {n.reason} · {n.use_in_review}</div>)}
        </div>
      </section>

      <div style={{ display: "flex", flexWrap: "wrap", gap: 16, alignItems: "flex-start" }}>
        <section className="card" style={{ flex: "2 1 520px", minWidth: 0 }}>
          <div style={{ padding: "16px 20px", borderBottom: "1px solid #E2E5EA" }}><h3 style={{ margin: 0, fontSize: 16 }}>Accounting trail, October</h3></div>
          <div style={{ overflowX: "auto" }}><table className="t">
            <thead><tr><th>Journal</th><th>Posting date</th><th>Created</th><th>Entry</th><th className="num">Amount</th></tr></thead>
            <tbody>{gl.map((g: any) => <tr key={g.journal}><td>{g.journal}</td><td>{when(g.posting_date)}</td><td>{when(g.created)}</td><td>{g.entry}</td><td className="num">{money(g.amount)}</td></tr>)}</tbody>
          </table></div>
        </section>
        <section className="card" style={{ flex: "1 1 300px", padding: 20 }}>
          {roll.map((r: any) => (
            <div key={r.ord} style={{ marginBottom: 14 }}>
              <div className="lbl">{r.account_label}</div><div className="mono" style={{ marginTop: 4 }}>{r.posted_text}</div><div className="muted" style={{ fontSize: 12 }}>{r.note}</div>
            </div>
          ))}
        </section>
      </div>
    </div>
  );
}
