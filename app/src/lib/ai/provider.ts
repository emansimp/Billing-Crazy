import type { AiProvider } from "./types";
import { TemplateProvider } from "./template";
import { AnthropicProvider } from "./anthropic";

/** Chooses the provider from the environment, with no code change: a key switches it on, removing the key switches it off. AI_PROVIDER=template forces the template. */
export function getProvider(env: Record<string, string | undefined> = process.env): AiProvider {
  const key = env.ANTHROPIC_API_KEY?.trim();
  if (key && env.AI_PROVIDER !== "template") return new AnthropicProvider({ apiKey: key })   // model is pinned to Sonnet 5.5 in anthropic.ts; not overridable by env;
  return new TemplateProvider();
}

export function providerStatus(env: Record<string, string | undefined> = process.env): { configured: boolean; provider: string; model?: string } {
  const p = getProvider(env);
  return p.name === "anthropic" ? { configured: true, provider: "anthropic", model: (p as AnthropicProvider).model } : { configured: false, provider: "template" };
}
