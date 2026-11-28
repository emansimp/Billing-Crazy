import { after } from "next/server";
import { rpc, fail } from "@/lib/admin";

export const maxDuration = 60;

// Controller approval of the proposed entries (no sign-in in this build: the approver name is free text and is recorded).
export async function POST(req: Request) {
  const { by } = await req.json().catch(() => ({ by: null }));
  try {
    const n = await rpc<number>("ui_approve_entries", { p_by: by ?? null });
    after(async () => { try { await rpc("ui_refresh_snapshots", { p_scope: "journal" }); } catch { /* best-effort */ } });
    return Response.json({ ok: true, approved: n });
  } catch (e) { return fail(e); }
}
