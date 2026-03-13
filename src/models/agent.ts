import { getPaneAgentAdapter } from "../agents/registry.ts";

export const PANE_AGENT_PROVIDERS = ["codex", "claude-code", "iflow"] as const;
export type PaneAgentProvider = (typeof PANE_AGENT_PROVIDERS)[number];
export type PaneAgentMode = "shell" | "agent";
export type PaneAgentStatus = "idle" | "starting" | "running" | "stopped" | "failed";
export type AgentShellFamily = "posix" | "powershell";

export type PaneAgentDescriptor = {
  provider: PaneAgentProvider;
  model?: string | null;
};

export type PaneCreationTemplate =
  | { mode: "shell" }
  | {
      mode: "agent";
      provider: PaneAgentProvider;
    };

export type PaneAgentRuntimeState = {
  status: PaneAgentStatus;
  command: string | null;
  ptyId: string | null;
  exitCode: number | null;
  error: string | null;
  outputTail: string;
};

export type PaneAgentRuntimeMap = Record<string, PaneAgentRuntimeState>;

export const DEVHAVEN_AGENT_STARTED_MARKER = "[DevHaven Agent Started]";
export const DEVHAVEN_AGENT_EXIT_MARKER_PREFIX = "[DevHaven Agent Exit:";
const OUTPUT_TAIL_MAX_CHARS = 512;

export const PANE_AGENT_PROVIDER_LABEL: Record<PaneAgentProvider, string> = {
  codex: "Codex",
  "claude-code": "Claude Code",
  iflow: "iFlow",
};

export const PANE_AGENT_STATUS_LABEL: Record<PaneAgentStatus, string> = {
  idle: "未启动",
  starting: "启动中",
  running: "运行中",
  stopped: "已停止",
  failed: "失败",
};

export function listPaneCreationTemplates(): PaneCreationTemplate[] {
  return [
    { mode: "shell" },
    ...PANE_AGENT_PROVIDERS.map((provider) => ({
      mode: "agent" as const,
      provider,
    })),
  ];
}

export function movePaneCreationSelection(
  currentIndex: number,
  direction: "up" | "down",
  count: number,
): number {
  if (count <= 0) {
    return 0;
  }
  const normalized = ((currentIndex % count) + count) % count;
  if (direction === "down") {
    return (normalized + 1) % count;
  }
  return (normalized - 1 + count) % count;
}

function normalizeOptionalText(value: string | null | undefined): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const normalized = value.trim();
  return normalized.length > 0 ? normalized : null;
}

function trimOutputTail(value: string): string {
  if (value.length <= OUTPUT_TAIL_MAX_CHARS) {
    return value;
  }
  return value.slice(-OUTPUT_TAIL_MAX_CHARS);
}

function resolveExitCodeFromTail(outputTail: string): number | null {
  const markerIndex = outputTail.lastIndexOf(DEVHAVEN_AGENT_EXIT_MARKER_PREFIX);
  if (markerIndex < 0) {
    return null;
  }
  const match = outputTail.slice(markerIndex).match(/\[DevHaven Agent Exit:(-?\d+)\]/);
  if (!match) {
    return null;
  }
  const parsed = Number.parseInt(match[1], 10);
  return Number.isFinite(parsed) ? parsed : null;
}

export function createPaneAgentRuntimeMap(): PaneAgentRuntimeMap {
  return {};
}

export function createPaneAgentRuntimeState(command: string | null): PaneAgentRuntimeState {
  return {
    status: "starting",
    command,
    ptyId: null,
    exitCode: null,
    error: null,
    outputTail: "",
  };
}

export function canStartPaneAgent(runtime: PaneAgentRuntimeState | null | undefined): boolean {
  if (!runtime) {
    return true;
  }
  return runtime.status !== "starting" && runtime.status !== "running";
}

export function resolvePaneAgentStatus(
  runtime: PaneAgentRuntimeState | null | undefined,
): PaneAgentStatus {
  return runtime?.status ?? "idle";
}

export function buildPaneAgentLaunchCommand(
  provider: PaneAgentProvider,
  options?: {
    model?: string | null;
    prompt?: string | null;
    fullAccess?: boolean;
    shellFamily?: AgentShellFamily;
  },
): string {
  return getPaneAgentAdapter(provider).buildLaunchCommand(options);
}

export function startPaneAgentRuntime(
  runtimeBySessionId: PaneAgentRuntimeMap,
  sessionId: string,
  command: string,
): PaneAgentRuntimeMap {
  return {
    ...runtimeBySessionId,
    [sessionId]: createPaneAgentRuntimeState(command),
  };
}

export function attachPaneAgentPty(
  runtimeBySessionId: PaneAgentRuntimeMap,
  sessionId: string,
  ptyId: string,
): PaneAgentRuntimeMap {
  const runtime = runtimeBySessionId[sessionId];
  if (!runtime || runtime.ptyId === ptyId) {
    return runtimeBySessionId;
  }

  return {
    ...runtimeBySessionId,
    [sessionId]: {
      ...runtime,
      ptyId,
    },
  };
}

export function consumePaneAgentOutput(
  runtimeBySessionId: PaneAgentRuntimeMap,
  sessionId: string,
  chunk: string,
): PaneAgentRuntimeMap {
  const runtime = runtimeBySessionId[sessionId];
  if (!runtime || !chunk) {
    return runtimeBySessionId;
  }

  const outputTail = trimOutputTail(`${runtime.outputTail}${chunk}`);
  const exitCode = resolveExitCodeFromTail(outputTail);
  let status = runtime.status;
  let error = runtime.error;

  if (outputTail.includes(DEVHAVEN_AGENT_STARTED_MARKER)) {
    status = "running";
    error = null;
  }

  if (exitCode !== null) {
    status = exitCode === 0 ? "stopped" : "failed";
    error = exitCode === 0 ? null : runtime.error;
  }

  return {
    ...runtimeBySessionId,
    [sessionId]: {
      ...runtime,
      status,
      exitCode: exitCode ?? runtime.exitCode,
      error,
      outputTail,
    },
  };
}

export function finishPaneAgentRuntime(
  runtimeBySessionId: PaneAgentRuntimeMap,
  sessionId: string,
  options?: {
    exitCode?: number | null;
    error?: string | null;
  },
): PaneAgentRuntimeMap {
  const runtime = runtimeBySessionId[sessionId];
  if (!runtime) {
    return runtimeBySessionId;
  }

  const exitCode = typeof options?.exitCode === "number" ? options.exitCode : null;
  const error = normalizeOptionalText(options?.error);

  return {
    ...runtimeBySessionId,
    [sessionId]: {
      ...runtime,
      status: error || (exitCode !== null && exitCode !== 0) ? "failed" : "stopped",
      exitCode,
      error,
    },
  };
}

export function clearPaneAgentRuntime(
  runtimeBySessionId: PaneAgentRuntimeMap,
  sessionId: string,
): PaneAgentRuntimeMap {
  if (!runtimeBySessionId[sessionId]) {
    return runtimeBySessionId;
  }

  const next = { ...runtimeBySessionId };
  delete next[sessionId];
  return next;
}

export function resolveAgentShellFamily(): AgentShellFamily {
  if (typeof navigator !== "undefined" && /windows/i.test(navigator.userAgent)) {
    return "powershell";
  }
  return "posix";
}
