export default function SectionCard({ title, description, children }) {
  return (
    <section className="section-card">
      <div className="section-header">
        <div className="section-title">{title}</div>
        <div className="section-description">{description}</div>
      </div>
      {children}
    </section>
  );
}
