import type { TerminalRightSidebarTab, TerminalTab } from "../../models/terminal";
import { IconFolder, IconGitBranch, IconSidebarRight } from "../Icons";
import TerminalTabs from "./TerminalTabs";

type TerminalWorkspaceHeaderProps = {
  projectName: string | null | undefined;
  projectPath: string;
  codexRunningCount: number;
  panelOpen: boolean;
  rightSidebarOpen: boolean;
  rightSidebarTab: TerminalRightSidebarTab;
  tabs: TerminalTab[];
  activeTabId: string;
  onTogglePanel: () => void;
  onToggleRightSidebar: () => void;
  onSelectTab: (tabId: string) => void;
  onNewTab: () => void;
  onCloseTab: (tabId: string) => void;
};

export default function TerminalWorkspaceHeader({
  projectName,
  projectPath,
  codexRunningCount,
  panelOpen,
  rightSidebarOpen,
  rightSidebarTab,
  tabs,
  activeTabId,
  onTogglePanel,
  onToggleRightSidebar,
  onSelectTab,
  onNewTab,
  onCloseTab,
}: TerminalWorkspaceHeaderProps) {
  return (
    <header className="flex items-center gap-3 border-b border-[var(--terminal-divider)] bg-[var(--terminal-panel-bg)] px-3 py-2">
      <div className="max-w-[200px] truncate text-[13px] font-semibold text-[var(--terminal-fg)]">{projectName ?? projectPath}</div>
      {codexRunningCount > 0 ? (
        <div
          className="inline-flex shrink-0 items-center gap-1.5 rounded-full border border-[var(--terminal-divider)] bg-[var(--terminal-hover-bg)] px-2 py-0.5 text-[11px] font-semibold text-[var(--terminal-muted-fg)]"
          title={`Codex 运行中（${codexRunningCount} 个会话）`}
        >
          <span className="h-2 w-2 rounded-full bg-[var(--terminal-accent)]" aria-hidden="true" />
          <span className="whitespace-nowrap">Codex 运行中</span>
        </div>
      ) : null}
      <button
        className={`inline-flex h-7 w-7 items-center justify-center rounded-md border border-[var(--terminal-divider)] text-[var(--terminal-muted-fg)] transition-colors duration-150 hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)] ${
          panelOpen ? "bg-[var(--terminal-hover-bg)]" : ""
        }`}
        type="button"
        title={panelOpen ? "隐藏快捷命令" : "显示快捷命令"}
        onClick={onTogglePanel}
      >
        <IconSidebarRight size={16} />
      </button>
      <button
        className={`inline-flex h-7 items-center gap-1.5 rounded-md border border-[var(--terminal-divider)] px-2 text-[var(--terminal-muted-fg)] transition-colors duration-150 hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)] ${
          rightSidebarOpen ? "bg-[var(--terminal-hover-bg)]" : ""
        }`}
        type="button"
        title={rightSidebarOpen ? "隐藏侧边栏" : "显示侧边栏"}
        onClick={onToggleRightSidebar}
      >
        {rightSidebarTab === "files" ? <IconFolder size={16} /> : <IconGitBranch size={16} />}
        <span className="text-[12px] font-semibold">{rightSidebarTab === "files" ? "文件" : "Git"}</span>
      </button>
      <TerminalTabs
        tabs={tabs}
        activeTabId={activeTabId}
        onSelect={onSelectTab}
        onNewTab={onNewTab}
        onCloseTab={onCloseTab}
      />
    </header>
  );
}
