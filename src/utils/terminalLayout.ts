import type {
  QuickCommandsPanelState,
  RightSidebarState,
  TerminalLayoutSnapshot,
  TerminalRightSidebarTab,
  TerminalWorkspaceUi,
} from "../models/terminal";

const FALLBACK_ID_CHARS = "abcdefghijklmnopqrstuvwxyz0123456789";
const DEFAULT_PANEL_OPEN = true;
const DEFAULT_RUN_PANEL_HEIGHT = 240;
const DEFAULT_RUN_CONFIGURATION_SCRIPT_ID: string | null = null;
const DEFAULT_FILE_PANEL_SHOW_HIDDEN = false;
const DEFAULT_RIGHT_SIDEBAR_WIDTH = 520;
const DEFAULT_RIGHT_SIDEBAR_TAB: TerminalRightSidebarTab = "files";

export type TerminalWorkspaceDefaults = {
  defaultQuickCommandsPanelOpen?: boolean;
  defaultRunPanelOpen?: boolean;
  defaultRunPanelHeight?: number;
  defaultFileExplorerPanelOpen?: boolean;
  defaultFileExplorerShowHidden?: boolean;
  defaultGitPanelOpen?: boolean;
  defaultRightSidebarOpen?: boolean;
  defaultRightSidebarWidth?: number;
  defaultRightSidebarTab?: TerminalRightSidebarTab;
};

function createDefaultLayoutSnapshotUi(defaults?: TerminalWorkspaceDefaults): TerminalWorkspaceUi {
  const quickCommandsPanel: QuickCommandsPanelState = {
    open: defaults?.defaultQuickCommandsPanelOpen ?? DEFAULT_PANEL_OPEN,
    x: null,
    y: null,
  };
  const sidebarTab: TerminalRightSidebarTab =
    defaults?.defaultGitPanelOpen && !defaults?.defaultFileExplorerPanelOpen
      ? "git"
      : defaults?.defaultRightSidebarTab ?? DEFAULT_RIGHT_SIDEBAR_TAB;
  const sidebarOpen = Boolean(
    defaults?.defaultRightSidebarOpen ||
      defaults?.defaultFileExplorerPanelOpen ||
      defaults?.defaultGitPanelOpen,
  );
  const rightSidebar: RightSidebarState = {
    open: sidebarOpen,
    width: defaults?.defaultRightSidebarWidth ?? DEFAULT_RIGHT_SIDEBAR_WIDTH,
    tab: sidebarTab,
  };
  return {
    quickCommandsPanel,
    runPanel: {
      open: false,
      height: defaults?.defaultRunPanelHeight ?? DEFAULT_RUN_PANEL_HEIGHT,
      activeTabId: null,
      tabs: [],
    },
    runConfiguration: {
      selectedScriptId: DEFAULT_RUN_CONFIGURATION_SCRIPT_ID,
    },
    fileExplorerPanel: {
      open: rightSidebar.open && rightSidebar.tab === "files",
      showHidden: defaults?.defaultFileExplorerShowHidden ?? DEFAULT_FILE_PANEL_SHOW_HIDDEN,
    },
    gitPanel: {
      open: rightSidebar.open && rightSidebar.tab === "git",
    },
    rightSidebar,
  };
}

export function createId() {
  // 部分 WebView/旧版本环境里 `crypto.randomUUID` 可能不存在或不是函数；用更严格的判断避免运行时崩溃。
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  let value = "";
  for (let i = 0; i < 16; i += 1) {
    value += FALLBACK_ID_CHARS[Math.floor(Math.random() * FALLBACK_ID_CHARS.length)];
  }
  return value;
}

export function createDefaultLayoutSnapshot(
  projectPath: string,
  projectId: string | null,
  defaults?: TerminalWorkspaceDefaults,
): TerminalLayoutSnapshot {
  const sessionId = createId();
  const tabId = createId();
  const paneId = `pane:${sessionId}`;
  const now = Date.now();
  return {
    version: 2,
    projectId,
    projectPath,
    activeTabId: tabId,
    tabs: [
      {
        id: tabId,
        title: "终端 1",
        root: { type: "leaf", paneId },
        activePaneId: paneId,
        zoomedPaneId: null,
      },
    ],
    panes: {
      [paneId]: {
        id: paneId,
        kind: "terminal",
        placement: "tree",
        sessionId,
        cwd: projectPath,
        restoreAnchor: {
          cwd: projectPath,
          savedState: null,
        },
      },
    },
    ui: createDefaultLayoutSnapshotUi(defaults),
    updatedAt: now,
    revision: now,
  };
}
