import { buildFindingContext } from "@/lib/ai/context";
import { runAi } from "@/lib/ai/run";

export const maxDuration = 60;

// Explain a finding. Server-side only: the context comes from the read-only views, and the guardrail runs before anything reaches the browser.
export async function POST(req: Request) {
  const { finding } = await req.json().catch(() => ({ finding: "" }));
  if (!/^F-\d{2}$/.test(String(finding))) return Response.json({ error: "A finding id like F-01 is required" }, { status: 400 });
  const ctx = await buildFindingContext(String(finding));
  if (!ctx) return Response.json({ error: "Unknown finding" }, { status: 404 });
  return Response.json(await runAi("explain_finding", ctx));
}
