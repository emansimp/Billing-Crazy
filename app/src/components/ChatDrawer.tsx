"use client";
import { useEffect, useRef, useState } from "react";

type Msg = { role: "user" | "ai"; text: string; meta?: string; warn?: string[] };
const EXAMPLES = ["What is wrong with Cedar Harbor Labs?", "Explain F-02", "What are the totals expected vs billed?", "Which controls are open?", "What is the unassigned workspace?", "Show invoice RC-261101-639373-U"];

export default function ChatDrawer() {
  const [open, setOpen] = useState(false);
  const [q, setQ] = useState("");
  const [busy, setBusy] = useState(false);
  const [msgs, setMsgs] = useState<Msg[]>([]);
  const [configured, setConfigured] = useState(false);
  const end = useRef<HTMLDivElement>(null);
  useEffect(() => { fetch("/api/ai/status").then((r) => r.json()).then((s) => setConfigured(!!s.configured)).catch(() => undefined); }, []);
  useEffect(() => { end.current?.scrollIntoView({ block: "end" }); }, [msgs, busy]);

  async function ask(text: string) {
    const question = text.trim(); if (!question || busy) return;
    setMsgs((m) => [...m, { role: "user", text: question }]); setQ(""); setBusy(true);
    try {
      const res = await fetch("/api/ai/chat", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ question }) });
      const r = await res.json();
      const body = r.text ?? r.fallbackText ?? r.error ?? "No answer";
      const meta = r.blocked ? "Output blocked by the amount check; showing the guard-checked template answer" : r.provider === "template" ? "AI not configured: answered from fixed lookups of the app's data" : `Answered by ${r.provider}`;
      setMsgs((m) => [...m, { role: "ai", text: body, meta: `${meta}${r.checks ? ` · ${r.checks.amounts} amounts and ${r.checks.citations} citations checked` : ""}`, warn: r.blocked ? r.warnings : undefined }]);
    } catch { setMsgs((m) => [...m, { role: "ai", text: "The question could not be answered." }]); }
    setBusy(false);
  }
  return (
    <>
      <button type="button" className="btn btn-p" onClick={() => setOpen((o) => !o)} aria-expanded={open} style={{ position: "fixed", right: 20, bottom: 52, zIndex: 20, boxShadow: "0 2px 8px rgba(0,0,0,.2)" }}>{open ? "Close chat" : "Ask the reconciliation"}</button>
      {open && (
        <div role="dialog" aria-label="Ask the reconciliation" style={{ position: "fixed", right: 20, bottom: 96, width: 380, maxWidth: "calc(100vw - 40px)", height: 480, maxHeight: "calc(100vh - 140px)", background: "#fff", border: "1px solid #C9CFD8", borderRadius: 10, boxShadow: "0 8px 24px rgba(0,0,0,.2)", zIndex: 20, display: "flex", flexDirection: "column" }}>
          <div style={{ padding: "10px 14px", borderBottom: "1px solid #E2E5EA" }}>
            <div style={{ fontWeight: 700 }}>Ask the reconciliation</div>
            <div className="muted" style={{ fontSize: 12 }}>Limited to the app&apos;s data. {configured ? "A real AI provider phrases the answer." : "AI not configured: answers come from fixed lookups."} Figures always come from the calculation.</div>
          </div>
          <div style={{ flex: 1, overflowY: "auto", padding: 12, display: "flex", flexDirection: "column", gap: 10 }}>
            {msgs.length === 0 && <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>{EXAMPLES.map((e) => <button key={e} className="btn" type="button" style={{ fontSize: 12, padding: "5px 8px" }} onClick={() => ask(e)}>{e}</button>)}</div>}
            {msgs.map((m, i) => (
              <div key={i} style={{ alignSelf: m.role === "user" ? "flex-end" : "flex-start", maxWidth: "92%", background: m.role === "user" ? "#E8EEFB" : "#F4F6F8", borderRadius: 8, padding: "8px 10px", whiteSpace: "pre-wrap", fontSize: 13 }}>
                {m.text}
                {m.warn && <ul style={{ color: "#8F2D0F", margin: "6px 0 0 16px" }}>{m.warn.map((w, k) => <li key={k}>{w}</li>)}</ul>}
                {m.meta && <div className="muted" style={{ fontSize: 11, marginTop: 4 }}>{m.meta}</div>}
              </div>
            ))}
            {busy && <div className="muted" style={{ fontSize: 12 }}>Looking up the data…</div>}
            <div ref={end} />
          </div>
          <form onSubmit={(e) => { e.preventDefault(); ask(q); }} style={{ display: "flex", gap: 6, padding: 10, borderTop: "1px solid #E2E5EA" }}>
            <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Ask about a customer, finding, invoice…" aria-label="Question" maxLength={300} style={{ flex: 1, padding: "8px 10px", border: "1px solid #C9CFD8", borderRadius: 6, fontFamily: "inherit", fontSize: 13 }} />
            <button className="btn btn-p" type="submit" disabled={busy || !q.trim()}>Ask</button>
          </form>
        </div>
      )}
    </>
  );
}
