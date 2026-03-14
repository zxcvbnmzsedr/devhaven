import { useEffect, useRef, useState } from "react";

import type { ScriptExecutionState } from "../../hooks/useQuickCommandRuntime";
import type { TerminalRightSidebarTab } from "../../models/terminal";
import type { ProjectScript } from "../../models/types";
import type {
  ControlPlaneSurfaceProjection,
  ControlPlaneWorkspaceProjection,
} from "../../utils/controlPlaneProjection";
import {
  resolveDisplayedControlPlaneMessage,
} from "../../utils/controlPlaneProjection";
import { IconChevronDown, IconFolder, IconGitBranch, IconPlay, IconRerun, IconSettings, IconSquareStop } from "../Icons";
import TerminalTabs from "./TerminalTabs";

type TerminalHeaderTab = {
  id: string;
  title: string;
};

type TerminalWorkspaceHeaderProps = {
  projectName: string | null | undefined;
  projectPath: string;
  codexRunningCount: number;
  controlPlaneProjection: ControlPlaneWorkspaceProjection;
  activePaneControlProjection: ControlPlaneSurfaceProjection | null;
  rightSidebarOpen: boolean;
  rightSidebarTab: TerminalRightSidebarTab;
  scripts: ProjectScript[];
  selectedScriptId: string | null;
  selectedScriptState: ScriptExecutionState;
  runDisabled: boolean;
  stopDisabled: boolean;
  scriptActionsDisabled: boolean;
  tabs: TerminalHeaderTab[];
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
  controlPlaneProjection,
  activePaneControlProjection,
  rightSidebarOpen,
  rightSidebarTab,
  scripts,
  selectedScriptId,
  selectedScriptState,
  runDisabled,
  stopDisabled,
  scriptActionsDisabled,
  tabs,
  activeTabId,
  onSelectScript,
  onEditScript,
  onDeleteScript: _onDeleteScript,
  onRunScript,
  onStopScript,
  onToggleRightSidebar,
  onSelectTab,
  onNewTab,
  onCloseTab,
}: TerminalWorkspaceHeaderProps) {
  const [configDropdownOpen, setConfigDropdownOpen] = useState(false);
  const configDropdownRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!configDropdownOpen) {
      return;
    }
    const handleMouseDown = (event: MouseEvent) => {
      if (configDropdownRef.current?.contains(event.target as Node)) {
        return;
      }
      setConfigDropdownOpen(false);
    };
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setConfigDropdownOpen(false);
      }
    };
    document.addEventListener("mousedown", handleMouseDown);
    document.addEventListener("keydown", handleKeyDown);
    return () => {
      document.removeEventListener("mousedown", handleMouseDown);
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, [configDropdownOpen]);

  useEffect(() => {
    if (!scriptActionsDisabled) {
      return;
    }
    setConfigDropdownOpen(false);
  }, [scriptActionsDisabled]);

  const scriptName = scripts.find((s) => s.id === selectedScriptId)?.name ?? "未选择";
  const isRunning = selectedScriptState === "running";
  const isStopping = selectedScriptState === "stoppingSoft" || selectedScriptState === "stoppingHard";
  const isStarting = selectedScriptState === "starting";
  const displayedControlPlaneMessage = resolveDisplayedControlPlaneMessage(
    activePaneControlProjection,
    controlPlaneProjection,
  );

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
      {controlPlaneProjection.attention !== "idle" || controlPlaneProjection.unreadCount > 0 ? (
        <div
          className="inline-flex shrink-0 items-center gap-1.5 rounded-full border border-[var(--terminal-divider)] bg-[var(--terminal-hover-bg)] px-2 py-0.5 text-[11px] font-semibold text-[var(--terminal-muted-fg)]"
          title={controlPlaneProjection.latestMessage ?? "控制平面状态更新"}
        >
          <span
            className={`h-2 w-2 rounded-full ${
              controlPlaneProjection.attention === "error"
                ? "bg-[rgba(239,68,68,0.95)]"
                : controlPlaneProjection.attention === "waiting"
                  ? "bg-[rgba(245,158,11,0.95)]"
                  : controlPlaneProjection.attention === "completed"
                    ? "bg-[rgba(34,197,94,0.95)]"
                    : "bg-[var(--terminal-accent)]"
            }`}
            aria-hidden="true"
          />
          <span className="whitespace-nowrap">控制面：{controlPlaneProjection.attention}</span>
          {controlPlaneProjection.unreadCount > 0 ? (
            <span className="rounded-full bg-[var(--terminal-accent-bg)] px-1.5 text-[10px] text-[var(--terminal-fg)]">
              {controlPlaneProjection.unreadCount}
            </span>
          ) : null}
        </div>
      ) : null}
      {displayedControlPlaneMessage ? (
        <div
          className="max-w-[260px] truncate text-[11px] font-medium text-[var(--terminal-muted-fg)]"
          title={displayedControlPlaneMessage}
        >
          {displayedControlPlaneMessage}
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
        {/* 配置选择器 */}
        <div className="relative" ref={configDropdownRef}>
          <button
            type="button"
            className="h-7 rounded-md border border-[var(--terminal-divider)] px-2 inline-flex items-center gap-1.5 text-[12px] font-semibold text-[var(--terminal-fg)] transition-colors duration-150 hover:bg-[var(--terminal-hover-bg)] disabled:cursor-not-allowed disabled:opacity-50"
            title={scripts.length === 0 ? "暂无配置" : "选择运行配置"}
            disabled={scriptActionsDisabled}
            onClick={() => setConfigDropdownOpen((prev) => !prev)}
          >
            {(isRunning || isStarting) ? (
              <span className="h-2 w-2 shrink-0 rounded-full bg-[rgba(34,197,94,0.95)] animate-pulse" aria-hidden="true" />
            ) : isStopping ? (
              <span className="h-2 w-2 shrink-0 rounded-full bg-[rgba(234,179,8,0.95)] animate-pulse" aria-hidden="true" />
            ) : null}
            <span className="max-w-[140px] truncate">{scripts.length === 0 ? "暂无配置" : scriptName}</span>
            <IconChevronDown size={12} className="shrink-0 text-[var(--terminal-muted-fg)]" />
          </button>
          {configDropdownOpen ? (
            <div className="absolute right-0 top-full z-20 mt-1.5 min-w-[180px] rounded-md border border-[var(--terminal-divider)] bg-[var(--terminal-panel-bg)] p-1 shadow-[0_8px_24px_rgba(0,0,0,0.28)]">
              {scripts.map((script) => (
                <button
                  key={script.id}
                  type="button"
                  className={`flex w-full items-center gap-1.5 rounded-md px-2 py-1.5 text-left text-[12px] text-[var(--terminal-fg)] transition-colors hover:bg-[var(--terminal-hover-bg)] ${
                    script.id === selectedScriptId ? "font-semibold" : ""
                  }`}
                  onClick={() => {
                    onSelectScript(script.id);
                    setConfigDropdownOpen(false);
                  }}
                >
                  {script.id === selectedScriptId && (isRunning || isStarting) ? (
                    <span className="h-2 w-2 shrink-0 rounded-full bg-[rgba(34,197,94,0.95)] animate-pulse" aria-hidden="true" />
                  ) : script.id === selectedScriptId && isStopping ? (
                    <span className="h-2 w-2 shrink-0 rounded-full bg-[rgba(234,179,8,0.95)] animate-pulse" aria-hidden="true" />
                  ) : (
                    <span className="h-2 w-2 shrink-0" aria-hidden="true" />
                  )}
                  {script.name}
                </button>
              ))}
              {scripts.length > 0 ? <hr className="my-1 border-[var(--terminal-divider)]" /> : null}
              <button
                type="button"
                className="flex w-full items-center rounded-md px-2 py-1.5 text-left text-[12px] text-[var(--terminal-fg)] transition-colors hover:bg-[var(--terminal-hover-bg)]"
                onClick={() => {
                  setConfigDropdownOpen(false);
                  onEditScript();
                }}
              >
                编辑配置...
              </button>
            </div>
          ) : null}
        </div>
        {/* 图标按钮组 */}
        <div className="flex items-center gap-1.5">
          {/* 运行 / 重新运行按钮 */}
          <button
            type="button"
            className="h-7 w-7 rounded-md border border-[var(--terminal-divider)] inline-flex items-center justify-center transition-colors duration-150 hover:bg-[var(--terminal-hover-bg)] disabled:cursor-not-allowed disabled:opacity-50 text-[rgba(34,197,94,0.95)]"
            title={isRunning ? `重新运行 '${scriptName}'` : `运行 '${scriptName}'`}
            disabled={runDisabled}
            onClick={onRunScript}
          >
            {isRunning ? <IconRerun size={14} /> : <IconPlay size={14} />}
          </button>
          {/* 停止按钮 */}
          <button
            type="button"
            className={`h-7 w-7 rounded-md border inline-flex items-center justify-center transition-colors duration-150 hover:bg-[var(--terminal-hover-bg)] disabled:cursor-not-allowed disabled:opacity-50 ${
              stopDisabled
                ? "border-[var(--terminal-divider)] text-[var(--terminal-muted-fg)]"
                : "border-[rgba(239,68,68,0.4)] text-[rgba(239,68,68,0.95)]"
            }`}
            title={`停止 '${scriptName}'`}
            disabled={stopDisabled}
            onClick={onStopScript}
          >
            <IconSquareStop size={14} />
          </button>
          {/* 设置按钮 */}
          <button
            type="button"
            className="h-7 w-7 rounded-md border border-[var(--terminal-divider)] inline-flex items-center justify-center transition-colors duration-150 hover:bg-[var(--terminal-hover-bg)] text-[var(--terminal-muted-fg)] hover:text-[var(--terminal-fg)]"
            title="运行配置"
            onClick={onEditScript}
          >
            <IconSettings size={14} />
          </button>
        </div>
      </div>
    </header>
  );
}
