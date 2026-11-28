import Link from "next/link";
import { view, one } from "@/lib/db";
import { money, cutoffLabel } from "@/lib/format";
import { Chip, ClassChip } from "@/components/Chip";

export const dynamic = "force-dynamic";

function Variance({ under, over }: { under: string; over: string }) {
  const u = Number(under) > 0, o = Number(over) > 0;
  if (!u && !o) return <span className="muted">None</span>;
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 2, alignItems: "flex-end" }}>
      {u && <span style={{ color: "#6B4A00" }}>Under {money(under)}</span>}
      {o && <span style={{ color: "#8F2D0F" }}>Over {money(over)}</span>}
    </div>
  );
}

export default async function CloseOverview({ searchParams }: { searchParams: Promise<{ class?: string }> }) {
  const { class: filter } = await searchParams;
  const [header, q1, q2, q3, q3s, counts, findings, corrections, ready] = await Promise.all([
    one("ui_close_header"), view("ui_overview_q1", "select=*&order=sort_no"), one("ui_overview_q2"), view("ui_overview_q3", "select=*&order=sort_no"),
    one("ui_overview_q3_summary"), one("ui_findings_counts"),
    view("ui_findings_list", `select=*&order=sort_no${filter ? `&class=eq.${filter}` : ""}`), view("ui_billing_corrections", "select=*&order=ref"), one("ui_readiness"),
  ]);
  const total = q1.find((r: any) => r.stream === "Total");
  // decisions are live; the snapshot rows are overlaid with the latest decision (display only)
  const decisions: Record<string, string> = Object.fromEntries((await view("ui_finding_decisions", "select=finding_id,decision")).map((d: any) => [d.finding_id, d.decision]));
  const corrStatus = (c: any) => (c.finding_id && decisions[c.finding_id] === "approved" ? "Approved" : c.status);
  return (
    <>
      <div style={{ padding: "24px 32px 0", display: "flex", flexWrap: "wrap", gap: 16, alignItems: "flex-end", justifyContent: "space-between" }}>
        <div>
          <h1 style={{ margin: 0, fontSize: 26, fontWeight: 700 }}>Close overview</h1>
          <div className="muted" style={{ marginTop: 4 }}>October 2026 service · {header?.customers} customers · Close cutoff {header && cutoffLabel(header.cutoff)}</div>
        </div>
        <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
          <Chip tone="info">{header?.status_label}</Chip>
          <Link className="btn btn-p" href="/journal">Go to journal entries</Link>
        </div>
      </div>

      <div style={{ padding: "20px 32px 32px", display: "flex", flexDirection: "column", gap: 20 }}>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 16 }}>
          <section className="card" style={{ flex: "1 1 340px", padding: 20, display: "flex", flexDirection: "column", gap: 12 }}>
            <div className="lbl">Question 1</div>
            <h2 style={{ margin: 0, fontSize: 17, fontWeight: 600 }}>What should we have billed, and how does it compare with actual?</h2>
            <table className="t">
              <thead><tr><th></th><th className="num">Expected</th><th className="num">Billed</th><th className="num">Variance</th></tr></thead>
              <tbody>
                {q1.map((r: any) => (
                  <tr key={r.stream}>
                    <td style={r.stream === "Total" ? { fontWeight: 600 } : undefined}>{r.stream}</td>
                    <td className="num" style={r.stream === "Total" ? { fontWeight: 600 } : undefined}>{money(r.expected)}</td>
                    <td className="num" style={r.stream === "Total" ? { fontWeight: 600 } : undefined}>{money(r.billed)}</td>
                    <td className="num"><Variance under={r.under_billed} over={r.over_billed} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
              <Chip tone="info">Under-billed {money(total?.under_billed)}</Chip>
              <Chip tone="err">Over-billed {money(total?.over_billed)}</Chip>
            </div>
            <div className="muted" style={{ fontSize: 12 }}>Billed platform uses a day-based allocation to October. Billed usage is the Nov 1 invoices for October service, net of issued credits. Under- and over-billing are never netted, across customers or across platform and usage.</div>
            <Link href="/reconciliation">Open reconciliation</Link>
          </section>

          <section className="card" style={{ flex: "1 1 340px", padding: 20, display: "flex", flexDirection: "column", gap: 12 }}>
            <div className="lbl">Question 2</div>
            <h2 style={{ margin: 0, fontSize: 17, fontWeight: 600 }}>Which differences need what action?</h2>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(2,minmax(0,1fr))", gap: 10 }}>
              {[[q2?.billing_corrections, "Billing corrections"], [q2?.october_accounting_adjustments, "October accounting adjustments"], [q2?.need_more_information, "Need more information"], [q2?.valid_explanations, "Valid explanations, no action"]].map(([n, l]) => (
                <div key={String(l)} style={{ border: "1px solid #EEF0F3", borderRadius: 8, padding: 12 }}><div style={{ fontSize: 26, fontWeight: 700 }}>{n}</div><div className="muted">{l}</div></div>
              ))}
            </div>
            <div className="muted" style={{ fontSize: 12 }}>A difference is not automatically an error. Approved credits, voids and timing can explain it.</div>
            <a href="#findings">Jump to findings</a>
          </section>

          <section className="card" style={{ flex: "1 1 340px", padding: 20, display: "flex", flexDirection: "column", gap: 12 }}>
            <div className="lbl">Question 3</div>
            <h2 style={{ margin: 0, fontSize: 17, fontWeight: 600 }}>What changes October&apos;s books?</h2>
            <table className="t"><tbody>
              {q3.map((r: any) => <tr key={r.label}><td>{r.label}</td><td className="num">{money(r.amount)}</td></tr>)}
              <tr><td style={{ fontWeight: 600 }}>Net effect on October revenue</td><td className="num" style={{ fontWeight: 600 }}>{money(q3s?.net_revenue_effect, { sign: true })}</td></tr>
            </tbody></table>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
              <Chip tone="blue">{q3s?.proposed_entries} proposed entries</Chip>
              <Chip tone="gray">Credit notes reduce AR in November: no second revenue reduction</Chip>
              {Number(q3s?.concessions_already_reflected) > 0 && <Chip tone="gray">Approved concession already in the accrual: no entry</Chip>}
            </div>
            <Link href="/journal">Review journal entries</Link>
          </section>
        </div>

        <section className="card" id="findings">
          <div style={{ padding: "16px 20px", display: "flex", flexWrap: "wrap", gap: 12, justifyContent: "space-between", alignItems: "center", borderBottom: "1px solid #E2E5EA" }}>
            <h2 style={{ margin: 0, fontSize: 17, fontWeight: 600 }}>Findings</h2>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
              <Link href="/#findings" style={{ textDecoration: "none" }}><span className="chip c-gray">All {counts?.total}</span></Link>
              <Link href="/?class=error#findings" style={{ textDecoration: "none" }}><span className="chip c-err">Error {counts?.errors}</span></Link>
              <Link href="/?class=valid_explanation#findings" style={{ textDecoration: "none" }}><span className="chip c-ok">Valid explanation {counts?.valid_explanations}</span></Link>
              <Link href="/?class=needs_info#findings" style={{ textDecoration: "none" }}><span className="chip c-info">Needs info {counts?.needs_info}</span></Link>
            </div>
          </div>
          <div style={{ overflowX: "auto" }}>
            <table className="t">
              <thead><tr><th>ID</th><th>Customer</th><th>What we found</th><th>Type</th><th>Period</th><th className="num">Amount</th><th>Next step</th><th>Owner</th></tr></thead>
              <tbody>
                {findings.map((f: any) => (
                  <tr key={f.finding_id}>
                    <td><Link href={`/findings/${f.display_id}`}>{f.display_id}</Link></td>
                    <td>{f.customer.startsWith("UNASSIGNED") ? "Unassigned workspace" : f.customer}</td>
                    <td>{f.what_we_found}</td>
                    <td><ClassChip cls={f.class} label={f.class_label} /> {f.direction_label && <span className="chip c-gray">{f.direction_label}</span>}</td>
                    <td>{f.period_label}</td>
                    <td className="num">{f.amount_display}</td>
                    <td>{f.next_step}</td>
                    <td>{f.owner}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        <div style={{ display: "flex", flexWrap: "wrap", gap: 16 }}>
          <section className="card" style={{ flex: "3 1 560px", minWidth: 0 }}>
            <div style={{ padding: "16px 20px", borderBottom: "1px solid #E2E5EA", display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
              <h2 style={{ margin: 0, fontSize: 17, fontWeight: 600 }}>Proposed billing corrections</h2>
              <span className="muted" style={{ fontSize: 12 }}>Proposed documents carry November issue dates and need Controller approval.</span>
            </div>
            <div style={{ overflowX: "auto" }}>
              <table className="t">
                <thead><tr><th>Ref</th><th>Customer</th><th>Document</th><th>Linked to</th><th className="num">Amount</th><th>Status</th></tr></thead>
                <tbody>
                  {corrections.map((c: any) => (
                    <tr key={c.ref}><td>{c.ref}</td><td>{c.customer}</td><td>{c.document}</td><td>{c.linked_to}</td><td className="num">{money(c.amount)}</td>
                      <td><Chip tone={["Already issued", "Approved"].includes(corrStatus(c)) ? "ok" : "info"}>{corrStatus(c)}</Chip></td></tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
          <section className="card" style={{ flex: "1 1 260px", padding: 20, display: "flex", flexDirection: "column", gap: 10 }}>
            <div className="lbl">Close readiness</div>
            <div><span style={{ fontSize: 26, fontWeight: 700 }}>{ready?.verified} of {ready?.total}</span> <span className="muted">checks verified</span></div>
            <div style={{ height: 8, borderRadius: 999, background: "#E8EBF0", overflow: "hidden" }}><div style={{ width: `${ready?.verified_pct}%`, height: "100%", background: "#1B4DB8" }} /></div>
            <div className="muted">{ready?.failed} failing · {ready?.pending} open: {ready?.pending_names}.</div>
            <Link href="/reconciliation">View controls and completeness</Link>
          </section>
        </div>
      </div>
    </>
  );
}
