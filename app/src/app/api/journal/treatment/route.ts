import { after } from "next/server";
import { rpc, fail } from "@/lib/admin";

export const maxDuration = 60;

// Sets or clears the accounting treatment of one adjustment line. An override needs a reason (enforced again in the database).
// The journal page reads live views, so it updates immediately; the Close overview snapshots refresh right after the response.
export async function POST(req: Request) {
  const { line_id, treatment, reason, by, clear } = await req.json().catch(() => ({}));
  if (!line_id) return Response.json({ error: "line_id is required" }, { status: 400 });
  try {
    if (clear) await rpc("ui_clear_treatment", { p_line_id: line_id });
    else {
      if (!treatment) return Response.json({ error: "treatment is required" }, { status: 400 });
      if (!reason || !String(reason).trim()) return Response.json({ error: "A reason is required to override the policy default." }, { status: 400 });
      await rpc("ui_set_treatment", { p_line_id: line_id, p_treatment: treatment, p_reason: reason, p_by: by ?? null });
    }
    after(async () => { try { await rpc("ui_refresh_snapshots", { p_scope: "journal" }); } catch { /* snapshot refresh is best-effort */ } });
    return Response.json({ ok: true });
  } catch (e) { return fail(e); }
}
