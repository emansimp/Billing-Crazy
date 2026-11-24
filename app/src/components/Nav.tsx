"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
const items = [["/", "Close overview"], ["/reconciliation", "Reconciliation"], ["/journal", "Journal entries"], ["/invoices", "Invoices"]] as const;
export default function Nav() {
  const p = usePathname();
  const active = (href: string) => (href === "/" ? p === "/" || p.startsWith("/findings") : p.startsWith(href));
  return (
    <nav className="side">
      <div style={{ padding: "4px 12px 18px" }}>
        <div style={{ fontWeight: 700, fontSize: 16, color: "#fff" }}>Billing Review</div>
        <div style={{ fontSize: 12, color: "#B7C2D9" }}>RelayCloud · October 2026 close</div>
      </div>
      {items.map(([href, label]) => <Link key={href} href={href} className={`nav${active(href) ? " active" : ""}`}>{label}</Link>)}
    </nav>
  );
}
