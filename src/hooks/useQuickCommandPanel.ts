import { useCallback, useEffect, useRef, useState, type PointerEvent as ReactPointerEvent, type RefObject } from "react";

import type { TerminalWorkspace } from "../models/terminal";

type UseQuickCommandPanelParams = {
  workspace: TerminalWorkspace | null;
  defaultPanelOpen: boolean;
  updateWorkspace: (updater: (prev: TerminalWorkspace) => TerminalWorkspace) => void;
};

type UseQuickCommandPanelReturn = {
  stageRef: RefObject<HTMLDivElement | null>;
  panelRef: RefObject<HTMLDivElement | null>;
  panelDraft: { x: number; y: number } | null;
  beginDragQuickCommandsPanel: (event: ReactPointerEvent<HTMLDivElement>) => void;
};

export function useQuickCommandPanel({
  workspace,
  defaultPanelOpen,
  updateWorkspace,
}: UseQuickCommandPanelParams): UseQuickCommandPanelReturn {
  const stageRef = useRef<HTMLDivElement | null>(null);
  const panelRef = useRef<HTMLDivElement | null>(null);
  const [panelDraft, setPanelDraft] = useState<{ x: number; y: number } | null>(null);
  const panelDraftRef = useRef<{ x: number; y: number } | null>(null);
  const dragStateRef = useRef<{
    startClientX: number;
    startClientY: number;
    baseX: number;
    baseY: number;
  } | null>(null);
  const workspaceRef = useRef<TerminalWorkspace | null>(workspace);

  useEffect(() => {
    workspaceRef.current = workspace;
  }, [workspace]);

  const commitQuickCommandsPanelPosition = useCallback(
    (x: number, y: number) => {
      updateWorkspace((current) => ({
        ...current,
        ui: {
          ...current.ui,
          quickCommandsPanel: {
            ...(current.ui?.quickCommandsPanel ?? {
              open: defaultPanelOpen,
              x: null,
              y: null,
            }),
            x,
            y,
          },
        },
      }));
    },
    [defaultPanelOpen, updateWorkspace],
  );

  const beginDragQuickCommandsPanel = useCallback(
    (event: ReactPointerEvent<HTMLDivElement>) => {
      if (event.button !== 0) {
        return;
      }
      event.preventDefault();
      event.stopPropagation();

      const current = workspaceRef.current;
      const panel = current?.ui?.quickCommandsPanel ?? {
        open: defaultPanelOpen,
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
    [commitQuickCommandsPanelPosition, defaultPanelOpen],
  );

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
            open: defaultPanelOpen,
            x: null,
            y: null,
          }),
          x: resolvedX,
          y: resolvedY,
        },
      },
    }));
  }, [defaultPanelOpen, updateWorkspace, workspace]);

  return {
    stageRef,
    panelRef,
    panelDraft,
    beginDragQuickCommandsPanel,
  };
}
