export const metadata = { title: "RelayCloud Billing Reconciliation", description: "October 2026 billing reconciliation - Phase 0 foundation" };
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body style={{ fontFamily: "system-ui, sans-serif", margin: 0, background: "#fafafa", color: "#111" }}>{children}</body>
    </html>
  );
}
