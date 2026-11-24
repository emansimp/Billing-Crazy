export default function Stub({ title, area }: { title: string; area: string }) {
  return (
    <div style={{ padding: "24px 32px" }}>
      <h1 style={{ margin: 0, fontSize: 26, fontWeight: 700 }}>{title}</h1>
      <div className="muted" style={{ marginTop: 8 }}>This area is built in a later step ({area}) and is not part of the current review.</div>
    </div>
  );
}
