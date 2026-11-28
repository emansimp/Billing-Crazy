import Link from "next/link";
import { view, one } from "@/lib/db";
import { Chip } from "@/components/Chip";

export const dynamic = "force-dynamic";
// Bar positions (left/width as percent of the Sep 1 - Nov 30 range) are computed in SQL; this page only draws them.
const COL: Record<string, { bg: string; fg: string }> = { platform: { bg: "#DCE6FB", fg: "#1B3A8C" }, usage: { bg: "#E1F2EC", fg: "#14594A" } };

export default async function Coverage({ searchParams }: { searchParams: Promise<{ all?: string }> }) {
  const { all } = await searchParams;
  const [meta, bars]: any = await Promise.all([one("ui_coverage_meta"), view("ui_coverage", "select=*&order=customer,row_order,left_pct")]);
  const flagged = new Set(bars.filter((b: any) => b.customer_finding_ids).map((b: any) => b.customer));
  const rows: { key: string; customer: string; label: string; bars: any[] }[] = [];
  for (const b of bars) {
    if (!all && !flagged.has(b.customer)) continue;
    const key = `${b.customer}|${b.row_order}`;
    let r = rows.find((x) => x.key === key);
    if (!r) { r = { key, customer: b.customer, label: b.bar_kind === "credit_note" ? "Usage" : b.row_label, bars: [] }; rows.push(r); }
    if (b.bar_kind !== "credit_note" && b.row_order === 1) r.label = b.row_label;
    r.bars.push(b);
  }
  return (
    <div style={{ padding: "16px 32px 32px", display: "flex", flexDirection: "column", gap: 16 }}>
      <div className="muted">Which invoice covers which service dates. Billing periods and service months are not the same thing.</div>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 12, alignItems: "center", justifyContent: "space-between" }}>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 8, alignItems: "center" }}>
          <span className="chip" style={{ background: COL.platform.bg, color: COL.platform.fg }}>Platform invoice period</span>
          <span className="chip" style={{ background: COL.usage.bg, color: COL.usage.fg }}>Usage invoice service period</span>
          <span className="chip c-info">October 2026</span><span className="chip c-blue">Finding</span><span className="chip c-err">Close cutoff, {meta?.cutoff_label}</span>
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          <Link href="/invoices/coverage" className={`btn${!all ? " btn-p" : ""}`}>Customers with findings</Link>
          <Link href="/invoices/coverage?all=1" className={`btn${all ? " btn-p" : ""}`}>All customers</Link>
        </div>
      </div>
      <section className="card" style={{ padding: 16, overflowX: "auto" }}>
        <div style={{ minWidth: 820 }}>
          <div style={{ display: "grid", gridTemplateColumns: "230px 1fr", gap: 12, marginBottom: 6 }}>
            <div className="lbl">Customer and invoice type</div>
            <div style={{ position: "relative", height: 22 }}>
              {[["September 2026", 0], ["October 2026", meta?.october_left_pct], ["November 2026", meta?.november_left_pct]].map(([l, left]) => (
                <div key={String(l)} className="lbl" style={{ position: "absolute", left: `${left}%` }}>{l}</div>
              ))}
            </div>
          </div>
          {rows.map((r) => (
            <div key={r.key} style={{ display: "grid", gridTemplateColumns: "230px 1fr", gap: 12, alignItems: "center", padding: "6px 0", borderTop: "1px solid #EEF0F3" }}>
              <div><div style={{ fontWeight: 600 }}>{r.customer}</div><div className="muted" style={{ fontSize: 12 }}>{r.label}</div></div>
              <div style={{ position: "relative", height: r.bars.some((b: any) => b.label.length > 70) ? 46 : 34 }}>
                <div style={{ position: "absolute", left: `${meta?.october_left_pct}%`, width: `${meta?.october_width_pct}%`, top: 0, bottom: 0, background: "#FFF8E1", opacity: 0.8 }} />
                <div style={{ position: "absolute", left: `${meta?.cutoff_pct}%`, top: 0, bottom: 0, borderLeft: "2px dashed #B6381A" }} title={`Close cutoff ${meta?.cutoff_label}`} />
                {r.bars.map((b: any, i: number) => b.bar_kind === "credit_note" ? (
                  <div key={i} title={b.label} style={{ position: "absolute", left: `${b.left_pct}%`, top: 0, fontSize: 11, color: "#8F2D0F", whiteSpace: "nowrap" }}>▼ {b.label}</div>
                ) : (
                  <div key={i} title={b.label} style={{ position: "absolute", left: `${b.left_pct}%`, width: `calc(${b.width_pct}% - 2px)`, top: 14, minHeight: 20, background: COL[b.bar_kind].bg, color: COL[b.bar_kind].fg, borderRadius: 4, padding: "2px 6px", fontSize: 11, overflow: "hidden", boxSizing: "border-box", lineHeight: 1.25, border: b.has_finding ? "1.5px solid #1B4DB8" : "none" }}>
                    {b.label}{b.finding_ids && b.finding_ids.split(", ").map((f: string) => <span key={f}> <Link href={`/findings/${f}`} style={{ color: "#1B4DB8", fontWeight: 700 }}>{f}</Link></span>)}
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      </section>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 16 }}>
        {[["Usage is billed in arrears", "The Nov 1 usage invoice is for October service. The Oct 1 usage invoice is for September. Only the Nov 1 invoices are October billing for usage."],
          ["Prepaid and 15th-anchor platform", "An annual invoice is not billed again in October, but October revenue still exists. A 15th-anchor customer has two partial October periods, each allocated by days."],
          ["Invoice amount is not revenue", "A full invoice crossing October does not equal October revenue. Revenue follows service days ÷ 365, shown on the Journal entries and customer detail screens."]]
          .map(([t, s]) => <section key={t} className="card" style={{ flex: "1 1 300px", padding: 18 }}><div style={{ fontWeight: 600 }}>{t}</div><div className="muted" style={{ marginTop: 6 }}>{s}</div></section>)}
      </div>
    </div>
  );
}
