"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";

export default function ResetDemo() {
  const router = useRouter();
  const [msg, setMsg] = useState<string | null>(null);
  async function go() {
    if (!window.confirm("Reset demo state? This clears finding decisions, treatment overrides and entry approvals. Source data and run history are kept.")) return;
    const res = await fetch("/api/demo/reset", { method: "POST" }); const j = await res.json().catch(() => ({}));
    if (!res.ok) setMsg(j.error ?? "Could not reset"); else { setMsg("Demo state reset"); router.refresh(); }
  }
  return <span><button className="btn" type="button" onClick={go} style={{ fontSize: 12, padding: "5px 10px" }}>Reset demo state</button> {msg && <span className="muted" style={{ fontSize: 12 }}>{msg}</span>}</span>;
}
