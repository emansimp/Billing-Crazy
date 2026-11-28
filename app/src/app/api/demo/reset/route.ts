import { after } from "next/server";
import { rpc, fail } from "@/lib/admin";

export const maxDuration = 60;

// Demo reset: clears finding decisions (and their history), treatment overrides and entry approvals. Source data and run history are untouched.
export async function POST() {
  try {
    await rpc("ui_reset_demo");
    after(async () => { try { await rpc("ui_refresh_snapshots", { p_scope: "journal" }); } catch { /* best-effort */ } });
    return Response.json({ ok: true });
  } catch (e) { return fail(e); }
}
