import Link from "next/link";
import { view, one } from "@/lib/db";
import { money } from "@/lib/format";
import { Chip } from "@/components/Chip";

export const dynamic = "force-dynamic";
const tone: Record<string, "ok" | "info" | "err"> = { pass: "ok", warning: "info", pending: "info", fail: "err" };
const word: Record<string, string> = { pass: "Pass", warning: "Warning", pending: "Pending", fail: "Fail" };

export default async function ExportPreview() {
  const [checks, lines, coa, sum]: any = await Promise.all([view("ui_export_checks"), view("ui_export_lines", "select=*&order=external_id,line_order,side_order"), view("ui_coa", "select=*&order=account_number"), one("ui_je_summary")]);
  const blocked = checks.some((c: any) => c.status === "fail");
  const approved = sum && sum.entries > 0 && Number(sum.approved_entries) >= Number(sum.entries);
  const ids = new Set(lines.map((l: any) => l.external_id));
  return (
    <>
      <div style={{ padding: "20px 32px 0" }}>
        <Link href="/journal" style={{ fontSize: 13 }}>Back to entries</Link>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 16, justifyContent: "space-between", alignItems: "flex-end", marginTop: 8 }}>
          <div>
            <h1 style={{ margin: 0, fontSize: 26, fontWeight: 700 }}>NetSuite journal export</h1>
            <div className="muted" style={{ marginTop: 4 }}>{ids.size} entries, {lines.length} lines, posting period {lines[0]?.posting_period}. File only, nothing is sent to NetSuite.</div>
          </div>
          <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
            <Chip tone={approved ? "ok" : "info"}>{approved ? "Approved" : "Unlocks after Controller approval"}</Chip>
            {approved && !blocked ? <a className="btn btn-p" href="/api/export/journal">Download CSV</a> : <button className="btn" disabled>Download CSV</button>}
          </div>
        </div>
      </div>

      <div style={{ padding: "20px 32px 32px", display: "flex", flexDirection: "column", gap: 20 }}>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 16, alignItems: "flex-start" }}>
          <section className="card" style={{ flex: "2 1 460px", padding: 20 }}>
            <h2 style={{ margin: "0 0 8px", fontSize: 16 }}>Pre-export checks</h2>
            {checks.map((c: any) => (
              <div key={c.check_name} className="step"><div><Chip tone={tone[c.status]}>{word[c.status]}</Chip></div><div><div style={{ fontWeight: 600 }}>{c.check_name}</div><div className="muted">{c.detail}</div></div></div>
            ))}
          </section>
          <section className="card" style={{ flex: "1 1 320px", padding: 20 }}>
            <h2 style={{ margin: "0 0 8px", fontSize: 16 }}>File settings</h2>
            <table className="t"><tbody>
              <tr><td>Format</td><td>NetSuite journal CSV (a generic CSV is also available from the download link: <a href="/api/export/journal?format=generic">generic</a>). Excel workbook is not built.</td></tr>
              <tr><td>Account column</td><td>Account number and name. Internal IDs are not in the supplied files.</td></tr>
              <tr><td>Subsidiary</td><td>Omitted: single entity.</td></tr>
            </tbody></table>
            <div className="muted" style={{ fontSize: 12, marginTop: 8 }}>The file layout follows NetSuite&apos;s journal entry CSV import. Final column mapping is confirmed against your NetSuite import map.</div>
          </section>
        </div>

        <section className="card">
          <div style={{ padding: "16px 20px", borderBottom: "1px solid #E2E5EA" }}><h2 style={{ margin: 0, fontSize: 16 }}>Chart of accounts used</h2><div className="muted" style={{ fontSize: 12 }}>Stored in /semantic/chart_of_accounts.v1.yaml. Edit there, not here.</div></div>
          <table className="t"><thead><tr><th>Account</th><th>Name</th><th>Status</th><th>In this file</th></tr></thead>
            <tbody>{coa.map((a: any) => <tr key={a.account_number}><td>{a.account_number}</td><td>{a.account_name}</td><td><Chip tone={a.placeholder ? "info" : "ok"}>{a.status}</Chip></td><td>{a.used_in_export ? "Yes" : <span className="muted">No</span>}</td></tr>)}</tbody></table>
        </section>

        <section className="card">
          <div style={{ padding: "16px 20px", borderBottom: "1px solid #E2E5EA" }}><h2 style={{ margin: 0, fontSize: 16 }}>File preview</h2><div className="mono muted">relaycloud_oct2026_adjustments_netsuite.csv · every line repeats its entry&apos;s External ID</div></div>
          <div style={{ overflowX: "auto" }}><table className="t">
            <thead><tr><th>External ID</th><th>Date</th><th>Posting Period</th><th>Journal Entry - Line: Account</th><th className="num">Debit</th><th className="num">Credit</th><th>Memo</th><th>Name</th></tr></thead>
            <tbody>
              {lines.map((l: any, i: number) => (
                <tr key={i}><td>{l.external_id}</td><td>{l.date}</td><td>{l.posting_period}</td><td>{l.account_label} {l.account_is_placeholder && <span className="chip c-info">PLACEHOLDER</span>}</td><td className="num">{money(l.debit)}</td><td className="num">{money(l.credit)}</td><td style={{ maxWidth: 380 }}>{l.memo}</td><td>{l.name}</td></tr>
              ))}
              <tr style={{ background: "#F8F9FB", fontWeight: 600 }}><td colSpan={4}>Totals (shown for review, not written to the file)</td><td className="num">{money(sum?.debits)}</td><td className="num">{money(sum?.credits)}</td><td colSpan={2}></td></tr>
            </tbody>
          </table></div>
          <div className="muted" style={{ padding: "10px 20px", fontSize: 12 }}>The totals row is shown for review and is not written to the file. A total row in an import file would be read as another journal line. Lines carry either a debit or a credit, never a zero in the other column.</div>
        </section>
      </div>
    </>
  );
}
