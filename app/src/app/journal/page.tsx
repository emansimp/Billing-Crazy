import Link from "next/link";
import { view, one } from "@/lib/db";
import { money } from "@/lib/format";
import { Chip } from "@/components/Chip";
import TreatmentRow from "@/components/TreatmentRow";
import RunPanel from "@/components/RunPanel";
import ApproveBar from "@/components/ApproveBar";
import ResetDemo from "@/components/ResetDemo";

export const dynamic = "force-dynamic";
const when = (iso: string) => new Date(iso).toLocaleString("en-US", { timeZone: "America/Denver", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }) + " MT";

export default async function Journal() {
  const [entries, lines, options, sum, runs, manifest]: any = await Promise.all([
    view("ui_je_entries", "select=*&order=external_id"), view("ui_je_lines", "select=*&order=external_id,line_order"), view("ui_je_options", "select=*"),
    one("ui_je_summary"), view("ui_run_history", "select=*&order=run_id.desc"), view("load_manifest_check", "select=status"),
  ]);
  const last = runs[0];
  const allApproved = sum && sum.entries > 0 && Number(sum.approved_entries) >= Number(sum.entries);
  const rowsOk = manifest.length > 0 && manifest.every((m: any) => m.status === "PASS");
  const lastRunText = last ? `Last run: #${last.run_id}, ${when(last.finished_at)}` : "No run recorded";
  return (
    <>
      <div style={{ padding: "24px 32px 0", display: "flex", flexWrap: "wrap", gap: 16, alignItems: "flex-end", justifyContent: "space-between" }}>
        <div>
          <h1 style={{ margin: 0, fontSize: 26, fontWeight: 700 }}>Journal entries</h1>
          <div className="muted" style={{ marginTop: 4 }}>Proposed October 2026 entries for Controller approval. Nothing is posted from this app.</div>
        </div>
        <Chip tone={allApproved ? "ok" : "info"}>{allApproved ? "Approved by Controller" : "Awaiting Controller approval"}</Chip>
      </div>

      <div style={{ padding: "20px 32px 32px", display: "flex", flexDirection: "column", gap: 20 }}>
        <section className="card" style={{ padding: 20 }}>
          <div className="lbl">Run</div>
          <h2 style={{ margin: "4px 0 0", fontSize: 17, fontWeight: 600 }}>Run the reconciliation</h2>
          <div className="muted" style={{ marginTop: 4 }}>Recompute every figure in this app from the loaded data. Findings, entries and invoice views all refresh from the same run.</div>
          <RunPanel lastRun={lastRunText} />
          <div className="muted" style={{ marginTop: 10, fontSize: 12 }}>
            {last?.input_counts ? `${Object.keys(last.input_counts).filter((k) => !k.includes("(")).length} source files loaded. ` : ""}{rowsOk ? "Row counts match the stated source counts." : "Row counts do not all match the stated source counts: see Controls."} Engine version and semantic commit are recorded with each run.
          </div>
          <table className="t" style={{ marginTop: 12 }}>
            <thead><tr><th>Run</th><th>Period</th><th>When</th><th>Engine commit</th><th>Result</th></tr></thead>
            <tbody>{runs.map((r: any) => <tr key={r.run_id}><td>#{r.run_id}</td><td>{r.period}</td><td>{when(r.finished_at)}</td><td className="mono">{String(r.git_commit).slice(0, 7)}</td><td><Chip tone={r.result === "Complete" ? "ok" : "gray"}>{r.result}</Chip></td></tr>)}</tbody>
          </table>
        </section>

        <section>
          <h2 style={{ margin: "0 0 4px", fontSize: 17, fontWeight: 600 }}>Accounting treatment</h2>
          <div className="muted" style={{ marginBottom: 12 }}>Choose per adjustment line. Each line starts on the policy default. Changing it updates the accounts and requires a reason. Missed revenue can only be accrued. Contra revenue applies to credited or waived amounts. Write-off is outside the exercise policy. Accounts 4090 and 6900 are <b>placeholders</b>, not in the supplied chart of accounts.</div>
          <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
            {entries.map((e: any) => {
              const el = lines.filter((l: any) => l.external_id === e.external_id);
              return (
                <div key={e.external_id} className="card" id={e.external_id}>
                  <div style={{ padding: "14px 20px", borderBottom: "1px solid #E2E5EA", display: "flex", justifyContent: "space-between", flexWrap: "wrap", gap: 8 }}>
                    <div><b>{e.external_id}</b> · {e.customer} · <span className="muted">{e.title}</span></div>
                    <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
                      <span className="muted" style={{ fontSize: 12 }}>Posting period {e.posting_period}</span>
                      {e.display_id && <Link href={`/findings/${e.display_id}`}><span className="chip c-blue">{e.display_id}</span></Link>}
                      <Chip tone={e.status === "Approved" ? "ok" : "info"}>{e.status}</Chip>
                    </div>
                  </div>
                  <div style={{ overflowX: "auto" }}>
                    <table className="t">
                      <thead><tr><th>Adjustment</th><th>Treatment</th><th>Debit account</th><th>Credit account</th><th className="num">Amount</th></tr></thead>
                      <tbody>{el.map((l: any) => <TreatmentRow key={l.line_id} line={l} options={options.filter((o: any) => o.line_id === l.line_id)} />)}</tbody>
                    </table>
                  </div>
                </div>
              );
            })}
          </div>
        </section>

        <div style={{ display: "flex", flexWrap: "wrap", gap: 16 }}>
          <section className="card" style={{ flex: "1 1 360px", padding: 20 }}>
            <div className="lbl">Check</div>
            <table className="t" style={{ marginTop: 8 }}><tbody>
              <tr><td>Debits</td><td className="num">{money(sum?.debits)}</td></tr>
              <tr><td>Credits</td><td className="num">{money(sum?.credits)}</td></tr>
              <tr><td>Entries balanced</td><td className="num"><Chip tone={sum?.balanced ? "ok" : "err"}>{sum?.balanced ? "Yes" : "No"}</Chip></td></tr>
              <tr><td style={{ fontWeight: 600 }}>Net effect on October revenue</td><td className="num" style={{ fontWeight: 700 }}>{money(sum?.net_revenue_effect, { sign: true })}</td></tr>
              <tr><td className="muted">Usage revenue (4010)</td><td className="num muted">{money(sum?.usage_effect, { sign: true })}</td></tr>
              <tr><td className="muted">Platform revenue (4000)</td><td className="num muted">{money(sum?.platform_effect, { sign: true })}</td></tr>
              {Number(sum?.contra_effect) !== 0 && <tr><td className="muted">Contra revenue (4090, placeholder)</td><td className="num muted">{money(sum?.contra_effect, { sign: true })}</td></tr>}
              {Number(sum?.writeoff_effect) !== 0 && <tr><td className="muted">Write-off (6900, placeholder)</td><td className="num muted">{money(sum?.writeoff_effect, { sign: true })}</td></tr>}
            </tbody></table>
            <div className="muted" style={{ marginTop: 10, fontSize: 12 }}>The Meridian catch-up invoice is issued in November but the platform true-up is October service, so it is October revenue. A credit note reverses AR and unbilled usage in November without reducing revenue a second time. A billing correction is not an automatic revenue adjustment.</div>
            {Number(sum?.double_count_lines) > 0 && <div style={{ marginTop: 8, color: "#8F2D0F", fontSize: 12 }}>{sum.double_count_lines} line(s) carry a double-count warning: the October accrual already reflects the concession.</div>}
          </section>
          <section className="card" style={{ flex: "1 1 420px", padding: 20, display: "flex", flexDirection: "column", gap: 12 }}>
            <div className="lbl">Export</div>
            <div className="muted">Writes one balanced journal per entry in the NetSuite journal import layout, using the treatments chosen above. This build exports a file only; it does not connect to NetSuite.</div>
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
              <Link className="btn" href="/journal/export">Preview export</Link>
              {allApproved ? <a className="btn btn-p" href="/api/export/journal">Download CSV</a> : <button className="btn" disabled title="Unlocks after Controller approval">Download, after approval</button>}
            </div>
            <ApproveBar approved={Number(sum?.approved_entries ?? 0)} entries={Number(sum?.entries ?? 0)} canApprove={!!sum?.balanced && Number(sum?.writeoff_lines ?? 0) === 0} />
            {Number(sum?.writeoff_lines) > 0 && <div style={{ color: "#8F2D0F", fontSize: 12 }}>A write-off treatment is selected. Remove it to approve and export.</div>}
          </section>
        </div>
        <div><ResetDemo /></div>
      </div>
    </>
  );
}
