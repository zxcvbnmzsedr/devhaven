import { invokeCommand } from "../platform/commandClient";
import { listenEvent } from "../platform/eventClient";
import {
  terminalPaneExitEventName,
  terminalPaneOutputEventName,
} from "../terminal-runtime-client/subscriptions";

export type TerminalCreateRequest = {
  projectPath: string;
  cols: number;
  rows: number;
  windowLabel: string;
  sessionId?: string;
  clientId?: string;
};

export type TerminalCreateResult = {
  ptyId: string;
  sessionId: string;
  shell: string;
  replayData?: string | null;
};

export type TerminalPtyReadyResult = {
  ptyId: string;
  replayData?: string | null;
};

export type TerminalOutputPayload = {
  sessionId: string;
  data: string;
};

export type TerminalPaneOutputPayload = {
  sessionId: string;
  data: string;
  seqStart?: number | null;
  seqEnd?: number | null;
};

export type TerminalExitPayload = {
  sessionId: string;
  code?: number | null;
};

export type TerminalPaneExitPayload = {
  sessionId: string;
  code?: number | null;
};

type TerminalPtyRegistryEntry = {
  ptyId: string | null;
  cachedState: string | null;
  refs: number;
  parked: boolean;
  needsReplay: boolean;
  terminating: boolean;
  killTimer: number | null;
  creating: Promise<TerminalPtyReadyResult> | null;
};

const PTY_KILL_GRACE_MS = 1000;
const TERMINAL_PTY_REGISTRY = new Map<string, TerminalPtyRegistryEntry>();

function terminalOutputEventName(sessionId: string) {
  return terminalPaneOutputEventName(sessionId);
}

function terminalExitEventName(sessionId: string) {
  return terminalPaneExitEventName(sessionId);
}

function cleanupTerminalPtyEntriesBySessionId(sessionId: string) {
  const suffix = `::${sessionId}`;
  for (const [key] of TERMINAL_PTY_REGISTRY) {
    if (key.endsWith(suffix)) {
      TERMINAL_PTY_REGISTRY.delete(key);
    }
  }
}

export function buildTerminalPtyRegistryKey(windowLabel: string, sessionId: string) {
  return `${windowLabel}::${sessionId}`;
}

function getOrCreateTerminalPtyRegistryEntry(key: string): TerminalPtyRegistryEntry {
  const existing = TERMINAL_PTY_REGISTRY.get(key);
  if (existing) {
    return existing;
  }
  const next: TerminalPtyRegistryEntry = {
    ptyId: null,
    cachedState: null,
    refs: 0,
    parked: false,
    needsReplay: false,
    terminating: false,
    killTimer: null,
    creating: null,
  };
  TERMINAL_PTY_REGISTRY.set(key, next);
  return next;
}

function clearTerminalPtyKillTimer(entry: TerminalPtyRegistryEntry) {
  if (entry.killTimer !== null) {
    window.clearTimeout(entry.killTimer);
    entry.killTimer = null;
  }
}

export function retainTerminalPtySession(key: string) {
  const entry = getOrCreateTerminalPtyRegistryEntry(key);
  entry.refs += 1;
  entry.parked = false;
  entry.terminating = false;
  clearTerminalPtyKillTimer(entry);
}

export function consumeTerminalPtyCachedState(key: string) {
  const entry = TERMINAL_PTY_REGISTRY.get(key);
  if (!entry?.cachedState) {
    return null;
  }
  const cachedState = entry.cachedState;
  entry.cachedState = null;
  return cachedState;
}

export function cacheTerminalPtyState(key: string, cachedState: string | null) {
  const entry = TERMINAL_PTY_REGISTRY.get(key);
  if (!entry) {
    return;
  }
  entry.cachedState = cachedState;
}

async function killTerminalPtyRegistryEntry(key: string, clientId: string) {
  const entry = TERMINAL_PTY_REGISTRY.get(key);
  if (!entry) {
    return;
  }
  entry.terminating = true;
  entry.parked = false;
  entry.needsReplay = false;
  clearTerminalPtyKillTimer(entry);

  let ptyId = entry.ptyId;
  if (!ptyId && entry.creating) {
    try {
      const created = await entry.creating;
      ptyId = created.ptyId;
    } catch {
      // ignore
    }
  }

  if (ptyId) {
    try {
      await killTerminal(ptyId, { clientId });
    } catch {
      // ignore
    }
  }

  const latest = TERMINAL_PTY_REGISTRY.get(key);
  if (latest && latest.terminating) {
    TERMINAL_PTY_REGISTRY.delete(key);
  }
}

function scheduleTerminalPtyKill(key: string, clientId: string) {
  const entry = TERMINAL_PTY_REGISTRY.get(key);
  if (!entry) {
    return;
  }
  if (entry.killTimer !== null || entry.terminating) {
    return;
  }
  if (!entry.ptyId && !entry.creating) {
    TERMINAL_PTY_REGISTRY.delete(key);
    return;
  }

  entry.killTimer = window.setTimeout(() => {
    void (async () => {
      const current = TERMINAL_PTY_REGISTRY.get(key);
      if (!current || current.refs > 0 || current.parked || current.terminating) {
        return;
      }
      current.killTimer = null;
      await killTerminalPtyRegistryEntry(key, clientId);
    })();
  }, PTY_KILL_GRACE_MS);
}

export function releaseTerminalPtySession(
  key: string,
  clientId: string,
  options?: { preserve?: boolean },
) {
  const entry = TERMINAL_PTY_REGISTRY.get(key);
  if (!entry) {
    return;
  }
  entry.refs = Math.max(0, entry.refs - 1);
  if (entry.refs > 0) {
    return;
  }
  if (entry.terminating) {
    return;
  }
  if (options?.preserve) {
    if (!entry.ptyId && !entry.creating) {
      TERMINAL_PTY_REGISTRY.delete(key);
      return;
    }
    entry.parked = true;
    entry.needsReplay = true;
    clearTerminalPtyKillTimer(entry);
    return;
  }
  scheduleTerminalPtyKill(key, clientId);
}

export async function ensureTerminalPtyId(
  key: string,
  request: TerminalCreateRequest & { sessionId: string; clientId: string },
): Promise<TerminalPtyReadyResult> {
  const entry = getOrCreateTerminalPtyRegistryEntry(key);
  if (entry.ptyId && !entry.needsReplay) {
    return {
      ptyId: entry.ptyId,
      replayData: null,
    };
  }
  if (entry.creating) {
    return entry.creating;
  }

  entry.creating = (async () => {
    const result = await createTerminalSession(request);
    entry.ptyId = result.ptyId;
    entry.parked = false;
    entry.needsReplay = false;
    entry.terminating = false;
    return result;
  })();

  try {
    return await entry.creating;
  } finally {
    const latest = TERMINAL_PTY_REGISTRY.get(key);
    if (latest) {
      latest.creating = null;
    }
  }
}

export async function terminateTerminalSession(windowLabel: string, sessionId: string, clientId: string) {
  await killTerminalPtyRegistryEntry(buildTerminalPtyRegistryKey(windowLabel, sessionId), clientId);
}

export async function terminateTerminalSessions(windowLabel: string, sessionIds: string[], clientId: string) {
  await Promise.all(sessionIds.map((sessionId) => terminateTerminalSession(windowLabel, sessionId, clientId)));
}

export async function createTerminalSession(request: TerminalCreateRequest): Promise<TerminalCreateResult> {
  return invokeCommand<TerminalCreateResult>("terminal_create_session", request);
}

export async function writeTerminal(ptyId: string, data: string): Promise<void> {
  await invokeCommand("terminal_write", { ptyId, data });
}

export async function resizeTerminal(ptyId: string, cols: number, rows: number): Promise<void> {
  await invokeCommand("terminal_resize", { ptyId, cols, rows });
}

export async function killTerminal(
  ptyId: string,
  options?: { clientId?: string; force?: boolean },
): Promise<void> {
  await invokeCommand("terminal_kill", {
    ptyId,
    clientId: options?.clientId,
    force: options?.force,
  });
}

export async function listenTerminalOutput(
  sessionId: string,
  handler: (event: { payload: TerminalOutputPayload }) => void,
): Promise<() => void>;
export async function listenTerminalOutput(
  sessionId: string,
  handler: (event: { payload: TerminalOutputPayload }) => void,
) {
  return listenEvent<TerminalOutputPayload>(terminalOutputEventName(sessionId.trim()), handler);
}

export async function listenTerminalExit(
  sessionId: string,
  handler: (event: { payload: TerminalExitPayload }) => void,
): Promise<() => void>;
export async function listenTerminalExit(
  sessionId: string,
  handler: (event: { payload: TerminalExitPayload }) => void,
) {
  return listenEvent<TerminalExitPayload>(terminalExitEventName(sessionId.trim()), (event) => {
    const resolvedSessionId = event.payload.sessionId?.trim();
    if (resolvedSessionId) {
      cleanupTerminalPtyEntriesBySessionId(resolvedSessionId);
    }
    handler(event);
  });
}

export async function listenTerminalPaneOutput(
  sessionId: string,
  handler: (event: { payload: TerminalPaneOutputPayload }) => void,
) {
  return listenEvent<TerminalPaneOutputPayload>(terminalPaneOutputEventName(sessionId.trim()), handler);
}

export async function listenTerminalPaneExit(
  sessionId: string,
  handler: (event: { payload: TerminalPaneExitPayload }) => void,
) {
  return listenEvent<TerminalPaneExitPayload>(terminalPaneExitEventName(sessionId.trim()), (event) => {
    const resolvedSessionId = event.payload.sessionId?.trim();
    if (resolvedSessionId) {
      cleanupTerminalPtyEntriesBySessionId(resolvedSessionId);
    }
    handler(event);
  });
}
