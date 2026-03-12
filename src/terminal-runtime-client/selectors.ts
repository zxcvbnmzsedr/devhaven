import type {
  RunPanelTab,
  TerminalLayoutSnapshot,
  TerminalPaneDescriptor,
  TerminalPaneId,
  TerminalPaneProjection,
  TerminalTabId,
  TerminalTabProjection,
  TerminalWindowProjection,
} from "../models/terminal.ts";
import {
  collectPaneIds,
  projectPaneProjection,
  projectTabProjection,
  projectWindowProjection,
} from "../models/terminal.ts";

export function selectWindowProjection(snapshot: TerminalLayoutSnapshot): TerminalWindowProjection {
  return projectWindowProjection(snapshot);
}

export function selectTabProjection(
  snapshot: TerminalLayoutSnapshot,
  tabId?: TerminalTabId | null,
): TerminalTabProjection | null {
  return projectTabProjection(snapshot, tabId);
}

export function selectPaneProjection(
  snapshot: TerminalLayoutSnapshot,
  paneId: TerminalPaneId,
): TerminalPaneProjection | null {
  return projectPaneProjection(snapshot, paneId);
}

export function selectActivePaneId(snapshot: TerminalLayoutSnapshot, tabId?: string | null): string | null {
  const tab = snapshot.tabs.find((item) => item.id === (tabId ?? snapshot.activeTabId)) ?? snapshot.tabs[0] ?? null;
  return tab?.activePaneId ?? null;
}

export function selectTreePaneIds(snapshot: TerminalLayoutSnapshot, tabId?: string | null): string[] {
  const tab = snapshot.tabs.find((item) => item.id === (tabId ?? snapshot.activeTabId)) ?? snapshot.tabs[0] ?? null;
  return tab ? collectPaneIds(tab.root) : [];
}

export function selectRunPanelTabs(snapshot: TerminalLayoutSnapshot): RunPanelTab[] {
  return snapshot.ui?.runPanel?.tabs ?? [];
}

export function selectRunPanelDescriptors(snapshot: TerminalLayoutSnapshot): TerminalPaneDescriptor[] {
  const runTabs = snapshot.ui?.runPanel?.tabs ?? [];
  return runTabs
    .map((tab) => snapshot.panes[`run:${tab.id}`] ?? snapshot.panes[tab.id] ?? null)
    .filter((pane): pane is TerminalPaneDescriptor => Boolean(pane));
}
