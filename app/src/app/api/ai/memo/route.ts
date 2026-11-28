import { buildFindingContext } from "@/lib/ai/context";
import { runAi } from "@/lib/ai/run";

export const maxDuration = 60;

// Draft a request to Billing or a note to the Controller for one finding. Draft text only; nothing is created or sent.
export async function POST(req: Request) {
  const { finding, kind } = await req.json().catch(() => ({ finding: "", kind: "" }));
  if (!/^F-\d{2}$/.test(String(finding))) return Response.json({ error: "A finding id like F-01 is required" }, { status: 400 });
  if (!["billing", "controller"].includes(kind)) return Response.json({ error: "kind must be billing or controller" }, { status: 400 });
  const ctx = await buildFindingContext(String(finding));
  if (!ctx) return Response.json({ error: "Unknown finding" }, { status: 404 });
  return Response.json(await runAi(kind === "controller" ? "draft_controller_note" : "draft_billing_request", ctx));
}
