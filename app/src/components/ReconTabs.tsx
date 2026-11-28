"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
const tabs = [["/reconciliation", "Customers"], ["/reconciliation/customer", "Customer detail"], ["/reconciliation/controls", "Controls"], ["/reconciliation/assumptions", "Assumptions and open items"]] as const;
export default function ReconTabs() {
  const p = usePathname();
  const active = (h: string) => (h === "/reconciliation" ? p === h : p.startsWith(h));
  return (
    <div style={{ display: "flex", flexWrap: "wrap", gap: 4, marginTop: 14, borderBottom: "1px solid #E2E5EA" }}>
      {tabs.map(([h, l]) => (
        <Link key={h} href={h} style={{ padding: "9px 14px", textDecoration: "none", fontWeight: 600, fontSize: 13, color: active(h) ? "#1B4DB8" : "#566070", borderBottom: active(h) ? "2px solid #1B4DB8" : "2px solid transparent", marginBottom: -1 }}>{l}</Link>
      ))}
    </div>
  );
}
