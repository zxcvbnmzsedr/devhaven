import { listen, type Event as TauriEvent, type UnlistenFn } from "@tauri-apps/api/event";

import { isTauriRuntime, resolveRuntimeWindowLabel, resolveWebApiBase } from "./runtime";

type EventHandler<TPayload> = (event: { payload: TPayload }) => void;
type EventEnvelope = {
  event: string;
  payload: unknown;
};

let socket: WebSocket | null = null;
let reconnectTimer: number | null = null;
let nextHandlerId = 0;
const handlers = new Map<string, Map<number, EventHandler<unknown>>>();

function clearReconnectTimer() {
  if (reconnectTimer === null) {
    return;
  }
  window.clearTimeout(reconnectTimer);
  reconnectTimer = null;
}

function scheduleReconnect() {
  if (reconnectTimer !== null) {
    return;
  }
  reconnectTimer = window.setTimeout(() => {
    reconnectTimer = null;
    ensureSocket();
  }, 1000);
}

function dispatchEnvelope(envelope: EventEnvelope) {
  const eventHandlers = handlers.get(envelope.event);
  if (!eventHandlers || eventHandlers.size === 0) {
    return;
  }

  for (const handler of eventHandlers.values()) {
    try {
      handler({ payload: envelope.payload });
    } catch (error) {
      console.error(`[eventClient] 事件处理失败: ${envelope.event}`, error);
    }
  }
}

function ensureSocket() {
  if (isTauriRuntime() || typeof window === "undefined") {
    return;
  }

  if (socket && (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING)) {
    return;
  }

  clearReconnectTimer();

  const wsBase = resolveWebApiBase().replace(/^http/i, "ws");
  const windowLabel = encodeURIComponent(resolveRuntimeWindowLabel());
  socket = new WebSocket(`${wsBase}/api/ws?windowLabel=${windowLabel}`);

  socket.onmessage = (event) => {
    try {
      const envelope = JSON.parse(String(event.data)) as EventEnvelope;
      if (!envelope || typeof envelope.event !== "string") {
        return;
      }
      dispatchEnvelope(envelope);
    } catch (error) {
      console.warn("[eventClient] 解析 WS 消息失败", error);
    }
  };

  socket.onclose = () => {
    socket = null;
    if (handlers.size > 0) {
      scheduleReconnect();
    }
  };

  socket.onerror = () => {
    if (socket && socket.readyState !== WebSocket.OPEN) {
      socket.close();
    }
  };
}

function releaseSocketIfIdle() {
  if (isTauriRuntime()) {
    return;
  }

  if (handlers.size > 0) {
    return;
  }

  clearReconnectTimer();
  if (socket) {
    socket.close();
    socket = null;
  }
}

/** 统一事件订阅入口：Tauri 走 listen，浏览器走 WebSocket。 */
export async function listenEvent<TPayload>(
  eventName: string,
  handler: EventHandler<TPayload>,
): Promise<UnlistenFn> {
  if (isTauriRuntime()) {
    return listen<TPayload>(eventName, handler as (event: TauriEvent<TPayload>) => void);
  }

  const handlerId = nextHandlerId;
  nextHandlerId += 1;

  const eventHandlers = handlers.get(eventName) ?? new Map<number, EventHandler<unknown>>();
  eventHandlers.set(handlerId, handler as EventHandler<unknown>);
  handlers.set(eventName, eventHandlers);

  ensureSocket();

  let active = true;
  return () => {
    if (!active) {
      return;
    }
    active = false;

    const scopedHandlers = handlers.get(eventName);
    if (scopedHandlers) {
      scopedHandlers.delete(handlerId);
      if (scopedHandlers.size === 0) {
        handlers.delete(eventName);
      }
    }

    releaseSocketIfIdle();
  };
}
