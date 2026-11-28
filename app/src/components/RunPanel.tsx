"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";

export default function RunPanel({ lastRun }: { lastRun: string }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  async function run() {
    setBusy(true); setMsg("Running: recomputing every snapshot from the loaded data (about 30 seconds)…");
    const res = await fetch("/api/run", { method: "POST" });
    const j = await res.json().catch(() => ({}));
    setBusy(false);
    if (!res.ok) setMsg(j.error ?? "The run failed"); else { setMsg(`Run #${j.run_id} complete. All screens now reflect run #${j.run_id}.`); router.refresh(); }
  }
  return (
    <div>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 12, alignItems: "flex-end", marginTop: 10 }}>
        <div><div className="lbl">Period</div>
          <select aria-label="Period" defaultValue="oct" style={{ marginTop: 4, padding: "8px 10px", border: "1px solid #C9CFD8", borderRadius: 6, fontFamily: "inherit", fontSize: 13 }}>
            <option value="oct">October 2026</option><option value="nov" disabled>November 2026 (out of scope)</option>
          </select></div>
        <button className="btn" type="button" disabled title="This build loads files with scripts/load_raw.py; browser upload is not built">Upload month&apos;s files</button>
        <button className="btn btn-p" type="button" disabled={busy} onClick={run}>{busy ? "Running…" : "Run reconciliation"}</button>
      </div>
      <div className="muted" style={{ marginTop: 8, fontSize: 12 }} role="status">{msg ?? lastRun}</div>
    </div>
  );
}
