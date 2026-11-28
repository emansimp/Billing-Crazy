import { test } from "node:test";
import assert from "node:assert/strict";
import { checkOutput } from "./guardrail";
import { makeContext } from "./context";
import { TemplateProvider } from "./template";
import { AnthropicProvider } from "./anthropic";
import { getProvider, providerStatus } from "./provider";
import { runAi } from "./run";
import { PROMPTS } from "./prompts.generated";
import type { AiProvider } from "./types";

const fields = {
  display_id: "F-01", customer: "Cedar Harbor Labs", title_tail: "usage under-billed",
  class_label: "Usage under-billing", what_we_found: "Expected $12,400.00 and billed $9,303.20 for October usage [F-01].",
  math_summary: "Difference $3,096.80 across 4 runs [F-01].", evidence_summary: "Invoice [RC-261101-639373-U] and contract [CT-100001].",
  evidence_cites: "[RC-261101-639373-U] [CT-100001]", action_text: "Issue a corrected invoice for $3,096.80 [F-01].",
  accounting_effect: "Revenue effect $3,096.80 [F-01].", correction_line: "Correction of $3,096.80 [F-01].", issue_date_line: "Issue date 2026-11-12 [F-01].",
  owner_line: "Owner: Billing [F-01].", question: "q", answer_lines: "Cedar owes $3,096.80 [F-01].", data: "",
};
const ctx = makeContext(fields);

test("guardrail passes text whose amounts and citations are in the context", () => {
  assert.equal(checkOutput("Cedar Harbor Labs was under-billed $3,096.80 on usage [F-01].", ctx).ok, true);
});
test("guardrail FAILS on a wrong number", () => {
  const r = checkOutput("Cedar Harbor Labs was under-billed $3,096.81 on usage [F-01].", ctx);
  assert.equal(r.ok, false);
  assert.ok(r.issues.some((i) => i.type === "amount_mismatch" && i.value === "3096.81"));
});
test("guardrail fails on an invented amount, unknown citation and uncited paragraph", () => {
  assert.equal(checkOutput("Total is $99,999.00 [F-01].", ctx).ok, false);
  assert.ok(checkOutput("Under-billed $3,096.80 [F-77].", ctx).issues.some((i) => i.type === "unknown_citation"));
  assert.ok(checkOutput("Cedar Harbor Labs was under-billed $3,096.80 on October usage with no source cited.", ctx).issues.some((i) => i.type === "uncited_paragraph"));
});
test("guardrail fails on a wrong run count", () => {
  assert.ok(checkOutput("Difference across 7 runs [F-01].", ctx).issues.some((i) => i.type === "quantity_mismatch"));
});
test("template output passes the guardrail for every prompt", async () => {
  for (const id of Object.keys(PROMPTS)) {
    const out = await new TemplateProvider().generate({ promptId: id, context: ctx });
    const g = checkOutput(out.text, ctx);
    assert.equal(g.ok, true, `${id}: ${JSON.stringify(g.issues)}`);
  }
});
test("template throws on missing required fields", async () => {
  await assert.rejects(new TemplateProvider().generate({ promptId: "explain_finding", context: makeContext({ display_id: "F-01" }) }));
});
test("env key switches the provider without code changes", () => {
  assert.equal(getProvider({}).name, "template");
  assert.equal(providerStatus({}).configured, false);
  assert.equal(getProvider({ ANTHROPIC_API_KEY: "k" }).name, "anthropic");
  assert.equal(providerStatus({ ANTHROPIC_API_KEY: "k" }).configured, true);
  assert.equal(getProvider({ ANTHROPIC_API_KEY: "k", AI_PROVIDER: "template" }).name, "template");
});
test("anthropic provider sends context and parses text (injected fetch)", async () => {
  let seen: any;
  const fetchImpl = async (url: string, init: any) => { seen = { url, init }; return { ok: true, status: 200, text: async () => JSON.stringify({ content: [{ type: "text", text: "Under-billed $3,096.80 [F-01]." }] }) } as any; };
  const p = new AnthropicProvider({ apiKey: "k", fetchImpl: fetchImpl as any });
  const out = await p.generate({ promptId: "explain_finding", context: ctx });
  assert.match(seen.url, /anthropic\.com\/v1\/messages/);
  assert.equal(seen.init.headers["x-api-key"], "k");
  assert.equal(out.text, "Under-billed $3,096.80 [F-01].");
});
test("runAi blocks a real provider's wrong number and falls back to checked template text", async () => {
  const bad: AiProvider = { name: "anthropic", generate: async () => ({ text: "Under-billed $3,096.81 [F-01].", citedIds: ["F-01"] }) };
  const r = await runAi("explain_finding", ctx, undefined, bad);
  assert.equal(r.blocked, true);
  assert.equal(r.text, null);
  assert.ok(r.fallbackText);
  assert.ok(r.warnings.length > 0);
});
