import "./globals.css";
import Nav from "@/components/Nav";
import ChatDrawer from "@/components/ChatDrawer";
import Footer from "@/components/Footer";
export const metadata = { title: "Billing Review · RelayCloud October 2026", description: "October 2026 billing reconciliation" };
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en"><body>
      <div className="shell">
        <Nav />
        <main className="main">{children}<Footer /></main>
      </div>
      <ChatDrawer />
    </body></html>
  );
}
