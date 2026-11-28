// Extraction helpers shared by the context builder and the guardrail (pure functions, no I/O).

const ID_PATTERNS: RegExp[] = [
  /\bF-\d{2}\b/g, /\bCORR-\d{2}\b/g, /\b(?:AM-)?OF-2026-\d{3}\b/g, /\bMSG-2026-\d{3}\b/g, /\bRC-\d{6}-\d{5,6}-[PU]\b/g, /\bCN-\d{6}-\d{8}\b/g,
  /\bJE-[0-9a-f]{10,}\b/g, /\bBR-OCT26-JE\d{2}\b/g, /\b(?:in|il|ur|pa|cus|cn)_[0-9a-f]{8,}\b/g, /\bCT-\d{6}\b/g, /\b[OA]-\d{1,2}\b/g, /\b[ABC]\d{1,2}\b(?=[ ,.:)\]"'])/g,
];

export function extractIds(text: string): string[] {
  const found = new Set<string>();
  for (const re of ID_PATTERNS) for (const m of text.matchAll(new RegExp(re.source, re.flags))) found.add(m[0]);
  return [...found];
}

/** "$3,096.80" / "−$526.03" / "$12,000" -> canonical magnitude "3096.80" / "526.03" / "12000.00" (string math only, no floats). */
export function canonicalAmount(raw: string): string | null {
  const s = raw.replace(/[−\-+$\s]/g, "").replace(/,/g, "");
  const m = s.match(/^(\d+)(?:\.(\d+))?$/);
  if (!m) return null;
  let dec = m[2] ?? "";
  while (dec.length > 2 && dec.endsWith("0")) dec = dec.slice(0, -1);
  while (dec.length < 2) dec += "0";
  return `${m[1].replace(/^0+(?=\d)/, "")}.${dec}`;
}

/** Dollar amounts written with a "$" sign. */
export function extractDollarAmounts(text: string): string[] {
  const out: string[] = [];
  for (const m of text.matchAll(/[−\-]?\$\s?\d[\d,]*(?:\.\d+)?/g)) { const c = canonicalAmount(m[0]); if (c) out.push(c); }
  return out;
}

/** Decimal figures with exactly two decimals that are not preceded by a "$" (raw view values such as 93060.17). Used to build the allowed set. */
export function extractBareDecimals(text: string): string[] {
  const out: string[] = [];
  for (const m of text.matchAll(/(?<![\d.$])(\d[\d,]*\.\d{2,4})(?![\d])/g)) { const c = canonicalAmount(m[1]); if (c) out.push(c); }
  return out;
}

/** Whole numbers followed by "runs" (run counts), as digit strings. */
export function extractRunCounts(text: string): string[] {
  const out: string[] = [];
  for (const m of text.matchAll(/\b(\d[\d,]*)\s+(?:runs|overage runs|included runs)\b/g)) out.push(m[1].replace(/,/g, ""));
  return out;
}

/** Every integer in a text (allowed-quantity set), digits only. */
export function extractIntegers(text: string): string[] {
  const out: string[] = [];
  for (const m of text.matchAll(/(?<![\d.])(\d{1,3}(?:,\d{3})+|\d+)(?![\d]*\.\d)/g)) out.push(m[1].replace(/,/g, ""));
  return out;
}

/** Citation groups like "[F-01]" or "[F-01, AM-OF-2026-157]" -> IDs. */
export function extractCitations(text: string): string[] {
  const out: string[] = [];
  for (const m of text.matchAll(/\[([^\]\n]+)\]/g)) for (const part of m[1].split(/[;,]/)) { const id = part.trim(); if (id) out.push(id); }
  return out;
}
