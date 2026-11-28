import { rpc, fail } from "@/lib/admin";

const ALLOWED = ["draft", "more_info_requested", "valid_explanation_marked", "approved"];

// Records (or resets) a decision on a finding; every change is also appended to the decision history.
export async function POST(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const { decision, by } = await req.json().catch(() => ({ decision: "", by: "" }));
  if (!ALLOWED.includes(decision)) return Response.json({ error: "Unknown decision" }, { status: 400 });
  try { await rpc("ui_record_finding_decision", { p_display_id: id, p_decision: decision, p_by: by ?? null }); return Response.json({ ok: true }); }
  catch (e) { return fail(e); }
}
