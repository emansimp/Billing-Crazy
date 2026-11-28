import type { AiProvider, AiRequest, AiResult } from "./types";
import { PROMPTS } from "./prompts.generated";
import { extractCitations } from "./ids";

/** Default provider: deterministic fill-in text. No key, no network, no model: the template in /semantic/prompts is filled from the context. */
export class TemplateProvider implements AiProvider {
  readonly name = "template";
  async generate(req: AiRequest): Promise<AiResult> {
    const p = PROMPTS[req.promptId];
    if (!p) throw new Error(`Unknown prompt template: ${req.promptId}`);
    const missing = p.required.filter((k) => !(k in req.context.fields));
    if (missing.length) throw new Error(`Prompt ${p.id} needs context fields: ${missing.join(", ")}`);
    const text = p.template.replace(/\{\{(\w+)\}\}/g, (_m, k: string) => {
      if (!(k in req.context.fields)) throw new Error(`Template ${p.id} uses an unknown field: ${k}`);
      return req.context.fields[k];
    });
    const allowed = new Set(req.context.ids);
    return { text, citedIds: [...new Set(extractCitations(text))].filter((id) => allowed.has(id)) };
  }
}
