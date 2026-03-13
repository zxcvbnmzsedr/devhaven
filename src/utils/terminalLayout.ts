import type {
  QuickCommandsPanelState,
  RightSidebarState,
  TerminalLayoutSnapshot,
  TerminalLayoutTab,
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
const TERMINAL_TITLE_PATTERN = /^终端\s*(\d+)$/;

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

function getNextTerminalTitle(tabs: Array<Pick<TerminalLayoutTab, "title">>) {
  const used = new Set<number>();
  for (const tab of tabs) {
    const match = tab.title.match(TERMINAL_TITLE_PATTERN);
    if (!match) {
      continue;
    }
    const value = Number(match[1]);
    if (Number.isInteger(value) && value > 0) {
      used.add(value);
    }
  }
  let next = 1;
  while (used.has(next)) {
    next += 1;
  }
  return `终端 ${next}`;
}

export function normalizeLayoutSnapshotForShellPrimitives(
  snapshot: TerminalLayoutSnapshot,
  options?: {
    createSessionId?: () => string;
  },
): TerminalLayoutSnapshot {
  const createSessionId = options?.createSessionId ?? createId;
  let changed = false;
  const nextPanes = { ...snapshot.panes };
  const nextTabs = snapshot.tabs.map((tab) => {
    const activePane = nextPanes[tab.activePaneId];
    if (activePane?.kind !== "pendingTerminal") {
      return tab;
    }
    changed = true;
    const nextTitle =
      tab.title && tab.title !== "新建 Pane" ? tab.title : getNextTerminalTitle(snapshot.tabs);
    nextPanes[tab.activePaneId] = {
      id: activePane.id,
      kind: "terminal",
      placement: activePane.placement ?? "tree",
      title: nextTitle,
      sessionId: createSessionId(),
      cwd: snapshot.projectPath,
      restoreAnchor: {
        cwd: snapshot.projectPath,
        savedState: null,
      },
    };
    return {
      ...tab,
      title: nextTitle,
    };
  });

  if (!changed) {
    return snapshot;
  }

  return {
    ...snapshot,
    tabs: nextTabs,
    panes: nextPanes,
  };
}

export function createDefaultLayoutSnapshot(
  projectPath: string,
  projectId: string | null,
  defaults?: TerminalWorkspaceDefaults,
): TerminalLayoutSnapshot {
  const tabId = createId();
  const paneId = `pane:${createId()}`;
  const sessionId = createId();
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
        title: "终端 1",
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
