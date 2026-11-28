import type { AiProvider, AiRequest, AiResult } from "./types";
import { PROMPTS } from "./prompts.generated";
import { extractCitations } from "./ids";

type FetchLike = (url: string, init: { method: string; headers: Record<string, string>; body: string }) => Promise<{ ok: boolean; status: number; text(): Promise<string> }>;

/** Real provider (Anthropic Messages API). Active only when ANTHROPIC_API_KEY is set; nothing else changes. The model only phrases the supplied context. */
export class AnthropicProvider implements AiProvider {
  readonly name = "anthropic";
  constructor(private opts: { apiKey: string; model?: string; fetchImpl?: FetchLike }) {}
  get model() { return this.opts.model ?? "claude-sonnet-5-5"; }

  async generate(req: AiRequest): Promise<AiResult> {
    const p = PROMPTS[req.promptId];
    if (!p) throw new Error(`Unknown prompt template: ${req.promptId}`);
    const missing = p.required.filter((k) => !(k in req.context.fields));
    if (missing.length) throw new Error(`Prompt ${p.id} needs context fields: ${missing.join(", ")}`);
    const f = this.opts.fetchImpl ?? ((url, init) => fetch(url, init));
    const context = { fields: req.context.fields, allowed_ids: req.context.ids };
    const res = await f("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": this.opts.apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({
        model: this.model, max_tokens: 1200, system: p.system,
        messages: [{ role: "user", content: `Context (SQL-produced; the only source of facts, figures and IDs):\n${JSON.stringify(context, null, 2)}\n\n${req.question ? `Question: ${req.question}\n\n` : ""}Write the response now. Format rules: plain sentences only, no markdown (no headings, bullets, bold or tables). Put each fact on its own line and end EVERY line longer than a few words with the supporting ID in [brackets] taken from the context (for example [F-01]). Use only amounts and run counts that appear verbatim in the context; do not add, subtract or total anything yourself.` }],
      }),
    });
    const raw = await res.text();
    if (!res.ok) throw new Error(`AI provider error ${res.status}: ${raw.slice(0, 200)}`);
    const body = JSON.parse(raw);
    const text: string = (body.content ?? []).filter((b: { type: string }) => b.type === "text").map((b: { text: string }) => b.text).join("\n").trim();
    if (!text) throw new Error("AI provider returned no text");
    const allowed = new Set(req.context.ids);
    return { text, citedIds: [...new Set(extractCitations(text))].filter((id) => allowed.has(id)) };
  }
}
