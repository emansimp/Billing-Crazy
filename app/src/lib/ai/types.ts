// The AI layer never computes numbers: the context holds SQL-produced text, figures and row/document IDs; providers only phrase it.
export type AiContext = {
  /** Named text fields filled from the read-only views (what templates and prompts may use). */
  fields: Record<string, string>;
  /** Every row/document ID that appears in the context (the only IDs a citation may use). */
  ids: string[];
  /** Canonical dollar amounts present in the context (e.g. "3096.80"). */
  amounts: string[];
  /** Integers present in the context (run counts, row counts) as digit strings without separators. */
  quantities: string[];
};

export type AiRequest = { promptId: string; context: AiContext; question?: string };
export type AiResult = { text: string; citedIds: string[] };

export interface AiProvider {
  readonly name: string;
  /** One method: prompt template id + context object in, text + cited IDs out. */
  generate(req: AiRequest): Promise<AiResult>;
}

export type GuardIssue =
  | { type: "amount_mismatch"; value: string }
  | { type: "quantity_mismatch"; value: string }
  | { type: "unknown_citation"; value: string }
  | { type: "uncited_paragraph"; value: string };

export type GuardResult = { ok: boolean; issues: GuardIssue[]; amountsChecked: number; quantitiesChecked: number; citationsChecked: number };
