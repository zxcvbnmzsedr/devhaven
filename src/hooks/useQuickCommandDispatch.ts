import { useCallback, useEffect, useRef } from "react";

import type { TerminalQuickCommandDispatch } from "../models/quickCommands";
import type { TerminalLayoutSnapshot } from "../models/terminal";
import type { ProjectScript } from "../models/types";

type UseQuickCommandDispatchParams = {
  projectId: string | null;
  projectPath: string;
  scripts: ProjectScript[];
  layoutSnapshot: TerminalLayoutSnapshot | null;
  quickCommandDispatch: TerminalQuickCommandDispatch | null | undefined;
  runQuickCommand: (script: ProjectScript) => void;
  stopScript: (scriptId: string) => void;
  showPanelMessage: (message: string) => void;
};

export function useQuickCommandDispatch({
  projectId,
  projectPath,
  scripts,
  layoutSnapshot,
  quickCommandDispatch,
  runQuickCommand,
  stopScript,
  showPanelMessage,
}: UseQuickCommandDispatchParams) {
  const handledDispatchSeqRef = useRef(0);
  const pendingQuickCommandDispatchRef = useRef<TerminalQuickCommandDispatch | null>(null);

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

      if (!layoutSnapshot) {
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

      stopScript(dispatch.scriptId);
    },
    [layoutSnapshot, projectId, projectPath, runQuickCommand, scripts, showPanelMessage, stopScript],
  );

  useEffect(() => {
    handleQuickCommandDispatch(quickCommandDispatch);
  }, [handleQuickCommandDispatch, quickCommandDispatch]);

  useEffect(() => {
    if (!layoutSnapshot) {
      return;
    }
    const pending = pendingQuickCommandDispatchRef.current;
    if (!pending) {
      return;
    }
    pendingQuickCommandDispatchRef.current = null;
    handleQuickCommandDispatch(pending);
  }, [handleQuickCommandDispatch, layoutSnapshot]);
}
