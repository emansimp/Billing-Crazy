import type { AiContext, AiProvider, GuardIssue } from "./types";
import { checkOutput, describeIssue } from "./guardrail";
import { getProvider } from "./provider";
import { TemplateProvider } from "./template";

export type AiResponse = {
  provider: string;
  configured: boolean;
  blocked: boolean;
  text: string | null;
  citedIds: string[];
  warnings: string[];
  issues: GuardIssue[];
  checks: { amounts: number; quantities: number; citations: number };
  /** Template text shown instead when a real provider's output is blocked or errors (always guard-checked). */
  fallbackText: string | null;
  error?: string;
};

/** Generate, then run the amount/citation guardrail on the result before anything reaches the browser. */
export async function runAi(promptId: string, context: AiContext, question?: string, provider: AiProvider = getProvider()): Promise<AiResponse> {
  const configured = provider.name !== "template";
  const base = { provider: provider.name, configured, citedIds: [] as string[], warnings: [] as string[], issues: [] as GuardIssue[], checks: { amounts: 0, quantities: 0, citations: 0 }, fallbackText: null as string | null };
  const template = async () => {
    const t = await new TemplateProvider().generate({ promptId, context, question });
    return checkOutput(t.text, context).ok ? t.text : null;   // template text is checked like everything else
  };
  try {
    const out = await provider.generate({ promptId, context, question });
    const guard = checkOutput(out.text, context);
    const checks = { amounts: guard.amountsChecked, quantities: guard.quantitiesChecked, citations: guard.citationsChecked };
    if (!guard.ok) {
      return { ...base, blocked: true, text: null, issues: guard.issues, checks, warnings: guard.issues.map(describeIssue), fallbackText: configured ? await template() : null };
    }
    return { ...base, blocked: false, text: out.text, citedIds: out.citedIds, checks };
  } catch (e) {
    return { ...base, blocked: false, text: null, error: e instanceof Error ? e.message : "AI generation failed", warnings: [], fallbackText: await template().catch(() => null) };
  }
}
