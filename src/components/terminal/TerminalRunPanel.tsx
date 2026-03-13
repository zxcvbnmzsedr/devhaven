import type { PointerEvent as ReactPointerEvent } from "react";
import type { ITheme } from "xterm";

import {
  toScriptExecutionStateFromQuickState,
  type ScriptLocalPhase,
  type ScriptRuntime,
} from "../../hooks/useQuickCommandRuntime";
import type { QuickCommandJob } from "../../models/quickCommands";
import type { RunPanelTab, TerminalSessionSnapshot } from "../../models/terminal";
import { IconChevronsDownUp, IconPlay, IconRerun, IconSquareStop, IconX } from "../Icons";
import PaneHost from "./PaneHost";

type TerminalRunPanelProps = {
  open: boolean;
  height: number;
  tabs: RunPanelTab[];
  activeTabId: string | null;
  sessions: Record<string, TerminalSessionSnapshot>;
  projectPath: string;
  windowLabel: string;
  clientId: string;
  xtermTheme: ITheme;
  terminalUseWebglRenderer: boolean;
  scriptRuntimeById: Record<string, ScriptRuntime>;
  quickCommandJobByScriptId: Record<string, QuickCommandJob>;
  scriptLocalPhaseById: Record<string, ScriptLocalPhase>;
  isScriptRuntimeValid: (runtime: ScriptRuntime) => boolean;
  onSelectTab: (tabId: string) => void;
  onCloseTab: (tabId: string) => void;
  onCollapse: () => void;
  onResizeStart: (event: ReactPointerEvent<HTMLDivElement>) => void;
  onRerunActiveTab?: () => void;
  onStopActiveTab?: () => void;
  activeTabRunning?: boolean;
  onPtyReady: (sessionId: string, ptyId: string) => void;
  onExit: (sessionId: string, code?: number | null) => void;
};

function resolveTabExecutionState({
  tab,
  scriptRuntimeById,
  quickCommandJobByScriptId,
  scriptLocalPhaseById,
  isScriptRuntimeValid,
}: {
  tab: RunPanelTab;
  scriptRuntimeById: Record<string, ScriptRuntime>;
  quickCommandJobByScriptId: Record<string, QuickCommandJob>;
  scriptLocalPhaseById: Record<string, ScriptLocalPhase>;
  isScriptRuntimeValid: (runtime: ScriptRuntime) => boolean;
}) {
  const quickJob = quickCommandJobByScriptId[tab.scriptId] ?? null;
  if (quickJob && (tab.endedAt === null || tab.endedAt === undefined)) {
    return toScriptExecutionStateFromQuickState(quickJob.state);
  }

  const runtime = scriptRuntimeById[tab.scriptId] ?? null;
  const runtimeMatches = Boolean(runtime && runtime.tabId === tab.id && isScriptRuntimeValid(runtime));
  if (!runtimeMatches) {
    return "idle";
  }
  return scriptLocalPhaseById[tab.scriptId] ?? "running";
}

function renderStatusLabel(tab: RunPanelTab, state: string) {
  if (state === "starting") {
    return "启动中";
  }
  if (state === "running") {
    return "运行中";
  }
  if (state === "stoppingSoft" || state === "stoppingHard") {
    return "停止中";
  }
  if (tab.endedAt === null || tab.endedAt === undefined) {
    return "已停止";
  }
  if (tab.exitCode === 0) {
    return "已完成";
  }
  if (typeof tab.exitCode === "number") {
    return `退出(${tab.exitCode})`;
  }
  return "已结束";
}

function resolveStatusClass(tab: RunPanelTab, state: string) {
  if (state === "starting" || state === "running") {
    return "bg-[var(--terminal-accent)]";
  }
  if (state === "stoppingSoft" || state === "stoppingHard") {
    return "bg-[rgba(251,191,36,0.95)]";
  }
  if (tab.endedAt !== null && tab.endedAt !== undefined) {
    return tab.exitCode === 0 ? "bg-[rgba(34,197,94,0.9)]" : "bg-[rgba(239,68,68,0.9)]";
  }
  return "bg-[var(--terminal-muted-fg)]";
}

export default function TerminalRunPanel({
  open,
  height,
  tabs,
  activeTabId,
  sessions,
  projectPath,
  windowLabel,
  clientId,
  xtermTheme,
  terminalUseWebglRenderer,
  scriptRuntimeById,
  quickCommandJobByScriptId,
  scriptLocalPhaseById,
  isScriptRuntimeValid,
  onSelectTab,
  onCloseTab,
  onCollapse,
  onResizeStart,
  onRerunActiveTab,
  onStopActiveTab,
  activeTabRunning = false,
  onPtyReady,
  onExit,
}: TerminalRunPanelProps) {
  const activeTab = activeTabId ? tabs.find((tab) => tab.id === activeTabId) ?? null : tabs[0] ?? null;
  const activeSession = activeTab ? sessions[activeTab.sessionId] ?? null : null;

  if (!open) {
    return null;
  }
  return (
    <section
      className="relative flex shrink-0 flex-col border-t border-[var(--terminal-divider)] bg-[var(--terminal-panel-bg)]"
      style={{ height }}
    >
      <div
        className="absolute left-0 right-0 top-0 z-20 h-1 cursor-row-resize bg-transparent hover:bg-[var(--terminal-divider)]"
        onPointerDown={onResizeStart}
      />
      <div className="flex h-9 shrink-0 items-center gap-2 border-b border-[var(--terminal-divider)] px-2">
        <span className="shrink-0 text-[11px] font-semibold text-[var(--terminal-muted-fg)]">运行</span>
        <div className="flex min-w-0 flex-1 items-center gap-1 overflow-x-auto">
          {tabs.map((tab) => {
            const state = resolveTabExecutionState({
              tab,
              scriptRuntimeById,
              quickCommandJobByScriptId,
              scriptLocalPhaseById,
              isScriptRuntimeValid,
            });
            const statusLabel = renderStatusLabel(tab, state);
            const isActive = tab.id === activeTabId;
            return (
              <button
                key={tab.id}
                type="button"
                className={`group flex shrink-0 items-center gap-2 rounded-md px-2 py-1 text-[11px] ${
                  isActive
                    ? "bg-[var(--terminal-accent-bg)] text-[var(--terminal-fg)]"
                    : "text-[var(--terminal-muted-fg)] hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)]"
                }`}
                title={`${tab.title} · ${statusLabel}`}
                onClick={() => onSelectTab(tab.id)}
              >
                <span className={`h-2 w-2 rounded-full ${resolveStatusClass(tab, state)}`} aria-hidden="true" />
                <span className="max-w-[200px] truncate">{tab.title}</span>
                <span className="max-w-[110px] truncate text-[10px] opacity-80">{statusLabel}</span>
                <span
                  className="inline-flex h-4 w-4 items-center justify-center rounded opacity-70 transition-opacity hover:bg-[var(--terminal-hover-bg)] hover:opacity-100"
                  onClick={(event) => {
                    event.preventDefault();
                    event.stopPropagation();
                    onCloseTab(tab.id);
                  }}
                >
                  <IconX size={11} />
                </span>
              </button>
            );
          })}
        </div>
        {/* Action buttons for active tab */}
        <div className="flex items-center gap-1">
          <button
            type="button"
            className="inline-flex h-7 w-7 items-center justify-center rounded-md border border-transparent text-[rgba(34,197,94,0.95)] transition-colors duration-150 hover:border-[var(--terminal-divider)] hover:bg-[var(--terminal-hover-bg)] disabled:cursor-not-allowed disabled:opacity-50"
            title={activeTabRunning ? "重新运行" : "运行"}
            disabled={!onRerunActiveTab}
            onClick={onRerunActiveTab}
          >
            {activeTabRunning ? <IconRerun size={14} /> : <IconPlay size={14} />}
          </button>
          <button
            type="button"
            className={`inline-flex h-7 w-7 items-center justify-center rounded-md border border-transparent transition-colors duration-150 hover:border-[var(--terminal-divider)] hover:bg-[var(--terminal-hover-bg)] disabled:cursor-not-allowed disabled:opacity-50 ${
              activeTabRunning
                ? "text-[rgba(239,68,68,0.95)]"
                : "text-[var(--terminal-muted-fg)]"
            }`}
            title="停止"
            disabled={!activeTabRunning || !onStopActiveTab}
            onClick={onStopActiveTab}
          >
            <IconSquareStop size={14} />
          </button>
        </div>
        <button
          type="button"
          className="inline-flex h-7 w-7 items-center justify-center rounded-md border border-transparent text-[var(--terminal-muted-fg)] transition-colors duration-150 hover:border-[var(--terminal-divider)] hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)]"
          title="收起运行面板"
          onClick={onCollapse}
        >
          <IconChevronsDownUp size={14} />
        </button>
      </div>
      <div className="relative min-h-0 flex-1 overflow-hidden">
        {tabs.length === 0 ? (
          <div className="flex h-full items-center justify-center text-[12px] text-[var(--terminal-muted-fg)]">
            暂无运行任务
          </div>
        ) : !activeTab || !activeSession ? (
          <div className="flex h-full items-center justify-center text-[12px] text-[var(--terminal-muted-fg)]">
            当前运行会话不可用
          </div>
        ) : (
          <div className="absolute inset-0 flex min-h-0 min-w-0">
            <PaneHost
              kind="run"
              sessionId={activeTab.sessionId}
              projectPath={projectPath}
              cwd={activeSession.cwd ?? projectPath}
              savedState={activeSession.savedState ?? null}
              windowLabel={windowLabel}
              clientId={clientId}
              useWebgl={terminalUseWebglRenderer}
              theme={xtermTheme}
              isActive
              onActivate={() => onSelectTab(activeTab.id)}
              onPtyReady={onPtyReady}
              onExit={onExit}
              preserveSessionOnUnmount
            />
          </div>
        )}
      </div>
    </section>
  );
}
