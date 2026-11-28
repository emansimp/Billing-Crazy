import { NextResponse } from "next/server";

// Server-side write: records a decision on a finding. Needs SUPABASE_SERVICE_ROLE_KEY (set in Vercel); the browser role cannot write.
const URL = process.env.SUPABASE_URL ?? "https://pejthvjkkyiuwcleywbf.supabase.co";
const ALLOWED = ["more_info_requested", "valid_explanation_marked", "approved"];

export async function POST(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const { decision } = await req.json().catch(() => ({ decision: "" }));
  if (!ALLOWED.includes(decision)) return NextResponse.json({ error: "Unknown decision" }, { status: 400 });
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return NextResponse.json({ error: "Saving decisions needs the server key (SUPABASE_SERVICE_ROLE_KEY), which is not configured on this deployment." }, { status: 503 });
  const res = await fetch(`${URL}/rest/v1/rpc/ui_record_finding_decision`, {
    // Legacy service_role keys are JWTs (sent as apikey + Bearer); new sb_secret_ keys are not JWTs and go in apikey only.
    method: "POST", headers: { apikey: key, ...(key.startsWith("sb_secret_") ? {} : { Authorization: `Bearer ${key}` }), "Content-Type": "application/json" }, body: JSON.stringify({ p_display_id: id, p_decision: decision }),
  });
  if (!res.ok) return NextResponse.json({ error: `Could not save (${res.status})` }, { status: 502 });
  return NextResponse.json({ ok: true });
}
