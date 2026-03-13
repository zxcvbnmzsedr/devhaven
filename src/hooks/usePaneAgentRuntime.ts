import { useCallback, useRef, useState } from "react";

import {
  attachPaneAgentPty,
  canStartPaneAgent,
  clearPaneAgentRuntime,
  consumePaneAgentOutput,
  createPaneAgentRuntimeMap,
  finishPaneAgentRuntime,
  resolvePaneAgentStatus,
  startPaneAgentRuntime,
  type PaneAgentRuntimeMap,
  type PaneAgentRuntimeState,
} from "../models/agent";

export type UsePaneAgentRuntimeReturn = {
  runtimeBySessionId: PaneAgentRuntimeMap;
  getRuntime: (sessionId: string) => PaneAgentRuntimeState | null;
  getPtyId: (sessionId: string) => string | null;
  getStatus: (sessionId: string) => ReturnType<typeof resolvePaneAgentStatus>;
  canStart: (sessionId: string) => boolean;
  requestStart: (sessionId: string, command: string) => void;
  connectPty: (sessionId: string, ptyId: string) => string | null;
  handleOutput: (sessionId: string, chunk: string) => void;
  handleExit: (sessionId: string, code?: number | null, error?: string | null) => void;
  clearRuntime: (sessionId: string) => void;
  disposeSession: (sessionId: string) => void;
};

/** 管理 terminal pane 级别的 agent 运行态。 */
export function usePaneAgentRuntime(): UsePaneAgentRuntimeReturn {
  const [runtimeBySessionId, setRuntimeBySessionId] = useState<PaneAgentRuntimeMap>(() =>
    createPaneAgentRuntimeMap(),
  );
  const pendingCommandBySessionIdRef = useRef(new Map<string, string>());
  const ptyIdBySessionIdRef = useRef(new Map<string, string>());

  const requestStart = useCallback((sessionId: string, command: string) => {
    pendingCommandBySessionIdRef.current.set(sessionId, command);
    setRuntimeBySessionId((current) => {
      const next = startPaneAgentRuntime(current, sessionId, command);
      const knownPtyId = ptyIdBySessionIdRef.current.get(sessionId);
      return knownPtyId ? attachPaneAgentPty(next, sessionId, knownPtyId) : next;
    });
  }, []);

  const connectPty = useCallback((sessionId: string, ptyId: string) => {
    ptyIdBySessionIdRef.current.set(sessionId, ptyId);
    setRuntimeBySessionId((current) => attachPaneAgentPty(current, sessionId, ptyId));

    const pendingCommand = pendingCommandBySessionIdRef.current.get(sessionId) ?? null;
    if (pendingCommand) {
      pendingCommandBySessionIdRef.current.delete(sessionId);
    }
    return pendingCommand;
  }, []);

  const handleOutput = useCallback((sessionId: string, chunk: string) => {
    setRuntimeBySessionId((current) => consumePaneAgentOutput(current, sessionId, chunk));
  }, []);

  const handleExit = useCallback((sessionId: string, code?: number | null, error?: string | null) => {
    pendingCommandBySessionIdRef.current.delete(sessionId);
    setRuntimeBySessionId((current) => finishPaneAgentRuntime(current, sessionId, { exitCode: code, error }));
  }, []);

  const clearRuntime = useCallback((sessionId: string) => {
    pendingCommandBySessionIdRef.current.delete(sessionId);
    setRuntimeBySessionId((current) => clearPaneAgentRuntime(current, sessionId));
  }, []);

  const disposeSession = useCallback((sessionId: string) => {
    pendingCommandBySessionIdRef.current.delete(sessionId);
    ptyIdBySessionIdRef.current.delete(sessionId);
    setRuntimeBySessionId((current) => clearPaneAgentRuntime(current, sessionId));
  }, []);

  const getRuntime = useCallback(
    (sessionId: string) => runtimeBySessionId[sessionId] ?? null,
    [runtimeBySessionId],
  );

  const getPtyId = useCallback(
    (sessionId: string) => ptyIdBySessionIdRef.current.get(sessionId) ?? null,
    [],
  );

  const getStatus = useCallback(
    (sessionId: string) => resolvePaneAgentStatus(runtimeBySessionId[sessionId]),
    [runtimeBySessionId],
  );

  const canStart = useCallback(
    (sessionId: string) => canStartPaneAgent(runtimeBySessionId[sessionId]),
    [runtimeBySessionId],
  );

  return {
    runtimeBySessionId,
    getRuntime,
    getPtyId,
    getStatus,
    canStart,
    requestStart,
    connectPty,
    handleOutput,
    handleExit,
    clearRuntime,
    disposeSession,
  };
}
