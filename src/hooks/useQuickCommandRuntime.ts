import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";

import type { QuickCommandJob, QuickCommandState } from "../models/quickCommands";
import type { TerminalWorkspace } from "../models/terminal";
import type { ProjectScript } from "../models/types";
import {
  finishQuickCommand,
  getQuickCommandSnapshot,
  listenQuickCommandEvent,
  startQuickCommand,
  stopQuickCommand as stopQuickCommandJob,
} from "../services/quickCommands";
import { killTerminal, writeTerminal } from "../services/terminal";
import { renderScriptTemplateCommand } from "../utils/scriptTemplate";
import { collectSessionIds, createId } from "../utils/terminalLayout";

const QUICK_COMMAND_FORCE_KILL_TIMEOUT_MS = 1500;
const QUICK_COMMAND_RECONCILE_INTERVAL_MS = 10000;
const DEFAULT_RUN_PANEL_HEIGHT = 240;

export type ScriptRuntime = {
  jobId: string;
  tabId: string;
  sessionId: string;
  ptyId: string | null;
};

export type ScriptLocalPhase = "starting" | "stoppingSoft" | "stoppingHard";
export type ScriptExecutionState = "idle" | "starting" | "running" | "stoppingSoft" | "stoppingHard";

export type UseQuickCommandRuntimeParams = {
  projectId: string | null;
  projectPath: string;
  windowLabel: string;
  scripts: ProjectScript[];
  sharedScriptsRoot: string;
  workspace: TerminalWorkspace | null;
  updateWorkspace: (updater: (prev: TerminalWorkspace) => TerminalWorkspace) => void;
  onRequestSessionClose?: (sessionId: string, code?: number | null) => void;
};

export type UseQuickCommandRuntimeReturn = {
  scriptRuntimeById: Record<string, ScriptRuntime>;
  quickCommandJobByScriptId: Record<string, QuickCommandJob>;
  scriptLocalPhaseById: Record<string, ScriptLocalPhase>;
  panelMessage: string | null;
  showPanelMessage: (message: string) => void;
  runQuickCommand: (script: ProjectScript, options?: RunQuickCommandOptions) => void;
  stopScript: (scriptId: string) => void;
  isScriptRuntimeValid: (runtime: ScriptRuntime) => boolean;
  handlePtyReady: (sessionId: string, ptyId: string) => void;
  handleSessionExit: (sessionId: string, code?: number | null) => void;
  cleanupRuntimeBySessionIds: (sessionIds: string[]) => void;
  finalizeRuntimeBySessionIds: (sessionIds: string[], exitCode: number, errorMessage: string) => void;
};

export type RunQuickCommandOptions = {
  reuseTabId?: string | null;
};

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

export function toScriptExecutionStateFromQuickState(state: QuickCommandState | string): ScriptExecutionState {
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

function getRunPanelState(workspace: TerminalWorkspace) {
  return workspace.ui?.runPanel ?? { open: false, height: DEFAULT_RUN_PANEL_HEIGHT, activeTabId: null, tabs: [] };
}

function resolveReusableRunTab(
  workspace: TerminalWorkspace,
  scriptId: string,
  preferredTabId?: string | null,
) {
  const runPanel = getRunPanelState(workspace);
  if (preferredTabId) {
    const preferred = runPanel.tabs.find((tab) => tab.id === preferredTabId && tab.scriptId === scriptId);
    if (preferred) {
      return preferred;
    }
  }
  const active =
    runPanel.activeTabId && runPanel.tabs.some((tab) => tab.id === runPanel.activeTabId)
      ? runPanel.tabs.find((tab) => tab.id === runPanel.activeTabId) ?? null
      : null;
  if (active?.scriptId === scriptId) {
    return active;
  }
  for (let i = runPanel.tabs.length - 1; i >= 0; i -= 1) {
    if (runPanel.tabs[i].scriptId === scriptId) {
      return runPanel.tabs[i];
    }
  }
  return null;
}

export function useQuickCommandRuntime({
  projectId,
  projectPath,
  windowLabel,
  scripts,
  sharedScriptsRoot,
  workspace,
  updateWorkspace,
  onRequestSessionClose,
}: UseQuickCommandRuntimeParams): UseQuickCommandRuntimeReturn {
  const [panelMessage, setPanelMessage] = useState<string | null>(null);
  const panelMessageTimerRef = useRef<number | null>(null);

  const [scriptRuntimeById, setScriptRuntimeById] = useState<Record<string, ScriptRuntime>>({});
  const scriptRuntimeByIdRef = useRef<Record<string, ScriptRuntime>>({});
  const [quickCommandJobByScriptId, setQuickCommandJobByScriptId] = useState<Record<string, QuickCommandJob>>({});
  const quickCommandJobByScriptIdRef = useRef<Record<string, QuickCommandJob>>({});
  const [scriptLocalPhaseById, setScriptLocalPhaseById] = useState<Record<string, ScriptLocalPhase>>({});
  const scriptLocalPhaseByIdRef = useRef<Record<string, ScriptLocalPhase>>({});

  const workspaceRef = useRef<TerminalWorkspace | null>(workspace);
  const sessionPtyIdRef = useRef(new Map<string, string>());
  const scriptIdBySessionIdRef = useRef(new Map<string, string>());
  const pendingStartBySessionIdRef = useRef(new Map<string, string>());
  const pendingStopAfterStartByScriptIdRef = useRef(new Set<string>());
  const pendingRestartByScriptIdRef = useRef(new Map<string, { reuseTabId: string | null }>());
  const finalizedQuickCommandJobIdsRef = useRef(new Set<string>());
  const stopKillTimerByScriptIdRef = useRef(new Map<string, number>());
  const stopScriptRef = useRef<(scriptId: string) => void>(() => {});
  const scriptsRef = useRef<ProjectScript[]>(scripts);

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
    scriptsRef.current = scripts;
    if (pendingRestartByScriptIdRef.current.size === 0) {
      return;
    }
    const validScriptIds = new Set(scripts.map((script) => script.id));
    for (const scriptId of Array.from(pendingRestartByScriptIdRef.current.keys())) {
      if (!validScriptIds.has(scriptId)) {
        pendingRestartByScriptIdRef.current.delete(scriptId);
      }
    }
  }, [scripts]);

  const clearAllStopKillTimers = useCallback(() => {
    for (const timer of stopKillTimerByScriptIdRef.current.values()) {
      window.clearTimeout(timer);
    }
    stopKillTimerByScriptIdRef.current.clear();
  }, []);

  useEffect(() => {
    return () => {
      if (panelMessageTimerRef.current !== null) {
        window.clearTimeout(panelMessageTimerRef.current);
        panelMessageTimerRef.current = null;
      }
      clearAllStopKillTimers();
    };
  }, [clearAllStopKillTimers]);

  useEffect(() => {
    setPanelMessage(null);
    if (panelMessageTimerRef.current !== null) {
      window.clearTimeout(panelMessageTimerRef.current);
      panelMessageTimerRef.current = null;
    }
    setScriptRuntimeById({});
    setQuickCommandJobByScriptId({});
    setScriptLocalPhaseById({});
    scriptRuntimeByIdRef.current = {};
    quickCommandJobByScriptIdRef.current = {};
    scriptLocalPhaseByIdRef.current = {};
    scriptIdBySessionIdRef.current.clear();
    sessionPtyIdRef.current.clear();
    pendingStartBySessionIdRef.current.clear();
    pendingStopAfterStartByScriptIdRef.current.clear();
    pendingRestartByScriptIdRef.current.clear();
    finalizedQuickCommandJobIdsRef.current.clear();
    clearAllStopKillTimers();
  }, [clearAllStopKillTimers, projectId, projectPath]);

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
    [projectId, projectPath],
  );

  const cleanupRuntimeBySessionIds = useCallback(
    (sessionIds: string[]) => {
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
      });

      clearScriptLocalPhase(removedScriptIds);
    },
    [clearScriptLocalPhase],
  );

  useEffect(() => {
    return () => {
      const runtimeSessionIds = Object.values(scriptRuntimeByIdRef.current).map((runtime) => runtime.sessionId);
      finalizeRuntimeBySessionIds(runtimeSessionIds, 130, "终端会话已关闭");
    };
  }, [finalizeRuntimeBySessionIds, projectId, projectPath]);

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

  const isScriptRuntimeValid = useCallback((runtime: ScriptRuntime) => {
    const current = workspaceRef.current;
    if (!current) {
      return false;
    }
    if (!current.sessions[runtime.sessionId]) {
      return false;
    }
    const runPanel = getRunPanelState(current);
    const runTab = runPanel.tabs.find((item) => item.id === runtime.tabId);
    if (!runTab) {
      return false;
    }
    return runTab.sessionId === runtime.sessionId;
  }, []);

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

      cleanupRuntimeBySessionIds([sessionId]);
    },
    [cleanupRuntimeBySessionIds, clearScriptLocalPhase, finishQuickCommandOnce, showPanelMessage],
  );

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
        onRequestSessionClose?.(sessionId, 1);
      });
    },
    [finishQuickCommandOnce, handleSessionExit, onRequestSessionClose, showPanelMessage],
  );

  const runQuickCommand = useCallback(
    (script: ProjectScript, options?: RunQuickCommandOptions) => {
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
      const requestedReuseTabId = options?.reuseTabId ?? null;
      const resolveReuseTabId = () =>
        resolveReusableRunTab(current, script.id, requestedReuseTabId)?.id ?? requestedReuseTabId;

      const localPhase = scriptLocalPhaseByIdRef.current[script.id] ?? null;
      if (localPhase === "starting") {
        showPanelMessage("命令正在启动中");
        return;
      }
      if (localPhase === "stoppingSoft" || localPhase === "stoppingHard") {
        pendingRestartByScriptIdRef.current.set(script.id, { reuseTabId: resolveReuseTabId() });
        showPanelMessage("命令停止后将自动重新运行");
        return;
      }

      const existing = scriptRuntimeByIdRef.current[script.id] ?? null;
      if (existing && isScriptRuntimeValid(existing)) {
        pendingStopAfterStartByScriptIdRef.current.delete(script.id);
        pendingRestartByScriptIdRef.current.set(script.id, {
          reuseTabId: requestedReuseTabId ?? existing.tabId,
        });
        stopScriptRef.current(script.id);
        showPanelMessage("正在重新运行命令...");
        return;
      }

      const existingJob = quickCommandJobByScriptIdRef.current[script.id] ?? null;
      if (existingJob && isActiveQuickCommandState(existingJob.state)) {
        const executionState = toScriptExecutionStateFromQuickState(existingJob.state);
        pendingRestartByScriptIdRef.current.set(script.id, { reuseTabId: resolveReuseTabId() });
        stopScriptRef.current(script.id);
        if (executionState === "starting") {
          showPanelMessage("命令启动中，启动后将自动重新运行");
        } else if (executionState === "stoppingSoft" || executionState === "stoppingHard") {
          showPanelMessage("命令停止后将自动重新运行");
        } else {
          showPanelMessage("正在重新运行命令...");
        }
        return;
      }

      if (existing) {
        cleanupRuntimeBySessionIds([existing.sessionId]);
      }

      const shellCommand = wrapQuickCommandForShell(rendered.command.trim(), {
        DEVHAVEN_SHARED_SCRIPTS: sharedScriptsRoot,
        DEVHAVEN_PROJECT_PATH: current.projectPath || projectPath,
      });
      if (!shellCommand) {
        showPanelMessage("命令为空，无法执行");
        return;
      }

      const reusableRunTab = resolveReusableRunTab(current, script.id, requestedReuseTabId);
      setScriptLocalPhaseById((prev) => ({ ...prev, [script.id]: "starting" }));
      pendingStopAfterStartByScriptIdRef.current.delete(script.id);
      pendingRestartByScriptIdRef.current.delete(script.id);

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
        const tabId = reusableRunTab?.id ?? createId();
        const replacedSessionId = reusableRunTab?.sessionId ?? null;
        scriptIdBySessionIdRef.current.set(sessionId, script.id);
        pendingStartBySessionIdRef.current.set(sessionId, shellCommand);

        setScriptRuntimeById((prev) => ({
          ...prev,
          [script.id]: { jobId: startedJob.jobId, tabId, sessionId, ptyId: null },
        }));
        clearScriptLocalPhase([script.id]);

        updateWorkspace((ws) => {
          const currentRunPanel = getRunPanelState(ws);
          const resolvedReusableRunTab = resolveReusableRunTab(ws, script.id, tabId);
          const title = script.name.trim() ? script.name.trim() : `运行 ${currentRunPanel.tabs.length + 1}`;
          const nextRunTab = {
            id: resolvedReusableRunTab?.id ?? tabId,
            title,
            sessionId,
            scriptId: script.id,
            createdAt: Date.now(),
            endedAt: null,
            exitCode: null,
          };
          const nextTabs = resolvedReusableRunTab
            ? currentRunPanel.tabs.map((tab) => (tab.id === resolvedReusableRunTab.id ? nextRunTab : tab))
            : [...currentRunPanel.tabs, nextRunTab];
          const nextSessions = {
            ...ws.sessions,
            [sessionId]: { id: sessionId, cwd: ws.projectPath, savedState: null },
          };
          const previousSessionId = resolvedReusableRunTab?.sessionId ?? replacedSessionId;
          if (previousSessionId && previousSessionId !== sessionId) {
            const sessionStillUsedByRunTabs = nextTabs.some((tab) => tab.sessionId === previousSessionId);
            const sessionStillUsedByTerminalTabs = ws.tabs.some((tab) =>
              collectSessionIds(tab.root).includes(previousSessionId),
            );
            if (!sessionStillUsedByRunTabs && !sessionStillUsedByTerminalTabs) {
              delete nextSessions[previousSessionId];
            }
          }
          return {
            ...ws,
            sessions: nextSessions,
            ui: {
              ...(ws.ui ?? {}),
              runPanel: {
                ...currentRunPanel,
                open: true,
                activeTabId: nextRunTab.id,
                tabs: nextTabs,
              },
            },
          };
        });
      })();
    },
    [
      clearScriptLocalPhase,
      cleanupRuntimeBySessionIds,
      isScriptRuntimeValid,
      projectId,
      projectPath,
      sharedScriptsRoot,
      showPanelMessage,
      updateWorkspace,
      windowLabel,
    ],
  );

  const stopScript = useCallback(
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
        onRequestSessionClose?.(resolvedRuntime.sessionId, 130);
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
          void killTerminal(latestPty, { force: true }).catch((error) => {
            console.error("强制停止快捷命令失败。", error);
          });
        }

        setScriptLocalPhaseById((prev) => ({ ...prev, [scriptId]: "stoppingHard" }));
        void stopQuickCommandJob({ jobId: resolvedRuntime.jobId, force: true }).catch((error) => {
          console.error("更新快捷命令强制停止状态失败。", error);
        });

        handleSessionExit(latest.sessionId, 130);
        onRequestSessionClose?.(latest.sessionId, 130);
      }, QUICK_COMMAND_FORCE_KILL_TIMEOUT_MS);
      stopKillTimerByScriptIdRef.current.set(scriptId, killTimer);
    },
    [cleanupRuntimeBySessionIds, handleSessionExit, isScriptRuntimeValid, onRequestSessionClose, showPanelMessage],
  );
  stopScriptRef.current = stopScript;

  useEffect(() => {
    if (pendingRestartByScriptIdRef.current.size === 0) {
      return;
    }
    const pendingEntries = Array.from(pendingRestartByScriptIdRef.current.entries());
    for (const [scriptId, request] of pendingEntries) {
      const runtime = scriptRuntimeById[scriptId] ?? null;
      const runtimeRunning = Boolean(runtime && isScriptRuntimeValid(runtime));
      if (runtimeRunning) {
        continue;
      }
      const quickJob = quickCommandJobByScriptId[scriptId] ?? null;
      if (quickJob && isActiveQuickCommandState(quickJob.state)) {
        continue;
      }
      const localPhase = scriptLocalPhaseById[scriptId] ?? null;
      if (localPhase === "starting" || localPhase === "stoppingSoft" || localPhase === "stoppingHard") {
        if (!quickJob && !runtimeRunning) {
          clearScriptLocalPhase([scriptId]);
        }
        continue;
      }
      pendingRestartByScriptIdRef.current.delete(scriptId);
      const script = scriptsRef.current.find((item) => item.id === scriptId) ?? null;
      if (!script) {
        continue;
      }
      runQuickCommand(script, { reuseTabId: request.reuseTabId });
    }
  }, [
    clearScriptLocalPhase,
    isScriptRuntimeValid,
    quickCommandJobByScriptId,
    runQuickCommand,
    scriptLocalPhaseById,
    scriptRuntimeById,
  ]);

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
      stopScript(scriptId);
    }
  }, [isScriptRuntimeValid, scriptRuntimeById, stopScript]);

  return {
    scriptRuntimeById,
    quickCommandJobByScriptId,
    scriptLocalPhaseById,
    panelMessage,
    showPanelMessage,
    runQuickCommand,
    stopScript,
    isScriptRuntimeValid,
    handlePtyReady,
    handleSessionExit,
    cleanupRuntimeBySessionIds,
    finalizeRuntimeBySessionIds,
  };
}
