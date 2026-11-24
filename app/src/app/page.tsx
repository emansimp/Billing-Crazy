export const dynamic = "force-dynamic"; // always read live counts

type Row = { source_file: string; expected_rows: number; csv_rows: number | null; db_rows: number; status: "PASS" | "FAIL"; basis: string };

async function loadManifest(): Promise<{ rows: Row[]; error?: string }> {
  // Publishable key is public by design and can only read public.load_manifest_check (counts). Env vars override the defaults.
  const url = process.env.SUPABASE_URL ?? "https://pejthvjkkyiuwcleywbf.supabase.co";
  const key = process.env.SUPABASE_PUBLISHABLE_KEY ?? "sb_publishable_OcgIf8C4Ge2gndql31db8g__kK7u7oL";
  try {
    const res = await fetch(`${url}/rest/v1/load_manifest_check?select=*&order=source_file`, {
      headers: { apikey: key, Authorization: `Bearer ${key}` }, cache: "no-store",
    });
    if (!res.ok) return { rows: [], error: `Supabase returned ${res.status}` };
    return { rows: (await res.json()) as Row[] };
  } catch (e) {
    return { rows: [], error: String(e) };
  }
}

export default async function Home() {
  const sha = process.env.VERCEL_GIT_COMMIT_SHA ?? "local (not a Vercel build)";
  const { rows, error } = await loadManifest();
  const failed = rows.filter((r) => r.status !== "PASS").length;
  const cell = { padding: "6px 10px", borderBottom: "1px solid #ddd", textAlign: "left" as const };
  return (
    <main style={{ maxWidth: 980, margin: "0 auto", padding: "32px 20px" }}>
      <h1 style={{ margin: 0 }}>RelayCloud billing reconciliation</h1>
      <p style={{ color: "#555" }}>October 2026 service &middot; Phase 0 foundation &middot; numbers are computed in SQL, never in this page.</p>
      <p>Commit: <code data-testid="commit-sha">{sha}</code></p>
      <h2>Source load vs START_HERE manifest</h2>
      {error ? <p style={{ color: "#b00020" }}>Could not read manifest: {error}</p> : (
        <>
          <p><strong>{rows.length === 0 ? "No load recorded" : failed === 0 ? "ALL PASS" : `${failed} FAIL`}</strong></p>
          <table style={{ borderCollapse: "collapse", width: "100%", background: "#fff", fontSize: 14 }}>
            <thead><tr>{["Source file", "Expected", "CSV rows", "In database", "Status"].map((h) => <th key={h} style={cell}>{h}</th>)}</tr></thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.source_file} title={r.basis}>
                  <td style={cell}>{r.source_file}</td><td style={cell}>{r.expected_rows}</td>
                  <td style={cell}>{r.csv_rows ?? ""}</td><td style={cell}>{r.db_rows}</td>
                  <td style={{ ...cell, fontWeight: 600, color: r.status === "PASS" ? "#0a7a2f" : "#b00020" }}>{r.status}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}
    </main>
  );
}
