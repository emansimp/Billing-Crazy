import Link from "next/link";
import ReconTabs from "@/components/ReconTabs";

export default function ReconLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <div style={{ padding: "24px 32px 0" }}>
        <h1 style={{ margin: 0, fontSize: 26, fontWeight: 700 }}>Reconciliation</h1>
        <div className="muted" style={{ marginTop: 4 }}>Expected vs. actual billing for October 2026 service, platform and usage shown separately. <Link href="/">Close overview</Link></div>
        <ReconTabs />
      </div>
      {children}
    </>
  );
}
