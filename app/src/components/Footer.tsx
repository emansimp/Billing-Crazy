import { one } from "@/lib/db";
import { runLabel } from "@/lib/format";
export default async function Footer() {
  const sha = process.env.VERCEL_GIT_COMMIT_SHA ?? "local build";
  let run: any; try { run = await one("ui_footer"); } catch { /* footer must never break a page */ }
  return (
    <div className="footer">
      <span>Commit <code data-testid="commit-sha">{sha}</code></span>
      <span data-testid="last-run">{run ? `Last run #${run.run_id} · ${runLabel(run.last_run_at)} · engine commit ${String(run.run_commit).slice(0, 7)}` : "No run recorded"}</span>
    </div>
  );
}
