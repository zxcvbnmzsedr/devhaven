import { invokeCommand } from "../platform/commandClient";
import { listenEvent } from "../platform/eventClient";

export type TerminalCreateRequest = {
  projectPath: string;
  cols: number;
  rows: number;
  windowLabel: string;
  sessionId?: string;
};

export type TerminalCreateResult = {
  ptyId: string;
  sessionId: string;
  shell: string;
};

export type TerminalOutputPayload = {
  sessionId: string;
  data: string;
};

export type TerminalExitPayload = {
  sessionId: string;
  code?: number | null;
};

type TerminalEventHandler<TPayload> = (event: { payload: TPayload }) => void;
type UnlistenFn = () => void;

function createSharedTerminalEventListener<TPayload>(eventName: string) {
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
const registerTerminalExitHandler = createSharedTerminalEventListener<TerminalExitPayload>(
  "terminal-exit",
);

export async function createTerminalSession(request: TerminalCreateRequest): Promise<TerminalCreateResult> {
  return invokeCommand<TerminalCreateResult>("terminal_create_session", request);
}

export async function writeTerminal(ptyId: string, data: string): Promise<void> {
  await invokeCommand("terminal_write", { ptyId, data });
}

export async function resizeTerminal(ptyId: string, cols: number, rows: number): Promise<void> {
  await invokeCommand("terminal_resize", { ptyId, cols, rows });
}

export async function killTerminal(ptyId: string): Promise<void> {
  await invokeCommand("terminal_kill", { ptyId });
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
