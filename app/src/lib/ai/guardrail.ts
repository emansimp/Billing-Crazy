import type { AiContext, GuardResult, GuardIssue } from "./types";
import { extractCitations, extractDollarAmounts, extractRunCounts } from "./ids";

/**
 * Post-generation guardrail. Blocks the output if
 *  - any dollar amount in the text is not among the amounts in the context (a wrong or invented figure),
 *  - any run count in the text is not among the integers in the context,
 *  - any citation is not an ID present in the context,
 *  - any substantive paragraph carries no citation.
 * It runs on every provider's output, including the deterministic template text.
 */
export function checkOutput(text: string, ctx: AiContext): GuardResult {
  const issues: GuardIssue[] = [];
  const allowedAmounts = new Set(ctx.amounts);
  const allowedQty = new Set(ctx.quantities);
  const allowedIds = new Set(ctx.ids);

  const amounts = extractDollarAmounts(text);
  for (const a of amounts) if (!allowedAmounts.has(a)) issues.push({ type: "amount_mismatch", value: a });
  const qty = extractRunCounts(text);
  for (const q of qty) if (!allowedQty.has(q)) issues.push({ type: "quantity_mismatch", value: q });
  const cites = extractCitations(text);
  for (const c of cites) if (!allowedIds.has(c)) issues.push({ type: "unknown_citation", value: c });
  for (const para of text.split(/\n+/).map((p) => p.trim()).filter((p) => p.length > 40)) {
    if (extractCitations(para).length === 0) issues.push({ type: "uncited_paragraph", value: para.slice(0, 80) });
  }
  const seen = new Set<string>();
  const unique = issues.filter((i) => { const k = `${i.type}|${i.value}`; if (seen.has(k)) return false; seen.add(k); return true; });
  return { ok: unique.length === 0, issues: unique, amountsChecked: amounts.length, quantitiesChecked: qty.length, citationsChecked: cites.length };
}

export function describeIssue(i: GuardIssue): string {
  switch (i.type) {
    case "amount_mismatch": return `Amount $${i.value} does not match any amount in the calculation.`;
    case "quantity_mismatch": return `Run count ${i.value} does not match any figure in the calculation.`;
    case "unknown_citation": return `Citation [${i.value}] is not a row or document ID in the context.`;
    case "uncited_paragraph": return `A paragraph has no citation: "${i.value}…"`;
  }
}
