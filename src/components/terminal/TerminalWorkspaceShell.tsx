import type { PointerEvent as ReactPointerEvent } from "react";
import type { ITheme } from "xterm";

import type { ScriptExecutionState, ScriptLocalPhase, ScriptRuntime } from "../../hooks/useQuickCommandRuntime";
import type {
  ControlPlaneSurfaceProjection,
  ControlPlaneWorkspaceProjection,
} from "../../utils/controlPlaneProjection";
import type { QuickCommandJob } from "../../models/quickCommands";
import type {
  RunPanelTab,
  TerminalLayoutTab,
  TerminalPaneProjection,
  TerminalRightSidebarTab,
  TerminalSessionSnapshot,
} from "../../models/terminal";
import type { ProjectScript } from "../../models/types";
import { IconChevronDown } from "../Icons";
import type { GitSelectedFile } from "./TerminalGitPanel";
import PaneHost from "./PaneHost";
import ResizablePanel from "./ResizablePanel";
import SplitLayout from "./SplitLayout";
import TerminalRunPanel from "./TerminalRunPanel";
import TerminalRightSidebar from "./TerminalRightSidebar";
import TerminalWorkspaceHeader from "./TerminalWorkspaceHeader";

type HeaderTab = {
  id: string;
  title: string;
};

export type TerminalWorkspaceShellProps = {
  projectName: string | null | undefined;
  projectId: string | null;
  projectPath: string;
  codexRunningCount: number;
  controlPlaneProjection: ControlPlaneWorkspaceProjection;
  activePaneControlProjection: ControlPlaneSurfaceProjection | null;
  isGitRepo: boolean;
  windowLabel: string;
  runtimeClientId: string;
  xtermTheme: ITheme;
  terminalPaneUseWebgl: boolean;
  scripts: ProjectScript[];
  selectedScriptId: string | null;
  selectedScriptState: ScriptExecutionState;
  runDisabled: boolean;
  stopDisabled: boolean;
  scriptActionsDisabled: boolean;
  headerTabs: HeaderTab[];
  activeTabId: string;
  activeWorkspaceTab: TerminalLayoutTab | null;
  activePaneProjections: Record<string, TerminalPaneProjection>;
  rightSidebarOpen: boolean;
  rightSidebarWidth: number;
  rightSidebarTab: TerminalRightSidebarTab;
  previewDirty: boolean;
  previewFilePath: string | null;
  filePanelShowHidden: boolean;
  gitSelected: GitSelectedFile | null;
  runPanelTabs: RunPanelTab[];
  runPanelActiveTabId: string | null;
  runPanelOpen: boolean;
  runPanelHeight: number;
  activeTabRunning: boolean;
  sessionSnapshots: Record<string, TerminalSessionSnapshot>;
  scriptRuntimeById: Record<string, ScriptRuntime>;
  quickCommandJobByScriptId: Record<string, QuickCommandJob>;
  scriptLocalPhaseById: Record<string, ScriptLocalPhase>;
  isScriptRuntimeValid: (runtime: ScriptRuntime) => boolean;
  onSelectScript: (scriptId: string) => void;
  onEditScript: () => void;
  onDeleteScript: () => void;
  onRunScript: () => void;
  onStopScript: () => void;
  onToggleRightSidebar: () => void;
  onSelectTab: (tabId: string) => void;
  onNewTab: () => void;
  onCloseTab: (tabId: string) => void;
  onResize: (path: number[], ratios: number[]) => void;
  onActivateSession: (tabId: string, sessionId: string) => void;
  onPtyReady: (sessionId: string, ptyId: string) => void;
  onSessionExit: (sessionId: string, code?: number | null) => void;
  onSessionOutput: (sessionId: string, data: string) => void;
  onSetRightSidebarWidth: (width: number) => void;
  onToggleShowHidden: (next: boolean) => void;
  onOpenPreview: (relativePath: string) => void;
  onClosePreview: () => void;
  onPreviewDirtyChange: (dirty: boolean) => void;
  onSelectGitFile: (next: GitSelectedFile | null) => void;
  onCloseGitSelection: () => void;
  onChangeRightSidebarTab: (tab: TerminalRightSidebarTab) => void;
  onCloseRightSidebar: () => void;
  onSelectRunTab: (tabId: string) => void;
  onCloseRunTab: (tabId: string) => void;
  onSetRunPanelOpen: (open: boolean) => void;
  onResizeRunPanelStart: (event: ReactPointerEvent<HTMLDivElement>) => void;
  onRerunActiveTab: () => void;
  onStopActiveTab: () => void;
};

export default function TerminalWorkspaceShell({
  projectName,
  projectId,
  projectPath,
  codexRunningCount,
  controlPlaneProjection,
  activePaneControlProjection,
  isGitRepo,
  windowLabel,
  runtimeClientId,
  xtermTheme,
  terminalPaneUseWebgl,
  scripts,
  selectedScriptId,
  selectedScriptState,
  runDisabled,
  stopDisabled,
  scriptActionsDisabled,
  headerTabs,
  activeTabId,
  activeWorkspaceTab,
  activePaneProjections,
  rightSidebarOpen,
  rightSidebarWidth,
  rightSidebarTab,
  previewDirty,
  previewFilePath,
  filePanelShowHidden,
  gitSelected,
  runPanelTabs,
  runPanelActiveTabId,
  runPanelOpen,
  runPanelHeight,
  activeTabRunning,
  sessionSnapshots,
  scriptRuntimeById,
  quickCommandJobByScriptId,
  scriptLocalPhaseById,
  isScriptRuntimeValid,
  onSelectScript,
  onEditScript,
  onDeleteScript,
  onRunScript,
  onStopScript,
  onToggleRightSidebar,
  onSelectTab,
  onNewTab,
  onCloseTab,
  onResize,
  onActivateSession,
  onPtyReady,
  onSessionExit,
  onSessionOutput,
  onSetRightSidebarWidth,
  onToggleShowHidden,
  onOpenPreview,
  onClosePreview,
  onPreviewDirtyChange,
  onSelectGitFile,
  onCloseGitSelection,
  onChangeRightSidebarTab,
  onCloseRightSidebar,
  onSelectRunTab,
  onCloseRunTab,
  onSetRunPanelOpen,
  onResizeRunPanelStart,
  onRerunActiveTab,
  onStopActiveTab,
}: TerminalWorkspaceShellProps) {
  return (
    <div className="flex h-full flex-col bg-[var(--terminal-bg)] text-[var(--terminal-fg)]">
      <TerminalWorkspaceHeader
        projectName={projectName}
        projectPath={projectPath}
        codexRunningCount={codexRunningCount}
        controlPlaneProjection={controlPlaneProjection}
        activePaneControlProjection={activePaneControlProjection}
        rightSidebarOpen={rightSidebarOpen}
        rightSidebarTab={rightSidebarTab}
        scripts={scripts}
        selectedScriptId={selectedScriptId}
        selectedScriptState={selectedScriptState}
        runDisabled={runDisabled}
        stopDisabled={stopDisabled}
        scriptActionsDisabled={scriptActionsDisabled}
        tabs={headerTabs}
        activeTabId={activeTabId}
        onSelectScript={onSelectScript}
        onEditScript={onEditScript}
        onDeleteScript={onDeleteScript}
        onRunScript={onRunScript}
        onStopScript={onStopScript}
        onToggleRightSidebar={onToggleRightSidebar}
        onSelectTab={onSelectTab}
        onNewTab={onNewTab}
        onCloseTab={onCloseTab}
      />
      <div className="flex min-h-0 min-w-0 flex-1 flex-col">
        <div className="flex min-h-0 min-w-0 flex-1 overflow-hidden">
          <div className="relative flex min-h-0 min-w-0 flex-1">
            {activeWorkspaceTab ? (
              <div key={activeWorkspaceTab.id} className="absolute inset-0 flex min-h-0 flex-1">
                <SplitLayout
                  root={activeWorkspaceTab.root}
                  activePaneId={activeWorkspaceTab.activePaneId}
                  onResize={onResize}
                  renderPane={(paneId, isPaneActive) => {
                    const pane = activePaneProjections[paneId] ?? null;
                    if (!pane) {
                      return null;
                    }
                    if (pane.kind === "terminal" || pane.kind === "run") {
                      return (
                        <PaneHost
                          kind={pane.kind}
                          sessionId={pane.sessionId}
                          projectPath={projectPath}
                          cwd={pane.kind === "terminal" ? pane.cwd : pane.restoreAnchor?.cwd ?? projectPath}
                          workspaceId={projectId ?? projectPath}
                          paneId={pane.kind === "terminal" ? pane.id : null}
                          surfaceId={pane.kind === "terminal" ? pane.id : null}
                          savedState={pane.restoreAnchor?.savedState ?? null}
                          windowLabel={windowLabel}
                          clientId={runtimeClientId}
                          useWebgl={terminalPaneUseWebgl && isPaneActive}
                          theme={xtermTheme}
                          isActive={isPaneActive}
                          onActivate={(nextSessionId) => onActivateSession(activeWorkspaceTab.id, nextSessionId)}
                          onPtyReady={onPtyReady}
                          onExit={onSessionExit}
                          onOutput={onSessionOutput}
                          preserveSessionOnUnmount
                        />
                      );
                    }
                    if (pane.kind === "filePreview") {
                      return (
                        <PaneHost
                          kind="filePreview"
                          projectPath={projectPath}
                          relativePath={pane.relativePath}
                          onClose={onClosePreview}
                          onDirtyChange={(dirty) => {
                            if (previewFilePath !== pane.relativePath) {
                              return;
                            }
                            onPreviewDirtyChange(dirty);
                          }}
                          emptyMessage="选择文件以预览/编辑"
                        />
                      );
                    }
                    if (pane.kind === "gitDiff") {
                      return (
                        <PaneHost
                          kind="gitDiff"
                          projectPath={projectPath}
                          selected={{
                            category: pane.category ?? "unstaged",
                            path: pane.relativePath,
                            oldPath: pane.oldRelativePath ?? null,
                          }}
                          onCloseSelected={onCloseGitSelection}
                        />
                      );
                    }
                    if (pane.kind === "pendingTerminal") {
                      return (
                        <PaneHost
                          kind="overlay"
                          emptyMessage="检测到旧版待定终端快照，请重新打开终端。"
                        />
                      );
                    }
                    return (
                      <PaneHost
                        kind="overlay"
                        emptyMessage={pane.overlayKind ? `暂未实现面板：${pane.overlayKind}` : "暂未实现该面板"}
                      />
                    );
                  }}
                />
              </div>
            ) : null}
          </div>
          {rightSidebarOpen ? (
            <ResizablePanel
              width={rightSidebarWidth}
              onWidthChange={onSetRightSidebarWidth}
              minWidth={360}
              maxWidth={960}
              handleSide="left"
            >
              <TerminalRightSidebar
                projectPath={projectPath}
                isGitRepo={isGitRepo}
                sidebarWidth={rightSidebarWidth}
                activeTab={rightSidebarTab}
                previewDirty={previewDirty}
                previewFilePath={previewFilePath}
                showHidden={Boolean(filePanelShowHidden)}
                onToggleShowHidden={onToggleShowHidden}
                onSelectFile={(relativePath) => {
                  if (previewDirty && relativePath !== previewFilePath) {
                    const ok = window.confirm("当前文件有未保存修改，确定切换文件？");
                    if (!ok) {
                      return;
                    }
                  }
                  onOpenPreview(relativePath);
                }}
                onClosePreview={onClosePreview}
                onPreviewDirtyChange={onPreviewDirtyChange}
                gitSelected={gitSelected}
                onSelectGitFile={onSelectGitFile}
                onCloseGitSelection={onCloseGitSelection}
                onChangeTab={onChangeRightSidebarTab}
                onClose={onCloseRightSidebar}
              />
            </ResizablePanel>
          ) : null}
        </div>
        {runPanelOpen ? (
          <TerminalRunPanel
            open
            height={runPanelHeight}
            tabs={runPanelTabs}
            activeTabId={runPanelActiveTabId}
            sessions={sessionSnapshots}
            projectPath={projectPath}
            windowLabel={windowLabel}
            clientId={runtimeClientId}
            xtermTheme={xtermTheme}
            terminalUseWebglRenderer={terminalPaneUseWebgl}
            scriptRuntimeById={scriptRuntimeById}
            quickCommandJobByScriptId={quickCommandJobByScriptId}
            scriptLocalPhaseById={scriptLocalPhaseById}
            isScriptRuntimeValid={isScriptRuntimeValid}
            onSelectTab={onSelectRunTab}
            onCloseTab={onCloseRunTab}
            onCollapse={() => onSetRunPanelOpen(false)}
            onResizeStart={onResizeRunPanelStart}
            onRerunActiveTab={onRerunActiveTab}
            onStopActiveTab={onStopActiveTab}
            activeTabRunning={activeTabRunning}
            onPtyReady={onPtyReady}
            onExit={onSessionExit}
          />
        ) : runPanelTabs.length > 0 ? (
          <button
            type="button"
            className="inline-flex h-8 shrink-0 items-center gap-1 border-t border-[var(--terminal-divider)] bg-[var(--terminal-panel-bg)] px-3 text-[11px] font-semibold text-[var(--terminal-muted-fg)] transition-colors hover:text-[var(--terminal-fg)]"
            onClick={() => onSetRunPanelOpen(true)}
          >
            <IconChevronDown size={14} />
            <span>显示运行面板（{runPanelTabs.length}）</span>
          </button>
        ) : null}
      </div>
    </div>
  );
}
