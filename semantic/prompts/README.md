# prompts
Prompts for the AI explanation layer. **The AI never computes a number.** SQL produces every figure; the AI only explains, citing row or document IDs.

Each file has three sections that the app reads (`app/scripts/sync-prompts.mjs` turns them into `app/src/lib/ai/prompts.generated.ts`):
- `## Required context` - the context fields the prompt needs (the server fails fast if one is missing).
- `## Template` - the deterministic text used by the **TemplateProvider** (default, no key): `{{field}}` placeholders filled from the context, with `[ID]` citations.
- `## System prompt` - the instruction sent to a real provider together with the context.

| Prompt id | Feature | Context fields |
|---|---|---|
| `explain_finding` | Explain a finding | display_id, customer, title_tail, class_label, what_we_found, math_summary, evidence_summary, evidence_cites, action_text, accounting_effect |
| `draft_billing_request` | Draft request to Billing | display_id, customer, title_tail, correction_line, issue_date_line, action_text, owner_line, evidence_summary, evidence_cites |
| `draft_controller_note` | Draft note to Controller | display_id, customer, title_tail, class_label, what_we_found, correction_line, accounting_effect, action_text, math_summary |
| `reconciliation_chat` | Ask the reconciliation | question, answer_lines, data |

**Guardrail (applies to every provider):** after generation the server extracts every dollar amount and run count from the text and compares it with the amounts in the context; any mismatch, any unknown citation or any uncited paragraph blocks the output and shows a warning. See `semantic/policies/ai_guardrail.md`.

**Switching providers:** set `ANTHROPIC_API_KEY` (optional `AI_MODEL`) in the environment; no code change. Without a key the buttons show "AI not configured" and render the template text.
