import { useEffect, useRef, useState } from "react";

import type { ScriptExecutionState } from "../../hooks/useQuickCommandRuntime";
import type { TerminalRightSidebarTab, TerminalTab } from "../../models/terminal";
import type { ProjectScript } from "../../models/types";
import { IconFolder, IconGitBranch, IconMoreHorizontal } from "../Icons";
import TerminalTabs from "./TerminalTabs";

type TerminalWorkspaceHeaderProps = {
  projectName: string | null | undefined;
  projectPath: string;
  codexRunningCount: number;
  rightSidebarOpen: boolean;
  rightSidebarTab: TerminalRightSidebarTab;
  scripts: ProjectScript[];
  selectedScriptId: string | null;
  selectedScriptState: ScriptExecutionState;
  quickCommandMessage: string | null;
  runDisabled: boolean;
  stopDisabled: boolean;
  scriptActionsDisabled: boolean;
  tabs: TerminalTab[];
  activeTabId: string;
  onSelectScript: (scriptId: string) => void;
  onEditScript: () => void;
  onDeleteScript: () => void;
  onRunScript: () => void;
  onStopScript: () => void;
  onToggleRightSidebar: () => void;
  onSelectTab: (tabId: string) => void;
  onNewTab: () => void;
  onCloseTab: (tabId: string) => void;
};

export default function TerminalWorkspaceHeader({
  projectName,
  projectPath,
  codexRunningCount,
  rightSidebarOpen,
  rightSidebarTab,
  scripts,
  selectedScriptId,
  selectedScriptState,
  quickCommandMessage,
  runDisabled,
  stopDisabled,
  scriptActionsDisabled,
  tabs,
  activeTabId,
  onSelectScript,
  onEditScript,
  onDeleteScript,
  onRunScript,
  onStopScript,
  onToggleRightSidebar,
  onSelectTab,
  onNewTab,
  onCloseTab,
}: TerminalWorkspaceHeaderProps) {
  const [scriptActionsOpen, setScriptActionsOpen] = useState(false);
  const scriptActionsRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!scriptActionsOpen) {
      return;
    }
    const handleMouseDown = (event: MouseEvent) => {
      if (scriptActionsRef.current?.contains(event.target as Node)) {
        return;
      }
      setScriptActionsOpen(false);
    };
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setScriptActionsOpen(false);
      }
    };
    document.addEventListener("mousedown", handleMouseDown);
    document.addEventListener("keydown", handleKeyDown);
    return () => {
      document.removeEventListener("mousedown", handleMouseDown);
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, [scriptActionsOpen]);

  useEffect(() => {
    if (!scriptActionsDisabled) {
      return;
    }
    setScriptActionsOpen(false);
  }, [scriptActionsDisabled]);

  const statusText =
    selectedScriptState === "stoppingHard"
      ? "强制停止中"
      : selectedScriptState === "stoppingSoft"
        ? "停止中"
        : selectedScriptState === "starting"
          ? "启动中"
          : selectedScriptState === "running"
            ? "运行中"
            : null;

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
      <TerminalTabs
        tabs={tabs}
        activeTabId={activeTabId}
        onSelect={onSelectTab}
        onNewTab={onNewTab}
        onCloseTab={onCloseTab}
      />
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
      <div className="ml-auto flex shrink-0 items-center gap-2">
        <div className="inline-flex h-7 min-w-[180px] items-center rounded-md border border-[var(--terminal-divider)] bg-[var(--terminal-bg)] px-2">
          <select
            className="w-full border-none bg-transparent text-[12px] font-semibold text-[var(--terminal-fg)] outline-none"
            value={selectedScriptId ?? ""}
            onChange={(event) => onSelectScript(event.target.value)}
            disabled={scripts.length === 0}
            title={scripts.length === 0 ? "暂无快捷命令" : "选择运行配置"}
          >
            {scripts.length === 0 ? <option value="">暂无快捷命令</option> : null}
            {scripts.map((script) => (
              <option key={script.id} value={script.id}>
                {script.name}
              </option>
            ))}
          </select>
        </div>
        <div className="relative" ref={scriptActionsRef}>
          <button
            className="inline-flex h-7 w-7 items-center justify-center rounded-md border border-[var(--terminal-divider)] bg-transparent text-[var(--terminal-muted-fg)] transition-colors duration-150 hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)] disabled:cursor-not-allowed disabled:opacity-50"
            type="button"
            title={scriptActionsDisabled ? "暂无可操作配置" : "配置操作"}
            onClick={() => setScriptActionsOpen((prev) => !prev)}
            disabled={scriptActionsDisabled}
          >
            <IconMoreHorizontal size={14} />
          </button>
          {scriptActionsOpen ? (
            <div className="absolute right-0 top-full z-20 mt-1.5 min-w-[160px] rounded-md border border-[var(--terminal-divider)] bg-[var(--terminal-panel-bg)] p-1 shadow-[0_8px_24px_rgba(0,0,0,0.28)]">
              <button
                type="button"
                className="flex w-full items-center rounded-md px-2 py-1.5 text-left text-[12px] text-[var(--terminal-fg)] transition-colors hover:bg-[var(--terminal-hover-bg)]"
                onClick={() => {
                  setScriptActionsOpen(false);
                  onEditScript();
                }}
              >
                编辑配置...
              </button>
              <button
                type="button"
                className="mt-1 flex w-full items-center rounded-md px-2 py-1.5 text-left text-[12px] text-[rgba(239,68,68,0.95)] transition-colors hover:bg-[rgba(239,68,68,0.15)]"
                onClick={() => {
                  setScriptActionsOpen(false);
                  onDeleteScript();
                }}
              >
                删除当前配置
              </button>
            </div>
          ) : null}
        </div>
        {quickCommandMessage ? (
          <span
            className="max-w-[180px] truncate text-[11px] font-semibold text-[var(--terminal-muted-fg)]"
            title={quickCommandMessage}
          >
            {quickCommandMessage}
          </span>
        ) : null}
        {statusText ? (
          <span className="inline-flex min-w-[56px] items-center justify-center text-[11px] font-semibold text-[var(--terminal-muted-fg)]">
            {statusText}
          </span>
        ) : null}
        <button
          className="inline-flex h-7 items-center justify-center rounded-md border border-[var(--terminal-divider)] bg-[var(--terminal-accent-bg)] px-2.5 text-[12px] font-semibold text-[var(--terminal-fg)] transition-colors duration-150 hover:bg-[var(--terminal-hover-bg)] disabled:cursor-not-allowed disabled:opacity-50"
          type="button"
          title="运行当前配置"
          disabled={runDisabled}
          onClick={onRunScript}
        >
          运行
        </button>
        <button
          className="inline-flex h-7 items-center justify-center rounded-md border border-[var(--terminal-divider)] bg-transparent px-2.5 text-[12px] font-semibold text-[var(--terminal-muted-fg)] transition-colors duration-150 hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)] disabled:cursor-not-allowed disabled:opacity-50"
          type="button"
          title="停止当前配置"
          disabled={stopDisabled}
          onClick={onStopScript}
        >
          停止
        </button>
      </div>
    </header>
  );
}
