"use client";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { money } from "@/lib/format";

type Opt = { option_treatment: string; is_policy_default: boolean; requires_reason: boolean; debit_label: string | null; credit_label: string | null; warning: string | null; note: string; uses_placeholder_account: boolean };
const NAMES: Record<string, string> = { accrual: "Accrual (missed or overstated revenue)", contra: "Contra revenue (waived or credited)", writeoff: "Write-off (outside policy)", none: "No entry (already in the accrual)" };

export default function TreatmentRow({ line, options }: { line: any; options: Opt[] }) {
  const router = useRouter();
  const [sel, setSel] = useState<string>(line.selected_treatment);
  const [reason, setReason] = useState<string>(line.override_reason ?? "");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const [by, setBy] = useState("");
  useEffect(() => { setSel(line.selected_treatment); setReason(line.override_reason ?? ""); }, [line.selected_treatment, line.override_reason]);
  useEffect(() => { try { setBy(localStorage.getItem("reviewer") ?? ""); } catch { /* optional */ } }, []);

  const chosen = options.find((o) => o.option_treatment === sel);
  const def = options.find((o) => o.is_policy_default);
  const isOverride = !!chosen && !!def && chosen.option_treatment !== def.option_treatment;
  const dirty = sel !== line.selected_treatment || (isOverride && reason !== (line.override_reason ?? ""));

  async function call(body: Record<string, unknown>) {
    setBusy(true); setMsg(null);
    const res = await fetch("/api/journal/treatment", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ line_id: line.line_id, by, ...body }) });
    const j = await res.json().catch(() => ({}));
    setBusy(false);
    if (!res.ok) setMsg(j.error ?? "Could not save"); else { setMsg("Saved"); router.refresh(); }
  }
  function onChange(v: string) {
    setSel(v); setMsg(null);
    if (def && v === def.option_treatment && line.treatment_overridden) call({ clear: true });   // back to the policy default: no reason needed
  }
  const fixed = line.fixed_by_policy;
  return (
    <>
      <tr>
        <td style={{ minWidth: 220 }}><div style={{ fontWeight: 600 }}>{line.adjustment_label}</div><div className="muted" style={{ fontSize: 12 }}>{line.calc_basis}</div></td>
        <td style={{ minWidth: 230 }}>
          {fixed ? <span className="chip c-gray">Fixed by policy</span> : (
            <select aria-label={`Treatment for ${line.external_id}`} value={sel} disabled={busy} onChange={(e) => onChange(e.target.value)} style={{ padding: "7px 8px", border: "1px solid #C9CFD8", borderRadius: 6, fontFamily: "inherit", fontSize: 13, width: "100%", maxWidth: 330 }}>
              {options.map((o) => <option key={o.option_treatment} value={o.option_treatment}>{NAMES[o.option_treatment] ?? o.option_treatment}</option>)}
            </select>
          )}
          {!fixed && chosen && <div className="muted" style={{ fontSize: 11, marginTop: 4 }}>{chosen.is_policy_default ? "Policy default. " : ""}{chosen.note}</div>}
        </td>
        <td>{(fixed ? line.debit_label : chosen?.debit_label) ?? <span className="muted">No entry</span>}</td>
        <td>{(fixed ? line.credit_label : chosen?.credit_label) ?? <span className="muted">No entry</span>}</td>
        <td className="num">{(fixed || chosen?.debit_label) ? money(line.amount) : <span className="muted">{money(line.amount)} reference</span>}</td>
      </tr>
      {!fixed && (isOverride || line.treatment_overridden) && (
        <tr><td colSpan={5} style={{ background: "#FFFBF0" }}>
          <div style={{ fontWeight: 600, marginBottom: 4 }}>Override of policy default</div>
          {chosen?.warning && <div style={{ color: "#8F2D0F", marginBottom: 6 }}>{chosen.warning}</div>}
          {chosen?.uses_placeholder_account && <div style={{ color: "#6B4A00", marginBottom: 6 }}>This treatment uses a PLACEHOLDER account (not in the supplied chart of accounts). Map it to a real NetSuite account before import.</div>}
          {sel === "writeoff" && <div style={{ color: "#8F2D0F", marginBottom: 6 }}>Write-off is not a treatment in the exercise policy. It needs explicit Controller approval before this entry can be exported, and it blocks the export check until removed.</div>}
          <label className="lbl" htmlFor={`why-${line.line_id}`}>Reason (required)</label>
          <textarea id={`why-${line.line_id}`} value={reason} onChange={(e) => setReason(e.target.value)} rows={2} placeholder="Why is the policy default not right for this line?" style={{ display: "block", width: "100%", boxSizing: "border-box", marginTop: 4, padding: 8, border: `1px solid ${reason.trim() ? "#C9CFD8" : "#E0A18C"}`, borderRadius: 6, fontFamily: "inherit", fontSize: 13 }} />
          <div style={{ marginTop: 8, display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
            <button className="btn btn-p" type="button" disabled={busy || !reason.trim() || !dirty} onClick={() => call({ treatment: sel, reason })}>Apply override</button>
            {line.treatment_overridden && <button className="btn" type="button" disabled={busy} onClick={() => { setSel(def!.option_treatment); call({ clear: true }); }}>Return to policy default</button>}
            {!reason.trim() && <span className="muted" style={{ fontSize: 12 }}>The override is not applied until a reason is entered.</span>}
          </div>
        </td></tr>
      )}
      {msg && <tr><td colSpan={5} className="muted" style={{ fontSize: 12 }} role="status">{msg}</td></tr>}
    </>
  );
}
