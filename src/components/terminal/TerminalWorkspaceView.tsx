import {
  useCallback,
  useEffect,
  useRef,
  useState,
} from "react";
import type { ITheme } from "xterm";

import type { TerminalQuickCommandDispatch } from "../../models/quickCommands";
import type {
  RightSidebarState,
  SplitDirection,
  TerminalRightSidebarTab,
  TerminalWorkspace,
} from "../../models/terminal";
import type { ProjectScript } from "../../models/types";
import { useDevHavenContext } from "../../state/DevHavenContext";
import { gitIsRepo } from "../../services/gitManagement";
import { loadTerminalWorkspace, saveTerminalWorkspace } from "../../services/terminalWorkspace";
import {
  collectSessionIds,
  createDefaultWorkspace,
  createId,
  findPanePath,
  normalizeWorkspace,
  removePane,
  splitPane,
  updateSplitRatios,
} from "../../utils/terminalLayout";
import { isInteractionLocked } from "../../utils/interactionLock";
import { useQuickCommandDispatch } from "../../hooks/useQuickCommandDispatch";
import { useQuickCommandPanel } from "../../hooks/useQuickCommandPanel";
import { useQuickCommandRuntime } from "../../hooks/useQuickCommandRuntime";
import QuickCommandsPanel from "./QuickCommandsPanel";
import ResizablePanel from "./ResizablePanel";
import SplitLayout from "./SplitLayout";
import TerminalPane from "./TerminalPane";
import TerminalRightSidebar from "./TerminalRightSidebar";
import TerminalWorkspaceHeader from "./TerminalWorkspaceHeader";

export type TerminalWorkspaceViewProps = {
  projectId: string | null;
  projectPath: string;
  projectName?: string | null;
  isActive: boolean;
  quickCommandDispatch?: TerminalQuickCommandDispatch | null;
  windowLabel: string;
  xtermTheme: ITheme;
  codexRunningCount?: number;
  scripts?: ProjectScript[];
};

const TERMINAL_TITLE_PATTERN = /^终端\s*(\d+)$/;

const DEFAULT_RIGHT_SIDEBAR: RightSidebarState = {
  open: false,
  width: 520,
  tab: "files",
};
const MIN_RIGHT_SIDEBAR_WIDTH = 360;
const MAX_RIGHT_SIDEBAR_WIDTH = 960;

function getNextTerminalTitle(tabs: TerminalWorkspace["tabs"]) {
  const used = new Set<number>();
  for (const tab of tabs) {
    const match = tab.title.match(TERMINAL_TITLE_PATTERN);
    if (!match) {
      continue;
    }
    const value = Number(match[1]);
    if (Number.isInteger(value) && value > 0) {
      used.add(value);
    }
  }
  let next = 1;
  while (used.has(next)) {
    next += 1;
  }
  return `终端 ${next}`;
}

export default function TerminalWorkspaceView({
  projectId,
  projectPath,
  projectName,
  isActive,
  quickCommandDispatch,
  windowLabel,
  xtermTheme,
  codexRunningCount = 0,
  scripts = [],
}: TerminalWorkspaceViewProps) {
  const { appState } = useDevHavenContext();
  const workspaceDefaultsRef = useRef<{
    defaultQuickCommandsPanelOpen: boolean;
    defaultFileExplorerPanelOpen: boolean;
    defaultFileExplorerShowHidden: boolean;
  }>({
    defaultQuickCommandsPanelOpen: scripts.length > 0,
    defaultFileExplorerPanelOpen: false,
    defaultFileExplorerShowHidden: false,
  });
  workspaceDefaultsRef.current.defaultQuickCommandsPanelOpen = scripts.length > 0;

  const [workspace, setWorkspace] = useState<TerminalWorkspace | null>(null);
  const [error, setError] = useState<string | null>(null);
  const workspaceRef = useRef<TerminalWorkspace | null>(null);
  const snapshotProviders = useRef(new Map<string, () => string | null>());
  const [previewFilePath, setPreviewFilePath] = useState<string | null>(null);
  const [previewDirty, setPreviewDirty] = useState(false);
  const [isGitRepo, setIsGitRepo] = useState(false);

  useEffect(() => {
    workspaceRef.current = workspace;
  }, [workspace]);

  useEffect(() => {
    let cancelled = false;
    setIsGitRepo(false);
    if (!projectPath) {
      return () => {
        cancelled = true;
      };
    }
    gitIsRepo(projectPath)
      .then((value) => {
        if (!cancelled) {
          setIsGitRepo(Boolean(value));
        }
      })
      .catch(() => {
        if (!cancelled) {
          setIsGitRepo(false);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [projectPath]);

  useEffect(() => {
    if (!projectPath) {
      return;
    }
    let cancelled = false;
    setError(null);
    setPreviewFilePath(null);
    setPreviewDirty(false);
    loadTerminalWorkspace(projectPath)
      .then((data) => {
        if (cancelled) {
          return;
        }
        const defaults = workspaceDefaultsRef.current;
        const next = data
          ? normalizeWorkspace(data, projectPath, projectId, defaults)
          : createDefaultWorkspace(projectPath, projectId, defaults);
        setWorkspace(next);
      })
      .catch((loadError) => {
        if (cancelled) {
          return;
        }
        setError(loadError instanceof Error ? loadError.message : String(loadError));
        setWorkspace(createDefaultWorkspace(projectPath, projectId, workspaceDefaultsRef.current));
      });
    return () => {
      cancelled = true;
    };
  }, [projectId, projectPath]);

  const registerSnapshotProvider = useCallback(
    (sessionId: string, provider: () => string | null) => {
      snapshotProviders.current.set(sessionId, provider);
      return () => snapshotProviders.current.delete(sessionId);
    },
    [],
  );

  const saveWorkspace = useCallback(async () => {
    const current = workspaceRef.current;
    if (!current) {
      return;
    }
    const sessions = { ...current.sessions };
    Object.entries(sessions).forEach(([sessionId, snapshot]) => {
      const provider = snapshotProviders.current.get(sessionId);
      if (provider) {
        sessions[sessionId] = { ...snapshot, savedState: provider() ?? null };
      }
    });
    const payload = {
      ...current,
      sessions,
      updatedAt: Date.now(),
    };
    try {
      await saveTerminalWorkspace(current.projectPath, payload);
    } catch (saveError) {
      console.error("保存终端工作空间失败。", saveError);
    }
  }, []);

  useEffect(() => {
    if (!workspace) {
      return;
    }
    const timer = window.setTimeout(() => {
      void saveWorkspace();
    }, 800);
    return () => {
      window.clearTimeout(timer);
    };
  }, [workspace, saveWorkspace]);

  useEffect(() => {
    const handleBeforeUnload = () => {
      void saveWorkspace();
    };
    window.addEventListener("beforeunload", handleBeforeUnload);
    return () => {
      window.removeEventListener("beforeunload", handleBeforeUnload);
    };
  }, [saveWorkspace]);

  const updateWorkspace = useCallback(
    (updater: (current: TerminalWorkspace) => TerminalWorkspace) => {
      setWorkspace((prev) => (prev ? updater(prev) : prev));
    },
    [],
  );

  const closeSessionLayout = useCallback(
    (sessionId: string) => {
      const current = workspaceRef.current;
      if (!current) {
        return [sessionId];
      }
      const targetTab = current.tabs.find((tab) => findPanePath(tab.root, sessionId) !== null) ?? null;
      if (!targetTab) {
        return [sessionId];
      }

      const nextRoot = removePane(targetTab.root, sessionId);
      const beforeSessionIds = collectSessionIds(targetTab.root);
      const afterSessionIds = nextRoot ? collectSessionIds(nextRoot) : [];
      const afterSet = new Set(afterSessionIds);
      const removedSessions = beforeSessionIds.filter((id) => !afterSet.has(id));

      updateWorkspace((currentWorkspace) => {
        const targetIndex = currentWorkspace.tabs.findIndex((tab) => findPanePath(tab.root, sessionId) !== null);
        if (targetIndex < 0) {
          return currentWorkspace;
        }

        const tab = currentWorkspace.tabs[targetIndex];
        const updatedRoot = removePane(tab.root, sessionId);
        const tabBeforeSessionIds = collectSessionIds(tab.root);
        const tabAfterSessionIds = updatedRoot ? collectSessionIds(updatedRoot) : [];
        const tabAfterSet = new Set(tabAfterSessionIds);
        const removed = tabBeforeSessionIds.filter((id) => !tabAfterSet.has(id));

        const nextSessions = { ...currentWorkspace.sessions };
        removed.forEach((id) => {
          delete nextSessions[id];
        });

        if (!updatedRoot) {
          const remainingTabs = currentWorkspace.tabs.filter((item) => item.id !== tab.id);
          if (remainingTabs.length === 0) {
            return createDefaultWorkspace(
              currentWorkspace.projectPath,
              currentWorkspace.projectId,
              workspaceDefaultsRef.current,
            );
          }
          const nextActiveTabId =
            currentWorkspace.activeTabId === tab.id ? remainingTabs[0].id : currentWorkspace.activeTabId;
          return {
            ...currentWorkspace,
            tabs: remainingTabs,
            activeTabId: nextActiveTabId,
            sessions: nextSessions,
          };
        }

        const nextActiveSessionId = tabAfterSet.has(tab.activeSessionId)
          ? tab.activeSessionId
          : tabAfterSessionIds[0];
        const nextTab = { ...tab, root: updatedRoot, activeSessionId: nextActiveSessionId };
        return {
          ...currentWorkspace,
          tabs: currentWorkspace.tabs.map((item) => (item.id === tab.id ? nextTab : item)),
          sessions: nextSessions,
        };
      });

      return removedSessions;
    },
    [updateWorkspace],
  );

  const requestSessionClose = useCallback(
    (sessionId: string) => {
      closeSessionLayout(sessionId);
    },
    [closeSessionLayout],
  );

  const {
    scriptRuntimeById,
    quickCommandJobByScriptId,
    scriptLocalPhaseById,
    panelMessage,
    showPanelMessage,
    runQuickCommand,
    stopScript,
    isScriptRuntimeValid,
    handlePtyReady,
    handleSessionExit: handleQuickCommandSessionExit,
    cleanupRuntimeBySessionIds,
    finalizeRuntimeBySessionIds,
  } = useQuickCommandRuntime({
    projectId,
    projectPath,
    windowLabel,
    scripts,
    sharedScriptsRoot: appState.settings.sharedScriptsRoot,
    workspace,
    updateWorkspace,
    onRequestSessionClose: requestSessionClose,
  });

  useQuickCommandDispatch({
    projectId,
    projectPath,
    scripts,
    workspace,
    quickCommandDispatch,
    runQuickCommand,
    stopScript,
    showPanelMessage,
  });

  const panel = useQuickCommandPanel({
    workspace,
    defaultPanelOpen: workspaceDefaultsRef.current.defaultQuickCommandsPanelOpen,
    updateWorkspace,
  });

  const handleSelectTab = useCallback(
    (tabId: string) => {
      updateWorkspace((current) => ({ ...current, activeTabId: tabId }));
    },
    [updateWorkspace],
  );

  const handleNewTab = useCallback(() => {
    updateWorkspace((current) => {
      const sessionId = createId();
      const tabId = createId();
      const title = getNextTerminalTitle(current.tabs);
      return {
        ...current,
        activeTabId: tabId,
        tabs: [
          ...current.tabs,
          {
            id: tabId,
            title,
            root: { type: "pane", sessionId },
            activeSessionId: sessionId,
          },
        ],
        sessions: {
          ...current.sessions,
          [sessionId]: { id: sessionId, cwd: current.projectPath, savedState: null },
        },
      };
    });
  }, [updateWorkspace]);

  const handleCloseTab = useCallback(
    (tabId: string) => {
      const current = workspaceRef.current;
      const closedTab = current?.tabs.find((tab) => tab.id === tabId) ?? null;
      const removedSessions = closedTab ? collectSessionIds(closedTab.root) : [];
      finalizeRuntimeBySessionIds(removedSessions, 130, "终端标签页已关闭");
      cleanupRuntimeBySessionIds(removedSessions);

      updateWorkspace((currentWorkspace) => {
        const remainingTabs = currentWorkspace.tabs.filter((tab) => tab.id !== tabId);
        const removedTab = currentWorkspace.tabs.find((tab) => tab.id === tabId);
        const removedSessionIds = removedTab ? collectSessionIds(removedTab.root) : [];
        if (remainingTabs.length === 0) {
          return createDefaultWorkspace(
            currentWorkspace.projectPath,
            currentWorkspace.projectId,
            workspaceDefaultsRef.current,
          );
        }
        const nextSessions = { ...currentWorkspace.sessions };
        removedSessionIds.forEach((sessionId) => {
          delete nextSessions[sessionId];
        });
        const nextActiveTabId =
          currentWorkspace.activeTabId === tabId ? remainingTabs[0].id : currentWorkspace.activeTabId;
        return {
          ...currentWorkspace,
          tabs: remainingTabs,
          activeTabId: nextActiveTabId,
          sessions: nextSessions,
        };
      });
    },
    [cleanupRuntimeBySessionIds, finalizeRuntimeBySessionIds, updateWorkspace],
  );

  const handleSelectTabRelative = useCallback(
    (delta: number) => {
      updateWorkspace((current) => {
        if (current.tabs.length <= 1) {
          return current;
        }
        const currentIndex = current.tabs.findIndex((tab) => tab.id === current.activeTabId);
        if (currentIndex < 0) {
          return current;
        }
        const nextIndex = (currentIndex + delta + current.tabs.length) % current.tabs.length;
        return { ...current, activeTabId: current.tabs[nextIndex].id };
      });
    },
    [updateWorkspace],
  );

  const handleSelectTabIndex = useCallback(
    (index: number) => {
      updateWorkspace((current) => {
        if (index < 0 || index >= current.tabs.length) {
          return current;
        }
        return { ...current, activeTabId: current.tabs[index].id };
      });
    },
    [updateWorkspace],
  );

  const handleSplit = useCallback(
    (direction: SplitDirection) => {
      updateWorkspace((current) => {
        const activeTab = current.tabs.find((tab) => tab.id === current.activeTabId);
        if (!activeTab) {
          return current;
        }
        const newSessionId = createId();
        const nextRoot = splitPane(activeTab.root, activeTab.activeSessionId, direction, newSessionId);
        const nextTab = {
          ...activeTab,
          root: nextRoot,
          activeSessionId: newSessionId,
        };
        return {
          ...current,
          tabs: current.tabs.map((tab) => (tab.id === activeTab.id ? nextTab : tab)),
          sessions: {
            ...current.sessions,
            [newSessionId]: { id: newSessionId, cwd: current.projectPath, savedState: null },
          },
        };
      });
    },
    [updateWorkspace],
  );

  const handleSessionExit = useCallback(
    (sessionId: string, code?: number | null) => {
      handleQuickCommandSessionExit(sessionId, code);
      const removedSessions = closeSessionLayout(sessionId);
      const extraRemovedSessions = removedSessions.filter((id) => id !== sessionId);
      if (extraRemovedSessions.length > 0) {
        cleanupRuntimeBySessionIds(extraRemovedSessions);
      }
    },
    [cleanupRuntimeBySessionIds, closeSessionLayout, handleQuickCommandSessionExit],
  );

  const setQuickCommandsPanelOpen = useCallback(
    (open: boolean) => {
      updateWorkspace((current) => ({
        ...current,
        ui: {
          ...current.ui,
          quickCommandsPanel: {
            ...(current.ui?.quickCommandsPanel ?? {
              open: workspaceDefaultsRef.current.defaultQuickCommandsPanelOpen,
              x: null,
              y: null,
            }),
            open,
          },
        },
      }));
    },
    [updateWorkspace],
  );

  const setFileExplorerShowHidden = useCallback(
    (showHidden: boolean) => {
      updateWorkspace((current) => ({
        ...current,
        ui: {
          ...current.ui,
          fileExplorerPanel: {
            ...(current.ui?.fileExplorerPanel ?? {
              open: workspaceDefaultsRef.current.defaultFileExplorerPanelOpen,
              showHidden: workspaceDefaultsRef.current.defaultFileExplorerShowHidden,
            }),
            showHidden,
          },
        },
      }));
    },
    [updateWorkspace],
  );

  const updateRightSidebar = useCallback(
    (updater: (current: RightSidebarState) => RightSidebarState) => {
      updateWorkspace((current) => {
        const ui = current.ui ?? {};
        const filePanel = ui.fileExplorerPanel ?? {
          open: workspaceDefaultsRef.current.defaultFileExplorerPanelOpen,
          showHidden: workspaceDefaultsRef.current.defaultFileExplorerShowHidden,
        };
        const gitPanel = ui.gitPanel ?? { open: false };
        const rightSidebar = ui.rightSidebar ?? DEFAULT_RIGHT_SIDEBAR;
        const nextRightSidebar = updater(rightSidebar);
        return {
          ...current,
          ui: {
            ...ui,
            rightSidebar: nextRightSidebar,
            fileExplorerPanel: {
              ...filePanel,
              open: nextRightSidebar.open && nextRightSidebar.tab === "files",
            },
            gitPanel: {
              ...gitPanel,
              open: nextRightSidebar.open && nextRightSidebar.tab === "git",
            },
          },
        };
      });
    },
    [updateWorkspace],
  );

  const closeRightSidebar = useCallback(() => {
    updateRightSidebar((current) => ({ ...current, open: false }));
    setPreviewFilePath(null);
    setPreviewDirty(false);
  }, [updateRightSidebar]);

  const requestCloseRightSidebar = useCallback(() => {
    if (previewDirty) {
      const ok = window.confirm("当前文件有未保存修改，确定关闭侧边栏？");
      if (!ok) {
        return;
      }
    }
    closeRightSidebar();
  }, [closeRightSidebar, previewDirty]);

  const setRightSidebarTab = useCallback(
    (tab: TerminalRightSidebarTab) => {
      updateRightSidebar((current) => ({ ...current, tab, open: true }));
    },
    [updateRightSidebar],
  );

  const setRightSidebarWidth = useCallback(
    (width: number) => {
      updateRightSidebar((current) => ({ ...current, width }));
    },
    [updateRightSidebar],
  );

  useEffect(() => {
    if (!isActive) {
      return;
    }
    const handleKeyDown = (event: KeyboardEvent) => {
      if (isInteractionLocked()) {
        event.preventDefault();
        event.stopPropagation();
        return;
      }
      if (event.defaultPrevented || event.repeat) {
        return;
      }
      if (!event.metaKey || event.ctrlKey || event.altKey) {
        return;
      }
      const key = event.key.toLowerCase();

      if (key === "meta") {
        event.preventDefault();
        event.stopPropagation();
        return;
      }

      if (key === "d") {
        event.preventDefault();
        event.stopPropagation();
        handleSplit(event.shiftKey ? "b" : "r");
        return;
      }

      if (key === "t" && !event.shiftKey) {
        event.preventDefault();
        event.stopPropagation();
        handleNewTab();
        return;
      }

      if (key === "w" && !event.shiftKey) {
        event.preventDefault();
        event.stopPropagation();
        const current = workspaceRef.current;
        if (!current) {
          return;
        }
        const activeTab = current.tabs.find((tab) => tab.id === current.activeTabId);
        if (!activeTab) {
          return;
        }
        handleSessionExit(activeTab.activeSessionId);
        return;
      }

      if (
        !event.shiftKey &&
        (event.code === "ArrowLeft" ||
          event.code === "ArrowRight" ||
          event.code === "ArrowUp" ||
          event.code === "ArrowDown")
      ) {
        event.preventDefault();
        event.stopPropagation();
        handleSelectTabRelative(event.code === "ArrowLeft" || event.code === "ArrowUp" ? -1 : 1);
        return;
      }

      if (event.shiftKey && (event.code === "BracketLeft" || event.code === "BracketRight")) {
        event.preventDefault();
        event.stopPropagation();
        handleSelectTabRelative(event.code === "BracketLeft" ? -1 : 1);
        return;
      }

      if (!event.shiftKey) {
        const digit = Number.parseInt(key, 10);
        if (Number.isFinite(digit) && digit >= 1 && digit <= 9) {
          event.preventDefault();
          event.stopPropagation();
          const current = workspaceRef.current;
          if (!current) {
            return;
          }
          const index = digit === 9 ? current.tabs.length - 1 : digit - 1;
          handleSelectTabIndex(index);
        }
      }
    };

    window.addEventListener("keydown", handleKeyDown, true);
    return () => {
      window.removeEventListener("keydown", handleKeyDown, true);
    };
  }, [handleNewTab, handleSelectTabIndex, handleSelectTabRelative, handleSessionExit, handleSplit, isActive]);

  const handleResize = useCallback(
    (path: number[], ratios: number[]) => {
      updateWorkspace((current) => {
        const activeTab = current.tabs.find((tab) => tab.id === current.activeTabId);
        if (!activeTab) {
          return current;
        }
        const nextRoot = updateSplitRatios(activeTab.root, path, ratios);
        const nextTab = { ...activeTab, root: nextRoot };
        return {
          ...current,
          tabs: current.tabs.map((tab) => (tab.id === activeTab.id ? nextTab : tab)),
        };
      });
    },
    [updateWorkspace],
  );

  const handleActivateSession = useCallback(
    (tabId: string, sessionId: string) => {
      updateWorkspace((current) => {
        const nextTabs = current.tabs.map((tab) =>
          tab.id === tabId ? { ...tab, activeSessionId: sessionId } : tab,
        );
        return { ...current, tabs: nextTabs };
      });
    },
    [updateWorkspace],
  );

  if (!projectPath) {
    return (
      <div className="flex h-full items-center justify-center text-[var(--terminal-muted-fg)]">未找到项目</div>
    );
  }

  if (error) {
    return <div className="flex h-full items-center justify-center text-[var(--terminal-muted-fg)]">{error}</div>;
  }

  if (!workspace) {
    return (
      <div className="flex h-full items-center justify-center text-[var(--terminal-muted-fg)]">
        正在加载终端工作空间...
      </div>
    );
  }

  const panelState = workspace.ui?.quickCommandsPanel ?? {
    open: workspaceDefaultsRef.current.defaultQuickCommandsPanelOpen,
    x: null,
    y: null,
  };
  const panelOpen = Boolean(panelState.open);
  const panelPosition = panel.panelDraft ?? { x: panelState.x ?? 12, y: panelState.y ?? 12 };

  const filePanelState = workspace.ui?.fileExplorerPanel ?? {
    open: workspaceDefaultsRef.current.defaultFileExplorerPanelOpen,
    showHidden: workspaceDefaultsRef.current.defaultFileExplorerShowHidden,
  };
  const rightSidebarState = workspace.ui?.rightSidebar ?? DEFAULT_RIGHT_SIDEBAR;
  const rightSidebarOpen = Boolean(rightSidebarState.open);
  const rightSidebarWidth = Math.max(
    MIN_RIGHT_SIDEBAR_WIDTH,
    Math.min(MAX_RIGHT_SIDEBAR_WIDTH, rightSidebarState.width),
  );
  const rightSidebarTab: TerminalRightSidebarTab =
    rightSidebarState.tab === "git" && !isGitRepo ? "files" : rightSidebarState.tab;

  return (
    <div className="flex h-full flex-col bg-[var(--terminal-bg)] text-[var(--terminal-fg)]">
      <TerminalWorkspaceHeader
        projectName={projectName}
        projectPath={projectPath}
        codexRunningCount={codexRunningCount}
        panelOpen={panelOpen}
        rightSidebarOpen={rightSidebarOpen}
        rightSidebarTab={rightSidebarTab}
        tabs={workspace.tabs}
        activeTabId={workspace.activeTabId}
        onTogglePanel={() => setQuickCommandsPanelOpen(!panelOpen)}
        onToggleRightSidebar={() => {
          if (rightSidebarOpen) {
            requestCloseRightSidebar();
            return;
          }
          setRightSidebarTab(rightSidebarTab === "files" && isGitRepo ? "git" : "files");
        }}
        onSelectTab={handleSelectTab}
        onNewTab={handleNewTab}
        onCloseTab={handleCloseTab}
      />
      <div ref={panel.stageRef} className="relative flex min-h-0 flex-1">
        {panelOpen ? (
          <QuickCommandsPanel
            scripts={scripts}
            scriptRuntimeById={scriptRuntimeById}
            quickCommandJobByScriptId={quickCommandJobByScriptId}
            scriptLocalPhaseById={scriptLocalPhaseById}
            panelMessage={panelMessage}
            panelPosition={panelPosition}
            isScriptRuntimeValid={isScriptRuntimeValid}
            onRun={runQuickCommand}
            onStop={stopScript}
            onClose={() => setQuickCommandsPanelOpen(false)}
            onDragStart={panel.beginDragQuickCommandsPanel}
            panelRef={panel.panelRef}
          />
        ) : null}
        <div className="flex min-h-0 min-w-0 flex-1 overflow-hidden">
          <div className="relative flex min-h-0 min-w-0 flex-1">
            {workspace.tabs.map((tab) => (
              <div
                key={tab.id}
                className={`absolute inset-0 flex min-h-0 flex-1 ${
                  tab.id === workspace.activeTabId ? "opacity-100" : "opacity-0 pointer-events-none"
                }`}
              >
                <SplitLayout
                  root={tab.root}
                  activeSessionId={tab.activeSessionId}
                  onActivate={(sessionId) => handleActivateSession(tab.id, sessionId)}
                  onResize={handleResize}
                  renderPane={(sessionId, isPaneActive) => (
                    <TerminalPane
                      sessionId={sessionId}
                      cwd={workspace.sessions[sessionId]?.cwd ?? workspace.projectPath}
                      savedState={workspace.sessions[sessionId]?.savedState ?? null}
                      windowLabel={windowLabel}
                      useWebgl={appState.settings.terminalUseWebglRenderer && tab.id === workspace.activeTabId}
                      theme={xtermTheme}
                      isActive={tab.id === workspace.activeTabId && isPaneActive}
                      onActivate={(nextSessionId) => handleActivateSession(tab.id, nextSessionId)}
                      onPtyReady={handlePtyReady}
                      onExit={handleSessionExit}
                      onRegisterSnapshotProvider={registerSnapshotProvider}
                    />
                  )}
                />
              </div>
            ))}
          </div>
          {rightSidebarOpen ? (
            <ResizablePanel
              width={rightSidebarWidth}
              onWidthChange={setRightSidebarWidth}
              minWidth={MIN_RIGHT_SIDEBAR_WIDTH}
              maxWidth={MAX_RIGHT_SIDEBAR_WIDTH}
              handleSide="left"
            >
              <TerminalRightSidebar
                projectPath={projectPath}
                isGitRepo={isGitRepo}
                sidebarWidth={rightSidebarWidth}
                activeTab={rightSidebarTab}
                previewDirty={previewDirty}
                previewFilePath={previewFilePath}
                showHidden={Boolean(filePanelState.showHidden)}
                onToggleShowHidden={setFileExplorerShowHidden}
                onSelectFile={(relativePath) => {
                  if (previewDirty && relativePath !== previewFilePath) {
                    const ok = window.confirm("当前文件有未保存修改，确定切换文件？");
                    if (!ok) {
                      return;
                    }
                  }
                  setPreviewFilePath(relativePath);
                  setPreviewDirty(false);
                }}
                onClosePreview={() => {
                  setPreviewFilePath(null);
                  setPreviewDirty(false);
                }}
                onPreviewDirtyChange={setPreviewDirty}
                onChangeTab={setRightSidebarTab}
                onClose={requestCloseRightSidebar}
              />
            </ResizablePanel>
          ) : null}
        </div>
      </div>
    </div>
  );
}
