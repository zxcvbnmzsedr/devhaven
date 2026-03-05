import { useEffect, useState } from "react";
import { listenEvent } from "../platform/eventClient";

import type { CodexAgentEvent, CodexMonitorSession, CodexMonitorSnapshot } from "../models/codex";
import {
  CODEX_MONITOR_AGENT_EVENT,
  CODEX_MONITOR_SNAPSHOT_EVENT,
  getCodexMonitorSnapshot,
} from "../services/codex";

const POLL_INTERVAL_IDLE_MS = 5000;
const POLL_INTERVAL_WARM_MS = 15000;
const POLL_INTERVAL_STABLE_MS = 30000;
const EVENT_STABLE_WINDOW_MS = 20000;
const EVENT_WARM_WINDOW_MS = 60000;
const MAX_EVENTS = 80;

export type CodexMonitorStore = {
  snapshot: CodexMonitorSnapshot | null;
  sessions: CodexMonitorSession[];
  isCodexRunning: boolean;
  agentEvents: CodexAgentEvent[];
  isLoading: boolean;
  error: string | null;
};

/** 监听 Codex 监控快照和状态事件，并保留低频轮询兜底。 */
export function useCodexMonitor(): CodexMonitorStore {
  const [snapshot, setSnapshot] = useState<CodexMonitorSnapshot | null>(null);
  const [sessions, setSessions] = useState<CodexMonitorSession[]>([]);
  const [isCodexRunning, setIsCodexRunning] = useState(false);
  const [agentEvents, setAgentEvents] = useState<CodexAgentEvent[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let canceled = false;
    let stopSnapshotListen: (() => void) | null = null;
    let stopEventListen: (() => void) | null = null;
    let pollTimer: number | null = null;
    let lastRealtimeAt = 0;

    const clearPollTimer = () => {
      if (pollTimer == null) {
        return;
      }
      window.clearTimeout(pollTimer);
      pollTimer = null;
    };

    const getNextPollDelay = () => {
      if (lastRealtimeAt <= 0) {
        return POLL_INTERVAL_IDLE_MS;
      }
      const elapsed = Date.now() - lastRealtimeAt;
      if (elapsed <= EVENT_STABLE_WINDOW_MS) {
        return POLL_INTERVAL_STABLE_MS;
      }
      if (elapsed <= EVENT_WARM_WINDOW_MS) {
        return POLL_INTERVAL_WARM_MS;
      }
      return POLL_INTERVAL_IDLE_MS;
    };

    const scheduleNextPoll = () => {
      if (canceled) {
        return;
      }
      clearPollTimer();
      pollTimer = window.setTimeout(() => {
        void load().finally(() => {
          scheduleNextPoll();
        });
      }, getNextPollDelay());
    };

    const markRealtimeAlive = () => {
      lastRealtimeAt = Date.now();
      scheduleNextPoll();
    };

    const applySnapshot = (next: CodexMonitorSnapshot) => {
      if (canceled) {
        return;
      }
      setSnapshot(next);
      setSessions(next.sessions ?? []);
      setIsCodexRunning(Boolean(next.isCodexRunning));
      setError(null);
      setIsLoading(false);
    };

    const load = async () => {
      try {
        const result = await getCodexMonitorSnapshot();
        applySnapshot(result);
      } catch (err) {
        if (canceled) {
          return;
        }
        setError(err instanceof Error ? err.message : String(err));
        setIsLoading(false);
      }
    };

    void load();
    scheduleNextPoll();

    void listenEvent<CodexMonitorSnapshot>(CODEX_MONITOR_SNAPSHOT_EVENT, (event) => {
      if (!event.payload || canceled) {
        return;
      }
      markRealtimeAlive();
      applySnapshot(event.payload);
    })
      .then((unlisten) => {
        if (canceled) {
          unlisten();
          return;
        }
        stopSnapshotListen = unlisten;
      })
      .catch((err) => {
        if (canceled) {
          return;
        }
        setError(err instanceof Error ? err.message : String(err));
      });

    void listenEvent<CodexAgentEvent>(CODEX_MONITOR_AGENT_EVENT, (event) => {
      if (canceled || !event.payload) {
        return;
      }
      markRealtimeAlive();
      setAgentEvents((prev) => {
        const next = [event.payload, ...prev];
        if (next.length > MAX_EVENTS) {
          return next.slice(0, MAX_EVENTS);
        }
        return next;
      });
    })
      .then((unlisten) => {
        if (canceled) {
          unlisten();
          return;
        }
        stopEventListen = unlisten;
      })
      .catch((err) => {
        if (canceled) {
          return;
        }
        setError(err instanceof Error ? err.message : String(err));
      });

    return () => {
      canceled = true;
      clearPollTimer();
      stopSnapshotListen?.();
      stopEventListen?.();
    };
  }, []);

  return {
    snapshot,
    sessions,
    isCodexRunning,
    agentEvents,
    isLoading,
    error,
  };
}
