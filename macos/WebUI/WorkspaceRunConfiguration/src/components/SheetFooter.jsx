export default function SheetFooter({ payload, onCancel, onSave }) {
  return (
    <footer className="sheet-footer">
      <div className="footer-note">{payload.footerNote}</div>

      <div className="footer-actions">
        <button
          type="button"
          className="button button-bordered"
          onClick={onCancel}
        >
          取消
        </button>
        <button
          type="button"
          className="button button-prominent"
          disabled={payload.isSaving}
          onClick={onSave}
        >
          {payload.isSaving ? "保存中..." : "保存并关闭"}
        </button>
      </div>
    </footer>
  );
}
