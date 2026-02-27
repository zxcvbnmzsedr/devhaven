import { useEffect, useRef, useState } from "react";
import type { ReactNode } from "react";

export type DropdownItem = {
  key?: string;
  label?: string;
  onClick?: () => void;
  disabled?: boolean;
  destructive?: boolean;
  divider?: boolean;
};

type DropdownMenuProps = {
  label: ReactNode;
  items: DropdownItem[];
  align?: "left" | "right";
  ariaLabel?: string;
};

/** 通用下拉菜单，支持外部点击关闭与键盘退出。 */
export default function DropdownMenu({ label, items, align = "right", ariaLabel }: DropdownMenuProps) {
  const [open, setOpen] = useState(false);
  const wrapperRef = useRef<HTMLDivElement | null>(null);
  const resolvedLabel = ariaLabel ?? (typeof label === "string" ? label : "更多操作");

  useEffect(() => {
    if (!open) {
      return;
    }
    const handleClick = (event: MouseEvent) => {
      if (wrapperRef.current && !wrapperRef.current.contains(event.target as Node)) {
        setOpen(false);
      }
    };
    const handleKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setOpen(false);
      }
    };
    document.addEventListener("mousedown", handleClick);
    document.addEventListener("keydown", handleKey);
    return () => {
      document.removeEventListener("mousedown", handleClick);
      document.removeEventListener("keydown", handleKey);
    };
  }, [open]);

  return (
    <div className="relative" ref={wrapperRef}>
      <button
        className="icon-btn rounded-md px-1.5"
        onClick={(event) => {
          event.stopPropagation();
          setOpen((prev) => !prev);
        }}
        aria-haspopup="menu"
        aria-label={resolvedLabel}
      >
        {label}
      </button>
      {open ? (
        <div
          className={`absolute top-full mt-1 min-w-[160px] rounded-lg border border-border bg-[#1f1f1f] p-1.5 shadow-[0_8px_24px_rgba(0,0,0,0.3)] z-30 flex flex-col ${
            align === "left" ? "left-0" : "right-0"
          }`}
        >
          {items.map((item, index) => {
            if (item.divider) {
              return (
                <div
                  key={item.key ?? `divider-${index}`}
                  className="my-1 h-px bg-divider"
                  role="separator"
                />
              );
            }
            return (
              <button
                key={item.key ?? item.label ?? `item-${index}`}
                className={`rounded-md px-2.5 py-2 text-left text-text hover:bg-[rgba(255,255,255,0.06)] disabled:cursor-not-allowed disabled:opacity-50 ${
                  item.destructive ? "text-error" : ""
                }`}
                onClick={(event) => {
                  event.stopPropagation();
                  if (item.disabled) {
                    return;
                  }
                  item.onClick?.();
                  setOpen(false);
                }}
                disabled={item.disabled}
              >
                {item.label}
              </button>
            );
          })}
        </div>
      ) : null}
    </div>
  );
}
