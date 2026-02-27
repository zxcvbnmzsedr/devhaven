import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
} from "react";
import type { ITheme } from "xterm";

import type { QuickCommandJob, QuickCommandState, TerminalQuickCommandDispatch } from "../../models/quickCommands";
import type { RightSidebarState, SplitDirection, TerminalRightSidebarTab, TerminalTab, TerminalWorkspace } from "../../models/terminal";
import type { ProjectScript } from "../../models/types";
import { useDevHavenContext } from "../../state/DevHavenContext";
import {
  finishQuickCommand,
  getQuickCommandSnapshot,
  listenQuickCommandEvent,
  startQuickCommand,
  stopQuickCommand as stopQuickCommandJob,
} from "../../services/quickCommands";
import {
  getTerminalCodexPaneOverlay,
  killTerminal,
  listenTerminalOutput,
  writeTerminal,
  type TerminalCodexPaneOverlay,
} from "../../services/terminal";
import { saveTerminalWorkspace, loadTerminalWorkspace } from "../../services/terminalWorkspace";
import { gitIsRepo } from "../../services/gitManagement";
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
import { renderScriptTemplateCommand } from "../../utils/scriptTemplate";
import { IconFolder, IconGitBranch, IconSidebarRight, IconX } from "../Icons";
import ResizablePanel from "./ResizablePanel";
import SplitLayout from "./SplitLayout";
import TerminalRightSidebar from "./TerminalRightSidebar";
import TerminalPane from "./TerminalPane";
import TerminalTabs from "./TerminalTabs";

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

type ScriptRuntime = {
  jobId: string;
  tabId: string;
  sessionId: string;
  ptyId: string | null;
};

const TERMINAL_TITLE_PATTERN = /^终端\s*(\d+)$/;
const CODEX_STARTUP_OUTPUT_BUFFER_LIMIT = 4096;
const QUICK_COMMAND_FORCE_KILL_TIMEOUT_MS = 1500;
const ANSI_CSI_REGEX = /\u001b\[[0-?]*[ -/]*[@-~]/g;
const ANSI_OSC_REGEX = /\u001b\][^\u0007]*(?:\u0007|\u001b\\)/g;
const CODEX_MODEL_LINE_REGEX = /model:\s*([^\s|]+)\s+([^\s|]+)\s+\/model\b/i;
const CODEX_MODEL_CHANGED_REGEX = /model changed to\s+([^\s`]+)(?:\s+([^\s`]+))?/i;
const CODEX_RESUME_MODEL_REGEX = /resuming with\s+`([^`]+)`/i;

const DEFAULT_RIGHT_SIDEBAR: RightSidebarState = {
  open: false,
  width: 520,
  tab: "files",
};
const MIN_RIGHT_SIDEBAR_WIDTH = 360;
const MAX_RIGHT_SIDEBAR_WIDTH = 960;
const CODEX_PANE_OVERLAY_REFRESH_INTERVAL_MS = 2500;
const QUICK_COMMAND_RECONCILE_INTERVAL_MS = 10000;

type CodexStartupHint = {
  model: string | null;
  effort: string | null;
  updatedAt: number;
};

type ScriptLocalPhase = "starting" | "stoppingSoft" | "stoppingHard";
type ScriptExecutionState = "idle" | "starting" | "running" | "stoppingSoft" | "stoppingHard";

function stripAnsiSequences(input: string) {
  return input.replace(ANSI_OSC_REGEX, "").replace(ANSI_CSI_REGEX, "");
}

function parseCodexStartupModelLine(buffer: string): Pick<CodexStartupHint, "model" | "effort"> | null {
  const lines = stripAnsiSequences(buffer).split(/\r?\n/);
  for (let index = lines.length - 1; index >= 0; index -= 1) {
    const normalized = lines[index].replace(/[│┃]/g, " ").replace(/\s+/g, " ").trim();
    if (!normalized) {
      continue;
    }

    const modelChangedMatched = normalized.match(CODEX_MODEL_CHANGED_REGEX);
    if (modelChangedMatched) {
      return {
        model: modelChangedMatched[1]?.trim() || null,
        effort: modelChangedMatched[2]?.trim() || null,
      };
    }

    const resumeModelMatched = normalized.match(CODEX_RESUME_MODEL_REGEX);
    if (resumeModelMatched) {
      return {
        model: resumeModelMatched[1]?.trim() || null,
        effort: null,
      };
    }

    if (!normalized.toLowerCase().includes("model:")) {
      continue;
    }
    const startupModelMatched = normalized.match(CODEX_MODEL_LINE_REGEX);
    if (!startupModelMatched) {
      continue;
    }
    return {
      model: startupModelMatched[1]?.trim() || null,
      effort: startupModelMatched[2]?.trim() || null,
    };
  }
  return null;
}

function shellQuote(value: string) {
  // POSIX-safe single-quote escaping: 'foo'"'"'bar'
  return `'${value.replace(/'/g, `'"'"'`)}'`;
}

function normalizePathForCompare(path: string) {
  const trimmed = path.trim();
  if (!trimmed) {
    return "";
  }
  return trimmed.replace(/\\/g, "/").replace(/\/+$/, "");
}

function isTerminalQuickCommandState(state: QuickCommandState | string) {
  return state === "exited" || state === "failed" || state === "cancelled";
}

function isActiveQuickCommandState(state: QuickCommandState | string) {
  return !isTerminalQuickCommandState(state);
}

function toScriptExecutionStateFromQuickState(state: QuickCommandState | string): ScriptExecutionState {
  if (state === "stoppingHard") {
    return "stoppingHard";
  }
  if (state === "stoppingSoft") {
    return "stoppingSoft";
  }
  if (state === "running") {
    return "running";
  }
  if (state === "starting" || state === "queued") {
    return "starting";
  }
  return "idle";
}

function wrapQuickCommandForShell(command: string, environment?: Record<string, string | undefined>) {
  const normalized = command
    .replace(/\r\n?/g, "\n")
    .split("\n")
    .filter((line) => line.trim().length > 0)
    .join("; ")
    .trim();
  if (!normalized) {
    return "";
  }

  const envAssignments: string[] = [];
  for (const [rawKey, rawValue] of Object.entries(environment ?? {})) {
    if (!rawValue) {
      continue;
    }
    const key = rawKey.trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) {
      continue;
    }
    envAssignments.push(`${key}=${shellQuote(rawValue)}`);
  }
  const envPrefix = envAssignments.length > 0 ? `${envAssignments.join(" ")} ` : "";

  // 用一次性 shell 执行命令并主动退出，统一依赖 terminal-exit 回收运行态。
  return envPrefix + `sh -lc ${shellQuote(normalized)}; exit $?`;
}

function getNextTerminalTitle(tabs: TerminalTab[]): string {
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

  const [panelMessage, setPanelMessage] = useState<string | null>(null);
  const panelMessageTimerRef = useRef<number | null>(null);

  const [scriptRuntimeById, setScriptRuntimeById] = useState<Record<string, ScriptRuntime>>({});
  const scriptRuntimeByIdRef = useRef<Record<string, ScriptRuntime>>({});
  const [quickCommandJobByScriptId, setQuickCommandJobByScriptId] = useState<Record<string, QuickCommandJob>>({});
  const quickCommandJobByScriptIdRef = useRef<Record<string, QuickCommandJob>>({});
  const [scriptLocalPhaseById, setScriptLocalPhaseById] = useState<Record<string, ScriptLocalPhase>>({});
  const scriptLocalPhaseByIdRef = useRef<Record<string, ScriptLocalPhase>>({});

  const sessionPtyIdRef = useRef(new Map<string, string>());
  const scriptIdBySessionIdRef = useRef(new Map<string, string>());
  const pendingStartBySessionIdRef = useRef(new Map<string, string>());
  const pendingStopAfterStartByScriptIdRef = useRef(new Set<string>());
  const finalizedQuickCommandJobIdsRef = useRef(new Set<string>());
  const codexStartupOutputBufferBySessionIdRef = useRef(new Map<string, string>());
  const handledDispatchSeqRef = useRef(0);
  const stopKillTimerByScriptIdRef = useRef(new Map<string, number>());
  const pendingQuickCommandDispatchRef = useRef<TerminalQuickCommandDispatch | null>(null);

  const stageRef = useRef<HTMLDivElement | null>(null);
  const panelRef = useRef<HTMLDivElement | null>(null);
  const [panelDraft, setPanelDraft] = useState<{ x: number; y: number } | null>(null);
  const panelDraftRef = useRef<{ x: number; y: number } | null>(null);
  const [previewFilePath, setPreviewFilePath] = useState<string | null>(null);
  const [previewDirty, setPreviewDirty] = useState(false);
  const [isGitRepo, setIsGitRepo] = useState(false);
  const [codexPaneOverlayBySessionId, setCodexPaneOverlayBySessionId] = useState<
    Record<string, TerminalCodexPaneOverlay>
  >({});
  const [codexStartupHintBySessionId, setCodexStartupHintBySessionId] = useState<
    Record<string, CodexStartupHint>
  >({});
  const dragStateRef = useRef<{
    startClientX: number;
    startClientY: number;
    baseX: number;
    baseY: number;
  } | null>(null);

  useEffect(() => {
    workspaceRef.current = workspace;
  }, [workspace]);

  useLayoutEffect(() => {
    scriptRuntimeByIdRef.current = scriptRuntimeById;
  }, [scriptRuntimeById]);

  useLayoutEffect(() => {
    quickCommandJobByScriptIdRef.current = quickCommandJobByScriptId;
  }, [quickCommandJobByScriptId]);

  useLayoutEffect(() => {
    scriptLocalPhaseByIdRef.current = scriptLocalPhaseById;
  }, [scriptLocalPhaseById]);

  useEffect(() => {
    return () => {
      if (panelMessageTimerRef.current !== null) {
        window.clearTimeout(panelMessageTimerRef.current);
        panelMessageTimerRef.current = null;
      }
      for (const timer of stopKillTimerByScriptIdRef.current.values()) {
        window.clearTimeout(timer);
      }
      stopKillTimerByScriptIdRef.current.clear();
    };
  }, []);

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
    setPanelMessage(null);
    if (panelMessageTimerRef.current !== null) {
      window.clearTimeout(panelMessageTimerRef.current);
      panelMessageTimerRef.current = null;
    }
    setScriptRuntimeById({});
    setQuickCommandJobByScriptId({});
    setScriptLocalPhaseById({});
    scriptIdBySessionIdRef.current.clear();
    sessionPtyIdRef.current.clear();
    pendingStartBySessionIdRef.current.clear();
    pendingStopAfterStartByScriptIdRef.current.clear();
    finalizedQuickCommandJobIdsRef.current.clear();
    codexStartupOutputBufferBySessionIdRef.current.clear();
    handledDispatchSeqRef.current = 0;
    pendingQuickCommandDispatchRef.current = null;
    for (const timer of stopKillTimerByScriptIdRef.current.values()) {
      window.clearTimeout(timer);
    }
    stopKillTimerByScriptIdRef.current.clear();
    setPreviewFilePath(null);
    setPreviewDirty(false);
    setCodexPaneOverlayBySessionId({});
    setCodexStartupHintBySessionId({});
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
      .catch((err) => {
        if (cancelled) {
          return;
        }
        setError(err instanceof Error ? err.message : String(err));
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
    } catch (err) {
      console.error("保存终端工作空间失败。", err);
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

  const showPanelMessage = useCallback((message: string) => {
    setPanelMessage(message);
    if (panelMessageTimerRef.current !== null) {
      window.clearTimeout(panelMessageTimerRef.current);
    }
    panelMessageTimerRef.current = window.setTimeout(() => {
      panelMessageTimerRef.current = null;
      setPanelMessage(null);
    }, 2500);
  }, []);

  const clearScriptLocalPhase = useCallback((scriptIds: string[]) => {
    if (scriptIds.length === 0) {
      return;
    }
    setScriptLocalPhaseById((prev) => {
      let next: typeof prev | null = null;
      for (const scriptId of scriptIds) {
        if (!(scriptId in prev)) {
          continue;
        }
        if (!next) {
          next = { ...prev };
        }
        delete next[scriptId];
      }
      return next ?? prev;
    });
  }, []);

  const finishQuickCommandOnce = useCallback(
    async ({ jobId, exitCode, error }: { jobId: string; exitCode?: number | null; error?: string | null }) => {
      const normalizedJobId = jobId.trim();
      if (!normalizedJobId) {
        return;
      }
      if (finalizedQuickCommandJobIdsRef.current.has(normalizedJobId)) {
        return;
      }
      finalizedQuickCommandJobIdsRef.current.add(normalizedJobId);
      if (finalizedQuickCommandJobIdsRef.current.size > 2048) {
        const iterator = finalizedQuickCommandJobIdsRef.current.values();
        const first = iterator.next();
        if (!first.done) {
          finalizedQuickCommandJobIdsRef.current.delete(first.value);
        }
      }

      try {
        await finishQuickCommand({
          jobId: normalizedJobId,
          exitCode,
          error,
        });
      } catch (requestError) {
        finalizedQuickCommandJobIdsRef.current.delete(normalizedJobId);
        throw requestError;
      }
    },
    [],
  );

  const finalizeRuntimeBySessionIds = useCallback(
    (sessionIds: string[], exitCode: number, errorMessage: string) => {
      if (sessionIds.length === 0) {
        return;
      }
      for (const sessionId of sessionIds) {
        const scriptId = scriptIdBySessionIdRef.current.get(sessionId) ?? null;
        if (!scriptId) {
          continue;
        }
        const runtime = scriptRuntimeByIdRef.current[scriptId] ?? null;
        if (!runtime || runtime.sessionId !== sessionId) {
          continue;
        }
        void finishQuickCommandOnce({
          jobId: runtime.jobId,
          exitCode,
          error: errorMessage,
        }).catch((requestError) => {
          console.error("回写快捷命令结束状态失败。", requestError);
        });
      }
    },
    [finishQuickCommandOnce],
  );

  const applyQuickCommandSnapshot = useCallback(
    (jobs: QuickCommandJob[]) => {
      const currentProjectPath = normalizePathForCompare(workspaceRef.current?.projectPath || projectPath);
      const next: Record<string, QuickCommandJob> = {};
      for (const job of jobs) {
        if (!job?.scriptId) {
          continue;
        }
        if (job.windowLabel && job.windowLabel !== windowLabel) {
          continue;
        }
        if (projectId && job.projectId && job.projectId !== projectId) {
          continue;
        }
        if (normalizePathForCompare(job.projectPath) !== currentProjectPath) {
          continue;
        }
        if (!isActiveQuickCommandState(job.state)) {
          continue;
        }
        const existing = next[job.scriptId];
        if (!existing || job.updatedAt > existing.updatedAt) {
          next[job.scriptId] = job;
        }
      }
      setQuickCommandJobByScriptId(next);
    },
    [projectId, projectPath, windowLabel],
  );

  const cleanupRuntimeBySessionIds = useCallback((sessionIds: string[]) => {
    if (sessionIds.length === 0) {
      return;
    }
    const removedScriptIds: string[] = [];
    const removeSet = new Set(sessionIds);
    setScriptRuntimeById((prev) => {
      let next: typeof prev | null = null;
      Object.entries(prev).forEach(([scriptId, runtime]) => {
        if (!removeSet.has(runtime.sessionId)) {
          return;
        }
        if (!next) {
          next = { ...prev };
        }
        delete next[scriptId];
      });
      return next ?? prev;
    });

    sessionIds.forEach((sessionId) => {
      const scriptId = scriptIdBySessionIdRef.current.get(sessionId) ?? null;
      if (scriptId) {
        removedScriptIds.push(scriptId);
        pendingStopAfterStartByScriptIdRef.current.delete(scriptId);
        const timer = stopKillTimerByScriptIdRef.current.get(scriptId);
        if (typeof timer === "number") {
          window.clearTimeout(timer);
          stopKillTimerByScriptIdRef.current.delete(scriptId);
        }
      }
      sessionPtyIdRef.current.delete(sessionId);
      scriptIdBySessionIdRef.current.delete(sessionId);
      pendingStartBySessionIdRef.current.delete(sessionId);
      codexStartupOutputBufferBySessionIdRef.current.delete(sessionId);
    });

    clearScriptLocalPhase(removedScriptIds);

    setCodexStartupHintBySessionId((prev) => {
      let next: Record<string, CodexStartupHint> | null = null;
      for (const sessionId of sessionIds) {
        if (!(sessionId in prev)) {
          continue;
        }
        if (!next) {
          next = { ...prev };
        }
        delete next[sessionId];
      }
      return next ?? prev;
    });

    setCodexPaneOverlayBySessionId((prev) => {
      let next: Record<string, TerminalCodexPaneOverlay> | null = null;
      for (const sessionId of sessionIds) {
        if (!(sessionId in prev)) {
          continue;
        }
        if (!next) {
          next = { ...prev };
        }
        delete next[sessionId];
      }
      return next ?? prev;
    });
  }, [clearScriptLocalPhase]);

  useEffect(() => {
    return () => {
      const runtimeSessionIds = Object.values(scriptRuntimeByIdRef.current).map((runtime) => runtime.sessionId);
      finalizeRuntimeBySessionIds(runtimeSessionIds, 130, "终端会话已关闭");
    };
  }, [finalizeRuntimeBySessionIds, projectId, projectPath]);

  useEffect(() => {
    let unlisten: (() => void) | null = null;

    const registerListener = async () => {
      try {
        unlisten = await listenTerminalOutput((event) => {
          const payload = event.payload;
          const sessionId = payload.sessionId;

          const startupBufferMap = codexStartupOutputBufferBySessionIdRef.current;
          const startupPrev = startupBufferMap.get(sessionId) ?? "";
          const startupNext = `${startupPrev}${payload.data}`.slice(-CODEX_STARTUP_OUTPUT_BUFFER_LIMIT);
          startupBufferMap.set(sessionId, startupNext);

          const startupHint = parseCodexStartupModelLine(startupNext);
          if (startupHint) {
            const now = Date.now();
            setCodexStartupHintBySessionId((prev) => {
              const existing = prev[sessionId];
              const nextModel = startupHint.model ?? existing?.model ?? null;
              const nextEffort = startupHint.effort ?? existing?.effort ?? null;
              if (existing && existing.model === nextModel && existing.effort === nextEffort) {
                return prev;
              }
              return {
                ...prev,
                [sessionId]: {
                  model: nextModel,
                  effort: nextEffort,
                  updatedAt: now,
                },
              };
            });
          }

        });
      } catch (error) {
        console.error("监听终端输出事件失败。", error);
      }
    };

    void registerListener();

    return () => {
      unlisten?.();
    };
  }, []);

  useEffect(() => {
    let unlisten: (() => void) | null = null;
    let cancelled = false;

    const refreshSnapshot = async () => {
      try {
        const snapshot = await getQuickCommandSnapshot();
        if (cancelled) {
          return;
        }
        applyQuickCommandSnapshot(snapshot.jobs ?? []);
      } catch (error) {
        if (!cancelled) {
          console.error("拉取快捷命令快照失败。", error);
        }
      }
    };

    const registerListener = async () => {
      try {
        unlisten = await listenQuickCommandEvent((event) => {
          if (cancelled) {
            return;
          }
          const jobs = event.payload?.snapshot?.jobs ?? [];
          applyQuickCommandSnapshot(jobs);
        });
      } catch (error) {
        if (!cancelled) {
          console.error("监听快捷命令事件失败。", error);
        }
      }
    };

    void refreshSnapshot();
    void registerListener();

    const timer = window.setInterval(() => {
      void refreshSnapshot();
    }, QUICK_COMMAND_RECONCILE_INTERVAL_MS);

    return () => {
      cancelled = true;
      window.clearInterval(timer);
      unlisten?.();
    };
  }, [applyQuickCommandSnapshot]);

  useEffect(() => {
    if (!workspace) {
      return;
    }
    const panel = workspace.ui?.quickCommandsPanel;
    if (!panel || !panel.open) {
      return;
    }
    if (panel.x !== null && panel.y !== null) {
      return;
    }
    const stage = stageRef.current;
    if (!stage) {
      return;
    }
    const margin = 12;
    const defaultWidth = 260;
    const rect = stage.getBoundingClientRect();
    const resolvedX =
      panel.x !== null ? panel.x : Math.max(margin, Math.round(rect.width - defaultWidth - margin));
    const resolvedY = panel.y !== null ? panel.y : margin;
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
          x: resolvedX,
          y: resolvedY,
        },
      },
    }));
  }, [updateWorkspace, workspace]);

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

      updateWorkspace((current) => {
        const remainingTabs = current.tabs.filter((tab) => tab.id !== tabId);
        const closedTab = current.tabs.find((tab) => tab.id === tabId);
        const removedSessions = closedTab ? collectSessionIds(closedTab.root) : [];
        if (remainingTabs.length === 0) {
          return createDefaultWorkspace(current.projectPath, current.projectId, workspaceDefaultsRef.current);
        }
        const nextSessions = { ...current.sessions };
        removedSessions.forEach((sessionId) => {
          delete nextSessions[sessionId];
        });
        const nextActiveTabId =
          current.activeTabId === tabId ? remainingTabs[0].id : current.activeTabId;
        return {
          ...current,
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
      const scriptId = scriptIdBySessionIdRef.current.get(sessionId) ?? null;
      const runtime = scriptId ? scriptRuntimeByIdRef.current[scriptId] ?? null : null;
      if (scriptId && runtime && runtime.sessionId === sessionId) {
        const resolvedCode = typeof code === "number" ? code : 130;
        const errorMessage = resolvedCode === 0 ? null : `命令结束（退出码 ${resolvedCode}）`;
        void finishQuickCommandOnce({
          jobId: runtime.jobId,
          exitCode: resolvedCode,
          error: errorMessage,
        }).catch((error) => {
          console.error("回写快捷命令结束状态失败。", error);
        });
        clearScriptLocalPhase([scriptId]);
        setQuickCommandJobByScriptId((prev) => {
          const existing = prev[scriptId];
          if (!existing || existing.jobId !== runtime.jobId) {
            return prev;
          }
          const next = { ...prev };
          delete next[scriptId];
          return next;
        });
        showPanelMessage(resolvedCode === 0 ? "命令已完成" : `命令已结束（退出码 ${resolvedCode}）`);
      }

      const current = workspaceRef.current;
      if (!current) {
        cleanupRuntimeBySessionIds([sessionId]);
      } else {
        const targetTab = current.tabs.find((tab) => findPanePath(tab.root, sessionId) !== null) ?? null;
        if (!targetTab) {
          cleanupRuntimeBySessionIds([sessionId]);
        } else {
          const nextRoot = removePane(targetTab.root, sessionId);
          const beforeSessionIds = collectSessionIds(targetTab.root);
          const afterSessionIds = nextRoot ? collectSessionIds(nextRoot) : [];
          const afterSet = new Set(afterSessionIds);
          const removedSessions = beforeSessionIds.filter((id) => !afterSet.has(id));
          cleanupRuntimeBySessionIds(removedSessions);
        }
      }

      updateWorkspace((current) => {
        const targetIndex = current.tabs.findIndex((tab) => findPanePath(tab.root, sessionId) !== null);
        if (targetIndex < 0) {
          return current;
        }

        const targetTab = current.tabs[targetIndex];
        const nextRoot = removePane(targetTab.root, sessionId);
        const beforeSessionIds = collectSessionIds(targetTab.root);
        const afterSessionIds = nextRoot ? collectSessionIds(nextRoot) : [];
        const afterSet = new Set(afterSessionIds);
        const removedSessions = beforeSessionIds.filter((id) => !afterSet.has(id));

        const nextSessions = { ...current.sessions };
        removedSessions.forEach((id) => {
          delete nextSessions[id];
        });

        if (!nextRoot) {
          const remainingTabs = current.tabs.filter((tab) => tab.id !== targetTab.id);
          if (remainingTabs.length === 0) {
            return createDefaultWorkspace(current.projectPath, current.projectId, workspaceDefaultsRef.current);
          }
          const nextActiveTabId =
            current.activeTabId === targetTab.id ? remainingTabs[0].id : current.activeTabId;
          return {
            ...current,
            tabs: remainingTabs,
            activeTabId: nextActiveTabId,
            sessions: nextSessions,
          };
        }

        const nextActiveSessionId = afterSet.has(targetTab.activeSessionId)
          ? targetTab.activeSessionId
          : afterSessionIds[0];
        const nextTab = { ...targetTab, root: nextRoot, activeSessionId: nextActiveSessionId };
        return {
          ...current,
          tabs: current.tabs.map((tab) => (tab.id === targetTab.id ? nextTab : tab)),
          sessions: nextSessions,
        };
      });
    },
    [cleanupRuntimeBySessionIds, clearScriptLocalPhase, finishQuickCommandOnce, showPanelMessage, updateWorkspace],
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

  const commitQuickCommandsPanelPosition = useCallback(
    (x: number, y: number) => {
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
            x,
            y,
          },
        },
      }));
    },
    [updateWorkspace],
  );

  const beginDragQuickCommandsPanel = useCallback(
    (event: ReactPointerEvent) => {
      if (event.button !== 0) {
        return;
      }
      event.preventDefault();
      event.stopPropagation();

      const current = workspaceRef.current;
      const panel = current?.ui?.quickCommandsPanel ?? {
        open: workspaceDefaultsRef.current.defaultQuickCommandsPanelOpen,
        x: null,
        y: null,
      };
      const base = panelDraftRef.current ?? { x: panel.x ?? 12, y: panel.y ?? 12 };
      dragStateRef.current = {
        startClientX: event.clientX,
        startClientY: event.clientY,
        baseX: base.x,
        baseY: base.y,
      };

      const handleMove = (moveEvent: PointerEvent) => {
        const state = dragStateRef.current;
        if (!state) {
          return;
        }
        const stage = stageRef.current;
        if (!stage) {
          return;
        }
        const stageRect = stage.getBoundingClientRect();
        const panelRect = panelRef.current?.getBoundingClientRect() ?? null;
        const panelWidth = panelRect ? panelRect.width : 260;
        const panelHeight = panelRect ? panelRect.height : 240;
        const margin = 8;
        const maxX = Math.max(margin, Math.round(stageRect.width - panelWidth - margin));
        const maxY = Math.max(margin, Math.round(stageRect.height - panelHeight - margin));

        const dx = moveEvent.clientX - state.startClientX;
        const dy = moveEvent.clientY - state.startClientY;
        const nextX = Math.min(maxX, Math.max(margin, Math.round(state.baseX + dx)));
        const nextY = Math.min(maxY, Math.max(margin, Math.round(state.baseY + dy)));
        panelDraftRef.current = { x: nextX, y: nextY };
        setPanelDraft({ x: nextX, y: nextY });
      };

      const handleUp = () => {
        window.removeEventListener("pointermove", handleMove);
        window.removeEventListener("pointerup", handleUp);
        const latest = panelDraftRef.current;
        panelDraftRef.current = null;
        dragStateRef.current = null;
        if (latest) {
          commitQuickCommandsPanelPosition(latest.x, latest.y);
        }
        setPanelDraft(null);
      };

      window.addEventListener("pointermove", handleMove);
      window.addEventListener("pointerup", handleUp);
    },
    [commitQuickCommandsPanelPosition],
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

      // 仅按下 Cmd（Meta）本身也可能触发 WebView/页面滚动（尤其在终端处于非底部时），直接吞掉。
      if (key === "meta") {
        event.preventDefault();
        event.stopPropagation();
        return;
      }

      // iTerm2 风格：⌘D 向右分屏，⌘⇧D 向下分屏。
      if (key === "d") {
        event.preventDefault();
        event.stopPropagation();
        handleSplit(event.shiftKey ? "b" : "r");
        return;
      }

      // ⌘T：新建标签页
      if (key === "t" && !event.shiftKey) {
        event.preventDefault();
        event.stopPropagation();
        handleNewTab();
        return;
      }

      // ⌘W：关闭当前 Pane；若该 Tab 只剩最后一个 Pane，则关闭 Tab
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

      // ⌘↑/⌘←：上一 Tab；⌘↓/⌘→：下一 Tab
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

      // ⌘⇧[ / ⌘⇧]：上一/下一 Tab（浏览器/iTerm2 常用）
      if (event.shiftKey && (event.code === "BracketLeft" || event.code === "BracketRight")) {
        event.preventDefault();
        event.stopPropagation();
        handleSelectTabRelative(event.code === "BracketLeft" ? -1 : 1);
        return;
      }

      // ⌘1..⌘8：切换到对应 Tab；⌘9：切到最后一个 Tab（浏览器常用）
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

    // Capture phase：确保终端（xterm）聚焦时也能触发快捷键。
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

  const isScriptRuntimeValid = useCallback((runtime: ScriptRuntime) => {
    const current = workspaceRef.current;
    if (!current) {
      return false;
    }
    if (!current.sessions[runtime.sessionId]) {
      return false;
    }
    const tab = current.tabs.find((item) => item.id === runtime.tabId);
    if (!tab) {
      return false;
    }
    return findPanePath(tab.root, runtime.sessionId) !== null;
  }, []);

  const handlePtyReady = useCallback(
    (sessionId: string, ptyId: string) => {
      sessionPtyIdRef.current.set(sessionId, ptyId);

      const scriptId = scriptIdBySessionIdRef.current.get(sessionId);
      if (scriptId) {
        setScriptRuntimeById((prev) => {
          const runtime = prev[scriptId];
          if (!runtime || runtime.sessionId !== sessionId || runtime.ptyId === ptyId) {
            return prev;
          }
          return { ...prev, [scriptId]: { ...runtime, ptyId } };
        });
      }

      const command = pendingStartBySessionIdRef.current.get(sessionId);
      if (!command) {
        return;
      }
      pendingStartBySessionIdRef.current.delete(sessionId);
      const payload = command.endsWith("\r") ? command : `${command}\r`;
      void writeTerminal(ptyId, payload).catch((error) => {
        console.error("快捷命令下发失败。", error);
        const ownedScriptId = scriptIdBySessionIdRef.current.get(sessionId) ?? null;
        const runtime = ownedScriptId ? scriptRuntimeByIdRef.current[ownedScriptId] ?? null : null;
        if (runtime && runtime.sessionId === sessionId) {
          void finishQuickCommandOnce({
            jobId: runtime.jobId,
            exitCode: 1,
            error: "命令下发失败",
          }).catch((finishError) => {
            console.error("回写快捷命令失败状态失败。", finishError);
          });
        }
        showPanelMessage("快捷命令下发失败");
        handleSessionExit(sessionId, 1);
      });
    },
    [finishQuickCommandOnce, handleSessionExit, showPanelMessage],
  );

  const runQuickCommand = useCallback(
    (script: ProjectScript) => {
      if (!script.start.trim()) {
        showPanelMessage("启动命令为空");
        return;
      }
      const rendered = renderScriptTemplateCommand(script);
      if (!rendered.ok) {
        showPanelMessage(rendered.error);
        return;
      }
      const current = workspaceRef.current;
      if (!current) {
        showPanelMessage("终端工作区尚未就绪");
        return;
      }

      const localPhase = scriptLocalPhaseByIdRef.current[script.id] ?? null;
      if (localPhase === "starting") {
        showPanelMessage("命令正在启动中");
        return;
      }
      if (localPhase === "stoppingSoft" || localPhase === "stoppingHard") {
        showPanelMessage("命令正在停止中");
        return;
      }

      const existing = scriptRuntimeByIdRef.current[script.id] ?? null;
      if (existing && isScriptRuntimeValid(existing)) {
        pendingStopAfterStartByScriptIdRef.current.delete(script.id);
        showPanelMessage("命令已在运行，已切换到对应终端");
        updateWorkspace((ws) => {
          const nextTabs = ws.tabs.map((tab) => {
            if (tab.id !== existing.tabId) {
              return tab;
            }
            return tab.activeSessionId === existing.sessionId ? tab : { ...tab, activeSessionId: existing.sessionId };
          });
          return { ...ws, activeTabId: existing.tabId, tabs: nextTabs };
        });
        return;
      }

      const existingJob = quickCommandJobByScriptIdRef.current[script.id] ?? null;
      if (existingJob && isActiveQuickCommandState(existingJob.state)) {
        const executionState = toScriptExecutionStateFromQuickState(existingJob.state);
        if (executionState === "starting") {
          showPanelMessage("命令正在启动中");
        } else if (executionState === "stoppingSoft" || executionState === "stoppingHard") {
          showPanelMessage("命令正在停止中");
        } else {
          showPanelMessage("命令已在运行");
        }
        return;
      }

      if (existing) {
        cleanupRuntimeBySessionIds([existing.sessionId]);
      }

      const shellCommand = wrapQuickCommandForShell(rendered.command.trim(), {
        DEVHAVEN_SHARED_SCRIPTS: appState.settings.sharedScriptsRoot,
        DEVHAVEN_PROJECT_PATH: current.projectPath || projectPath,
      });
      if (!shellCommand) {
        showPanelMessage("命令为空，无法执行");
        return;
      }

      setScriptLocalPhaseById((prev) => ({ ...prev, [script.id]: "starting" }));
      pendingStopAfterStartByScriptIdRef.current.delete(script.id);

      void (async () => {
        let startedJob: QuickCommandJob;
        try {
          startedJob = await startQuickCommand({
            projectId: projectId || current.projectId || current.projectPath,
            projectPath: current.projectPath || projectPath,
            scriptId: script.id,
            command: rendered.command.trim(),
            windowLabel,
          });
          setQuickCommandJobByScriptId((prev) => {
            const existingJob = prev[script.id];
            if (existingJob && existingJob.updatedAt > startedJob.updatedAt) {
              return prev;
            }
            return { ...prev, [script.id]: startedJob };
          });
        } catch (error) {
          console.error("启动快捷命令任务失败。", error);
          clearScriptLocalPhase([script.id]);
          showPanelMessage("启动快捷命令失败");
          return;
        }

        const sessionId = createId();
        const tabId = createId();
        scriptIdBySessionIdRef.current.set(sessionId, script.id);
        pendingStartBySessionIdRef.current.set(sessionId, shellCommand);

        setScriptRuntimeById((prev) => ({
          ...prev,
          [script.id]: { jobId: startedJob.jobId, tabId, sessionId, ptyId: null },
        }));
        clearScriptLocalPhase([script.id]);

        updateWorkspace((ws) => {
          const title = script.name.trim() ? script.name.trim() : `命令 ${ws.tabs.length + 1}`;
          return {
            ...ws,
            activeTabId: tabId,
            tabs: [
              ...ws.tabs,
              { id: tabId, title, root: { type: "pane", sessionId }, activeSessionId: sessionId },
            ],
            sessions: {
              ...ws.sessions,
              [sessionId]: { id: sessionId, cwd: ws.projectPath, savedState: null },
            },
          };
        });
      })();
    },
    [
      appState.settings.sharedScriptsRoot,
      clearScriptLocalPhase,
      cleanupRuntimeBySessionIds,
      isScriptRuntimeValid,
      projectId,
      projectPath,
      showPanelMessage,
      updateWorkspace,
      windowLabel,
    ],
  );

  const stopQuickCommand = useCallback(
    (scriptId: string) => {
      const runtime = scriptRuntimeByIdRef.current[scriptId] ?? null;
      const quickJob = quickCommandJobByScriptIdRef.current[scriptId] ?? null;
      const localPhase = scriptLocalPhaseByIdRef.current[scriptId] ?? null;
      const isStartingPhase =
        localPhase === "starting" || (quickJob ? toScriptExecutionStateFromQuickState(quickJob.state) === "starting" : false);
      const resolvedRuntime = runtime && isScriptRuntimeValid(runtime) ? runtime : null;

      if (!resolvedRuntime) {
        if (runtime) {
          cleanupRuntimeBySessionIds([runtime.sessionId]);
        }
        if (isStartingPhase) {
          pendingStopAfterStartByScriptIdRef.current.add(scriptId);
          setScriptLocalPhaseById((prev) => ({ ...prev, [scriptId]: "stoppingSoft" }));
          if (quickJob) {
            void stopQuickCommandJob({ jobId: quickJob.jobId, force: false }).catch((error) => {
              console.error("更新快捷命令停止状态失败。", error);
            });
          }
          showPanelMessage("命令启动中，启动后将自动停止");
          return;
        }
        if (quickJob && isActiveQuickCommandState(quickJob.state)) {
          setScriptLocalPhaseById((prev) => ({ ...prev, [scriptId]: "stoppingSoft" }));
          void stopQuickCommandJob({ jobId: quickJob.jobId, force: false }).catch((error) => {
            console.error("更新快捷命令停止状态失败。", error);
          });
          showPanelMessage("已请求停止命令，等待会话回收");
          return;
        }
        showPanelMessage("该命令未在运行");
        return;
      }

      const ptyId = resolvedRuntime.ptyId ?? sessionPtyIdRef.current.get(resolvedRuntime.sessionId) ?? null;
      const timer = stopKillTimerByScriptIdRef.current.get(scriptId);
      if (typeof timer === "number") {
        window.clearTimeout(timer);
        stopKillTimerByScriptIdRef.current.delete(scriptId);
      }

      setScriptLocalPhaseById((prev) => ({ ...prev, [scriptId]: "stoppingSoft" }));
      void stopQuickCommandJob({ jobId: resolvedRuntime.jobId, force: false }).catch((error) => {
        console.error("更新快捷命令停止状态失败。", error);
      });

      showPanelMessage("正在停止命令...");

      if (!ptyId) {
        handleSessionExit(resolvedRuntime.sessionId, 130);
        return;
      }

      void writeTerminal(ptyId, "\u0003").catch((error) => {
        console.error("发送中断信号失败。", error);
      });

      const killTimer = window.setTimeout(() => {
        const latest = scriptRuntimeByIdRef.current[scriptId] ?? null;
        if (!latest || latest.jobId !== resolvedRuntime.jobId) {
          return;
        }

        const latestPty = latest.ptyId ?? sessionPtyIdRef.current.get(latest.sessionId) ?? null;
        if (latestPty) {
          void killTerminal(latestPty).catch((error) => {
            console.error("强制停止快捷命令失败。", error);
          });
        }

        setScriptLocalPhaseById((prev) => ({ ...prev, [scriptId]: "stoppingHard" }));
        void stopQuickCommandJob({ jobId: resolvedRuntime.jobId, force: true }).catch((error) => {
          console.error("更新快捷命令强制停止状态失败。", error);
        });

        handleSessionExit(latest.sessionId, 130);
      }, QUICK_COMMAND_FORCE_KILL_TIMEOUT_MS);
      stopKillTimerByScriptIdRef.current.set(scriptId, killTimer);
    },
    [cleanupRuntimeBySessionIds, handleSessionExit, isScriptRuntimeValid, showPanelMessage],
  );

  useEffect(() => {
    if (pendingStopAfterStartByScriptIdRef.current.size === 0) {
      return;
    }
    const pendingScriptIds = Array.from(pendingStopAfterStartByScriptIdRef.current.values());
    for (const scriptId of pendingScriptIds) {
      const runtime = scriptRuntimeById[scriptId] ?? null;
      if (!runtime || !isScriptRuntimeValid(runtime)) {
        continue;
      }
      pendingStopAfterStartByScriptIdRef.current.delete(scriptId);
      stopQuickCommand(scriptId);
    }
  }, [isScriptRuntimeValid, scriptRuntimeById, stopQuickCommand]);

  const handleQuickCommandDispatch = useCallback(
    (dispatch: TerminalQuickCommandDispatch | null | undefined) => {
      if (!dispatch) {
        return;
      }
      if (dispatch.seq <= handledDispatchSeqRef.current) {
        return;
      }
      if (dispatch.projectPath !== projectPath) {
        return;
      }
      if (projectId && dispatch.projectId !== projectId) {
        return;
      }

      if (!workspaceRef.current) {
        pendingQuickCommandDispatchRef.current = dispatch;
        return;
      }

      handledDispatchSeqRef.current = dispatch.seq;

      if (dispatch.type === "run") {
        const script = scripts.find((item) => item.id === dispatch.scriptId) ?? null;
        if (!script) {
          showPanelMessage("命令不存在或已被删除");
          return;
        }
        runQuickCommand(script);
        return;
      }

      stopQuickCommand(dispatch.scriptId);
    },
    [projectId, projectPath, runQuickCommand, scripts, showPanelMessage, stopQuickCommand],
  );

  useEffect(() => {
    handleQuickCommandDispatch(quickCommandDispatch);
  }, [handleQuickCommandDispatch, quickCommandDispatch]);

  useEffect(() => {
    if (!workspace) {
      return;
    }
    const pending = pendingQuickCommandDispatchRef.current;
    if (!pending) {
      return;
    }
    pendingQuickCommandDispatchRef.current = null;
    handleQuickCommandDispatch(pending);
  }, [handleQuickCommandDispatch, workspace]);

  useEffect(() => {
    if (!workspace || !isActive) {
      setCodexPaneOverlayBySessionId({});
      return;
    }

    const sessionIds = Object.keys(workspace.sessions ?? {});
    if (sessionIds.length === 0) {
      setCodexPaneOverlayBySessionId({});
      return;
    }

    let cancelled = false;

    const refreshOverlay = async () => {
      if (document.visibilityState === "hidden") {
        return;
      }

      try {
        const items = await getTerminalCodexPaneOverlay(windowLabel, sessionIds);
        if (cancelled) {
          return;
        }
        const next: Record<string, TerminalCodexPaneOverlay> = {};
        for (const item of items ?? []) {
          if (!item?.sessionId) {
            continue;
          }
          next[item.sessionId] = item;
        }
        setCodexPaneOverlayBySessionId(next);
      } catch {
        if (!cancelled) {
          setCodexPaneOverlayBySessionId({});
        }
      }
    };

    void refreshOverlay();
    const timer = window.setInterval(() => {
      void refreshOverlay();
    }, CODEX_PANE_OVERLAY_REFRESH_INTERVAL_MS);

    return () => {
      cancelled = true;
      window.clearInterval(timer);
    };
  }, [isActive, windowLabel, workspace]);

  if (!projectPath) {
    return (
      <div className="flex h-full items-center justify-center text-[var(--terminal-muted-fg)]">
        未找到项目
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex h-full items-center justify-center text-[var(--terminal-muted-fg)]">
        {error}
      </div>
    );
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
  const panelPosition = panelDraft ?? { x: panelState.x ?? 12, y: panelState.y ?? 12 };

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
      <header className="flex items-center gap-3 border-b border-[var(--terminal-divider)] bg-[var(--terminal-panel-bg)] px-3 py-2">
        <div className="max-w-[200px] truncate text-[13px] font-semibold text-[var(--terminal-fg)]">
          {projectName ?? projectPath}
        </div>
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
          onClick={() => setQuickCommandsPanelOpen(!panelOpen)}
        >
          <IconSidebarRight size={16} />
        </button>
        <button
          className={`inline-flex h-7 items-center gap-1.5 rounded-md border border-[var(--terminal-divider)] px-2 text-[var(--terminal-muted-fg)] transition-colors duration-150 hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)] ${
            rightSidebarOpen ? "bg-[var(--terminal-hover-bg)]" : ""
          }`}
          type="button"
          title={rightSidebarOpen ? "隐藏侧边栏" : "显示侧边栏"}
          onClick={() => {
            if (rightSidebarOpen) {
              requestCloseRightSidebar();
              return;
            }
            setRightSidebarTab(rightSidebarTab === "files" && isGitRepo ? "git" : "files");
          }}
        >
          {rightSidebarTab === "files" ? <IconFolder size={16} /> : <IconGitBranch size={16} />}
          <span className="text-[12px] font-semibold">{rightSidebarTab === "files" ? "文件" : "Git"}</span>
        </button>
        <TerminalTabs
          tabs={workspace.tabs}
          activeTabId={workspace.activeTabId}
          onSelect={handleSelectTab}
          onNewTab={handleNewTab}
          onCloseTab={handleCloseTab}
        />
      </header>
      <div ref={stageRef} className="relative flex min-h-0 flex-1">
        {panelOpen ? (
          <div
            ref={panelRef}
            className="absolute z-20 w-[260px] select-none rounded-lg border border-[var(--terminal-divider)] bg-[var(--terminal-panel-bg)] shadow-lg"
            style={{ transform: `translate3d(${panelPosition.x}px, ${panelPosition.y}px, 0)` }}
          >
            <div
              className="flex items-center justify-between gap-2 border-b border-[var(--terminal-divider)] px-3 py-2 text-[12px] font-semibold text-[var(--terminal-muted-fg)] cursor-move"
              onPointerDown={beginDragQuickCommandsPanel}
            >
              <span className="truncate">快捷命令</span>
              <button
                className="inline-flex h-6 w-6 items-center justify-center rounded-md border border-transparent text-[var(--terminal-muted-fg)] hover:border-[var(--terminal-divider)] hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)]"
                type="button"
                title="关闭"
                onClick={(event) => {
                  event.preventDefault();
                  event.stopPropagation();
                  setQuickCommandsPanelOpen(false);
                }}
              >
                <IconX size={12} />
              </button>
            </div>
            <div className="max-h-[360px] overflow-y-auto p-2">
              {panelMessage ? (
                <div className="px-2 pb-2 text-[11px] font-semibold text-[var(--terminal-muted-fg)]">
                  {panelMessage}
                </div>
              ) : null}
              {scripts.length === 0 ? (
                <div className="px-2 py-2 text-[12px] text-[var(--terminal-muted-fg)]">
                  暂无快捷命令，请在项目详情面板中配置
                </div>
              ) : (
                <div className="flex flex-col gap-1">
                  {scripts.map((script) => {
                    const runtime = scriptRuntimeById[script.id] ?? null;
                    const runtimeValid = runtime ? isScriptRuntimeValid(runtime) : false;
                    const quickJob = quickCommandJobByScriptId[script.id] ?? null;
                    const localPhase = scriptLocalPhaseById[script.id] ?? null;
                    const executionState: ScriptExecutionState = quickJob
                      ? toScriptExecutionStateFromQuickState(quickJob.state)
                      : localPhase ?? (runtimeValid ? "running" : "idle");
                    const isRunning = executionState === "running";
                    const isStarting = executionState === "starting";
                    const isStoppingSoft = executionState === "stoppingSoft";
                    const isStoppingHard = executionState === "stoppingHard";
                    const canStop = isRunning || isStarting || isStoppingSoft || isStoppingHard;
                    const disableRun = isStarting || isStoppingSoft || isStoppingHard;
                    const statusText = isStoppingHard
                      ? "强制停止中"
                      : isStoppingSoft
                        ? "停止中"
                        : isStarting
                          ? "启动中"
                          : isRunning
                            ? "运行中"
                            : null;
                    return (
                      <div
                        key={script.id}
                        className="flex items-center justify-between gap-2 rounded-md border border-[var(--terminal-divider)] bg-[var(--terminal-bg)] px-2.5 py-2"
                        title={script.start}
                      >
                        <div className="min-w-0 flex-1">
                          <div className="truncate text-[12px] font-semibold text-[var(--terminal-fg)]">
                            {script.name}
                          </div>
                          <div className="truncate text-[11px] text-[var(--terminal-muted-fg)]">
                            {script.start}
                          </div>
                        </div>
                        <div className="flex shrink-0 items-center gap-1.5">
                          {statusText ? (
                            <span className="inline-flex items-center gap-1 text-[10px] font-semibold text-[var(--terminal-muted-fg)]">
                              <span
                                className={`h-2 w-2 rounded-full ${
                                  isStoppingHard ? "bg-[rgba(239,68,68,0.9)]" : "bg-[var(--terminal-accent)]"
                                }`}
                                aria-hidden="true"
                              />
                              <span className="whitespace-nowrap">{statusText}</span>
                            </span>
                          ) : null}
                          <button
                            className="inline-flex h-7 items-center justify-center rounded-md border border-[var(--terminal-divider)] bg-[var(--terminal-hover-bg)] px-2 text-[11px] font-semibold text-[var(--terminal-muted-fg)] transition-colors duration-150 hover:text-[var(--terminal-fg)]"
                            type="button"
                            disabled={disableRun}
                            onClick={() => runQuickCommand(script)}
                          >
                            {isStarting ? "启动中" : "运行"}
                          </button>
                          <button
                            className="inline-flex h-7 items-center justify-center rounded-md border border-[var(--terminal-divider)] bg-transparent px-2 text-[11px] font-semibold text-[var(--terminal-muted-fg)] transition-colors duration-150 hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)] disabled:cursor-not-allowed disabled:opacity-50"
                            type="button"
                            disabled={!canStop}
                            onClick={() => stopQuickCommand(script.id)}
                          >
                            {isStoppingSoft || isStoppingHard ? "停止中" : "停止"}
                          </button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          </div>
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
                  renderPane={(sessionId, isActive) => (
                    <TerminalPane
                      sessionId={sessionId}
                      cwd={workspace.sessions[sessionId]?.cwd ?? workspace.projectPath}
                      savedState={workspace.sessions[sessionId]?.savedState ?? null}
                      codexPaneOverlay={(() => {
                        const backendOverlay = codexPaneOverlayBySessionId[sessionId] ?? null;
                        if (!backendOverlay) {
                          return null;
                        }
                        const startupHint = codexStartupHintBySessionId[sessionId] ?? null;
                        if (!startupHint) {
                          return backendOverlay;
                        }
                        return {
                          ...backendOverlay,
                          model: startupHint.model ?? backendOverlay.model,
                          effort: startupHint.effort ?? backendOverlay.effort,
                        };
                      })()}
                      windowLabel={windowLabel}
                      // 仅对当前激活 Tab 启用 WebGL 渲染，避免创建过多 WebGL contexts（浏览器有上限）。
                      useWebgl={appState.settings.terminalUseWebglRenderer && tab.id === workspace.activeTabId}
                      theme={xtermTheme}
                      isActive={tab.id === workspace.activeTabId && isActive}
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
