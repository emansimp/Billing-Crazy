import InvoicesTabs from "@/components/InvoicesTabs";

export default function InvoicesLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <div style={{ padding: "24px 32px 0" }}>
        <h1 style={{ margin: 0, fontSize: 26, fontWeight: 700 }}>Invoices</h1>
        <div className="muted" style={{ marginTop: 4 }}>Every invoice issued by the cutoff, with its service period, credits and accounting posting.</div>
        <InvoicesTabs />
      </div>
      {children}
    </>
  );
}
