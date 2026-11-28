"use client";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";

type D = "draft" | "more_info_requested" | "valid_explanation_marked" | "approved";
export default function DecisionButtons({ displayId, decision }: { displayId: string; decision: string }) {
  const [busy, setBusy] = useState<D | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const [by, setBy] = useState("");
  const router = useRouter();
  useEffect(() => { try { setBy(localStorage.getItem("reviewer") ?? ""); } catch { /* optional */ } }, []);
  async function save(d: D) {
    setBusy(d); setMsg(null);
    try { localStorage.setItem("reviewer", by); } catch { /* optional */ }
    const res = await fetch(`/api/findings/${displayId}/decision`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ decision: d, by }) });
    const j = await res.json().catch(() => ({}));
    setBusy(null);
    if (!res.ok) setMsg(j.error ?? "Could not save the decision"); else { setMsg(d === "draft" ? "Reset to Draft" : "Saved"); router.refresh(); }
  }
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 6, alignItems: "flex-end" }}>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 8, justifyContent: "flex-end" }}>
        <button className="btn" type="button" disabled={busy !== null} onClick={() => save("more_info_requested")}>Request more information</button>
        <button className="btn" type="button" disabled={busy !== null} onClick={() => save("valid_explanation_marked")}>Mark as valid explanation</button>
        <button className="btn btn-p" type="button" disabled={busy !== null || decision === "approved"} onClick={() => save("approved")}>Approve recommendation</button>
      </div>
      <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap", justifyContent: "flex-end" }}>
        <input value={by} onChange={(e) => setBy(e.target.value)} placeholder="Your name (optional)" aria-label="Your name" style={{ padding: "6px 8px", border: "1px solid #C9CFD8", borderRadius: 6, fontFamily: "inherit", fontSize: 12, width: 160 }} />
        <button className="btn" type="button" disabled={busy !== null || decision === "draft"} onClick={() => save("draft")} style={{ padding: "6px 10px", fontSize: 12 }}>Reset to Draft</button>
      </div>
      {msg && <div className="muted" style={{ fontSize: 12 }} role="status">{msg}</div>}
    </div>
  );
}
