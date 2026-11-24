export function ClassChip({ cls, label }: { cls: string; label: string }) {
  const c = cls === "error" ? "c-err" : cls === "valid_explanation" ? "c-ok" : "c-info";
  return <span className={`chip ${c}`}>{label}</span>;
}
export function Chip({ tone, children }: { tone: "err" | "ok" | "info" | "blue" | "gray"; children: React.ReactNode }) {
  return <span className={`chip c-${tone}`}>{children}</span>;
}
