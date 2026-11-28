import { buildChatContext } from "@/lib/ai/context";
import { runAi } from "@/lib/ai/run";

export const maxDuration = 60;

// Ask the reconciliation: limited to data in the read-only views. Template mode answers from fixed lookups; a real provider only phrases the same data.
export async function POST(req: Request) {
  const { question } = await req.json().catch(() => ({ question: "" }));
  const q = String(question ?? "").trim().slice(0, 300);
  if (!q) return Response.json({ error: "Ask a question" }, { status: 400 });
  return Response.json(await runAi("reconciliation_chat", await buildChatContext(q), q));
}
