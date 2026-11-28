import { view, one } from "../db";
import { money, int } from "../format";
import type { AiContext } from "./types";
import { canonicalAmount, extractBareDecimals, extractDollarAmounts, extractIds, extractIntegers } from "./ids";

// Builds the context object from the read-only ui_* views only. Nothing here calculates: it selects and phrases SQL-produced values.

export function makeContext(fields: Record<string, string>): AiContext {
  const all = Object.values(fields).join("\n");
  const amounts = new Set<string>([...extractDollarAmounts(all), ...extractBareDecimals(all)]);
  for (const m of all.matchAll(/(?<![\d.])\d{1,3}(?:,\d{3})+(?![\d])/g)) { const c = canonicalAmount(m[0]); if (c) amounts.add(c); }   // 12,000 style numbers may be written with a $
  for (const i of extractIntegers(all)) { const c = canonicalAmount(i); if (c) amounts.add(c); }
  return { fields, ids: extractIds(all), amounts: [...amounts], quantities: [...new Set(extractIntegers(all))] };
}

const cite = (ids: string[]) => [...new Set(ids)].map((i) => `[${i}]`).join(" ");

export async function buildFindingContext(displayId: string): Promise<AiContext | null> {
  const d: any = await one("ui_finding_detail", `select=*&display_id=eq.${encodeURIComponent(displayId)}`);
  if (!d) return null;
  const fid = encodeURIComponent(d.finding_id);
  const [evidence, math, action, corrs]: any = await Promise.all([
    view("ui_finding_evidence", `select=*&finding_id=eq.${fid}&order=item_no`), view("ui_finding_math", `select=*&finding_id=eq.${fid}&order=step_no`),
    one("ui_finding_action", `select=*&finding_id=eq.${fid}`), view("ui_billing_corrections", `select=*&finding_id=eq.${fid}`),
  ]);
  const evidenceText = evidence.map((e: any) => `${e.title}: ${e.body} (${e.source_ref}).`).join(" ");
  const corr = corrs[0];
  const fields: Record<string, string> = {
    display_id: d.display_id, customer: d.customer, class_label: d.class_label, direction_label: d.direction_label ?? "",
    title_tail: String(d.title).replace(/^[^:]+:\s*/, ""), what_we_found: d.what_we_found,
    math_summary: math.map((m: any) => `${m.step.replace(/^\d+\.\s*/, "")}: ${m.calculation} = ${m.result}.`).join(" "),
    evidence_summary: evidenceText, evidence_cites: cite(extractIds(evidenceText)),
    action_text: action?.action_text ?? "", owner_line: action?.owner_line ?? "", accounting_effect: d.accounting_effect ?? "",
    correction_line: corr ? `${corr.ref}: ${corr.document} of ${money(corr.amount)} (${corr.linked_to}).` : "No billing document is proposed for this finding.",
    issue_date_line: corr?.proposed_issue_date ? `Proposed November issue date: ${corr.proposed_issue_date}. The finalized invoice is not edited.` : "No issue date applies.",
  };
  return makeContext(fields);
}

const HELP = "I can answer questions about customers (for example Cedar Harbor Labs), findings ([F-01] to [F-15]), invoices (RC-… numbers), controls, open items, totals (expected vs billed), journal entries and the unassigned workspace. I answer only from the app's data.";

export async function buildChatContext(question: string): Promise<AiContext> {
  const q = question.toLowerCase();
  const lines: string[] = []; const data: Record<string, unknown> = {};
  const [customers]: any = await Promise.all([view("ui_customers", "select=*&order=customer")]);

  // findings
  const findingIds = [...new Set([...question.matchAll(/\bF-?(\d{1,2})\b/gi)].map((m) => `F-${String(m[1]).padStart(2, "0")}`))];
  for (const f of findingIds) {
    const d: any = await one("ui_finding_detail", `select=*&display_id=eq.${f}`); if (!d) continue;
    data[f] = { what_we_found: d.what_we_found, class: d.class_label, direction: d.direction_label, recommended_action: d.recommended_action };
    const act: any = await one("ui_finding_action", `select=*&finding_id=eq.${encodeURIComponent(d.finding_id)}`);
    lines.push(`${d.customer}: ${d.what_we_found}. Classified ${d.class_label}${d.direction_label ? `, ${d.direction_label}` : ""}. Next step: ${String(act?.action_text ?? d.recommended_action).replace(/\.+$/, "")}. ${cite([f])}`);
  }
  // invoices
  for (const inv of [...new Set([...question.matchAll(/RC-\d{6}-\d{5,6}-[PU]/gi)].map((m) => m[0].toUpperCase()))]) {
    const r: any = await one("ui_invoices", `select=*&invoice_number=eq.${inv}`); if (!r) continue;
    data[inv] = r;
    lines.push(`${inv} (${r.customer}, ${r.type}): ${money(r.amount)}, service period ${r.service_period}, ${r.status}. Role in the October review: ${r.role_in_review}. ${cite([inv, ...(r.finding_ids ? r.finding_ids.split(", ") : [])])}`);
  }
  // customers
  const named = customers.filter((c: any) => q.includes(c.customer.toLowerCase()) || (c.customer.split(" ").length > 1 && q.includes(c.customer.split(" ").slice(0, 2).join(" ").toLowerCase())) ||
    (customers.filter((x: any) => x.customer.split(" ")[0].toLowerCase() === c.customer.split(" ")[0].toLowerCase()).length === 1 && c.customer.split(" ")[0].length >= 5 && q.includes(c.customer.split(" ")[0].toLowerCase())));
  for (const c of named) {
    data[c.customer] = c;
    const h: any = await one("ui_customer_header", `select=stripe_customer_id,contract_ids&salesforce_account_id=eq.${encodeURIComponent(c.salesforce_account_id)}`);
    const flags = c.flags ? ` Flags: ${c.flags.replace(/ (error|valid|info)/g, "")}.` : " No findings.";
    lines.push(`${c.customer} (NetSuite ${c.ns_id}, Stripe ${h?.stripe_customer_id}, contract ${h?.contract_ids}): platform expected ${money(c.plat_exp_alloc)}, billed ${money(c.plat_bill_alloc)}; usage ${c.usage_unattributed ? "not attributable (no verified product account)" : `expected ${money(c.usage_exp)}, billed ${money(c.usage_bill)}`}` +
      `${Number(c.usage_over) > 0 ? `; over-billed ${money(c.usage_over)}` : ""}${Number(c.usage_under) > 0 ? `; under-billed ${money(c.usage_under)}` : ""}${Number(c.plat_under_alloc) > 0 ? `; platform under-billed ${money(c.plat_under_alloc)}` : ""}.${flags} ` +
      cite([...(c.flags ? c.flags.split(", ").map((x: string) => x.split(" ")[0]) : []), h?.stripe_customer_id, ...(String(h?.contract_ids ?? "").split(", "))].filter(Boolean)));
  }
  // topics
  if (/(total|expected|billed|variance|compare|how much)/.test(q) && !lines.length) {
    const q1: any = await view("ui_overview_q1", "select=*&order=sort_no"); data.totals = q1;
    const fl: any = await view("ui_findings_list", "select=display_id,stream,class,check_code&order=sort_no"); data.variance_findings = fl.filter((f: any) => f.class === "error");
    const ids = (check: string) => fl.filter((f: any) => f.check_code === check).map((f: any) => f.display_id);
    for (const r of q1.filter((x: any) => x.stream !== "Total")) {
      const platform = r.stream.startsWith("Platform");
      lines.push(`${r.stream}: expected ${money(r.expected)}, billed ${money(r.billed)}; under-billed ${money(r.under_billed)}, over-billed ${money(r.over_billed)} (never netted). ${cite(ids(platform ? "platform_variance" : "usage_variance"))}`);
    }
  }
  if (/control|complete|tie-?out|verified/.test(q)) {
    const rd: any = await one("ui_readiness"); const ctl: any = await view("ui_controls", "select=control_id,control_name,status"); data.controls = ctl;
    const open = ctl.filter((c: any) => c.status !== "pass").map((c: any) => c.control_id);
    lines.push(`${rd.verified} of ${rd.total} controls verified; ${rd.failed} failing; ${rd.pending} open (${rd.pending_names}). ${cite(open.length ? open : [ctl[0].control_id])}`);
  }
  if (/open item|assumption|unresolved|outstanding/.test(q)) {
    const oi: any = await view("ui_open_items", "select=ref,item,status,owner"); data.open_items = oi;
    for (const o of oi.filter((x: any) => x.status === "Open")) lines.push(`${o.ref}: ${o.item} (owner ${o.owner}, ${o.status}). [${o.ref}]`);
  }
  if (/journal|entry|entries|net revenue|accrual|reclass/.test(q) && !/F-?\d/i.test(question)) {
    const s: any = await one("ui_je_summary"); data.journal = s;
    lines.push(`${s.entries} proposed entries, debits ${money(s.debits)} equal credits ${money(s.credits)}. Net effect on October revenue ${money(s.net_revenue_effect, { sign: true })} (usage ${money(s.usage_effect, { sign: true })}, platform ${money(s.platform_effect, { sign: true })}). ${s.approved_entries} approved. [BR-OCT26-JE01]`);
  }
  if (/unassigned|workspace|unverified|pa_676/.test(q)) {
    const w: any = await one("ui_unassigned_workspace"); data.workspace = w;
    lines.push(`Workspace ${w.product_account_id} has ${int(w.october_runs)} October runs in ${w.october_records} records and no verified owner; it is excluded from every customer total and is never assigned by elimination. [F-05] [${w.product_account_id}]`);
  }
  if (/catch-?up|meridian/.test(q) && !named.length && !findingIds.length) {
    const d: any = await one("ui_finding_detail", "select=*&display_id=eq.F-02"); if (d) lines.push(`${d.customer}: ${d.what_we_found}. [F-02]`);
  }
  if (!lines.length && /finding|error|issue|problem|what.?s wrong/.test(q)) {
    const list: any = await view("ui_findings_list", "select=display_id,customer,what_we_found,class_label,amount_display&order=sort_no"); data.findings = list;
    for (const f of list.filter((x: any) => x.class_label === "Error")) lines.push(`${f.display_id} ${f.customer}: ${f.what_we_found} (${f.amount_display}). [${f.display_id}]`);
  }
  const answer = lines.length ? lines.join("\n") : HELP;
  return makeContext({ question, answer_lines: answer, data: JSON.stringify(data) });
}
