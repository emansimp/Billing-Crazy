"use client";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";

export default function ApproveBar({ approved, entries, canApprove }: { approved: number; entries: number; canApprove: boolean }) {
  const router = useRouter();
  const [by, setBy] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  useEffect(() => { try { setBy(localStorage.getItem("reviewer") ?? ""); } catch { /* optional */ } }, []);
  const all = entries > 0 && approved >= entries;
  async function go(path: string, body: unknown) {
    setBusy(true); setMsg(null);
    try { localStorage.setItem("reviewer", by); } catch { /* optional */ }
    const res = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
    const j = await res.json().catch(() => ({}));
    setBusy(false);
    if (!res.ok) setMsg(j.error ?? "Could not save"); else { setMsg("Saved"); router.refresh(); }
  }
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
        <input value={by} onChange={(e) => setBy(e.target.value)} placeholder="Approver name (optional)" aria-label="Approver name" style={{ padding: "8px 10px", border: "1px solid #C9CFD8", borderRadius: 6, fontFamily: "inherit", fontSize: 13, width: 200 }} />
        <button className="btn btn-p" type="button" disabled={busy || all || !canApprove} onClick={() => go("/api/journal/approve", { by })}>{all ? "Entries approved" : "Approve entries as Controller"}</button>
        {approved > 0 && <button className="btn" type="button" disabled={busy} onClick={() => go("/api/journal/revoke", {})}>Revoke approval</button>}
      </div>
      <div className="muted" style={{ fontSize: 12 }}>{approved} of {entries} entries approved. Changing a treatment withdraws that entry&apos;s approval. Nothing is posted from this app.</div>
      {msg && <div className="muted" style={{ fontSize: 12 }} role="status">{msg}</div>}
    </div>
  );
}
