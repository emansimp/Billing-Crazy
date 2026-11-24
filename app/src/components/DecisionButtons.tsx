"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";

type D = "more_info_requested" | "valid_explanation_marked" | "approved";
export default function DecisionButtons({ displayId, decision }: { displayId: string; decision: string }) {
  const [busy, setBusy] = useState<D | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const router = useRouter();
  async function save(d: D) {
    setBusy(d); setMsg(null);
    const res = await fetch(`/api/findings/${displayId}/decision`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ decision: d }) });
    const j = await res.json().catch(() => ({}));
    setBusy(null);
    if (!res.ok) setMsg(j.error ?? "Could not save the decision");
    else { setMsg("Saved"); router.refresh(); }
  }
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 6, alignItems: "flex-end" }}>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
        <button className="btn" type="button" disabled={busy !== null} onClick={() => save("more_info_requested")}>Request more information</button>
        <button className="btn" type="button" disabled={busy !== null} onClick={() => save("valid_explanation_marked")}>Mark as valid explanation</button>
        <button className="btn btn-p" type="button" disabled={busy !== null || decision === "approved"} onClick={() => save("approved")}>Approve recommendation</button>
      </div>
      {msg && <div className="muted" style={{ fontSize: 12 }} role="status">{msg}</div>}
    </div>
  );
}
