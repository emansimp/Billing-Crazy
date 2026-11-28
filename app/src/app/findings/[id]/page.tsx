import Link from "next/link";
import { notFound } from "next/navigation";
import { view, one } from "@/lib/db";
import { Chip, ClassChip } from "@/components/Chip";
import DecisionButtons from "@/components/DecisionButtons";

export const dynamic = "force-dynamic";

const decisionLabel: Record<string, string> = { draft: "Draft", more_info_requested: "More information requested", valid_explanation_marked: "Marked valid explanation", approved: "Approved" };

export default async function FindingDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const f: any = await one("ui_finding_detail", `select=*&display_id=eq.${encodeURIComponent(id)}`);
  if (!f) notFound();
  const fid = encodeURIComponent(f.finding_id);
  const [evidence, math, notes, action, sources] = await Promise.all([
    view("ui_finding_evidence", `select=*&finding_id=eq.${fid}&order=item_no`), view("ui_finding_math", `select=*&finding_id=eq.${fid}&order=step_no`),
    view("ui_finding_math_notes", `select=*&finding_id=eq.${fid}`), one("ui_finding_action", `select=*&finding_id=eq.${fid}`),
    view("ui_finding_sources", `select=*&finding_id=eq.${fid}&order=item_no`),
  ]);
  const note: any = notes[0]; const act: any = action;
  const live: any = await one("ui_finding_decisions", `select=*&finding_id=eq.${fid}`); // decisions are live; the rest is a snapshot
  const decision: string = live?.decision ?? "draft";
  const log: any[] = await view("ui_finding_decision_log", `select=*&finding_id=eq.${fid}&order=decided_at.desc&limit=10`);
  return (
    <>
      <div style={{ padding: "20px 32px 0" }}>
        <Link href="/" style={{ fontSize: 13 }}>Close overview</Link><span className="muted"> / Findings / {f.display_id}</span>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 16, justifyContent: "space-between", alignItems: "flex-start", marginTop: 8 }}>
          <div style={{ flex: "1 1 520px" }}>
            <h1 style={{ margin: 0, fontSize: 24, fontWeight: 700 }}>{f.display_id} · {f.title}</h1>
            <div className="muted" style={{ marginTop: 6 }}>
              {[f.netsuite_id && `NetSuite ${f.netsuite_id}`, f.stripe_customer && `Stripe ${f.stripe_customer}`, f.contract_ids && `Contract ${f.contract_ids}`, `Service period ${f.service_period}`].filter(Boolean).join(" · ")}
            </div>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 8, marginTop: 10 }}>
              <ClassChip cls={f.class} label={f.class_label} />
              <Chip tone="gray">{f.direction_label ? `${f.direction_label} ${f.stream}` : f.stream === "usage" ? "Usage" : "Platform"}</Chip>
              {f.has_billing_correction && <Chip tone="blue">Billing correction</Chip>}
              {f.has_october_adjustment && <Chip tone="blue">October accounting adjustment</Chip>}
              <Chip tone="info">{decisionLabel[decision] ?? decision}</Chip>
            </div>
          </div>
          <DecisionButtons displayId={f.display_id} decision={decision} />
        </div>
      </div>

      <div style={{ padding: "20px 32px 32px", display: "flex", flexDirection: "column", gap: 20 }}>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 16, alignItems: "flex-start" }}>
          <section className="card" style={{ flex: "1 1 340px", padding: 20 }}>
            <h2 style={{ margin: "0 0 4px", fontSize: 16, fontWeight: 600 }}>Evidence trail</h2>
            <div className="muted" style={{ fontSize: 12 }}>Every item links to its source row or page.</div>
            {evidence.map((e: any, i: number) => (
              <div className="step" key={e.item_no} style={i === evidence.length - 1 ? { borderBottom: 0 } : undefined}>
                <div className="stepn">{e.item_no}</div>
                <div>
                  <div style={{ fontWeight: 600 }}>{e.title} {e.badge && <span className="chip c-ok">{e.badge}</span>}</div>
                  <div>{e.body}</div>
                  <a className="src" href="#src" style={{ textDecoration: "underline" }}>{e.source_ref}</a>
                </div>
              </div>
            ))}
          </section>

          <section className="card" style={{ flex: "2 1 440px", padding: 20 }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
              <h2 style={{ margin: 0, fontSize: 16, fontWeight: 600 }}>Show the math</h2>
              <span className="chip c-ok">Computed in SQL</span>
            </div>
            <table className="t" style={{ marginTop: 10 }}>
              <thead><tr><th>Step</th><th>Calculation</th><th className="num">Result</th></tr></thead>
              <tbody>
                {math.map((m: any, i: number) => (
                  <tr key={`${m.step_no}-${i}`}>
                    <td style={i === math.length - 1 && math.length > 1 ? { fontWeight: 600 } : undefined}>{m.step}</td>
                    <td className="mono">{m.calculation}</td>
                    <td className="num" style={i === math.length - 1 && math.length > 1 ? { fontWeight: 700 } : undefined}>{m.result}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            {note && (
              <>
                <div style={{ marginTop: 14, padding: 12, borderRadius: 8, background: "#F4F6F8" }}>
                  <div style={{ fontWeight: 600, marginBottom: 4 }}>{note.heading}</div>
                  <div className="muted">{note.body}</div>
                </div>
                <div style={{ marginTop: 14, display: "flex", flexWrap: "wrap", gap: 8 }}>
                  <Chip tone="gray">{note.rounding_note}</Chip><Chip tone="gray">{note.source_rule}</Chip>
                </div>
              </>
            )}
          </section>

          <section className="card" style={{ flex: "1 1 340px", padding: 20, display: "flex", flexDirection: "column", gap: 14 }}>
            <div>
              <div className="lbl">Recommended action</div>
              <div style={{ marginTop: 6 }} dangerouslySetInnerHTML={{ __html: String(act?.action_text ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/(\$[\d,]+\.\d\d)/, "<b>$1</b>") }} />
              <div className="muted" style={{ marginTop: 6, fontSize: 12 }}>{act?.owner_line}</div>
            </div>
            <div style={{ borderTop: "1px solid #EEF0F3", paddingTop: 14 }}>
              <div className="lbl">October accounting effect</div>
              {String(f.accounting_effect ?? "").split(/ (?=The November)/).map((t: string, i: number) => <div key={i} className={i ? "muted" : undefined} style={{ marginTop: 6 }}>{t}</div>)}
              {f.entry_id && <div style={{ marginTop: 8 }}><Link href="/journal">View proposed entry {f.entry_id}</Link></div>}
            </div>
            <div style={{ borderTop: "1px solid #EEF0F3", paddingTop: 14 }}>
              <div className="lbl">Related</div>
              {act?.related_invoice && <div style={{ marginTop: 6 }}><Link href="/invoices">Invoice {act.related_invoice}</Link></div>}
              <div><Link href="/reconciliation">{f.customer} customer detail</Link></div>
            </div>
          </section>
        </div>

        <div style={{ display: "flex", flexWrap: "wrap", gap: 16, alignItems: "flex-start" }}>
          <section className="card" style={{ flex: "1 1 520px", padding: 20 }}>
            <div style={{ display: "flex", justifyContent: "space-between", gap: 12, flexWrap: "wrap", alignItems: "center" }}>
              <h2 style={{ margin: 0, fontSize: 16, fontWeight: 600 }}>Plain-language explanation</h2>
              <Chip tone="gray">Templated, AI provider not configured</Chip>
            </div>
            <div style={{ marginTop: 10, padding: 14, borderRadius: 8, background: "#F8F9FB", border: "1px dashed #C9CFD8" }}>{f.explanation}</div>
            <div style={{ marginTop: 12, display: "flex", flexWrap: "wrap", gap: 8 }}>
              <button className="btn" disabled title="AI not configured">Rewrite with AI</button>
              <button className="btn" disabled title="AI not configured">Draft request to Billing</button>
              <button className="btn" disabled title="AI not configured">Draft note to Controller</button>
            </div>
            <div className="muted" style={{ marginTop: 10, fontSize: 12 }}>Text is built from the finding data and the policy file in /semantic. Numbers always come from the calculation, never from the AI. Semantic layer version: commit <code>{process.env.VERCEL_GIT_COMMIT_SHA ? process.env.VERCEL_GIT_COMMIT_SHA.slice(0, 7) : "local build"}</code>.</div>
          </section>

          <section className="card" id="src" style={{ flex: "1 1 360px", minWidth: 0 }}>
            <div style={{ padding: "16px 20px", borderBottom: "1px solid #E2E5EA" }}><h2 style={{ margin: 0, fontSize: 16, fontWeight: 600 }}>Source documents</h2></div>
            <table className="t">
              <thead><tr><th>Source</th><th>Reference</th></tr></thead>
              <tbody>{sources.map((s: any) => <tr key={`${s.item_no}`}><td>{s.source}</td><td>{s.reference}</td></tr>)}</tbody>
            </table>
          </section>

          <section className="card" style={{ flex: "1 1 360px", minWidth: 0 }}>
            <div style={{ padding: "16px 20px", borderBottom: "1px solid #E2E5EA" }}><h2 style={{ margin: 0, fontSize: 16, fontWeight: 600 }}>Decision history</h2></div>
            {log.length === 0 ? <div className="muted" style={{ padding: 16 }}>No decisions recorded. Status is Draft.</div> : (
              <table className="t"><thead><tr><th>When</th><th>Decision</th><th>By</th></tr></thead>
                <tbody>{log.map((l: any, i: number) => <tr key={i}><td>{new Date(l.decided_at).toLocaleString("en-US", { timeZone: "America/Denver", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })} MT</td><td>{decisionLabel[l.decision] ?? l.decision}</td><td>{l.decided_by}</td></tr>)}</tbody></table>
            )}
          </section>
        </div>
      </div>
    </>
  );
}
