import type { GitSelectedFile } from "./TerminalGitPanel";
import type {
  RunPanelTab,
  TerminalFilePreviewPaneDescriptor,
  TerminalGitDiffPaneDescriptor,
  TerminalLayoutSnapshot,
  TerminalPaneProjection,
  TerminalRightSidebarTab,
  TerminalWindowProjection,
  TerminalTabProjection,
} from "../../models/terminal";
import {
  selectRunPanelTabs,
  selectTabProjection,
  selectWindowProjection,
} from "../../terminal-runtime-client/selectors.ts";
import {
  selectRightSidebarGitDiffPane,
  selectRightSidebarPreviewPane,
} from "../../models/terminal.ts";

export type TerminalWorkspaceShellModel = {
  windowProjection: TerminalWindowProjection;
  headerTabs: Array<Pick<TerminalWindowProjection["tabs"][number], "id" | "title">>;
  activeTabId: string;
  activeTabProjection: TerminalTabProjection | null;
  activeWorkspaceTab: TerminalTabProjection["tab"] | null;
  activePaneProjections: Record<string, TerminalPaneProjection>;
  selectedRunConfigurationId: string | null;
  runPanelTabs: RunPanelTab[];
  runPanelActiveTabId: string | null;
  runPanelOpen: boolean;
  runPanelHeight: number;
  activeRunTab: RunPanelTab | null;
  rightSidebarOpen: boolean;
  rightSidebarWidth: number;
  rightSidebarTab: TerminalRightSidebarTab;
  filePanelShowHidden: boolean;
  previewPane: TerminalFilePreviewPaneDescriptor | null;
  previewFilePath: string | null;
  previewDirty: boolean;
  gitDiffPane: TerminalGitDiffPaneDescriptor | null;
  gitSelected: GitSelectedFile | null;
};

export type TerminalWorkspaceShellModelOptions = {
  isGitRepo: boolean;
  defaultFileExplorerPanelOpen: boolean;
  defaultFileExplorerShowHidden: boolean;
  minRunPanelHeight: number;
  minRightSidebarWidth: number;
  maxRightSidebarWidth: number;
};

const DEFAULT_RIGHT_SIDEBAR = {
  open: false,
  width: 520,
  tab: "files",
} as const;

const DEFAULT_RUN_PANEL_HEIGHT = 240;

export function buildTerminalWorkspaceShellModel(
  snapshot: TerminalLayoutSnapshot,
  options: TerminalWorkspaceShellModelOptions,
): TerminalWorkspaceShellModel {
  const windowProjection = selectWindowProjection(snapshot);
  const activeTabProjection = selectTabProjection(snapshot, snapshot.activeTabId);
  const runPanelState = snapshot.ui?.runPanel ?? {
    open: false,
    height: DEFAULT_RUN_PANEL_HEIGHT,
    activeTabId: null,
    tabs: [],
  };
  const runPanelTabs = selectRunPanelTabs(snapshot);
  const runPanelActiveTabId =
    runPanelState.activeTabId && runPanelTabs.some((tab) => tab.id === runPanelState.activeTabId)
      ? runPanelState.activeTabId
      : runPanelTabs[runPanelTabs.length - 1]?.id ?? null;
  const activeRunTab = runPanelActiveTabId
    ? runPanelTabs.find((tab) => tab.id === runPanelActiveTabId) ?? null
    : null;
  const rightSidebarState = snapshot.ui?.rightSidebar ?? DEFAULT_RIGHT_SIDEBAR;
  const previewPane = selectRightSidebarPreviewPane(
    snapshot,
    "right-sidebar:file-preview",
  ) as TerminalFilePreviewPaneDescriptor | null;
  const gitDiffPane = selectRightSidebarGitDiffPane(
    snapshot,
    "right-sidebar:git-diff",
  ) as TerminalGitDiffPaneDescriptor | null;

  return {
    windowProjection,
    headerTabs: windowProjection.tabs.map((tab) => ({
      id: tab.id,
      title: tab.title,
    })),
    activeTabId: windowProjection.activeTabId,
    activeTabProjection,
    activeWorkspaceTab: activeTabProjection?.tab ?? null,
    activePaneProjections: activeTabProjection?.panes ?? {},
    selectedRunConfigurationId: snapshot.ui?.runConfiguration?.selectedScriptId ?? null,
    runPanelTabs,
    runPanelActiveTabId,
    runPanelOpen: Boolean(runPanelState.open && runPanelTabs.length > 0),
    runPanelHeight: Math.max(
      options.minRunPanelHeight,
      Math.min(720, runPanelState.height ?? DEFAULT_RUN_PANEL_HEIGHT),
    ),
    activeRunTab,
    rightSidebarOpen: Boolean(rightSidebarState.open),
    rightSidebarWidth: Math.max(
      options.minRightSidebarWidth,
      Math.min(options.maxRightSidebarWidth, rightSidebarState.width),
    ),
    rightSidebarTab:
      rightSidebarState.tab === "git" && !options.isGitRepo ? "files" : rightSidebarState.tab,
    filePanelShowHidden:
      snapshot.ui?.fileExplorerPanel?.showHidden ?? options.defaultFileExplorerShowHidden,
    previewPane,
    previewFilePath: previewPane?.relativePath ?? null,
    previewDirty: Boolean(previewPane?.dirty),
    gitDiffPane,
    gitSelected: gitDiffPane
      ? {
          category: gitDiffPane.category ?? "unstaged",
          path: gitDiffPane.relativePath,
          oldPath: gitDiffPane.oldRelativePath ?? null,
        }
      : null,
  };
}
