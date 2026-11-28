import { view, one } from "@/lib/db";
import { Chip } from "@/components/Chip";

export const dynamic = "force-dynamic";
const label: Record<string, [string, "ok" | "info" | "err"]> = { pass: ["Pass", "ok"], pending: ["Open", "info"], fail: ["Fail", "err"] };

export default async function Controls() {
  const [rows, r]: any = await Promise.all([view("ui_controls", "select=*"), one("ui_readiness")]);
  const sorted = [...rows].sort((a: any, b: any) => a.control_id[0].localeCompare(b.control_id[0]) || Number(a.control_id.slice(1)) - Number(b.control_id.slice(1)));
  const groups = Array.from(new Set(sorted.map((c: any) => c.control_group)));
  return (
    <div style={{ padding: "16px 32px 32px", display: "flex", flexDirection: "column", gap: 16 }}>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 12 }}>
        <div className="card" style={{ padding: 16, minWidth: 220 }}><div className="lbl">Verified</div><div style={{ fontSize: 26, fontWeight: 700 }}>{r?.verified}</div><div className="muted">of {r?.total} checks</div></div>
        <div className="card" style={{ padding: 16, minWidth: 220 }}><div className="lbl">Failing</div><div style={{ fontSize: 26, fontWeight: 700 }}>{r?.failed}</div><div className="muted">computed on each run</div></div>
        <div className="card" style={{ padding: 16, minWidth: 220 }}><div className="lbl">Open</div><div style={{ fontSize: 26, fontWeight: 700 }}>{r?.pending}</div><div className="muted">{r?.pending_names}</div></div>
      </div>
      <div className="card" style={{ padding: 16 }}>
        <div style={{ fontWeight: 600 }}>Why this matters</div>
        <div className="muted" style={{ marginTop: 4 }}>Reconciliation totals only mean something if every source file is complete and tied out. Each check below shows what was expected, what was found, and where to look. A row count that matches the stated source count shows the extract is complete. It does not show that a commercially required invoice was actually issued; that is tested separately in the reconciliation.</div>
      </div>
      <section className="card"><div style={{ overflowX: "auto" }}>
        <table className="t">
          <thead><tr><th>Check</th><th>Expected</th><th>Found</th><th>Status</th><th>Source</th></tr></thead>
          <tbody>
            {groups.map((g: any) => (
              <>
                <tr key={`g-${g}`}><td colSpan={5} style={{ fontWeight: 700, background: "#F4F6F8" }}>{g}</td></tr>
                {sorted.filter((c: any) => c.control_group === g).map((c: any) => (
                  <tr key={c.control_id}>
                    <td><b>{c.control_id}</b> {c.control_name}</td><td>{c.expected}</td><td>{c.found}{c.status === "pending" && <div className="muted" style={{ fontSize: 11 }}>{c.detail}</div>}</td>
                    <td><Chip tone={label[c.status]?.[1] ?? "gray"}>{label[c.status]?.[0] ?? c.status}</Chip></td><td className="muted">{c.source}</td>
                  </tr>
                ))}
              </>
            ))}
          </tbody>
        </table>
      </div></section>
    </div>
  );
}
