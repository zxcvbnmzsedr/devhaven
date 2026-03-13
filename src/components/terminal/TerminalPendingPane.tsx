import { useEffect, useMemo, useRef, useState } from "react";

import {
  PANE_AGENT_PROVIDER_LABEL,
  listPaneCreationTemplates,
  movePaneCreationSelection,
  type PaneCreationTemplate,
} from "../../models/agent";

type TerminalPendingPaneProps = {
  onSelectTemplate: (template: PaneCreationTemplate) => void;
};

export default function TerminalPendingPane({
  onSelectTemplate,
}: TerminalPendingPaneProps) {
  const templates = useMemo(() => listPaneCreationTemplates(), []);
  const [selectedIndex, setSelectedIndex] = useState(0);
  const optionRefs = useRef<Array<HTMLButtonElement | null>>([]);

  useEffect(() => {
    const target = optionRefs.current[selectedIndex];
    if (!target) {
      return;
    }
    const frame = window.requestAnimationFrame(() => {
      target.focus();
    });
    return () => {
      window.cancelAnimationFrame(frame);
    };
  }, [selectedIndex]);

  const handleKeyDown = (event: React.KeyboardEvent<HTMLButtonElement>) => {
    if (event.key === "ArrowDown") {
      event.preventDefault();
      setSelectedIndex((current) =>
        movePaneCreationSelection(current, "down", templates.length),
      );
      return;
    }
    if (event.key === "ArrowUp") {
      event.preventDefault();
      setSelectedIndex((current) =>
        movePaneCreationSelection(current, "up", templates.length),
      );
      return;
    }
    if (event.key === "Enter") {
      event.preventDefault();
      onSelectTemplate(templates[selectedIndex] ?? templates[0] ?? { mode: "shell" });
    }
  };

  return (
    <div className="flex h-full w-full min-h-0 min-w-0 items-center justify-center bg-[linear-gradient(180deg,rgba(255,255,255,0.02),rgba(255,255,255,0.01))] p-6">
      <div className="flex w-full max-w-[420px] flex-col gap-3 rounded-2xl border border-dashed border-[var(--terminal-divider)] bg-[color-mix(in_srgb,var(--terminal-panel-bg)_86%,transparent)] p-5 shadow-[inset_0_1px_0_rgba(255,255,255,0.04),0_18px_40px_rgba(0,0,0,0.18)] backdrop-blur-sm">
        {templates.map((template, index) => {
          const isSelected = index === selectedIndex;
          const title =
            template.mode === "shell"
              ? "Shell"
              : `${PANE_AGENT_PROVIDER_LABEL[template.provider]} Agent`;
          const description =
            template.mode === "shell"
              ? "打开一个普通终端，会话完全由你自己控制。"
              : `在这个 Pane 中直接启动 ${PANE_AGENT_PROVIDER_LABEL[template.provider]}。`;
          return (
            <button
              key={template.mode === "shell" ? "shell" : template.provider}
              ref={(node) => {
                optionRefs.current[index] = node;
              }}
              type="button"
              className={`rounded-xl border px-3 py-3 text-left text-[13px] font-semibold text-[var(--terminal-fg)] transition-colors outline-none ${
                isSelected
                  ? "border-[var(--terminal-accent-outline)] bg-[var(--terminal-hover-bg)] ring-1 ring-[var(--terminal-accent-outline)]"
                  : "border-[var(--terminal-divider)] bg-[var(--terminal-bg)] hover:bg-[var(--terminal-hover-bg)]"
              }`}
              onFocus={() => setSelectedIndex(index)}
              onKeyDown={handleKeyDown}
              onClick={() => onSelectTemplate(template)}
            >
              <div>{title}</div>
              <div className="mt-1 text-[11px] font-normal text-[var(--terminal-muted-fg)]">
                {description}
              </div>
            </button>
          );
        })}
      </div>
    </div>
  );
}
