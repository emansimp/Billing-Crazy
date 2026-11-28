import Link from "next/link";
import { view, one } from "@/lib/db";
import { money } from "@/lib/format";
import { Chip } from "@/components/Chip";

export const dynamic = "force-dynamic";
const PAGE = 15;

function Var({ under, over }: { under: any; over: any }) {
  if (Number(over) > 0) return <div><div style={{ color: "#8F2D0F", fontWeight: 600 }}>{money(over, { sign: true })}</div><div style={{ fontSize: 11, color: "#8F2D0F" }}>Over-billed</div></div>;
  if (Number(under) > 0) return <div><div style={{ color: "#6B4A00", fontWeight: 600 }}>{money(under).replace("$", "−$")}</div><div style={{ fontSize: 11, color: "#6B4A00" }}>Under-billed</div></div>;
  return <span className="muted">$0.00</span>;
}
const Note = ({ children }: { children?: React.ReactNode }) => (children ? <div className="muted" style={{ fontSize: 11 }}>{children}</div> : null);
const flagTone = (f: string) => (f.includes("error") ? "c-err" : f.includes("valid") ? "c-ok" : "c-info");

export default async function Customers({ searchParams }: { searchParams: Promise<{ q?: string; f?: string; basis?: string; page?: string }> }) {
  const { q = "", f = "all", basis = "alloc", page = "1" } = await searchParams;
  const [rows, sum, ws] = await Promise.all([view("ui_customers", "select=*&order=customer"), one("ui_customers_summary"), one("ui_unassigned_workspace")]);
  const alloc = basis !== "inv";
  const pick = (r: any, k: string) => r[`plat_${k}_${alloc ? "alloc" : "inv"}`];
  let list = rows.filter((r: any) => !q || r.customer.toLowerCase().includes(q.toLowerCase()) || String(r.ns_id).includes(q));
  if (f === "variance") list = list.filter((r: any) => r.has_variance); else if (f === "info") list = list.filter((r: any) => r.has_needs_info);
  const pages = Math.max(1, Math.ceil(list.length / PAGE)); const p = Math.min(Math.max(1, Number(page) || 1), pages);
  const shown = list.slice((p - 1) * PAGE, p * PAGE);
  const href = (o: Record<string, string>) => { const u = new URLSearchParams({ q, f, basis, page: "1", ...o }); return `/reconciliation?${u.toString()}`; };
  return (
    <div style={{ padding: "16px 32px 32px", display: "flex", flexDirection: "column", gap: 16 }}>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 8, alignItems: "center" }}>
        <Chip tone="info">Under-billed {money(sum?.under_billed)}</Chip><Chip tone="err">Over-billed {money(sum?.over_billed)}</Chip>
        <Chip tone="gray">{sum?.customers_with_variance} of {sum?.customers} customers with a variance</Chip><Chip tone="gray">{sum?.unassigned_workspaces} unassigned workspace isolated</Chip>
      </div>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 12, alignItems: "center", justifyContent: "space-between" }}>
        <form method="get" action="/reconciliation" style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
          <input type="hidden" name="f" value={f} /><input type="hidden" name="basis" value={basis} />
          <input name="q" defaultValue={q} placeholder="Customer or NetSuite ID" aria-label="Search customers" style={{ padding: "8px 10px", border: "1px solid #C9CFD8", borderRadius: 6, fontFamily: "inherit", fontSize: 13, minWidth: 200 }} />
          <button className="btn" type="submit">Search</button>
          {[["all", "All"], ["variance", "Variance only"], ["info", "Needs info"]].map(([k, l]) => <Link key={k} href={href({ f: k })} className={`btn${f === k ? " btn-p" : ""}`}>{l}</Link>)}
        </form>
        <div style={{ display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap" }}>
          <span className="muted" style={{ fontSize: 12 }}>Platform basis</span>
          <Link href={href({ basis: "alloc" })} className={`btn${alloc ? " btn-p" : ""}`}>Day-based allocation</Link>
          <Link href={href({ basis: "inv" })} className={`btn${!alloc ? " btn-p" : ""}`}>Invoice periods covering October</Link>
        </div>
      </div>
      <div className="muted" style={{ fontSize: 12 }}>{alloc ? "Platform basis: day-based allocation to October. Annual prepaid fees are not billed again in October." : "Platform basis: invoices issued in October for October service (plus the required Meridian catch-up). Annual prepaid fees show $0."}</div>
      <section className="card"><div style={{ overflowX: "auto" }}>
        <table className="t">
          <thead>
            <tr><th rowSpan={2}>Customer</th><th rowSpan={2}>NetSuite ID</th><th colSpan={3} style={{ textAlign: "center" }}>Platform subscription</th><th colSpan={3} style={{ textAlign: "center" }}>Workflow-run usage</th><th rowSpan={2}>Flag</th></tr>
            <tr><th className="num">Expected</th><th className="num">Billed</th><th className="num">Variance</th><th className="num">Expected</th><th className="num">Billed</th><th className="num">Variance</th></tr>
          </thead>
          <tbody>
            {shown.map((r: any) => (
              <tr key={r.salesforce_account_id} style={r.has_variance ? { background: "#FFF8F5" } : undefined}>
                <td><Link href={`/reconciliation/customer?id=${r.salesforce_account_id}`}>{r.customer}</Link></td><td>{r.ns_id}</td>
                <td className="num">{money(pick(r, "exp"))}<Note>{r.plat_note}</Note></td><td className="num">{money(pick(r, "bill"))}</td><td className="num"><Var under={pick(r, "under")} over={pick(r, "over")} /></td>
                <td className="num">{r.usage_unattributed ? <span className="muted">To be verified</span> : money(r.usage_exp)}</td>
                <td className="num">{r.usage_unattributed ? <span className="muted">No invoice</span> : money(r.usage_bill)}<Note>{r.usage_note}</Note></td>
                <td className="num">{r.usage_unattributed ? <Chip tone="info">Pending</Chip> : <Var under={r.usage_under} over={r.usage_over} />}</td>
                <td>{r.flags && r.flags.split(", ").map((x: string) => <div key={x}><span className={`chip ${flagTone(x)}`}>{x}</span></div>)}</td>
              </tr>
            ))}
            {ws && f === "all" && !q && (
              <tr className="hatch">
                <td><b>Unassigned workspace</b><div className="muted" style={{ fontSize: 11 }}>{ws.product_account_id}, no verified owner</div></td><td className="muted">None</td>
                <td className="num muted">Not applicable</td><td className="num muted">Not applicable</td><td className="num muted">Not applicable</td>
                <td className="num">Conditional</td><td className="num"><div className="muted" style={{ fontSize: 11 }}>{Number(ws.october_runs).toLocaleString("en-US")} October runs in metering</div></td><td className="num muted">Excluded</td>
                <td><Link href="/findings/F-05"><span className="chip c-info">F-05 info</span></Link></td>
              </tr>
            )}
          </tbody>
          <tfoot>
            <tr style={{ fontWeight: 600, background: "#F8F9FB" }}>
              <td colSpan={2}>All {sum?.customers} customers</td>
              <td className="num">{money(sum && sum[`plat_exp_${alloc ? "alloc" : "inv"}`])}</td><td className="num">{money(sum && sum[`plat_bill_${alloc ? "alloc" : "inv"}`])}</td>
              <td className="num"><Var under={sum && sum[`plat_under_${alloc ? "alloc" : "inv"}`]} over={sum && sum[`plat_over_${alloc ? "alloc" : "inv"}`]} /></td>
              <td className="num">{money(sum?.usage_exp)}</td><td className="num">{money(sum?.usage_bill)}</td>
              <td className="num"><div style={{ color: "#6B4A00" }}>{Number(sum?.usage_under) > 0 && <div>Under {money(sum?.usage_under)}</div>}</div><div style={{ color: "#8F2D0F" }}>{Number(sum?.usage_over) > 0 && <div>Over {money(sum?.usage_over)}</div>}</div></td><td></td>
            </tr>
          </tfoot>
        </table>
      </div></section>
      <div style={{ display: "flex", flexWrap: "wrap", justifyContent: "space-between", alignItems: "center", gap: 12 }}>
        <span className="muted" style={{ fontSize: 12 }}>Showing {shown.length} of {list.length} customers plus the isolated workspace. Totals cover all {sum?.customers} and exclude unassigned usage.</span>
        <div style={{ display: "flex", gap: 8 }}>
          {p > 1 ? <Link className="btn" href={href({ page: String(p - 1) })}>Previous</Link> : <span className="btn" style={{ opacity: 0.5 }}>Previous</span>}
          {p < pages ? <Link className="btn" href={href({ page: String(p + 1) })}>Next</Link> : <span className="btn" style={{ opacity: 0.5 }}>Next</span>}
          <a className="btn" href={`/api/export/customers?basis=${basis}`}>Export CSV</a>
        </div>
      </div>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 16 }}>
        <section className="card" style={{ flex: "1 1 340px", padding: 18 }}>
          <div style={{ fontWeight: 600 }}>How to read this table</div>
          <div className="muted" style={{ marginTop: 6 }}>Variance is billed minus expected. A positive number is over-billed, a negative number is under-billed. Prepaid annual platform fees show the day-based October allocation (annual fee × days ÷ 365), not a new charge.</div>
        </section>
        <section className="card" style={{ flex: "1 1 340px", padding: 18 }}>
          <div style={{ fontWeight: 600 }}>Not netted</div>
          <div className="muted" style={{ marginTop: 6 }}>Platform and usage variances stay separate, customers are never offset against each other, and unverified usage is never assigned to a customer by elimination.</div>
        </section>
      </div>
    </div>
  );
}
