import { invokeCommand } from "../platform/commandClient";
import { listenEvent } from "../platform/eventClient";

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

export type TerminalExitPayload = {
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

type TerminalEventHandler<TPayload> = (event: { payload: TPayload }) => void;
type UnlistenFn = () => void;

const PTY_KILL_GRACE_MS = 1000;
const TERMINAL_PTY_REGISTRY = new Map<string, TerminalPtyRegistryEntry>();

function createSharedTerminalEventListener<TPayload>(
  eventName: string,
  options?: { afterDispatch?: (event: { payload: TPayload }) => void },
) {
  let nextHandlerId = 0;
  const handlers = new Map<number, TerminalEventHandler<TPayload>>();
  let baseUnlisten: UnlistenFn | null = null;
  let baseSubscriptionPromise: Promise<void> | null = null;

  const releaseBaseSubscription = () => {
    if (handlers.size > 0 || baseSubscriptionPromise) {
      return;
    }

    if (!baseUnlisten) {
      return;
    }

    const unlistenBase = baseUnlisten;
    baseUnlisten = null;
    unlistenBase();
  };

  const dispatch = (event: { payload: TPayload }) => {
    for (const handler of handlers.values()) {
      try {
        handler(event);
      } catch (error) {
        console.error(`[terminal] ${eventName} handler failed`, error);
      }
    }
    options?.afterDispatch?.(event);
  };

  const ensureBaseSubscription = async () => {
    if (baseUnlisten) {
      return;
    }

    if (!baseSubscriptionPromise) {
      baseSubscriptionPromise = listenEvent<TPayload>(eventName, dispatch)
        .then((unlisten) => {
          baseUnlisten = unlisten;
          baseSubscriptionPromise = null;

          // 如果订阅建立前所有 handler 都已取消，立即释放底层监听。
          releaseBaseSubscription();
        })
        .catch((error) => {
          baseSubscriptionPromise = null;
          throw error;
        });
    }

    await baseSubscriptionPromise;
  };

  return async (handler: TerminalEventHandler<TPayload>) => {
    const handlerId = nextHandlerId;
    nextHandlerId += 1;
    handlers.set(handlerId, handler);

    try {
      await ensureBaseSubscription();
    } catch (error) {
      handlers.delete(handlerId);
      releaseBaseSubscription();
      throw error;
    }

    let active = true;
    return () => {
      if (!active) {
        return;
      }

      active = false;
      handlers.delete(handlerId);
      releaseBaseSubscription();
    };
  };
}

const registerTerminalOutputHandler = createSharedTerminalEventListener<TerminalOutputPayload>(
  "terminal-output",
);

function cleanupTerminalPtyEntriesBySessionId(sessionId: string) {
  const suffix = `::${sessionId}`;
  for (const [key] of TERMINAL_PTY_REGISTRY) {
    if (key.endsWith(suffix)) {
      TERMINAL_PTY_REGISTRY.delete(key);
    }
  }
}

const registerTerminalExitHandler = createSharedTerminalEventListener<TerminalExitPayload>("terminal-exit", {
  afterDispatch: (event) => {
    const sessionId = event.payload.sessionId?.trim();
    if (!sessionId) {
      return;
    }
    cleanupTerminalPtyEntriesBySessionId(sessionId);
  },
});

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
  handler: (event: { payload: TerminalOutputPayload }) => void,
) {
  return registerTerminalOutputHandler(handler);
}

export async function listenTerminalExit(
  handler: (event: { payload: TerminalExitPayload }) => void,
) {
  return registerTerminalExitHandler(handler);
}
