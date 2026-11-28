# AI guardrail policy

The AI layer never computes numbers. SQL views produce every figure; the AI only phrases them.

1. Context only: prompts receive a context object built server-side from the read-only `ui_*` views (figures, text, row/document IDs). Nothing else.
2. Post-generation check on every output (including the deterministic template):
   - every dollar amount must equal an amount in the context (string comparison on canonical values, no floats);
   - every run count must be an integer present in the context;
   - every `[ID]` citation must be an ID present in the context;
   - every substantive paragraph (over 40 characters) must carry a citation.
3. On any mismatch the text is blocked, a warning lists each issue, and the guard-checked template text is shown instead.
4. Provider is chosen by environment: `ANTHROPIC_API_KEY` set (and `AI_PROVIDER` not `template`) uses the real provider; otherwise the template provider. Optional `AI_MODEL`.
5. Routes are server-only (`/api/ai/*`); the key is never sent to the browser.
6. Tests: `npm test` in `app/` (see `app/src/lib/ai/ai.test.ts`); the wrong-number test fails the guardrail on `$3,096.81`.
