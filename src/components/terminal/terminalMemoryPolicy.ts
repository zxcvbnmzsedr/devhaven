export type CountVisibleTerminalPanesOptions = {
  activePaneKinds: string[];
  hasVisibleRunPanelTab: boolean;
};

export type ShouldEnableTerminalWebglOptions = {
  terminalUseWebglRenderer: boolean;
  workspaceVisible: boolean;
  visibleTerminalPaneCount: number;
};

const TERMINAL_PANE_KINDS = new Set(["terminal", "run"]);

export function countVisibleTerminalPanes({
  activePaneKinds,
  hasVisibleRunPanelTab,
}: CountVisibleTerminalPanesOptions): number {
  const workspacePaneCount = activePaneKinds.reduce((count, kind) => {
    return TERMINAL_PANE_KINDS.has(kind) ? count + 1 : count;
  }, 0);

  return workspacePaneCount + (hasVisibleRunPanelTab ? 1 : 0);
}

export function shouldEnableTerminalWebgl({
  terminalUseWebglRenderer,
  workspaceVisible,
  visibleTerminalPaneCount,
}: ShouldEnableTerminalWebglOptions): boolean {
  return terminalUseWebglRenderer && workspaceVisible && visibleTerminalPaneCount === 1;
}
