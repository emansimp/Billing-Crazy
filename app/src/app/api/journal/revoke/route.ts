import { after } from "next/server";
import { rpc, fail } from "@/lib/admin";

export const maxDuration = 60;

export async function POST() {
  try {
    await rpc("ui_revoke_approvals");
    after(async () => { try { await rpc("ui_refresh_snapshots", { p_scope: "journal" }); } catch { /* best-effort */ } });
    return Response.json({ ok: true });
  } catch (e) { return fail(e); }
}
