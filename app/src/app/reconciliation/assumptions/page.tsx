import { view } from "@/lib/db";
import { Chip } from "@/components/Chip";

export const dynamic = "force-dynamic";

export default async function Assumptions() {
  const [open, ass]: any = await Promise.all([view("ui_open_items", "select=*"), view("ui_assumptions", "select=*")]);
  const openCount = open.filter((o: any) => o.status === "Open").length;
  return (
    <div style={{ padding: "16px 32px 32px", display: "flex", flexDirection: "column", gap: 20 }}>
      <section className="card">
        <div style={{ padding: "16px 20px", borderBottom: "1px solid #E2E5EA", display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: 8 }}>
          <h2 style={{ margin: 0, fontSize: 17 }}>Open items</h2><Chip tone="info">{openCount} open</Chip>
        </div>
        <div style={{ overflowX: "auto" }}><table className="t">
          <thead><tr><th>Ref</th><th>Item</th><th>What we know</th><th>What is missing</th><th>Exposure</th><th>Owner</th><th>Status</th></tr></thead>
          <tbody>{open.map((o: any) => (
            <tr key={o.ref}><td>{o.ref}</td><td style={{ fontWeight: 600, minWidth: 140 }}>{o.item}</td><td style={{ minWidth: 220 }}>{o.what_we_know}</td><td style={{ minWidth: 200 }}>{o.what_is_missing}</td><td style={{ minWidth: 200 }}>{o.exposure}</td><td>{o.owner}</td>
              <td><Chip tone={o.status === "Resolved" ? "ok" : "info"}>{o.status}</Chip></td></tr>
          ))}</tbody>
        </table></div>
      </section>
      <section className="card">
        <div style={{ padding: "16px 20px", borderBottom: "1px solid #E2E5EA" }}>
          <h2 style={{ margin: 0, fontSize: 17 }}>Assumptions and basis</h2>
          <div className="muted" style={{ fontSize: 12, marginTop: 2 }}>Each rule is stored in /semantic (policies) with its source reference.</div>
        </div>
        <div style={{ overflowX: "auto" }}><table className="t">
          <thead><tr><th>Ref</th><th>Assumption</th><th>Source</th><th>Status</th></tr></thead>
          <tbody>{ass.map((a: any) => <tr key={a.ref}><td>{a.ref}</td><td>{a.assumption}</td><td>{a.source}</td><td><Chip tone={a.status === "Basis chosen" ? "blue" : a.status === "Policy" ? "gray" : "ok"}>{a.status}</Chip></td></tr>)}</tbody>
        </table></div>
      </section>
    </div>
  );
}
