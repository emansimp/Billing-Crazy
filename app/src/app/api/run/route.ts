import { rpc, fail } from "@/lib/admin";

export const maxDuration = 60;

// "Run reconciliation": recomputes every snapshot from the loaded data and stores a run record (timestamp, commit, input counts, output totals).
export async function POST() {
  try {
    const id = await rpc<number>("ui_record_run", { p_commit: process.env.VERCEL_GIT_COMMIT_SHA ?? "local build" });
    return Response.json({ ok: true, run_id: id });
  } catch (e) { return fail(e); }
}
