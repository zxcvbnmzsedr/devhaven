export type SplitOrientation = "h" | "v";
export type SplitDirection = "r" | "b" | "l" | "t";

// ==================== 兼容会话快照 ====================

export type TerminalSessionSnapshot = {
  id: string;
  cwd: string;
  savedState?: string | null;
};

export type QuickCommandsPanelState = {
  open: boolean;
  x: number | null;
  y: number | null;
};

export type RunPanelTab = {
  id: string;
  title: string;
  sessionId: string;
  scriptId: string;
  createdAt: number;
  endedAt?: number | null;
  exitCode?: number | null;
};

export type RunPanelState = {
  open: boolean;
  height: number;
  activeTabId: string | null;
  tabs: RunPanelTab[];
};

export type RunConfigurationState = {
  selectedScriptId: string | null;
};

export type FileExplorerPanelState = {
  open: boolean;
  showHidden: boolean;
};

export type GitPanelState = {
  open: boolean;
};

export type TerminalRightSidebarTab = "files" | "git";

export type RightSidebarState = {
  open: boolean;
  width: number;
  tab: TerminalRightSidebarTab;
};

export type TerminalWorkspaceUi = {
  quickCommandsPanel?: QuickCommandsPanelState;
  runPanel?: RunPanelState;
  runConfiguration?: RunConfigurationState;
  fileExplorerPanel?: FileExplorerPanelState;
  gitPanel?: GitPanelState;
  rightSidebar?: RightSidebarState;
};

// ==================== 新版 runtime / layout snapshot 模型 ====================

export type TerminalWindowId = string;
export type TerminalTabId = string;
export type TerminalPaneId = string;
export type TerminalSessionId = string;
export type TerminalLayoutRevision = number;

export type TerminalPaneKind = "terminal" | "run" | "filePreview" | "gitDiff" | "overlay";
export type TerminalPanePlacement = "tree" | "runPanel" | "rightSidebar" | "overlay";

export type TerminalRestoreAnchor = {
  cwd: string;
  command?: string | null;
  profile?: string | null;
  envHash?: string | null;
  savedState?: string | null;
};

export type TerminalPaneDescriptorBase = {
  id: TerminalPaneId;
  kind: TerminalPaneKind;
  title?: string | null;
  placement?: TerminalPanePlacement;
};

export type TerminalShellPaneDescriptor = TerminalPaneDescriptorBase & {
  kind: "terminal";
  sessionId: TerminalSessionId;
  cwd: string;
  restoreAnchor?: TerminalRestoreAnchor | null;
};

export type TerminalRunPaneDescriptor = TerminalPaneDescriptorBase & {
  kind: "run";
  sessionId: TerminalSessionId;
  scriptId: string;
  restoreAnchor?: TerminalRestoreAnchor | null;
};

export type TerminalFilePreviewPaneDescriptor = TerminalPaneDescriptorBase & {
  kind: "filePreview";
  relativePath: string;
  dirty?: boolean;
};

export type TerminalGitDiffCategory = "staged" | "unstaged" | "untracked";

export type TerminalGitDiffPaneDescriptor = TerminalPaneDescriptorBase & {
  kind: "gitDiff";
  relativePath: string;
  oldRelativePath?: string | null;
  category?: TerminalGitDiffCategory;
  comparison?: "workingTree" | "staged" | "committed";
};

export type TerminalOverlayPaneDescriptor = TerminalPaneDescriptorBase & {
  kind: "overlay";
  overlayKind: string;
};

export type TerminalPaneDescriptor =
  | TerminalShellPaneDescriptor
  | TerminalRunPaneDescriptor
  | TerminalFilePreviewPaneDescriptor
  | TerminalGitDiffPaneDescriptor
  | TerminalOverlayPaneDescriptor;

export type TerminalPaneNode =
  | {
      type: "leaf";
      paneId: TerminalPaneId;
    }
  | {
      type: "split";
      orientation: SplitOrientation;
      ratios: number[];
      children: TerminalPaneNode[];
    };

export type TerminalLayoutTab = {
  id: TerminalTabId;
  title: string;
  root: TerminalPaneNode;
  activePaneId: TerminalPaneId;
  zoomedPaneId?: TerminalPaneId | null;
};

export type TerminalLayoutSnapshot = {
  version: number;
  projectId: string | null;
  projectPath: string;
  windowId?: TerminalWindowId | null;
  tabs: TerminalLayoutTab[];
  panes: Record<TerminalPaneId, TerminalPaneDescriptor>;
  activeTabId: TerminalTabId;
  ui?: TerminalWorkspaceUi;
  updatedAt: number;
  revision?: TerminalLayoutRevision;
  importedFromLegacy?: boolean;
};

export type TerminalLayoutSnapshotSummary = {
  projectPath: string;
  projectId: string | null;
  updatedAt: number | null;
  revision?: TerminalLayoutRevision | null;
};

export type TerminalWindowProjection = {
  windowId: TerminalWindowId | null;
  projectId: string | null;
  projectPath: string;
  activeTabId: TerminalTabId;
  tabs: Array<{
    id: TerminalTabId;
    title: string;
    paneIds: TerminalPaneId[];
    activePaneId: TerminalPaneId;
    zoomedPaneId: TerminalPaneId | null;
  }>;
  ui: TerminalWorkspaceUi;
  updatedAt: number;
  revision: TerminalLayoutRevision;
};

export type TerminalTabProjection = {
  windowId: TerminalWindowId | null;
  projectPath: string;
  tab: TerminalLayoutTab;
  panes: Record<TerminalPaneId, TerminalPaneProjection>;
  activePaneId: TerminalPaneId;
};

export type TerminalPaneProjection = TerminalPaneDescriptor & {
  tabId: TerminalTabId | null;
  isActive: boolean;
  isZoomed: boolean;
};

export type TerminalLayoutChangeType =
  | "snapshotLoaded"
  | "snapshotSaved"
  | "snapshotDeleted"
  | "treeChanged"
  | "uiChanged"
  | "workspaceRestored"
  | (string & {});

export type TerminalWindowLayoutChangedPayload = {
  projectPath: string;
  projectId?: string | null;
  windowId?: string | null;
  revision?: number | null;
  updatedAt?: number | null;
  changeType?: TerminalLayoutChangeType;
  deleted?: boolean;
};

export type TerminalWorkspaceRestoredPayload = {
  projectPath: string;
  projectId?: string | null;
  windowId?: string | null;
  restoredAt: number;
  importedFromLegacy?: boolean;
};

// ==================== 共享转换与投影工具 ====================

export function isTerminalLayoutSnapshot(value: unknown): value is TerminalLayoutSnapshot {
  if (!value || typeof value !== "object") {
    return false;
  }
  const candidate = value as Partial<TerminalLayoutSnapshot>;
  return Array.isArray(candidate.tabs) && typeof candidate.projectPath === "string" && candidate.panes !== undefined;
}

export function collectPaneIds(node: TerminalPaneNode): TerminalPaneId[] {
  if (node.type === "leaf") {
    return [node.paneId];
  }
  return node.children.flatMap((child) => collectPaneIds(child));
}

export function buildSessionSnapshotMap(snapshot: TerminalLayoutSnapshot): Record<string, TerminalSessionSnapshot> {
  const sessions: Record<string, TerminalSessionSnapshot> = {};
  Object.values(snapshot.panes).forEach((pane) => {
    if (pane.kind !== "terminal" && pane.kind !== "run") {
      return;
    }
    sessions[pane.sessionId] = {
      id: pane.sessionId,
      cwd: pane.kind === "terminal" ? pane.cwd : pane.restoreAnchor?.cwd ?? snapshot.projectPath,
      savedState: pane.restoreAnchor?.savedState ?? null,
    };
  });
  return sessions;
}

function findLayoutPanePath(root: TerminalPaneNode, paneId: TerminalPaneId): number[] | null {
  if (root.type === "leaf") {
    return root.paneId === paneId ? [] : null;
  }
  for (let i = 0; i < root.children.length; i += 1) {
    const result = findLayoutPanePath(root.children[i], paneId);
    if (result) {
      return [i, ...result];
    }
  }
  return null;
}

function getLayoutNodeAtPath(root: TerminalPaneNode, path: number[]): TerminalPaneNode | null {
  let current: TerminalPaneNode = root;
  for (const index of path) {
    if (current.type !== "split") {
      return null;
    }
    const next = current.children[index];
    if (!next) {
      return null;
    }
    current = next;
  }
  return current;
}

function updateLayoutNodeAtPath(
  root: TerminalPaneNode,
  path: number[],
  nextNode: TerminalPaneNode,
): TerminalPaneNode {
  if (path.length === 0) {
    return nextNode;
  }
  if (root.type !== "split") {
    return root;
  }
  const [index, ...rest] = path;
  return {
    ...root,
    children: root.children.map((child, childIndex) =>
      childIndex === index ? updateLayoutNodeAtPath(child, rest, nextNode) : child,
    ),
    ratios: normalizeLayoutRatios(root.ratios, root.children.length),
  };
}

function normalizeLayoutRatios(ratios: number[], count: number) {
  if (count <= 0) {
    return [];
  }
  let next = ratios.slice(0, count);
  if (next.length < count) {
    next = next.concat(Array.from({ length: count - next.length }, () => 1 / count));
  }
  const sum = next.reduce((total, value) => total + value, 0);
  if (!sum) {
    return Array.from({ length: count }, () => 1 / count);
  }
  return next.map((value) => value / sum);
}

function splitOrientationForDirection(direction: SplitDirection): SplitOrientation {
  return direction === "l" || direction === "r" ? "v" : "h";
}

function createSplitLayoutNode(
  primary: TerminalPaneNode,
  secondary: TerminalPaneNode,
  orientation: SplitOrientation,
  direction: SplitDirection,
): TerminalPaneNode {
  const insertBefore = direction === "l" || direction === "t";
  return {
    type: "split",
    orientation,
    children: insertBefore ? [secondary, primary] : [primary, secondary],
    ratios: [0.5, 0.5],
  };
}

function removeLayoutPaneFromNode(node: TerminalPaneNode, paneId: TerminalPaneId): TerminalPaneNode | null {
  if (node.type === "leaf") {
    return node.paneId === paneId ? null : node;
  }

  let changed = false;
  const nextChildren: TerminalPaneNode[] = [];
  const nextRatios: number[] = [];

  node.children.forEach((child, index) => {
    const nextChild = removeLayoutPaneFromNode(child, paneId);
    if (!nextChild) {
      changed = true;
      return;
    }
    if (nextChild !== child) {
      changed = true;
    }
    nextChildren.push(nextChild);
    nextRatios.push(node.ratios[index] ?? 1 / node.children.length);
  });

  if (!changed) {
    return node;
  }
  if (nextChildren.length === 0) {
    return null;
  }
  if (nextChildren.length === 1) {
    return nextChildren[0];
  }
  return {
    ...node,
    children: nextChildren,
    ratios: normalizeLayoutRatios(nextRatios, nextChildren.length),
  };
}

function createFallbackTabAndPane(
  options: {
    tabId: TerminalTabId;
    paneId: TerminalPaneId;
    sessionId: TerminalSessionId;
    title: string;
    cwd: string;
  },
): { tab: TerminalLayoutTab; pane: TerminalPaneDescriptor } {
  return {
    tab: {
      id: options.tabId,
      title: options.title,
      root: { type: "leaf", paneId: options.paneId },
      activePaneId: options.paneId,
      zoomedPaneId: null,
    },
    pane: {
      id: options.paneId,
      kind: "terminal",
      placement: "tree",
      sessionId: options.sessionId,
      cwd: options.cwd,
      restoreAnchor: {
        cwd: options.cwd,
        savedState: null,
      },
    },
  };
}

function findPaneIdBySessionId(
  snapshot: TerminalLayoutSnapshot,
  tabId: TerminalTabId,
  sessionId: TerminalSessionId,
): TerminalPaneId | null {
  const tab = snapshot.tabs.find((item) => item.id === tabId);
  if (!tab) {
    return null;
  }
  for (const paneId of collectPaneIds(tab.root)) {
    const pane = snapshot.panes[paneId];
    if ((pane?.kind === "terminal" || pane?.kind === "run") && pane.sessionId === sessionId) {
      return paneId;
    }
  }
  return null;
}

export function updateLayoutNodeRatios(
  root: TerminalPaneNode,
  path: number[],
  ratios: number[],
): TerminalPaneNode {
  const node = getLayoutNodeAtPath(root, path);
  if (!node || node.type !== "split") {
    return root;
  }
  return updateLayoutNodeAtPath(root, path, {
    ...node,
    ratios: normalizeLayoutRatios(ratios, node.children.length),
  });
}

export function appendTerminalTabToSnapshot(
  snapshot: TerminalLayoutSnapshot,
  options: {
    tabId: TerminalTabId;
    paneId: TerminalPaneId;
    sessionId: TerminalSessionId;
    title: string;
    cwd: string;
  },
): TerminalLayoutSnapshot {
  const nextTab: TerminalLayoutTab = {
    id: options.tabId,
    title: options.title,
    root: { type: "leaf", paneId: options.paneId },
    activePaneId: options.paneId,
    zoomedPaneId: null,
  };

  return {
    ...snapshot,
    activeTabId: nextTab.id,
    tabs: [...snapshot.tabs, nextTab],
    panes: {
      ...snapshot.panes,
      [options.paneId]: {
        id: options.paneId,
        kind: "terminal",
        placement: "tree",
        sessionId: options.sessionId,
        cwd: options.cwd,
        restoreAnchor: {
          cwd: options.cwd,
          savedState: null,
        },
      },
    },
  };
}

export function activateTerminalSessionInSnapshot(
  snapshot: TerminalLayoutSnapshot,
  tabId: TerminalTabId,
  sessionId: TerminalSessionId,
): TerminalLayoutSnapshot {
  const paneId = findPaneIdBySessionId(snapshot, tabId, sessionId);
  if (!paneId) {
    return snapshot;
  }
  return {
    ...snapshot,
    tabs: snapshot.tabs.map((tab) =>
      tab.id === tabId && tab.activePaneId !== paneId
        ? { ...tab, activePaneId: paneId }
        : tab,
    ),
  };
}

const DEFAULT_RUN_PANEL_HEIGHT = 240;

function getRunPanelState(snapshot: TerminalLayoutSnapshot): RunPanelState {
  return snapshot.ui?.runPanel ?? { open: false, height: DEFAULT_RUN_PANEL_HEIGHT, activeTabId: null, tabs: [] };
}

function getRunPanelPaneId(tabId: string): TerminalPaneId {
  return `run:${tabId}`;
}

function getRightSidebarState(snapshot: TerminalLayoutSnapshot): RightSidebarState {
  return snapshot.ui?.rightSidebar ?? { open: false, width: 520, tab: "files" };
}

function getFileExplorerPanelState(snapshot: TerminalLayoutSnapshot): FileExplorerPanelState {
  return snapshot.ui?.fileExplorerPanel ?? { open: false, showHidden: false };
}

function getGitPanelState(snapshot: TerminalLayoutSnapshot): GitPanelState {
  return snapshot.ui?.gitPanel ?? { open: false };
}

function resolveRunPanelActiveTabId(runPanel: RunPanelState, tabs: RunPanelTab[]): string | null {
  if (runPanel.activeTabId && tabs.some((tab) => tab.id === runPanel.activeTabId)) {
    return runPanel.activeTabId;
  }
  return tabs[tabs.length - 1]?.id ?? null;
}

export function setRunPanelOpenInSnapshot(snapshot: TerminalLayoutSnapshot, open: boolean): TerminalLayoutSnapshot {
  const runPanel = getRunPanelState(snapshot);
  if (runPanel.open === open) {
    return snapshot;
  }
  return {
    ...snapshot,
    ui: {
      ...(snapshot.ui ?? {}),
      runPanel: {
        ...runPanel,
        open,
      },
    },
  };
}

export function setRunPanelHeightInSnapshot(snapshot: TerminalLayoutSnapshot, height: number): TerminalLayoutSnapshot {
  const runPanel = getRunPanelState(snapshot);
  if (runPanel.height === height) {
    return snapshot;
  }
  return {
    ...snapshot,
    ui: {
      ...(snapshot.ui ?? {}),
      runPanel: {
        ...runPanel,
        height,
      },
    },
  };
}

export function activateRunPanelTabInSnapshot(
  snapshot: TerminalLayoutSnapshot,
  tabId: string,
  options?: { open?: boolean },
): TerminalLayoutSnapshot {
  const runPanel = getRunPanelState(snapshot);
  if (!runPanel.tabs.some((tab) => tab.id === tabId)) {
    return snapshot;
  }
  const nextOpen = options?.open ?? true;
  if (runPanel.activeTabId === tabId && runPanel.open === nextOpen) {
    return snapshot;
  }
  return {
    ...snapshot,
    ui: {
      ...(snapshot.ui ?? {}),
      runPanel: {
        ...runPanel,
        open: nextOpen,
        activeTabId: tabId,
      },
    },
  };
}

export function upsertRunPanelTabInSnapshot(
  snapshot: TerminalLayoutSnapshot,
  options: {
    tab: RunPanelTab;
    cwd?: string;
    savedState?: string | null;
    open?: boolean;
    activate?: boolean;
  },
): TerminalLayoutSnapshot {
  const runPanel = getRunPanelState(snapshot);
  const existingIndex = runPanel.tabs.findIndex((tab) => tab.id === options.tab.id);
  const nextTabs =
    existingIndex >= 0
      ? runPanel.tabs.map((tab, index) => (index === existingIndex ? options.tab : tab))
      : [...runPanel.tabs, options.tab];
  const nextOpen = options.open ?? true;
  const nextActiveTabId =
    options.activate === false
      ? resolveRunPanelActiveTabId(runPanel, nextTabs)
      : options.tab.id;
  const nextPaneId = getRunPanelPaneId(options.tab.id);
  const nextPane: TerminalRunPaneDescriptor = {
    id: nextPaneId,
    kind: "run",
    placement: "runPanel",
    title: options.tab.title,
    sessionId: options.tab.sessionId,
    scriptId: options.tab.scriptId,
    restoreAnchor: {
      cwd: options.cwd ?? snapshot.projectPath,
      savedState: options.savedState ?? null,
    },
  };

  return {
    ...snapshot,
    panes: {
      ...snapshot.panes,
      [nextPaneId]: nextPane,
    },
    ui: {
      ...(snapshot.ui ?? {}),
      runPanel: {
        ...runPanel,
        open: nextOpen,
        activeTabId: nextActiveTabId,
        tabs: nextTabs,
      },
    },
  };
}

export function removeRunPanelTabFromSnapshot(
  snapshot: TerminalLayoutSnapshot,
  tabId: string,
  options?: { keepOpenWhenEmpty?: boolean },
): TerminalLayoutSnapshot {
  const runPanel = getRunPanelState(snapshot);
  if (!runPanel.tabs.some((tab) => tab.id === tabId)) {
    return snapshot;
  }
  const nextTabs = runPanel.tabs.filter((tab) => tab.id !== tabId);
  const nextActiveTabId = resolveRunPanelActiveTabId(
    {
      ...runPanel,
      activeTabId: runPanel.activeTabId === tabId ? null : runPanel.activeTabId,
    },
    nextTabs,
  );
  const nextPanes = { ...snapshot.panes };
  delete nextPanes[getRunPanelPaneId(tabId)];
  return {
    ...snapshot,
    panes: nextPanes,
    ui: {
      ...(snapshot.ui ?? {}),
      runPanel: {
        ...runPanel,
        open: nextTabs.length > 0 ? runPanel.open : Boolean(options?.keepOpenWhenEmpty),
        activeTabId: nextActiveTabId,
        tabs: nextTabs,
      },
    },
  };
}

export function removeRunPanelSessionFromSnapshot(
  snapshot: TerminalLayoutSnapshot,
  sessionId: string,
  options?: { keepOpenWhenEmpty?: boolean },
): TerminalLayoutSnapshot {
  const runPanel = getRunPanelState(snapshot);
  const tab = runPanel.tabs.find((item) => item.sessionId === sessionId);
  if (!tab) {
    return snapshot;
  }
  return removeRunPanelTabFromSnapshot(snapshot, tab.id, options);
}

export function syncRunPanelTabsInSnapshot(
  snapshot: TerminalLayoutSnapshot,
  validSessionIds: Iterable<string>,
): TerminalLayoutSnapshot {
  const validSessionSet = new Set(validSessionIds);
  const runPanel = getRunPanelState(snapshot);
  const nextTabs = runPanel.tabs.filter((tab) => validSessionSet.has(tab.sessionId));
  const nextOpen = nextTabs.length > 0 ? runPanel.open : false;
  const nextActiveTabId = resolveRunPanelActiveTabId(runPanel, nextTabs);
  const retainedPaneIds = new Set(nextTabs.map((tab) => getRunPanelPaneId(tab.id)));
  let nextPanes: Record<TerminalPaneId, TerminalPaneDescriptor> | null = null;

  Object.entries(snapshot.panes).forEach(([paneId, pane]) => {
    if (pane.kind !== "run") {
      return;
    }
    if (retainedPaneIds.has(paneId) && validSessionSet.has(pane.sessionId)) {
      return;
    }
    if (!nextPanes) {
      nextPanes = { ...snapshot.panes };
    }
    delete nextPanes[paneId];
  });

  if (
    nextTabs.length === runPanel.tabs.length &&
    nextOpen === runPanel.open &&
    nextActiveTabId === runPanel.activeTabId &&
    !nextPanes
  ) {
    return snapshot;
  }

  return {
    ...snapshot,
    panes: nextPanes ?? snapshot.panes,
    ui: {
      ...(snapshot.ui ?? {}),
      runPanel: {
        ...runPanel,
        open: nextOpen,
        activeTabId: nextActiveTabId,
        tabs: nextTabs,
      },
    },
  };
}

export function markRunPanelTabExitedInSnapshot(
  snapshot: TerminalLayoutSnapshot,
  sessionId: string,
  result: {
    endedAt: number;
    exitCode: number | null;
  },
): TerminalLayoutSnapshot {
  const runPanel = getRunPanelState(snapshot);
  let changed = false;
  const nextTabs = runPanel.tabs.map((tab) => {
    if (tab.sessionId !== sessionId) {
      return tab;
    }
    if (tab.endedAt === result.endedAt && tab.exitCode === result.exitCode) {
      return tab;
    }
    changed = true;
    return {
      ...tab,
      endedAt: result.endedAt,
      exitCode: result.exitCode,
    };
  });

  if (!changed) {
    return snapshot;
  }

  return {
    ...snapshot,
    ui: {
      ...(snapshot.ui ?? {}),
      runPanel: {
        ...runPanel,
        tabs: nextTabs,
      },
    },
  };
}

export function updateRightSidebarStateInSnapshot(
  snapshot: TerminalLayoutSnapshot,
  updater: (current: RightSidebarState) => RightSidebarState,
): TerminalLayoutSnapshot {
  const rightSidebar = getRightSidebarState(snapshot);
  const filePanel = getFileExplorerPanelState(snapshot);
  const gitPanel = getGitPanelState(snapshot);
  const nextRightSidebar = updater(rightSidebar);

  if (
    nextRightSidebar.open === rightSidebar.open &&
    nextRightSidebar.width === rightSidebar.width &&
    nextRightSidebar.tab === rightSidebar.tab
  ) {
    return snapshot;
  }

  return {
    ...snapshot,
    ui: {
      ...(snapshot.ui ?? {}),
      rightSidebar: nextRightSidebar,
      fileExplorerPanel: {
        ...filePanel,
        open: nextRightSidebar.open && nextRightSidebar.tab === "files",
      },
      gitPanel: {
        ...gitPanel,
        open: nextRightSidebar.open && nextRightSidebar.tab === "git",
      },
    },
  };
}

export function setFileExplorerShowHiddenInSnapshot(
  snapshot: TerminalLayoutSnapshot,
  showHidden: boolean,
): TerminalLayoutSnapshot {
  const filePanel = getFileExplorerPanelState(snapshot);
  if (filePanel.showHidden === showHidden) {
    return snapshot;
  }
  return {
    ...snapshot,
    ui: {
      ...(snapshot.ui ?? {}),
      fileExplorerPanel: {
        ...filePanel,
        showHidden,
      },
    },
  };
}

export function upsertFilePreviewPaneInSnapshot(
  snapshot: TerminalLayoutSnapshot,
  options: {
    paneId: TerminalPaneId;
    relativePath: string;
    dirty: boolean;
  },
): TerminalLayoutSnapshot {
  const nextPane: TerminalFilePreviewPaneDescriptor = {
    id: options.paneId,
    kind: "filePreview",
    placement: "rightSidebar",
    title: options.relativePath.split("/").pop() ?? options.relativePath,
    relativePath: options.relativePath,
    dirty: options.dirty,
  };
  const currentPane = snapshot.panes[options.paneId];
  if (
    currentPane?.kind === "filePreview" &&
    currentPane.relativePath === nextPane.relativePath &&
    Boolean(currentPane.dirty) === nextPane.dirty &&
    currentPane.title === nextPane.title
  ) {
    return snapshot;
  }
  return {
    ...snapshot,
    panes: {
      ...snapshot.panes,
      [options.paneId]: nextPane,
    },
  };
}

export function selectRightSidebarPreviewPane(
  snapshot: TerminalLayoutSnapshot,
  paneId: TerminalPaneId,
): TerminalFilePreviewPaneDescriptor | null {
  const pane = snapshot.panes[paneId];
  return pane?.kind === "filePreview" ? pane : null;
}

export function upsertGitDiffPaneInSnapshot(
  snapshot: TerminalLayoutSnapshot,
  options: {
    paneId: TerminalPaneId;
    relativePath: string;
    oldRelativePath?: string | null;
    category: TerminalGitDiffCategory;
  },
): TerminalLayoutSnapshot {
  const comparison =
    options.category === "staged"
      ? "staged"
      : options.category === "unstaged" || options.category === "untracked"
        ? "workingTree"
        : undefined;
  const nextPane: TerminalGitDiffPaneDescriptor = {
    id: options.paneId,
    kind: "gitDiff",
    placement: "rightSidebar",
    title: options.relativePath.split("/").pop() ?? options.relativePath,
    relativePath: options.relativePath,
    oldRelativePath: options.oldRelativePath ?? null,
    category: options.category,
    comparison,
  };
  const currentPane = snapshot.panes[options.paneId];
  if (
    currentPane?.kind === "gitDiff" &&
    currentPane.relativePath === nextPane.relativePath &&
    (currentPane.oldRelativePath ?? null) === nextPane.oldRelativePath &&
    currentPane.category === nextPane.category &&
    currentPane.comparison === nextPane.comparison &&
    currentPane.title === nextPane.title
  ) {
    return snapshot;
  }
  return {
    ...snapshot,
    panes: {
      ...snapshot.panes,
      [options.paneId]: nextPane,
    },
  };
}

export function selectRightSidebarGitDiffPane(
  snapshot: TerminalLayoutSnapshot,
  paneId: TerminalPaneId,
): TerminalGitDiffPaneDescriptor | null {
  const pane = snapshot.panes[paneId];
  return pane?.kind === "gitDiff" ? pane : null;
}

export function removePaneFromSnapshot(
  snapshot: TerminalLayoutSnapshot,
  paneId: TerminalPaneId,
): TerminalLayoutSnapshot {
  if (!snapshot.panes[paneId]) {
    return snapshot;
  }
  const nextPanes = { ...snapshot.panes };
  delete nextPanes[paneId];
  return {
    ...snapshot,
    panes: nextPanes,
  };
}

export function splitTerminalSessionInSnapshot(
  snapshot: TerminalLayoutSnapshot,
  options: {
    tabId: TerminalTabId;
    targetSessionId: TerminalSessionId;
    direction: SplitDirection;
    newPaneId: TerminalPaneId;
    newSessionId: TerminalSessionId;
    cwd: string;
  },
): TerminalLayoutSnapshot {
  const tabIndex = snapshot.tabs.findIndex((tab) => tab.id === options.tabId);
  if (tabIndex < 0) {
    return snapshot;
  }
  const tab = snapshot.tabs[tabIndex];
  const targetPaneId = findPaneIdBySessionId(snapshot, tab.id, options.targetSessionId);
  if (!targetPaneId) {
    return snapshot;
  }
  const targetPath = findLayoutPanePath(tab.root, targetPaneId);
  if (!targetPath) {
    return snapshot;
  }

  const orientation = splitOrientationForDirection(options.direction);
  const newLeaf: TerminalPaneNode = { type: "leaf", paneId: options.newPaneId };
  let nextRoot: TerminalPaneNode;

  if (targetPath.length === 0) {
    nextRoot = createSplitLayoutNode(tab.root, newLeaf, orientation, options.direction);
  } else {
    const parentPath = targetPath.slice(0, -1);
    const targetIndex = targetPath[targetPath.length - 1];
    const parentNode = getLayoutNodeAtPath(tab.root, parentPath);
    if (!parentNode || parentNode.type !== "split") {
      return snapshot;
    }
    if (parentNode.orientation === orientation) {
      const insertBefore = options.direction === "l" || options.direction === "t";
      const insertIndex = insertBefore ? targetIndex : targetIndex + 1;
      const nextChildren = [...parentNode.children];
      nextChildren.splice(insertIndex, 0, newLeaf);
      const nextRatios = [...parentNode.ratios];
      const baseRatio = nextRatios[targetIndex] ?? 1 / parentNode.children.length;
      const half = baseRatio / 2;
      if (insertBefore) {
        nextRatios.splice(insertIndex, 0, half);
        nextRatios[targetIndex + 1] = half;
      } else {
        nextRatios[targetIndex] = half;
        nextRatios.splice(insertIndex, 0, half);
      }
      nextRoot = updateLayoutNodeAtPath(tab.root, parentPath, {
        ...parentNode,
        children: nextChildren,
        ratios: normalizeLayoutRatios(nextRatios, nextChildren.length),
      });
    } else {
      const targetNode = getLayoutNodeAtPath(tab.root, targetPath);
      if (!targetNode) {
        return snapshot;
      }
      nextRoot = updateLayoutNodeAtPath(
        tab.root,
        targetPath,
        createSplitLayoutNode(targetNode, newLeaf, orientation, options.direction),
      );
    }
  }

  const nextTab: TerminalLayoutTab = {
    ...tab,
    root: nextRoot,
    activePaneId: options.newPaneId,
  };

  return {
    ...snapshot,
    tabs: snapshot.tabs.map((item, index) => (index === tabIndex ? nextTab : item)),
    panes: {
      ...snapshot.panes,
      [options.newPaneId]: {
        id: options.newPaneId,
        kind: "terminal",
        placement: "tree",
        sessionId: options.newSessionId,
        cwd: options.cwd,
        restoreAnchor: {
          cwd: options.cwd,
          savedState: null,
        },
      },
    },
  };
}

export function removeTerminalSessionFromSnapshot(
  snapshot: TerminalLayoutSnapshot,
  sessionId: TerminalSessionId,
  options: {
    createFallbackTab: () => {
      tabId: TerminalTabId;
      paneId: TerminalPaneId;
      sessionId: TerminalSessionId;
      title: string;
      cwd: string;
    };
  },
): TerminalLayoutSnapshot {
  const tabIndex = snapshot.tabs.findIndex((tab) =>
    collectPaneIds(tab.root).some((paneId) => {
      const pane = snapshot.panes[paneId];
      return pane?.kind === "terminal" && pane.sessionId === sessionId;
    }),
  );
  if (tabIndex < 0) {
    return snapshot;
  }
  const tab = snapshot.tabs[tabIndex];
  const targetPaneId = findPaneIdBySessionId(snapshot, tab.id, sessionId);
  if (!targetPaneId) {
    return snapshot;
  }
  const beforePaneIds = collectPaneIds(tab.root);
  const nextRoot = removeLayoutPaneFromNode(tab.root, targetPaneId);
  const nextPanes = { ...snapshot.panes };

  if (!nextRoot) {
    beforePaneIds.forEach((paneId) => {
      delete nextPanes[paneId];
    });
    const remainingTabs = snapshot.tabs.filter((item) => item.id !== tab.id);
    if (remainingTabs.length === 0) {
      const fallback = createFallbackTabAndPane(options.createFallbackTab());
      return {
        ...snapshot,
        activeTabId: fallback.tab.id,
        tabs: [fallback.tab],
        panes: {
          ...nextPanes,
          [fallback.pane.id]: fallback.pane,
        },
      };
    }
    return {
      ...snapshot,
      activeTabId: snapshot.activeTabId === tab.id ? remainingTabs[0].id : snapshot.activeTabId,
      tabs: remainingTabs,
      panes: nextPanes,
    };
  }

  const afterPaneIds = collectPaneIds(nextRoot);
  beforePaneIds
    .filter((paneId) => !afterPaneIds.includes(paneId))
    .forEach((paneId) => {
      delete nextPanes[paneId];
    });

  const nextActivePaneId = afterPaneIds.includes(tab.activePaneId) ? tab.activePaneId : afterPaneIds[0];
  const nextTab: TerminalLayoutTab = {
    ...tab,
    root: nextRoot,
    activePaneId: nextActivePaneId,
    zoomedPaneId: tab.zoomedPaneId && afterPaneIds.includes(tab.zoomedPaneId) ? tab.zoomedPaneId : null,
  };
  return {
    ...snapshot,
    tabs: snapshot.tabs.map((item, index) => (index === tabIndex ? nextTab : item)),
    panes: nextPanes,
  };
}

export function removeTerminalTabFromSnapshot(
  snapshot: TerminalLayoutSnapshot,
  tabId: TerminalTabId,
  fallback: {
    tabId: TerminalTabId;
    paneId: TerminalPaneId;
    sessionId: TerminalSessionId;
    title: string;
    cwd: string;
  },
): TerminalLayoutSnapshot {
  const tab = snapshot.tabs.find((item) => item.id === tabId);
  if (!tab) {
    return snapshot;
  }
  const nextPanes = { ...snapshot.panes };
  collectPaneIds(tab.root).forEach((paneId) => {
    delete nextPanes[paneId];
  });
  const remainingTabs = snapshot.tabs.filter((item) => item.id !== tabId);
  if (remainingTabs.length === 0) {
    const fallbackEntry = createFallbackTabAndPane(fallback);
    return {
      ...snapshot,
      activeTabId: fallbackEntry.tab.id,
      tabs: [fallbackEntry.tab],
      panes: {
        ...nextPanes,
        [fallbackEntry.pane.id]: fallbackEntry.pane,
      },
    };
  }
  return {
    ...snapshot,
    activeTabId: snapshot.activeTabId === tabId ? remainingTabs[0].id : snapshot.activeTabId,
    tabs: remainingTabs,
    panes: nextPanes,
  };
}

export function projectWindowProjection(snapshot: TerminalLayoutSnapshot): TerminalWindowProjection {
  return {
    windowId: snapshot.windowId ?? null,
    projectId: snapshot.projectId,
    projectPath: snapshot.projectPath,
    activeTabId: snapshot.activeTabId,
    tabs: snapshot.tabs.map((tab) => ({
      id: tab.id,
      title: tab.title,
      paneIds: collectPaneIds(tab.root),
      activePaneId: tab.activePaneId,
      zoomedPaneId: tab.zoomedPaneId ?? null,
    })),
    ui: snapshot.ui ?? {},
    updatedAt: snapshot.updatedAt,
    revision: snapshot.revision ?? snapshot.updatedAt,
  };
}

export function projectTabProjection(
  snapshot: TerminalLayoutSnapshot,
  tabId: TerminalTabId | null | undefined,
): TerminalTabProjection | null {
  const tab = snapshot.tabs.find((item) => item.id === (tabId ?? snapshot.activeTabId)) ?? snapshot.tabs[0] ?? null;
  if (!tab) {
    return null;
  }
  const paneIds = collectPaneIds(tab.root);
  const panes: Record<string, TerminalPaneProjection> = {};
  paneIds.forEach((paneId) => {
    const pane = snapshot.panes[paneId];
    if (!pane) {
      return;
    }
    panes[paneId] = {
      ...pane,
      tabId: tab.id,
      isActive: paneId === tab.activePaneId,
      isZoomed: paneId === (tab.zoomedPaneId ?? null),
    };
  });
  return {
    windowId: snapshot.windowId ?? null,
    projectPath: snapshot.projectPath,
    tab,
    panes,
    activePaneId: tab.activePaneId,
  };
}

export function projectPaneProjection(
  snapshot: TerminalLayoutSnapshot,
  paneId: TerminalPaneId,
): TerminalPaneProjection | null {
  for (const tab of snapshot.tabs) {
    if (!collectPaneIds(tab.root).includes(paneId)) {
      continue;
    }
    const pane = snapshot.panes[paneId];
    if (!pane) {
      return null;
    }
    return {
      ...pane,
      tabId: tab.id,
      isActive: paneId === tab.activePaneId,
      isZoomed: paneId === (tab.zoomedPaneId ?? null),
    };
  }

  const pane = snapshot.panes[paneId];
  if (!pane) {
    return null;
  }
  return {
    ...pane,
    tabId: null,
    isActive: false,
    isZoomed: false,
  };
}
