import {
  memo,
  useCallback,
  useEffect,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
} from "react";
import type { ITheme } from "xterm";

import type { TerminalQuickCommandDispatch } from "../../models/quickCommands";
import type {
  RunPanelState,
  RightSidebarState,
  SplitDirection,
  TerminalRightSidebarTab,
  TerminalWorkspace,
} from "../../models/terminal";
import type { ProjectScript, ScriptParamField, SharedScriptEntry } from "../../models/types";
import { resolveRuntimeClientId } from "../../platform/runtime";
import { gitIsRepo } from "../../services/gitManagement";
import { listSharedScripts } from "../../services/sharedScripts";
import {
  listenTerminalWorkspaceSync,
  loadTerminalWorkspace,
  saveTerminalWorkspace,
} from "../../services/terminalWorkspace";
import {
  applySharedScriptCommandTemplate,
  buildTemplateParams,
  mergeScriptParamSchema,
  renderScriptTemplateCommand,
} from "../../utils/scriptTemplate";
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
import {
  toScriptExecutionStateFromQuickState,
  useQuickCommandRuntime,
  type ScriptExecutionState,
} from "../../hooks/useQuickCommandRuntime";
import { IconChevronDown } from "../Icons";
import ResizablePanel from "./ResizablePanel";
import SplitLayout from "./SplitLayout";
import TerminalPane from "./TerminalPane";
import TerminalRunPanel from "./TerminalRunPanel";
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
  sharedScriptsRoot: string;
  terminalUseWebglRenderer: boolean;
  codexRunningCount?: number;
  scripts?: ProjectScript[];
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

function getRunPanelState(workspace: TerminalWorkspace) {
  return workspace.ui?.runPanel ?? DEFAULT_RUN_PANEL;
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

  const [workspace, setWorkspace] = useState<TerminalWorkspace | null>(null);
  const [error, setError] = useState<string | null>(null);
  const workspaceRef = useRef<TerminalWorkspace | null>(null);
  const snapshotProviders = useRef(new Map<string, () => string | null>());
  const [previewFilePath, setPreviewFilePath] = useState<string | null>(null);
  const [previewDirty, setPreviewDirty] = useState(false);
  const [isGitRepo, setIsGitRepo] = useState(false);
  const [runConfigurationsDialog, setRunConfigurationsDialog] = useState<RunConfigurationsDialogState | null>(null);
  const [sharedScripts, setSharedScripts] = useState<SharedScriptEntry[]>([]);
  const [sharedScriptsLoading, setSharedScriptsLoading] = useState(false);
  const [sharedScriptsError, setSharedScriptsError] = useState<string | null>(null);
  const runtimeClientIdRef = useRef(resolveRuntimeClientId());
  const runtimeClientId = runtimeClientIdRef.current;
  const skipAutoSaveFingerprintRef = useRef<string | null>(null);

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

  useEffect(() => {
    let cancelled = false;
    let unlisten: (() => void) | null = null;

    const register = async () => {
      try {
        unlisten = await listenTerminalWorkspaceSync((event) => {
          if (cancelled) {
            return;
          }
          const payload = event.payload;
          if (!payload || payload.projectPath !== projectPath) {
            return;
          }
          if (payload.sourceClientId && payload.sourceClientId === runtimeClientId) {
            return;
          }

          setWorkspace((current) => {
            const currentUpdatedAt = current?.updatedAt ?? 0;
            const incomingUpdatedAt = Number(payload.updatedAt ?? 0);
            if (incomingUpdatedAt > 0 && incomingUpdatedAt <= currentUpdatedAt) {
              return current;
            }

            if (payload.deleted) {
              const fallback = createDefaultWorkspace(projectPath, projectId, workspaceDefaultsRef.current);
              const next = {
                ...fallback,
                updatedAt: incomingUpdatedAt || fallback.updatedAt,
              };
              skipAutoSaveFingerprintRef.current = JSON.stringify(next);
              return next;
            }

            if (!payload.workspace) {
              return current;
            }
            const next = normalizeWorkspace(
              payload.workspace,
              projectPath,
              projectId,
              workspaceDefaultsRef.current,
            );
            skipAutoSaveFingerprintRef.current = JSON.stringify(next);
            return next;
          });
        });
      } catch (syncError) {
        if (!cancelled) {
          console.error("监听终端工作区同步事件失败。", syncError);
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
    const currentFingerprint = JSON.stringify(current);
    if (
      skipAutoSaveFingerprintRef.current &&
      skipAutoSaveFingerprintRef.current === currentFingerprint
    ) {
      skipAutoSaveFingerprintRef.current = null;
      return;
    }
    skipAutoSaveFingerprintRef.current = null;

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
      await saveTerminalWorkspace(current.projectPath, payload, runtimeClientId);
    } catch (saveError) {
      console.error("保存终端工作空间失败。", saveError);
    }
  }, [runtimeClientId]);

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
            const nextSessionId = createId();
            const nextTabId = createId();
            return {
              ...currentWorkspace,
              activeTabId: nextTabId,
              tabs: [
                {
                  id: nextTabId,
                  title: "终端 1",
                  root: { type: "pane", sessionId: nextSessionId },
                  activeSessionId: nextSessionId,
                },
              ],
              sessions: {
                ...nextSessions,
                [nextSessionId]: { id: nextSessionId, cwd: currentWorkspace.projectPath, savedState: null },
              },
            };
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

  const closeRunPanelSession = useCallback(
    (sessionId: string, options?: { closePanelWhenEmpty?: boolean }) => {
      const current = workspaceRef.current;
      if (!current) {
        return false;
      }
      const currentRunPanel = getRunPanelState(current);
      const targetTab = currentRunPanel.tabs.find((tab) => tab.sessionId === sessionId);
      if (!targetTab) {
        return false;
      }
      updateWorkspace((currentWorkspace) => {
        const runPanel = getRunPanelState(currentWorkspace);
        const target = runPanel.tabs.find((tab) => tab.sessionId === sessionId);
        if (!target) {
          return currentWorkspace;
        }
        const nextTabs = runPanel.tabs.filter((tab) => tab.id !== target.id);
        const nextActiveTabId =
          runPanel.activeTabId === target.id ? nextTabs[nextTabs.length - 1]?.id ?? null : runPanel.activeTabId;
        const nextSessions = { ...currentWorkspace.sessions };
        delete nextSessions[sessionId];
        return {
          ...currentWorkspace,
          sessions: nextSessions,
          ui: {
            ...(currentWorkspace.ui ?? {}),
            runPanel: {
              ...runPanel,
              tabs: nextTabs,
              activeTabId: nextActiveTabId,
              open: nextTabs.length > 0 ? runPanel.open : !(options?.closePanelWhenEmpty ?? true),
            },
          },
        };
      });
      return true;
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
    sharedScriptsRoot,
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

  useEffect(() => {
    if (!workspace) {
      return;
    }
    updateWorkspace((current) => {
      const currentRunPanel = getRunPanelState(current);
      const validTabs = currentRunPanel.tabs.filter((tab) => Boolean(current.sessions[tab.sessionId]));
      const nextActiveTabId =
        currentRunPanel.activeTabId && validTabs.some((tab) => tab.id === currentRunPanel.activeTabId)
          ? currentRunPanel.activeTabId
          : validTabs[validTabs.length - 1]?.id ?? null;
      const nextOpen = validTabs.length > 0 ? currentRunPanel.open : false;
      if (
        validTabs.length === currentRunPanel.tabs.length &&
        nextActiveTabId === currentRunPanel.activeTabId &&
        nextOpen === currentRunPanel.open
      ) {
        return current;
      }
      return {
        ...current,
        ui: {
          ...(current.ui ?? {}),
          runPanel: {
            ...currentRunPanel,
            tabs: validTabs,
            activeTabId: nextActiveTabId,
            open: nextOpen,
          },
        },
      };
    });
  }, [updateWorkspace, workspace]);

  const setRunConfigurationScriptId = useCallback(
    (scriptId: string | null) => {
      const nextScriptId =
        scriptId && scripts.some((script) => script.id === scriptId) ? scriptId : scripts[0]?.id ?? null;
      updateWorkspace((current) => ({
        ...current,
        ui: {
          ...current.ui,
          runConfiguration: {
            ...(current.ui?.runConfiguration ?? { selectedScriptId: null }),
            selectedScriptId: nextScriptId,
          },
        },
      }));
    },
    [scripts, updateWorkspace],
  );

  useEffect(() => {
    if (!workspace) {
      return;
    }
    const currentSelected = workspace.ui?.runConfiguration?.selectedScriptId ?? null;
    const nextSelected =
      currentSelected && scripts.some((script) => script.id === currentSelected)
        ? currentSelected
        : scripts[0]?.id ?? null;
    if (currentSelected === nextSelected) {
      return;
    }
    setRunConfigurationScriptId(nextSelected);
  }, [scripts, setRunConfigurationScriptId, workspace]);

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
    const current = workspaceRef.current;
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
      updateWorkspace((current) => {
        const runPanel = getRunPanelState(current);
        if (runPanel.open === open) {
          return current;
        }
        return {
          ...current,
          ui: {
            ...(current.ui ?? {}),
            runPanel: {
              ...runPanel,
              open,
            },
          },
        };
      });
    },
    [updateWorkspace],
  );

  const setRunPanelHeight = useCallback(
    (height: number) => {
      const normalizedHeight = Math.max(MIN_RUN_PANEL_HEIGHT, Math.min(720, Math.round(height)));
      updateWorkspace((current) => {
        const runPanel = getRunPanelState(current);
        if (runPanel.height === normalizedHeight) {
          return current;
        }
        return {
          ...current,
          ui: {
            ...(current.ui ?? {}),
            runPanel: {
              ...runPanel,
              height: normalizedHeight,
            },
          },
        };
      });
    },
    [updateWorkspace],
  );

  const handleSelectRunTab = useCallback(
    (tabId: string) => {
      updateWorkspace((current) => {
        const runPanel = getRunPanelState(current);
        if (!runPanel.tabs.some((tab) => tab.id === tabId)) {
          return current;
        }
        return {
          ...current,
          ui: {
            ...(current.ui ?? {}),
            runPanel: {
              ...runPanel,
              open: true,
              activeTabId: tabId,
            },
          },
        };
      });
    },
    [updateWorkspace],
  );

  const handleCloseRunTab = useCallback(
    (tabId: string) => {
      const current = workspaceRef.current;
      if (!current) {
        return;
      }
      const runPanel = getRunPanelState(current);
      const targetTab = runPanel.tabs.find((tab) => tab.id === tabId);
      if (!targetTab) {
        return;
      }
      finalizeRuntimeBySessionIds([targetTab.sessionId], 130, "运行标签页已关闭");
      cleanupRuntimeBySessionIds([targetTab.sessionId]);
      closeRunPanelSession(targetTab.sessionId, { closePanelWhenEmpty: true });
    },
    [cleanupRuntimeBySessionIds, closeRunPanelSession, finalizeRuntimeBySessionIds],
  );

  const handleBeginResizeRunPanel = useCallback(
    (event: ReactPointerEvent<HTMLDivElement>) => {
      if (event.button !== 0) {
        return;
      }
      event.preventDefault();
      const current = workspaceRef.current;
      if (!current) {
        return;
      }
      const runPanel = getRunPanelState(current);
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
          const nextSessions = { ...currentWorkspace.sessions };
          removedSessionIds.forEach((sessionId) => {
            delete nextSessions[sessionId];
          });
          const nextSessionId = createId();
          const nextTabId = createId();
          return {
            ...currentWorkspace,
            activeTabId: nextTabId,
            tabs: [
              {
                id: nextTabId,
                title: "终端 1",
                root: { type: "pane", sessionId: nextSessionId },
                activeSessionId: nextSessionId,
              },
            ],
            sessions: {
              ...nextSessions,
              [nextSessionId]: { id: nextSessionId, cwd: currentWorkspace.projectPath, savedState: null },
            },
          };
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
      const current = workspaceRef.current;
      const runPanel = current ? getRunPanelState(current) : null;
      const runTab = runPanel?.tabs.find((tab) => tab.sessionId === sessionId) ?? null;
      if (runTab) {
        const resolvedCode = typeof code === "number" ? code : null;
        updateWorkspace((currentWorkspace) => {
          const currentRunPanel = getRunPanelState(currentWorkspace);
          const nextTabs = currentRunPanel.tabs.map((tab) =>
            tab.sessionId === sessionId
              ? {
                  ...tab,
                  endedAt: Date.now(),
                  exitCode: resolvedCode,
                }
              : tab,
          );
          return {
            ...currentWorkspace,
            ui: {
              ...(currentWorkspace.ui ?? {}),
              runPanel: {
                ...currentRunPanel,
                tabs: nextTabs,
              },
            },
          };
        });
        return;
      }
      const removedSessions = closeSessionLayout(sessionId);
      const extraRemovedSessions = removedSessions.filter((id) => id !== sessionId);
      if (extraRemovedSessions.length > 0) {
        cleanupRuntimeBySessionIds(extraRemovedSessions);
      }
    },
    [cleanupRuntimeBySessionIds, closeSessionLayout, handleQuickCommandSessionExit, updateWorkspace],
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

  const runConfigurationState = workspace.ui?.runConfiguration ?? { selectedScriptId: null };
  const selectedScriptId =
    runConfigurationState.selectedScriptId &&
    scripts.some((script) => script.id === runConfigurationState.selectedScriptId)
      ? runConfigurationState.selectedScriptId
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
  const runPanelState = workspace.ui?.runPanel ?? DEFAULT_RUN_PANEL;
  const runPanelTabs = runPanelState.tabs;
  const runPanelActiveTabId =
    runPanelState.activeTabId && runPanelTabs.some((tab) => tab.id === runPanelState.activeTabId)
      ? runPanelState.activeTabId
      : runPanelTabs[runPanelTabs.length - 1]?.id ?? null;
  const runPanelOpen = Boolean(runPanelState.open && runPanelTabs.length > 0);
  const runPanelHeight = Math.max(MIN_RUN_PANEL_HEIGHT, Math.min(720, runPanelState.height));

  const activeRunTab = runPanelActiveTabId ? runPanelTabs.find((t) => t.id === runPanelActiveTabId) ?? null : null;
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
        rightSidebarOpen={rightSidebarOpen}
        rightSidebarTab={rightSidebarTab}
        scripts={scripts}
        selectedScriptId={selectedScriptId}
        selectedScriptState={selectedScriptState}
        quickCommandMessage={panelMessage}
        runDisabled={runDisabled}
        stopDisabled={stopDisabled}
        scriptActionsDisabled={!selectedScript}
        tabs={workspace.tabs}
        activeTabId={workspace.activeTabId}
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
      />
      <div className="flex min-h-0 min-w-0 flex-1 flex-col">
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
                      clientId={runtimeClientId}
                      useWebgl={terminalUseWebglRenderer && tab.id === workspace.activeTabId}
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
        {runPanelOpen ? (
          <TerminalRunPanel
            open
            height={runPanelHeight}
            tabs={runPanelTabs}
            activeTabId={runPanelActiveTabId}
            sessions={workspace.sessions}
            projectPath={projectPath}
            windowLabel={windowLabel}
            clientId={runtimeClientId}
            xtermTheme={xtermTheme}
            terminalUseWebglRenderer={terminalUseWebglRenderer}
            scriptRuntimeById={scriptRuntimeById}
            quickCommandJobByScriptId={quickCommandJobByScriptId}
            scriptLocalPhaseById={scriptLocalPhaseById}
            isScriptRuntimeValid={isScriptRuntimeValid}
            onSelectTab={handleSelectRunTab}
            onCloseTab={handleCloseRunTab}
            onCollapse={() => setRunPanelOpen(false)}
            onResizeStart={handleBeginResizeRunPanel}
            onRerunActiveTab={rerunActiveTab}
            onStopActiveTab={stopActiveTab}
            activeTabRunning={activeTabRunning}
            onPtyReady={handlePtyReady}
            onExit={handleSessionExit}
            onRegisterSnapshotProvider={registerSnapshotProvider}
          />
        ) : runPanelTabs.length > 0 ? (
          <button
            type="button"
            className="inline-flex h-8 shrink-0 items-center gap-1 border-t border-[var(--terminal-divider)] bg-[var(--terminal-panel-bg)] px-3 text-[11px] font-semibold text-[var(--terminal-muted-fg)] transition-colors hover:text-[var(--terminal-fg)]"
            onClick={() => setRunPanelOpen(true)}
          >
            <IconChevronDown size={14} />
            <span>显示运行面板（{runPanelTabs.length}）</span>
          </button>
        ) : null}
      </div>
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
    </div>
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
