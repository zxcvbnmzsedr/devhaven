export function TextField({ label, value, placeholder, onChange }) {
  return (
    <label className="labeled-field">
      <span className="field-label">{label}</span>
      <input
        type="text"
        value={value || ""}
        placeholder={placeholder || ""}
        onChange={(event) => onChange(event.target.value)}
      />
    </label>
  );
}

export function ToggleField({ label, checked, onChange }) {
  return (
    <label className="toggle-row">
      <input
        type="checkbox"
        checked={Boolean(checked)}
        onChange={(event) => onChange(event.target.checked)}
      />
      <span>{label}</span>
    </label>
  );
}

export function Placeholder({ text, className = "" }) {
  const resolvedClassName = className
    ? `placeholder ${className}`
    : "placeholder";

  return <div className={resolvedClassName}>{text}</div>;
}
