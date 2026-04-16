import { useEffect, useRef, useState } from "react";

export default function AddConfigurationMenu({ availableKinds, onAdd }) {
  const [isOpen, setIsOpen] = useState(false);
  const anchorRef = useRef(null);

  useEffect(() => {
    if (!isOpen) {
      return undefined;
    }

    function handlePointerDown(event) {
      if (!anchorRef.current || anchorRef.current.contains(event.target)) {
        return;
      }
      setIsOpen(false);
    }

    window.addEventListener("pointerdown", handlePointerDown);
    return () => {
      window.removeEventListener("pointerdown", handlePointerDown);
    };
  }, [isOpen]);

  return (
    <div className="add-menu-anchor" ref={anchorRef}>
      <button
        type="button"
        className="button button-prominent"
        onClick={() => setIsOpen((current) => !current)}
      >
        <span className="button-icon">+</span>
        <span>新增配置</span>
      </button>

      {isOpen ? (
        <div className="menu-popover">
          {availableKinds.map((kind) => (
            <button
              key={kind.id}
              type="button"
              className="menu-item"
              onClick={() => {
                setIsOpen(false);
                onAdd(kind.id);
              }}
            >
              <span className="menu-item-title">{kind.title}</span>
              <span className="menu-item-subtitle">{kind.subtitle}</span>
            </button>
          ))}
        </div>
      ) : null}
    </div>
  );
}
