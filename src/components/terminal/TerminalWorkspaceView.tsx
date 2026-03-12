import {
  memo,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
} from "react";
import type { ITheme } from "xterm";

import type { TerminalQuickCommandDispatch } from "../../models/quickCommands";
import {
  activateRunPanelTabInSnapshot,
  appendTerminalTabToSnapshot,
  activateTerminalSessionInSnapshot,
  buildSessionSnapshotMap,
  collectPaneIds,
  markRunPanelTabExitedInSnapshot,
  removePaneFromSnapshot,
  removeRunPanelSessionFromSnapshot,
  removeTerminalSessionFromSnapshot,
  removeTerminalTabFromSnapshot,
  setRunPanelHeightInSnapshot,
  setRunPanelOpenInSnapshot,
  setFileExplorerShowHiddenInSnapshot,
  splitTerminalSessionInSnapshot,
  syncRunPanelTabsInSnapshot,
  updateRightSidebarStateInSnapshot,
  updateLayoutNodeRatios,
  upsertFilePreviewPaneInSnapshot,
  upsertGitDiffPaneInSnapshot,
} from "../../models/terminal";
import type {
  TerminalLayoutSnapshot,
  TerminalLayoutTab,
  RunPanelState,
  RightSidebarState,
  SplitDirection,
  TerminalRightSidebarTab,
} from "../../models/terminal";
import type { ProjectScript, ScriptParamField, SharedScriptEntry } from "../../models/types";
import { resolveRuntimeClientId } from "../../platform/runtime";
import { gitIsRepo } from "../../services/gitManagement";
import { listSharedScripts } from "../../services/sharedScripts";
import { terminateTerminalSessions } from "../../services/terminal";
import {
  listenTerminalLayoutChanged,
  loadTerminalLayout,
  saveTerminalLayout,
} from "../../services/terminalWorkspace";
import {
  applySharedScriptCommandTemplate,
  buildTemplateParams,
  mergeScriptParamSchema,
  renderScriptTemplateCommand,
} from "../../utils/scriptTemplate";
import {
  createDefaultLayoutSnapshot,
  createId,
} from "../../utils/terminalLayout";
import { isInteractionLocked } from "../../utils/interactionLock";
import { useQuickCommandDispatch } from "../../hooks/useQuickCommandDispatch";
import {
  toScriptExecutionStateFromQuickState,
  useQuickCommandRuntime,
  type ScriptExecutionState,
} from "../../hooks/useQuickCommandRuntime";
import TerminalWorkspaceShell from "./TerminalWorkspaceShell";
import { buildTerminalWorkspaceShellModel } from "./terminalWorkspaceShellModel";

export type TerminalWorkspaceViewProps = {
  projectId: string | null;
  projectPath: string;
  projectName?: string | null;
  isActive: boolean;
  quickCommandDispatch?: TerminalQuickCommandDispatch | null;
  windowLabel: string;
  xtermTheme: ITheme;
  sharedScriptsRoot: string;
  terminalUseWebglRenderer: boolean;
  codexRunningCount?: number;
  scripts?: ProjectScript[];
  onRegisterPersistWorkspace?: (projectId: string, persistWorkspace: (() => Promise<void>) | null) => void;
  onRegisterWorkspaceSessionIds?: (projectId: string, sessionIds: string[]) => void;
  onAddProjectScript: (
    projectId: string,
    script: {
      name: string;
      start: string;
      paramSchema?: ProjectScript["paramSchema"];
      templateParams?: ProjectScript["templateParams"];
    },
  ) => Promise<void>;
  onUpdateProjectScript: (projectId: string, script: ProjectScript) => Promise<void>;
  onRemoveProjectScript: (projectId: string, scriptId: string) => Promise<void>;
};

const TERMINAL_TITLE_PATTERN = /^终端\s*(\d+)$/;

const DEFAULT_RIGHT_SIDEBAR: RightSidebarState = {
  open: false,
  width: 520,
  tab: "files",
};
const DEFAULT_RUN_PANEL: RunPanelState = {
  open: false,
  height: 240,
  activeTabId: null,
  tabs: [],
};
const MIN_RUN_PANEL_HEIGHT = 140;
const MIN_RIGHT_SIDEBAR_WIDTH = 360;
const MAX_RIGHT_SIDEBAR_WIDTH = 960;
const RIGHT_SIDEBAR_PREVIEW_PANE_ID = "right-sidebar:file-preview";
const RIGHT_SIDEBAR_GIT_DIFF_PANE_ID = "right-sidebar:git-diff";

type ScriptFormState = {
  scriptId: string | null;
  name: string;
  start: string;
  error: string;
  selectedSharedScriptId: string;
  paramSchema: ScriptParamField[];
  templateParams: Record<string, string>;
};

type RunConfigurationsDialogState = {
  selectedScriptId: string | null;
  draft: ScriptFormState;
};

function getNextTerminalTitle(tabs: Array<Pick<TerminalLayoutTab, "title">>) {
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

function touchLayoutSnapshot(snapshot: TerminalLayoutSnapshot): TerminalLayoutSnapshot {
  const now = Date.now();
  return {
    ...snapshot,
    updatedAt: now,
    revision: now,
  };
}

function collectSessionIdsForLayoutTab(snapshot: TerminalLayoutSnapshot, tab: TerminalLayoutTab): string[] {
  const sessionIds: string[] = [];
  collectPaneIds(tab.root).forEach((paneId) => {
    const pane = snapshot.panes[paneId];
    if ((pane?.kind === "terminal" || pane?.kind === "run") && pane.sessionId) {
      sessionIds.push(pane.sessionId);
    }
  });
  return sessionIds;
}

function findLayoutTabBySessionId(
  snapshot: TerminalLayoutSnapshot,
  sessionId: string,
): TerminalLayoutTab | null {
  return (
    snapshot.tabs.find((tab) =>
      collectPaneIds(tab.root).some((paneId) => {
        const pane = snapshot.panes[paneId];
        return (pane?.kind === "terminal" || pane?.kind === "run") && pane.sessionId === sessionId;
      }),
    ) ?? null
  );
}

function areTerminalWorkspaceViewPropsEqual(
  prevProps: TerminalWorkspaceViewProps,
  nextProps: TerminalWorkspaceViewProps,
) {
  if (prevProps.projectId !== nextProps.projectId) {
    return false;
  }
  if (prevProps.projectPath !== nextProps.projectPath) {
    return false;
  }
  if (prevProps.projectName !== nextProps.projectName) {
    return false;
  }
  if (prevProps.isActive !== nextProps.isActive) {
    return false;
  }
  if (prevProps.windowLabel !== nextProps.windowLabel) {
    return false;
  }
  if (prevProps.xtermTheme !== nextProps.xtermTheme) {
    return false;
  }
  if (prevProps.sharedScriptsRoot !== nextProps.sharedScriptsRoot) {
    return false;
  }
  if (prevProps.terminalUseWebglRenderer !== nextProps.terminalUseWebglRenderer) {
    return false;
  }
  if (prevProps.codexRunningCount !== nextProps.codexRunningCount) {
    return false;
  }
  if (prevProps.scripts !== nextProps.scripts) {
    return false;
  }
  if (prevProps.onRegisterPersistWorkspace !== nextProps.onRegisterPersistWorkspace) {
    return false;
  }
  if (prevProps.onRegisterWorkspaceSessionIds !== nextProps.onRegisterWorkspaceSessionIds) {
    return false;
  }
  if (prevProps.onAddProjectScript !== nextProps.onAddProjectScript) {
    return false;
  }
  if (prevProps.onUpdateProjectScript !== nextProps.onUpdateProjectScript) {
    return false;
  }
  if (prevProps.onRemoveProjectScript !== nextProps.onRemoveProjectScript) {
    return false;
  }

  const nextDispatch = nextProps.quickCommandDispatch ?? null;
  if (!nextDispatch) {
    return true;
  }
  const prevDispatch = prevProps.quickCommandDispatch ?? null;
  return Boolean(prevDispatch && prevDispatch.seq === nextDispatch.seq);
}

function TerminalWorkspaceView({
  projectId,
  projectPath,
  projectName,
  isActive,
  quickCommandDispatch,
  windowLabel,
  xtermTheme,
  sharedScriptsRoot,
  terminalUseWebglRenderer,
  codexRunningCount = 0,
  scripts = [],
  onRegisterPersistWorkspace,
  onRegisterWorkspaceSessionIds,
  onAddProjectScript,
  onUpdateProjectScript,
  onRemoveProjectScript,
}: TerminalWorkspaceViewProps) {
  const workspaceDefaultsRef = useRef<{
    defaultRunPanelOpen: boolean;
    defaultRunPanelHeight: number;
    defaultFileExplorerPanelOpen: boolean;
    defaultFileExplorerShowHidden: boolean;
  }>({
    defaultRunPanelOpen: false,
    defaultRunPanelHeight: DEFAULT_RUN_PANEL.height,
    defaultFileExplorerPanelOpen: false,
    defaultFileExplorerShowHidden: false,
  });

  const [layoutSnapshot, setLayoutSnapshot] = useState<TerminalLayoutSnapshot | null>(null);
  const [error, setError] = useState<string | null>(null);
  const layoutSnapshotRef = useRef<TerminalLayoutSnapshot | null>(null);
  const [isGitRepo, setIsGitRepo] = useState(false);
  const [runConfigurationsDialog, setRunConfigurationsDialog] = useState<RunConfigurationsDialogState | null>(null);
  const [sharedScripts, setSharedScripts] = useState<SharedScriptEntry[]>([]);
  const [sharedScriptsLoading, setSharedScriptsLoading] = useState(false);
  const [sharedScriptsError, setSharedScriptsError] = useState<string | null>(null);
  const runtimeClientIdRef = useRef(resolveRuntimeClientId());
  const runtimeClientId = runtimeClientIdRef.current;
  const layoutDirtyRef = useRef(false);
  const layoutDirtyRevisionRef = useRef(0);

  const activeSnapshot = useMemo(() => {
    if (!layoutSnapshot) {
      return null;
    }
    if (layoutSnapshot.projectPath !== projectPath) {
      return null;
    }
    if (projectId && layoutSnapshot.projectId && layoutSnapshot.projectId !== projectId) {
      return null;
    }
    return layoutSnapshot;
  }, [layoutSnapshot, projectId, projectPath]);

  const sessionSnapshots = useMemo(
    () => (activeSnapshot ? buildSessionSnapshotMap(activeSnapshot) : {}),
    [activeSnapshot],
  );

  const shellModel = useMemo(
    () =>
      activeSnapshot
        ? buildTerminalWorkspaceShellModel(activeSnapshot, {
            isGitRepo,
            defaultFileExplorerPanelOpen: workspaceDefaultsRef.current.defaultFileExplorerPanelOpen,
            defaultFileExplorerShowHidden: workspaceDefaultsRef.current.defaultFileExplorerShowHidden,
            minRunPanelHeight: MIN_RUN_PANEL_HEIGHT,
            minRightSidebarWidth: MIN_RIGHT_SIDEBAR_WIDTH,
            maxRightSidebarWidth: MAX_RIGHT_SIDEBAR_WIDTH,
          })
        : null,
    [activeSnapshot, isGitRepo],
  );

  const previewFilePath = shellModel?.previewFilePath ?? null;
  const previewDirty = shellModel?.previewDirty ?? false;
  const gitSelected = shellModel?.gitSelected ?? null;

  useEffect(() => {
    layoutSnapshotRef.current = layoutSnapshot;
  }, [layoutSnapshot]);

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
    setLayoutSnapshot(null);
    loadTerminalLayout(projectPath)
      .then((data) => {
        if (cancelled) {
          return;
        }
        const defaults = workspaceDefaultsRef.current;
        const next = data ?? createDefaultLayoutSnapshot(projectPath, projectId, defaults);
        layoutDirtyRef.current = false;
        layoutDirtyRevisionRef.current = 0;
        setLayoutSnapshot(next);
      })
      .catch((loadError) => {
        if (cancelled) {
          return;
        }
        setError(loadError instanceof Error ? loadError.message : String(loadError));
        layoutDirtyRef.current = false;
        layoutDirtyRevisionRef.current = 0;
        setLayoutSnapshot(createDefaultLayoutSnapshot(projectPath, projectId, workspaceDefaultsRef.current));
      });
    return () => {
      cancelled = true;
    };
  }, [projectId, projectPath]);

  useEffect(() => {
    let cancelled = false;
    let unlisten: (() => void) | null = null;

    const register = async () => {
      try {
        unlisten = await listenTerminalLayoutChanged((event) => {
          if (cancelled) {
            return;
          }
          const payload = event.payload;
          if (!payload || payload.projectPath !== projectPath) {
            return;
          }
          if (payload.deleted) {
            const fallback = createDefaultLayoutSnapshot(projectPath, projectId, workspaceDefaultsRef.current);
            layoutDirtyRef.current = false;
            layoutDirtyRevisionRef.current = 0;
            setLayoutSnapshot({
              ...fallback,
              updatedAt: Number(payload.updatedAt ?? payload.revision ?? fallback.updatedAt) || fallback.updatedAt,
            });
            return;
          }
          const incomingUpdatedAt = Number(payload.updatedAt ?? payload.revision ?? 0);
          const currentUpdatedAt = layoutSnapshotRef.current?.updatedAt ?? 0;
          if (incomingUpdatedAt > 0 && incomingUpdatedAt <= currentUpdatedAt) {
            return;
          }
          void loadTerminalLayout(projectPath)
            .then((snapshot) => {
              if (cancelled || !snapshot) {
                return;
              }
              layoutDirtyRef.current = false;
              layoutDirtyRevisionRef.current = 0;
              setLayoutSnapshot(snapshot);
            })
            .catch((syncError) => {
              if (!cancelled) {
                console.error("同步终端布局快照失败。", syncError);
              }
            });
        });
      } catch (syncError) {
        if (!cancelled) {
          console.error("监听终端布局变更事件失败。", syncError);
        }
      }
    };

    void register();
    return () => {
      cancelled = true;
      unlisten?.();
    };
  }, [projectId, projectPath, runtimeClientId]);

  useEffect(() => {
    setRunConfigurationsDialog(null);
  }, [projectId]);

  useEffect(() => {
    if (!runConfigurationsDialog) {
      return;
    }
    let cancelled = false;
    setSharedScriptsLoading(true);
    setSharedScriptsError(null);
    void listSharedScripts(sharedScriptsRoot)
      .then((entries) => {
        if (cancelled) {
          return;
        }
        setSharedScripts(entries);
      })
      .catch((error) => {
        if (cancelled) {
          return;
        }
        console.error("读取通用脚本失败。", error);
        setSharedScriptsError(error instanceof Error ? error.message : String(error));
        setSharedScripts([]);
      })
      .finally(() => {
        if (!cancelled) {
          setSharedScriptsLoading(false);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [runConfigurationsDialog, sharedScriptsRoot]);

  const saveWorkspace = useCallback(async () => {
    const current = layoutSnapshotRef.current;
    if (!current || !layoutDirtyRef.current) {
      return;
    }
    const saveRevision = layoutDirtyRevisionRef.current;

    try {
      await saveTerminalLayout(current.projectPath, current, runtimeClientId);
      if (layoutDirtyRevisionRef.current === saveRevision) {
        layoutDirtyRef.current = false;
      }
    } catch (saveError) {
      console.error("保存终端布局快照失败。", saveError);
    }
  }, [runtimeClientId]);

  useEffect(() => {
    if (!projectId || !onRegisterPersistWorkspace) {
      return;
    }
    onRegisterPersistWorkspace(projectId, saveWorkspace);
    return () => {
      onRegisterPersistWorkspace(projectId, null);
    };
  }, [onRegisterPersistWorkspace, projectId, saveWorkspace]);

  useEffect(() => {
    if (!projectId || !activeSnapshot || !onRegisterWorkspaceSessionIds) {
      return;
    }
    onRegisterWorkspaceSessionIds(projectId, Object.keys(sessionSnapshots));
  }, [activeSnapshot, onRegisterWorkspaceSessionIds, projectId, sessionSnapshots]);

  useEffect(() => {
    const handleBeforeUnload = () => {
      void saveWorkspace();
    };
    window.addEventListener("beforeunload", handleBeforeUnload);
    return () => {
      window.removeEventListener("beforeunload", handleBeforeUnload);
    };
  }, [saveWorkspace]);

  useEffect(() => {
    const handleBlur = () => {
      void saveWorkspace();
    };
    const handleVisibilityChange = () => {
      if (document.visibilityState === "hidden") {
        void saveWorkspace();
      }
    };
    window.addEventListener("blur", handleBlur);
    document.addEventListener("visibilitychange", handleVisibilityChange);
    return () => {
      window.removeEventListener("blur", handleBlur);
      document.removeEventListener("visibilitychange", handleVisibilityChange);
    };
  }, [saveWorkspace]);

  const updateLayoutSnapshot = useCallback(
    (updater: (current: TerminalLayoutSnapshot) => TerminalLayoutSnapshot) => {
      setLayoutSnapshot((prevSnapshot) => {
        if (!prevSnapshot) {
          return prevSnapshot;
        }
        const nextSnapshot = updater(prevSnapshot);
        if (nextSnapshot === prevSnapshot) {
          return prevSnapshot;
        }
        layoutDirtyRevisionRef.current += 1;
        layoutDirtyRef.current = true;
        return touchLayoutSnapshot(nextSnapshot);
      });
    },
    [],
  );

  const terminateWorkspaceSessions = useCallback(
    (sessionIds: string[]) => {
      if (sessionIds.length === 0) {
        return;
      }
      void terminateTerminalSessions(windowLabel, sessionIds, runtimeClientId).catch((error) => {
        console.error("关闭终端会话失败。", error);
      });
    },
    [runtimeClientId, windowLabel],
  );

  const closeSessionLayout = useCallback(
    (sessionId: string) => {
      const current = layoutSnapshotRef.current;
      if (!current) {
        return;
      }
      const targetTab = findLayoutTabBySessionId(current, sessionId);
      if (!targetTab) {
        return;
      }

      updateLayoutSnapshot((currentSnapshot) =>
        removeTerminalSessionFromSnapshot(currentSnapshot, sessionId, {
          createFallbackTab: () => {
            const nextSessionId = createId();
            return {
              tabId: createId(),
              paneId: `pane:${nextSessionId}`,
              sessionId: nextSessionId,
              title: "终端 1",
              cwd: currentSnapshot.projectPath,
            };
          },
        }),
      );
    },
    [updateLayoutSnapshot],
  );

  const closeRunPanelSession = useCallback(
    (sessionId: string, options?: { closePanelWhenEmpty?: boolean }) => {
      const current = layoutSnapshotRef.current;
      if (!current) {
        return false;
      }
      const currentRunPanel = current.ui?.runPanel ?? DEFAULT_RUN_PANEL;
      const targetTab = currentRunPanel.tabs.find((tab) => tab.sessionId === sessionId);
      if (!targetTab) {
        return false;
      }
      updateLayoutSnapshot((currentSnapshot) =>
        removeRunPanelSessionFromSnapshot(currentSnapshot, sessionId, {
          keepOpenWhenEmpty: !(options?.closePanelWhenEmpty ?? true),
        }),
      );
      return true;
    },
    [updateLayoutSnapshot],
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
    sharedScriptsRoot,
    layoutSnapshot: activeSnapshot,
    updateLayoutSnapshot,
    onRequestSessionClose: requestSessionClose,
  });

  useQuickCommandDispatch({
    projectId,
    projectPath,
    scripts,
    layoutSnapshot: activeSnapshot,
    quickCommandDispatch,
    runQuickCommand,
    stopScript,
    showPanelMessage,
  });

  useEffect(() => {
    if (!activeSnapshot) {
      return;
    }
    const validSessionIds = new Set(Object.keys(sessionSnapshots));
    updateLayoutSnapshot((current) => syncRunPanelTabsInSnapshot(current, validSessionIds));
  }, [activeSnapshot, sessionSnapshots, updateLayoutSnapshot]);

  const setRunConfigurationScriptId = useCallback(
    (scriptId: string | null) => {
      const nextScriptId =
        scriptId && scripts.some((script) => script.id === scriptId) ? scriptId : scripts[0]?.id ?? null;
      updateLayoutSnapshot((current) => ({
        ...current,
        ui: {
          ...(current.ui ?? {}),
          runConfiguration: {
            ...(current.ui?.runConfiguration ?? { selectedScriptId: null }),
            selectedScriptId: nextScriptId,
          },
        },
      }));
    },
    [scripts, updateLayoutSnapshot],
  );

  useEffect(() => {
    if (!activeSnapshot) {
      return;
    }
    const currentSelected = shellModel?.selectedRunConfigurationId ?? null;
    const nextSelected =
      currentSelected && scripts.some((script) => script.id === currentSelected)
        ? currentSelected
        : scripts[0]?.id ?? null;
    if (currentSelected === nextSelected) {
      return;
    }
    setRunConfigurationScriptId(nextSelected);
  }, [activeSnapshot, scripts, setRunConfigurationScriptId, shellModel]);

  useEffect(() => {
    if (!runConfigurationsDialog) {
      return;
    }
    if (runConfigurationsDialog.selectedScriptId) {
      const selectedExists = scripts.some((script) => script.id === runConfigurationsDialog.selectedScriptId);
      if (!selectedExists) {
        const fallbackScript = scripts[0] ?? null;
        setRunConfigurationsDialog(
          fallbackScript
            ? {
                selectedScriptId: fallbackScript.id,
                draft: createScriptFormState(fallbackScript),
              }
            : {
                selectedScriptId: null,
                draft: createNewScriptFormState(),
              },
        );
        return;
      }
    }
    if (runConfigurationsDialog.draft.scriptId) {
      const draftExists = scripts.some((script) => script.id === runConfigurationsDialog.draft.scriptId);
      if (!draftExists) {
        setRunConfigurationsDialog((prev) =>
          prev
            ? {
                ...prev,
                draft: createNewScriptFormState(),
              }
            : prev,
        );
      }
    }
  }, [runConfigurationsDialog, scripts]);

  const resolveSelectedScript = useCallback((): ProjectScript | null => {
    const current = layoutSnapshotRef.current;
    const selectedScriptId = current?.ui?.runConfiguration?.selectedScriptId ?? null;
    const resolvedScriptId =
      selectedScriptId && scripts.some((script) => script.id === selectedScriptId)
        ? selectedScriptId
        : scripts[0]?.id ?? null;
    if (!resolvedScriptId) {
      return null;
    }
    return scripts.find((script) => script.id === resolvedScriptId) ?? null;
  }, [scripts]);

  const runSelectedScript = useCallback(() => {
    const selectedScript = resolveSelectedScript();
    if (!selectedScript) {
      showPanelMessage("暂无快捷命令，请在项目详情面板中配置");
      return;
    }
    runQuickCommand(selectedScript);
  }, [resolveSelectedScript, runQuickCommand, showPanelMessage]);

  const stopSelectedScript = useCallback(() => {
    const selectedScript = resolveSelectedScript();
    if (!selectedScript) {
      showPanelMessage("暂无快捷命令，请在项目详情面板中配置");
      return;
    }
    stopScript(selectedScript.id);
  }, [resolveSelectedScript, showPanelMessage, stopScript]);

  const openRunConfigurationsDialog = useCallback(() => {
    const selectedScript = resolveSelectedScript();
    if (selectedScript) {
      setRunConfigurationsDialog({
        selectedScriptId: selectedScript.id,
        draft: createScriptFormState(selectedScript),
      });
      return;
    }
    setRunConfigurationsDialog({
      selectedScriptId: null,
      draft: createNewScriptFormState(),
    });
  }, [resolveSelectedScript]);

  const removeSelectedScript = useCallback(() => {
    if (!projectId) {
      showPanelMessage("项目不存在或已移除");
      return;
    }
    const selectedScript = resolveSelectedScript();
    if (!selectedScript) {
      showPanelMessage("暂无快捷命令，请在项目详情面板中配置");
      return;
    }
    const confirmed = window.confirm(`确定删除运行配置“${selectedScript.name}”吗？`);
    if (!confirmed) {
      return;
    }
    void onRemoveProjectScript(projectId, selectedScript.id)
      .then(() => {
        showPanelMessage(`已删除配置：${selectedScript.name}`);
        setRunConfigurationsDialog((prev) => {
          if (!prev || prev.draft.scriptId !== selectedScript.id) {
            return prev;
          }
          return {
            selectedScriptId: null,
            draft: createNewScriptFormState(),
          };
        });
      })
      .catch((error) => {
        console.error("删除运行配置失败。", error);
        showPanelMessage("删除运行配置失败");
      });
  }, [onRemoveProjectScript, projectId, resolveSelectedScript, showPanelMessage]);

  const selectDialogScript = useCallback((scriptId: string) => {
    const target = scripts.find((item) => item.id === scriptId);
    if (!target) {
      return;
    }
    setRunConfigurationsDialog((prev) =>
      prev
        ? {
            ...prev,
            selectedScriptId: scriptId,
            draft: createScriptFormState(target),
          }
        : prev,
    );
  }, [scripts]);

  const createDialogScript = useCallback(() => {
    setRunConfigurationsDialog((prev) =>
      prev
        ? {
            ...prev,
            selectedScriptId: null,
            draft: createNewScriptFormState(),
          }
        : prev,
    );
  }, []);

  const updateDialogDraft = useCallback((updater: (draft: ScriptFormState) => ScriptFormState) => {
    setRunConfigurationsDialog((prev) => (prev ? { ...prev, draft: updater(prev.draft) } : prev));
  }, []);

  const handleSaveRunConfiguration = useCallback(
    (closeAfterSave: boolean) => {
      if (!runConfigurationsDialog || !projectId) {
        return;
      }
      const draft = runConfigurationsDialog.draft;
      const scriptName = draft.name.trim();
      const startCommand = draft.start.trim();
      if (!scriptName) {
        updateDialogDraft((prev) => ({ ...prev, error: "名称不能为空" }));
        return;
      }
      if (!startCommand) {
        updateDialogDraft((prev) => ({ ...prev, error: "启动命令不能为空" }));
        return;
      }
      const paramSchema = mergeScriptParamSchema(startCommand, draft.paramSchema, draft.templateParams);
      const templateParams = buildTemplateParams(paramSchema, draft.templateParams);
      const rendered = renderScriptTemplateCommand({
        id: draft.scriptId ?? "validation-only",
        name: scriptName,
        start: startCommand,
        paramSchema,
        templateParams,
      });
      if (!rendered.ok) {
        updateDialogDraft((prev) => ({ ...prev, error: rendered.error }));
        return;
      }

      const scriptPayload = {
        name: scriptName,
        start: startCommand,
        paramSchema: paramSchema.length > 0 ? paramSchema : undefined,
        templateParams: paramSchema.length > 0 ? templateParams : undefined,
      };

      if (!draft.scriptId) {
        void onAddProjectScript(projectId, scriptPayload)
          .then(() => {
            showPanelMessage(`已新增配置：${scriptName}`);
            if (closeAfterSave) {
              setRunConfigurationsDialog(null);
              return;
            }
            setRunConfigurationsDialog((prev) =>
              prev
                ? {
                    ...prev,
                    draft: createNewScriptFormState(),
                    selectedScriptId: null,
                  }
                : prev,
            );
          })
          .catch((error) => {
            console.error("新增运行配置失败。", error);
            updateDialogDraft((prev) => ({ ...prev, error: "保存失败，请重试" }));
          });
        return;
      }

      const targetScript = scripts.find((script) => script.id === draft.scriptId);
      if (!targetScript) {
        updateDialogDraft((prev) => ({ ...prev, error: "命令不存在或已被删除" }));
        return;
      }

      void onUpdateProjectScript(projectId, {
        ...targetScript,
        ...scriptPayload,
      })
        .then(() => {
          setRunConfigurationScriptId(targetScript.id);
          if (closeAfterSave) {
            setRunConfigurationsDialog(null);
            return;
          }
          updateDialogDraft((prev) => ({
            ...prev,
            name: scriptName,
            start: startCommand,
            paramSchema,
            templateParams,
            error: "",
          }));
        })
        .catch((error) => {
          console.error("更新运行配置失败。", error);
          updateDialogDraft((prev) => ({ ...prev, error: "保存失败，请重试" }));
        });
    },
    [
      onAddProjectScript,
      onUpdateProjectScript,
      projectId,
      runConfigurationsDialog,
      scripts,
      setRunConfigurationScriptId,
      showPanelMessage,
      updateDialogDraft,
    ],
  );

  const handleDeleteDialogScript = useCallback(() => {
    if (!projectId || !runConfigurationsDialog) {
      return;
    }
    const targetId = runConfigurationsDialog.draft.scriptId;
    if (!targetId) {
      setRunConfigurationsDialog((prev) =>
        prev
          ? {
              ...prev,
              draft: createNewScriptFormState(),
            }
          : prev,
      );
      return;
    }
    const targetScript = scripts.find((script) => script.id === targetId);
    if (!targetScript) {
      setRunConfigurationsDialog((prev) =>
        prev
          ? {
              ...prev,
              draft: createNewScriptFormState(),
              selectedScriptId: null,
            }
          : prev,
      );
      return;
    }
    const confirmed = window.confirm(`确定删除运行配置“${targetScript.name}”吗？`);
    if (!confirmed) {
      return;
    }
    const remainingScripts = scripts.filter((script) => script.id !== targetId);
    const fallbackScript = remainingScripts[0] ?? null;
    void onRemoveProjectScript(projectId, targetId)
      .then(() => {
        showPanelMessage(`已删除配置：${targetScript.name}`);
        setRunConfigurationScriptId(fallbackScript?.id ?? null);
        setRunConfigurationsDialog((prev) => {
          if (!prev) {
            return prev;
          }
          if (fallbackScript) {
            return {
              ...prev,
              selectedScriptId: fallbackScript.id,
              draft: createScriptFormState(fallbackScript),
            };
          }
          return {
            ...prev,
            selectedScriptId: null,
            draft: createNewScriptFormState(),
          };
        });
      })
      .catch((error) => {
        console.error("删除运行配置失败。", error);
        updateDialogDraft((prev) => ({ ...prev, error: "删除失败，请重试" }));
      });
  }, [
    onRemoveProjectScript,
    projectId,
    runConfigurationsDialog,
    scripts,
    setRunConfigurationScriptId,
    showPanelMessage,
    updateDialogDraft,
  ]);

  const setRunPanelOpen = useCallback(
    (open: boolean) => {
      updateLayoutSnapshot((current) => setRunPanelOpenInSnapshot(current, open));
    },
    [updateLayoutSnapshot],
  );

  const setRunPanelHeight = useCallback(
    (height: number) => {
      const normalizedHeight = Math.max(MIN_RUN_PANEL_HEIGHT, Math.min(720, Math.round(height)));
      updateLayoutSnapshot((current) => setRunPanelHeightInSnapshot(current, normalizedHeight));
    },
    [updateLayoutSnapshot],
  );

  const handleSelectRunTab = useCallback(
    (tabId: string) => {
      updateLayoutSnapshot((current) => activateRunPanelTabInSnapshot(current, tabId, { open: true }));
    },
    [updateLayoutSnapshot],
  );

  const handleCloseRunTab = useCallback(
    (tabId: string) => {
      const current = layoutSnapshotRef.current;
      if (!current) {
        return;
      }
      const runPanel = current.ui?.runPanel ?? DEFAULT_RUN_PANEL;
      const targetTab = runPanel.tabs.find((tab) => tab.id === tabId);
      if (!targetTab) {
        return;
      }
      terminateWorkspaceSessions([targetTab.sessionId]);
      finalizeRuntimeBySessionIds([targetTab.sessionId], 130, "运行标签页已关闭");
      cleanupRuntimeBySessionIds([targetTab.sessionId]);
      closeRunPanelSession(targetTab.sessionId, { closePanelWhenEmpty: true });
    },
    [cleanupRuntimeBySessionIds, closeRunPanelSession, finalizeRuntimeBySessionIds, terminateWorkspaceSessions],
  );

  const handleBeginResizeRunPanel = useCallback(
    (event: ReactPointerEvent<HTMLDivElement>) => {
      if (event.button !== 0) {
        return;
      }
      event.preventDefault();
      const current = layoutSnapshotRef.current;
      if (!current) {
        return;
      }
      const runPanel = current.ui?.runPanel ?? DEFAULT_RUN_PANEL;
      const startClientY = event.clientY;
      const startHeight = runPanel.height;
      const maxHeight = Math.max(MIN_RUN_PANEL_HEIGHT, window.innerHeight - 120);

      const handlePointerMove = (moveEvent: PointerEvent) => {
        const delta = startClientY - moveEvent.clientY;
        const nextHeight = Math.max(MIN_RUN_PANEL_HEIGHT, Math.min(maxHeight, startHeight + delta));
        setRunPanelHeight(nextHeight);
      };
      const handlePointerUp = () => {
        window.removeEventListener("pointermove", handlePointerMove);
        window.removeEventListener("pointerup", handlePointerUp);
      };

      window.addEventListener("pointermove", handlePointerMove);
      window.addEventListener("pointerup", handlePointerUp);
    },
    [setRunPanelHeight],
  );

  const handleSelectTab = useCallback(
    (tabId: string) => {
      updateLayoutSnapshot((current) => {
        if (current.activeTabId === tabId) {
          return current;
        }
        return { ...current, activeTabId: tabId };
      });
    },
    [updateLayoutSnapshot],
  );

  const handleNewTab = useCallback(() => {
    updateLayoutSnapshot((current) => {
      const sessionId = createId();
      const tabId = createId();
      const title = getNextTerminalTitle(current.tabs);
      return appendTerminalTabToSnapshot(current, {
        tabId,
        paneId: `pane:${sessionId}`,
        sessionId,
        title,
        cwd: current.projectPath,
      });
    });
  }, [updateLayoutSnapshot]);

  const handleCloseTab = useCallback(
    (tabId: string) => {
      const current = layoutSnapshotRef.current;
      const closedTab = current?.tabs.find((tab) => tab.id === tabId) ?? null;
      const removedSessions = current && closedTab ? collectSessionIdsForLayoutTab(current, closedTab) : [];
      terminateWorkspaceSessions(removedSessions);
      finalizeRuntimeBySessionIds(removedSessions, 130, "终端标签页已关闭");
      cleanupRuntimeBySessionIds(removedSessions);

      updateLayoutSnapshot((currentSnapshot) => {
        const nextSessionId = createId();
        return removeTerminalTabFromSnapshot(currentSnapshot, tabId, {
          tabId: createId(),
          paneId: `pane:${nextSessionId}`,
          sessionId: nextSessionId,
          title: "终端 1",
          cwd: currentSnapshot.projectPath,
        });
      });
    },
    [cleanupRuntimeBySessionIds, finalizeRuntimeBySessionIds, terminateWorkspaceSessions, updateLayoutSnapshot],
  );

  const handleSelectTabRelative = useCallback(
    (delta: number) => {
      updateLayoutSnapshot((current) => {
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
    [updateLayoutSnapshot],
  );

  const handleSelectTabIndex = useCallback(
    (index: number) => {
      updateLayoutSnapshot((current) => {
        if (index < 0 || index >= current.tabs.length) {
          return current;
        }
        if (current.tabs[index]?.id === current.activeTabId) {
          return current;
        }
        return { ...current, activeTabId: current.tabs[index].id };
      });
    },
    [updateLayoutSnapshot],
  );

  const handleSplit = useCallback(
    (direction: SplitDirection) => {
      updateLayoutSnapshot((current) => {
        const activeTab = current.tabs.find((tab) => tab.id === current.activeTabId) ?? null;
        if (!activeTab) {
          return current;
        }
        const activePane = current.panes[activeTab.activePaneId];
        if (!activePane || activePane.kind !== "terminal") {
          return current;
        }
        const newSessionId = createId();
        return splitTerminalSessionInSnapshot(current, {
          tabId: activeTab.id,
          targetSessionId: activePane.sessionId,
          direction,
          newPaneId: `pane:${newSessionId}`,
          newSessionId,
          cwd: current.projectPath,
        });
      });
    },
    [updateLayoutSnapshot],
  );

  const handleSessionExit = useCallback(
    (sessionId: string, code?: number | null) => {
      handleQuickCommandSessionExit(sessionId, code);
      const current = layoutSnapshotRef.current;
      const runPanel = current?.ui?.runPanel ?? null;
      const runTab = runPanel?.tabs.find((tab) => tab.sessionId === sessionId) ?? null;
      if (runTab) {
        const resolvedCode = typeof code === "number" ? code : null;
        updateLayoutSnapshot((current) =>
          markRunPanelTabExitedInSnapshot(current, sessionId, {
            endedAt: Date.now(),
            exitCode: resolvedCode,
          }),
        );
        return;
      }
      closeSessionLayout(sessionId);
    },
    [closeSessionLayout, handleQuickCommandSessionExit, updateLayoutSnapshot],
  );

  const setFileExplorerShowHidden = useCallback(
    (showHidden: boolean) => {
      updateLayoutSnapshot((current) => setFileExplorerShowHiddenInSnapshot(current, showHidden));
    },
    [updateLayoutSnapshot],
  );

  const updateRightSidebar = useCallback(
    (updater: (current: RightSidebarState) => RightSidebarState) => {
      updateLayoutSnapshot((current) => updateRightSidebarStateInSnapshot(current, updater));
    },
    [updateLayoutSnapshot],
  );

  const upsertPreviewPane = useCallback(
    (relativePath: string, dirty: boolean) => {
      updateLayoutSnapshot((current) =>
        upsertFilePreviewPaneInSnapshot(current, {
          paneId: RIGHT_SIDEBAR_PREVIEW_PANE_ID,
          relativePath,
          dirty,
        }),
      );
    },
    [updateLayoutSnapshot],
  );

  const clearPreviewPane = useCallback(() => {
    updateLayoutSnapshot((current) => removePaneFromSnapshot(current, RIGHT_SIDEBAR_PREVIEW_PANE_ID));
  }, [updateLayoutSnapshot]);

  const upsertGitDiffPane = useCallback(
    (selection: { category: "staged" | "unstaged" | "untracked"; path: string; oldPath?: string | null } | null) => {
      updateLayoutSnapshot((current) =>
        selection
          ? upsertGitDiffPaneInSnapshot(current, {
              paneId: RIGHT_SIDEBAR_GIT_DIFF_PANE_ID,
              relativePath: selection.path,
              oldRelativePath: selection.oldPath ?? null,
              category: selection.category,
            })
          : removePaneFromSnapshot(current, RIGHT_SIDEBAR_GIT_DIFF_PANE_ID),
      );
    },
    [updateLayoutSnapshot],
  );

  const clearGitDiffPane = useCallback(() => {
    updateLayoutSnapshot((current) => removePaneFromSnapshot(current, RIGHT_SIDEBAR_GIT_DIFF_PANE_ID));
  }, [updateLayoutSnapshot]);

  const closeRightSidebar = useCallback(() => {
    updateRightSidebar((current) => ({ ...current, open: false }));
    clearPreviewPane();
    clearGitDiffPane();
  }, [clearGitDiffPane, clearPreviewPane, updateRightSidebar]);

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
        const current = layoutSnapshotRef.current;
        if (!current) {
          return;
        }
        const activeTab = current.tabs.find((tab) => tab.id === current.activeTabId);
        if (!activeTab) {
          return;
        }
        const activePane = current.panes[activeTab.activePaneId];
        if (!activePane || activePane.kind !== "terminal") {
          return;
        }
        terminateWorkspaceSessions([activePane.sessionId]);
        handleSessionExit(activePane.sessionId, 130);
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
          const current = layoutSnapshotRef.current;
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
      updateLayoutSnapshot((current) => {
        const activeTab = current.tabs.find((tab) => tab.id === current.activeTabId);
        if (!activeTab) {
          return current;
        }
        const nextRoot = updateLayoutNodeRatios(activeTab.root, path, ratios);
        if (nextRoot === activeTab.root) {
          return current;
        }
        const nextTab = { ...activeTab, root: nextRoot };
        return {
          ...current,
          tabs: current.tabs.map((tab) => (tab.id === activeTab.id ? nextTab : tab)),
        };
      });
    },
    [updateLayoutSnapshot],
  );

  const handleActivateSession = useCallback(
    (tabId: string, sessionId: string) => {
      updateLayoutSnapshot((current) => activateTerminalSessionInSnapshot(current, tabId, sessionId));
    },
    [updateLayoutSnapshot],
  );

  if (!projectPath) {
    return (
      <div className="flex h-full items-center justify-center text-[var(--terminal-muted-fg)]">未找到项目</div>
    );
  }

  if (error) {
    return <div className="flex h-full items-center justify-center text-[var(--terminal-muted-fg)]">{error}</div>;
  }

  if (!activeSnapshot) {
    return (
      <div className="flex h-full items-center justify-center text-[var(--terminal-muted-fg)]">
        正在加载终端工作空间...
      </div>
    );
  }

  const selectedScriptId =
    shellModel?.selectedRunConfigurationId &&
    scripts.some((script) => script.id === shellModel.selectedRunConfigurationId)
      ? shellModel.selectedRunConfigurationId
      : scripts[0]?.id ?? null;
  const selectedScript = selectedScriptId
    ? scripts.find((script) => script.id === selectedScriptId) ?? null
    : null;
  const selectedRuntime = selectedScript ? scriptRuntimeById[selectedScript.id] ?? null : null;
  const selectedRuntimeValid = selectedRuntime ? isScriptRuntimeValid(selectedRuntime) : false;
  const selectedQuickJob = selectedScript ? quickCommandJobByScriptId[selectedScript.id] ?? null : null;
  const selectedLocalPhase = selectedScript ? scriptLocalPhaseById[selectedScript.id] ?? null : null;
  const selectedScriptState: ScriptExecutionState = !selectedScript
    ? "idle"
    : selectedQuickJob
      ? toScriptExecutionStateFromQuickState(selectedQuickJob.state)
      : selectedLocalPhase ?? (selectedRuntimeValid ? "running" : "idle");
  const runDisabled =
    !selectedScript ||
    selectedScriptState === "starting" ||
    selectedScriptState === "stoppingSoft" ||
    selectedScriptState === "stoppingHard";
  const stopDisabled =
    !selectedScript ||
    !(
      selectedScriptState === "running" ||
      selectedScriptState === "starting" ||
      selectedScriptState === "stoppingSoft" ||
      selectedScriptState === "stoppingHard"
    );
  const filePanelShowHidden =
    shellModel?.filePanelShowHidden ?? workspaceDefaultsRef.current.defaultFileExplorerShowHidden;
  const rightSidebarOpen = shellModel?.rightSidebarOpen ?? false;
  const rightSidebarWidth = shellModel?.rightSidebarWidth ?? DEFAULT_RIGHT_SIDEBAR.width;
  const rightSidebarTab: TerminalRightSidebarTab = shellModel?.rightSidebarTab ?? DEFAULT_RIGHT_SIDEBAR.tab;
  const headerTabs = shellModel?.headerTabs ?? [];
  const activeTabId = shellModel?.activeTabId ?? activeSnapshot.activeTabId;
  const activeWorkspaceTab = shellModel?.activeWorkspaceTab ?? null;
  const activePaneProjections = shellModel?.activePaneProjections ?? {};
  const runPanelTabs = shellModel?.runPanelTabs ?? [];
  const runPanelActiveTabId = shellModel?.runPanelActiveTabId ?? null;
  const runPanelOpen = shellModel?.runPanelOpen ?? false;
  const runPanelHeight = shellModel?.runPanelHeight ?? DEFAULT_RUN_PANEL.height;
  const activeRunTab = shellModel?.activeRunTab ?? null;

  const activeTabRunning = (() => {
    if (!activeRunTab) return false;
    const quickJob = quickCommandJobByScriptId[activeRunTab.scriptId] ?? null;
    if (quickJob && (activeRunTab.endedAt === null || activeRunTab.endedAt === undefined)) {
      const state = toScriptExecutionStateFromQuickState(quickJob.state);
      return state === "running" || state === "starting";
    }
    const runtime = scriptRuntimeById[activeRunTab.scriptId] ?? null;
    const runtimeMatches = Boolean(runtime && runtime.tabId === activeRunTab.id && isScriptRuntimeValid(runtime));
    if (!runtimeMatches) return false;
    const localPhase = scriptLocalPhaseById[activeRunTab.scriptId] ?? null;
    return localPhase === "starting" || localPhase === null;
  })();

  const rerunActiveTab = () => {
    if (!activeRunTab) return;
    const script = scripts.find((s) => s.id === activeRunTab.scriptId);
    if (!script) return;
    runQuickCommand(script, { reuseTabId: activeRunTab.id });
  };

  const stopActiveTab = () => {
    if (!activeRunTab) return;
    stopScript(activeRunTab.scriptId);
  };

  return (
    <>
      <TerminalWorkspaceShell
        projectName={projectName}
        projectPath={projectPath}
        codexRunningCount={codexRunningCount}
        isGitRepo={isGitRepo}
        windowLabel={windowLabel}
        runtimeClientId={runtimeClientId}
        xtermTheme={xtermTheme}
        terminalUseWebglRenderer={terminalUseWebglRenderer}
        scripts={scripts}
        selectedScriptId={selectedScriptId}
        selectedScriptState={selectedScriptState}
        runDisabled={runDisabled}
        stopDisabled={stopDisabled}
        scriptActionsDisabled={!selectedScript}
        headerTabs={headerTabs}
        activeTabId={activeTabId}
        activeWorkspaceTab={activeWorkspaceTab}
        activePaneProjections={activePaneProjections}
        rightSidebarOpen={rightSidebarOpen}
        rightSidebarWidth={rightSidebarWidth}
        rightSidebarTab={rightSidebarTab}
        previewDirty={previewDirty}
        previewFilePath={previewFilePath}
        filePanelShowHidden={Boolean(filePanelShowHidden)}
        gitSelected={gitSelected}
        runPanelTabs={runPanelTabs}
        runPanelActiveTabId={runPanelActiveTabId}
        runPanelOpen={runPanelOpen}
        runPanelHeight={runPanelHeight}
        activeTabRunning={activeTabRunning}
        sessionSnapshots={sessionSnapshots}
        scriptRuntimeById={scriptRuntimeById}
        quickCommandJobByScriptId={quickCommandJobByScriptId}
        scriptLocalPhaseById={scriptLocalPhaseById}
        isScriptRuntimeValid={isScriptRuntimeValid}
        onSelectScript={(scriptId) => setRunConfigurationScriptId(scriptId || null)}
        onEditScript={openRunConfigurationsDialog}
        onDeleteScript={removeSelectedScript}
        onRunScript={runSelectedScript}
        onStopScript={stopSelectedScript}
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
        onResize={handleResize}
        onActivateSession={handleActivateSession}
        onPtyReady={handlePtyReady}
        onSessionExit={handleSessionExit}
        onSetRightSidebarWidth={setRightSidebarWidth}
        onToggleShowHidden={setFileExplorerShowHidden}
        onOpenPreview={(relativePath) => upsertPreviewPane(relativePath, false)}
        onClosePreview={clearPreviewPane}
        onPreviewDirtyChange={(dirty) => {
          if (!previewFilePath) {
            return;
          }
          upsertPreviewPane(previewFilePath, dirty);
        }}
        onSelectGitFile={upsertGitDiffPane}
        onCloseGitSelection={clearGitDiffPane}
        onChangeRightSidebarTab={setRightSidebarTab}
        onCloseRightSidebar={requestCloseRightSidebar}
        onSelectRunTab={handleSelectRunTab}
        onCloseRunTab={handleCloseRunTab}
        onSetRunPanelOpen={setRunPanelOpen}
        onResizeRunPanelStart={handleBeginResizeRunPanel}
        onRerunActiveTab={rerunActiveTab}
        onStopActiveTab={stopActiveTab}
      />
      {runConfigurationsDialog ? (
        <div className="modal-overlay" role="dialog" aria-modal>
          <div className="modal-panel w-[min(980px,94vw)] max-h-[90vh] overflow-hidden p-0">
            <div className="border-b border-border px-4 py-3 text-[16px] font-semibold text-text">运行配置</div>
            <div className="flex min-h-[520px]">
              <aside className="flex w-[260px] shrink-0 flex-col border-r border-border bg-secondary-background">
                <div className="flex items-center gap-2 border-b border-border px-3 py-2">
                  <button type="button" className="btn btn-outline px-2.5 py-1" onClick={createDialogScript}>
                    新建
                  </button>
                  <button
                    type="button"
                    className="btn px-2.5 py-1"
                    onClick={handleDeleteDialogScript}
                    disabled={!runConfigurationsDialog.draft.scriptId}
                  >
                    删除
                  </button>
                </div>
                <div className="flex min-h-0 flex-1 flex-col gap-1 overflow-y-auto p-2">
                  {scripts.length === 0 ? (
                    <div className="rounded-md border border-border bg-card-bg px-2 py-2 text-[12px] text-secondary-text">
                      暂无运行配置，点击“新建”创建。
                    </div>
                  ) : (
                    scripts.map((script) => {
                      const isActive = runConfigurationsDialog.selectedScriptId === script.id;
                      return (
                        <button
                          key={script.id}
                          type="button"
                          className={`rounded-md border px-2 py-2 text-left text-[12px] transition-colors ${
                            isActive
                              ? "border-accent bg-[rgba(59,130,246,0.15)] text-text"
                              : "border-transparent text-secondary-text hover:border-border hover:bg-card-bg hover:text-text"
                          }`}
                          onClick={() => selectDialogScript(script.id)}
                        >
                          <div className="truncate font-semibold">{script.name}</div>
                          <div className="truncate text-[11px] opacity-80">{script.start}</div>
                        </button>
                      );
                    })
                  )}
                  {runConfigurationsDialog.draft.scriptId === null ? (
                    <div className="rounded-md border border-dashed border-border bg-card-bg px-2 py-2 text-[12px] text-secondary-text">
                      新建配置（未保存）
                    </div>
                  ) : null}
                </div>
              </aside>
              <section className="flex min-h-0 min-w-0 flex-1 flex-col gap-3 overflow-y-auto p-4">
                <label className="flex flex-col gap-1.5 text-[13px] text-secondary-text">
                  <span>插入通用脚本（可选）</span>
                  <select
                    className="rounded-md border border-border bg-card-bg px-2 py-2 text-text"
                    value={runConfigurationsDialog.draft.selectedSharedScriptId}
                    onChange={(event) => {
                      const selectedId = event.target.value;
                      updateDialogDraft((draft) => {
                        if (!selectedId) {
                          return { ...draft, selectedSharedScriptId: "", error: "" };
                        }
                        const selected = sharedScripts.find((item) => item.id === selectedId);
                        if (!selected) {
                          return {
                            ...draft,
                            selectedSharedScriptId: selectedId,
                            error: "通用脚本不存在或已失效",
                          };
                        }
                        const start = applySharedScriptCommandTemplate(
                          selected.commandTemplate,
                          selected.absolutePath,
                        );
                        const paramSchema = mergeScriptParamSchema(start, selected.params, draft.templateParams);
                        const templateParams = buildTemplateParams(paramSchema, draft.templateParams);
                        return {
                          ...draft,
                          selectedSharedScriptId: selected.id,
                          name: draft.name.trim() ? draft.name : selected.name,
                          start,
                          paramSchema,
                          templateParams,
                          error: "",
                        };
                      });
                    }}
                  >
                    <option value="">手动输入命令</option>
                    {sharedScripts.map((item) => (
                      <option key={item.id} value={item.id}>
                        {item.name} ({item.relativePath})
                      </option>
                    ))}
                  </select>
                  {sharedScriptsLoading ? (
                    <div className="text-fs-caption text-secondary-text">正在加载通用脚本...</div>
                  ) : null}
                  {sharedScriptsError ? <div className="text-fs-caption text-error">{sharedScriptsError}</div> : null}
                </label>
                <label className="flex flex-col gap-1.5 text-[13px] text-secondary-text">
                  <span>名称</span>
                  <input
                    className="rounded-md border border-border bg-card-bg px-2 py-2 text-text"
                    value={runConfigurationsDialog.draft.name}
                    onChange={(event) =>
                      updateDialogDraft((draft) => ({ ...draft, name: event.target.value, error: "" }))
                    }
                  />
                </label>
                <label className="flex flex-col gap-1.5 text-[13px] text-secondary-text">
                  <span>启动命令</span>
                  <textarea
                    className="min-h-[90px] resize-y rounded-md border border-border bg-card-bg px-2 py-2 text-text"
                    value={runConfigurationsDialog.draft.start}
                    onChange={(event) => {
                      const nextStart = event.target.value;
                      updateDialogDraft((draft) => {
                        const paramSchema = mergeScriptParamSchema(
                          nextStart,
                          draft.paramSchema,
                          draft.templateParams,
                        );
                        const templateParams = buildTemplateParams(paramSchema, draft.templateParams);
                        return {
                          ...draft,
                          start: nextStart,
                          paramSchema,
                          templateParams,
                          error: "",
                        };
                      });
                    }}
                    placeholder="例如：pnpm dev"
                  />
                </label>
                {runConfigurationsDialog.draft.paramSchema.length > 0 ? (
                  <section className="flex flex-col gap-2 rounded-md border border-border bg-secondary-background p-2.5">
                    <div className="text-[13px] font-semibold text-text">参数配置</div>
                    <div className="grid gap-2 sm:grid-cols-2">
                      {runConfigurationsDialog.draft.paramSchema.map((field) => (
                        <label key={field.key} className="flex flex-col gap-1.5 text-[13px] text-secondary-text">
                          <span>
                            {field.label}
                            {field.required ? <span className="text-error"> *</span> : null}
                          </span>
                          <input
                            type={field.type === "secret" ? "password" : field.type === "number" ? "number" : "text"}
                            className="rounded-md border border-border bg-card-bg px-2 py-2 text-text"
                            value={runConfigurationsDialog.draft.templateParams[field.key] ?? ""}
                            onChange={(event) =>
                              updateDialogDraft((draft) => ({
                                ...draft,
                                templateParams: {
                                  ...draft.templateParams,
                                  [field.key]: event.target.value,
                                },
                                error: "",
                              }))
                            }
                            placeholder={field.defaultValue ?? `请输入 ${field.label}`}
                          />
                          {field.description ? (
                            <span className="text-fs-caption text-secondary-text">{field.description}</span>
                          ) : null}
                        </label>
                      ))}
                    </div>
                  </section>
                ) : null}
                {runConfigurationsDialog.draft.error ? (
                  <div className="text-fs-caption text-error">{runConfigurationsDialog.draft.error}</div>
                ) : null}
                <div className="mt-auto flex items-center justify-between gap-2 border-t border-border pt-3">
                  <button
                    type="button"
                    className="btn btn-outline"
                    onClick={() => {
                      const target = runConfigurationsDialog.draft.scriptId
                        ? scripts.find((script) => script.id === runConfigurationsDialog.draft.scriptId) ?? null
                        : null;
                      if (!target) {
                        showPanelMessage("请先保存配置再运行");
                        return;
                      }
                      runQuickCommand(target);
                    }}
                  >
                    运行
                  </button>
                  <div className="flex items-center gap-2">
                    <button type="button" className="btn" onClick={() => setRunConfigurationsDialog(null)}>
                      取消
                    </button>
                    <button type="button" className="btn btn-outline" onClick={() => handleSaveRunConfiguration(false)}>
                      应用
                    </button>
                    <button type="button" className="btn btn-primary" onClick={() => handleSaveRunConfiguration(true)}>
                      确定
                    </button>
                  </div>
                </div>
              </section>
            </div>
          </div>
        </div>
      ) : null}
    </>
  );
}

function createScriptFormState(script: ProjectScript): ScriptFormState {
  const start = script.start ?? "";
  const paramSchema = mergeScriptParamSchema(start, script.paramSchema, script.templateParams);
  const templateParams = buildTemplateParams(paramSchema, script.templateParams);
  return {
    scriptId: script.id,
    name: script.name ?? "",
    start,
    error: "",
    selectedSharedScriptId: "",
    paramSchema,
    templateParams,
  };
}

function createNewScriptFormState(): ScriptFormState {
  return {
    scriptId: null,
    name: "",
    start: "",
    error: "",
    selectedSharedScriptId: "",
    paramSchema: [],
    templateParams: {},
  };
}

export default memo(TerminalWorkspaceView, areTerminalWorkspaceViewPropsEqual);
