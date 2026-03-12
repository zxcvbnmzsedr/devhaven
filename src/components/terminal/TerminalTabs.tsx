import { IconPlusCircle, IconX } from "../Icons";

type HeaderTab = {
  id: string;
  title: string;
};

type TerminalTabsProps = {
  tabs: HeaderTab[];
  activeTabId: string;
  onSelect: (tabId: string) => void;
  onNewTab: () => void;
  onCloseTab: (tabId: string) => void;
};

export default function TerminalTabs({
  tabs,
  activeTabId,
  onSelect,
  onNewTab,
  onCloseTab,
}: TerminalTabsProps) {
  return (
    <div className="flex min-w-0 flex-1 items-center gap-1 overflow-x-auto">
      {tabs.map((tab) => (
        <button
          key={tab.id}
          className={`flex shrink-0 items-center gap-2 rounded-md px-2.5 py-1 text-[12px] font-semibold ${
            tab.id === activeTabId
              ? "bg-[var(--terminal-accent-bg)] text-[var(--terminal-fg)]"
              : "text-[var(--terminal-muted-fg)] hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)]"
          }`}
          onClick={() => onSelect(tab.id)}
        >
          <span className="truncate max-w-[140px]">{tab.title}</span>
          {tabs.length > 1 ? (
            <span
              className="inline-flex h-4 w-4 items-center justify-center rounded hover:bg-[var(--terminal-hover-bg)]"
              onClick={(event) => {
                event.stopPropagation();
                onCloseTab(tab.id);
              }}
            >
              <IconX size={12} />
            </span>
          ) : null}
        </button>
      ))}
      <button
        className="inline-flex min-h-6 min-w-6 shrink-0 items-center justify-center rounded-md p-1 text-[var(--terminal-muted-fg)] transition-colors duration-150 hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)]"
        onClick={onNewTab}
        aria-label="新建终端 Tab"
      >
        <IconPlusCircle size={16} />
      </button>
    </div>
  );
}
