import test from "node:test";
import assert from "node:assert/strict";

import {
  activateTerminalSessionInSnapshot,
  appendTerminalTabToSnapshot,
  collectPaneIds,
  markRunPanelTabExitedInSnapshot,
  removePaneFromSnapshot,
  removeTerminalSessionFromSnapshot,
  removeTerminalTabFromSnapshot,
  removeRunPanelTabFromSnapshot,
  selectRightSidebarPreviewPane,
  selectRightSidebarGitDiffPane,
  setFileExplorerShowHiddenInSnapshot,
  splitTerminalSessionInSnapshot,
  syncRunPanelTabsInSnapshot,
  updateRightSidebarStateInSnapshot,
  upsertGitDiffPaneInSnapshot,
  upsertRunPanelTabInSnapshot,
  upsertFilePreviewPaneInSnapshot,
  updateLayoutNodeRatios,
} from "./terminal.ts";
import { createDefaultLayoutSnapshot } from "../utils/terminalLayout.ts";

function createSnapshot() {
  return {
    version: 2,
    projectId: "project-1",
    projectPath: "/repo",
    activeTabId: "tab-1",
    updatedAt: 1,
    revision: 1,
    tabs: [
      {
        id: "tab-1",
        title: "终端 1",
        activePaneId: "pane-1",
        root: {
          type: "leaf",
          paneId: "pane-1",
        },
      },
    ],
    panes: {
      "pane-1": {
        id: "pane-1",
        kind: "terminal",
        placement: "tree",
        sessionId: "session-1",
        cwd: "/repo",
        restoreAnchor: {
          cwd: "/repo",
        },
      },
    },
    ui: {},
  };
}

test("appendTerminalTabToSnapshot adds a new active terminal tab", () => {
  const snapshot = appendTerminalTabToSnapshot(createSnapshot(), {
    tabId: "tab-2",
    paneId: "pane-2",
    sessionId: "session-2",
    title: "终端 2",
    cwd: "/repo",
  });

  assert.equal(snapshot.activeTabId, "tab-2");
  assert.equal(snapshot.tabs.length, 2);
  assert.equal(snapshot.tabs[1]?.activePaneId, "pane-2");
  assert.equal(snapshot.panes["pane-2"]?.kind, "terminal");
});

test("activateTerminalSessionInSnapshot updates the active pane of a tab", () => {
  const splitSnapshot = splitTerminalSessionInSnapshot(createSnapshot(), {
    tabId: "tab-1",
    targetSessionId: "session-1",
    direction: "r",
    newPaneId: "pane-2",
    newSessionId: "session-2",
    cwd: "/repo",
  });

  const snapshot = activateTerminalSessionInSnapshot(splitSnapshot, "tab-1", "session-1");
  const tab = snapshot.tabs[0];
  assert.equal(tab?.activePaneId, "pane-1");
});

test("splitTerminalSessionInSnapshot inserts a new pane and activates it", () => {
  const snapshot = splitTerminalSessionInSnapshot(createSnapshot(), {
    tabId: "tab-1",
    targetSessionId: "session-1",
    direction: "r",
    newPaneId: "pane-2",
    newSessionId: "session-2",
    cwd: "/repo",
  });

  const tab = snapshot.tabs[0];
  assert.equal(tab?.activePaneId, "pane-2");
  assert.deepEqual(collectPaneIds(tab.root), ["pane-1", "pane-2"]);
  assert.equal(snapshot.panes["pane-2"]?.kind, "terminal");
  assert.equal(snapshot.panes["pane-2"]?.sessionId, "session-2");
});

test("updateLayoutNodeRatios updates ratios for a nested split path", () => {
  const splitSnapshot = splitTerminalSessionInSnapshot(createSnapshot(), {
    tabId: "tab-1",
    targetSessionId: "session-1",
    direction: "r",
    newPaneId: "pane-2",
    newSessionId: "session-2",
    cwd: "/repo",
  });

  const tab = splitSnapshot.tabs[0];
  assert.equal(tab?.root.type, "split");

  const nextRoot = updateLayoutNodeRatios(tab.root, [], [0.2, 0.8]);
  assert.equal(nextRoot.type, "split");
  if (nextRoot.type !== "split") {
    throw new Error("expected split node");
  }
  assert.deepEqual(nextRoot.ratios, [0.2, 0.8]);
});

test("removeTerminalSessionFromSnapshot drops the session pane and keeps sibling active", () => {
  const splitSnapshot = splitTerminalSessionInSnapshot(createSnapshot(), {
    tabId: "tab-1",
    targetSessionId: "session-1",
    direction: "r",
    newPaneId: "pane-2",
    newSessionId: "session-2",
    cwd: "/repo",
  });

  const snapshot = removeTerminalSessionFromSnapshot(splitSnapshot, "session-2", {
    createFallbackTab: () => ({
      tabId: "tab-fallback",
      paneId: "pane-fallback",
      sessionId: "session-fallback",
      title: "终端 1",
      cwd: "/repo",
    }),
  });

  assert.equal(snapshot.tabs.length, 1);
  assert.deepEqual(collectPaneIds(snapshot.tabs[0].root), ["pane-1"]);
  assert.equal(snapshot.tabs[0].activePaneId, "pane-1");
  assert.equal(snapshot.panes["pane-2"], undefined);
});

test("removeTerminalTabFromSnapshot creates a fallback tab when last tab closes", () => {
  const snapshot = removeTerminalTabFromSnapshot(createSnapshot(), "tab-1", {
    tabId: "tab-fallback",
    paneId: "pane-fallback",
    sessionId: "session-fallback",
    title: "终端 1",
    cwd: "/repo",
  });

  assert.equal(snapshot.tabs.length, 1);
  assert.equal(snapshot.activeTabId, "tab-fallback");
  assert.equal(snapshot.tabs[0].id, "tab-fallback");
  assert.equal(snapshot.panes["pane-fallback"]?.sessionId, "session-fallback");
  assert.equal(snapshot.panes["pane-1"], undefined);
});

test("upsertRunPanelTabInSnapshot adds a run tab, run pane, and activates the panel", () => {
  const snapshot = upsertRunPanelTabInSnapshot(createSnapshot(), {
    tab: {
      id: "run-tab-1",
      title: "构建",
      sessionId: "run-session-1",
      scriptId: "script-1",
      createdAt: 10,
      endedAt: null,
      exitCode: null,
    },
    cwd: "/repo",
  });

  assert.equal(snapshot.ui?.runPanel?.open, true);
  assert.equal(snapshot.ui?.runPanel?.activeTabId, "run-tab-1");
  assert.deepEqual(snapshot.ui?.runPanel?.tabs, [
    {
      id: "run-tab-1",
      title: "构建",
      sessionId: "run-session-1",
      scriptId: "script-1",
      createdAt: 10,
      endedAt: null,
      exitCode: null,
    },
  ]);
  assert.deepEqual(snapshot.panes["run:run-tab-1"], {
    id: "run:run-tab-1",
    kind: "run",
    placement: "runPanel",
    title: "构建",
    sessionId: "run-session-1",
    scriptId: "script-1",
    restoreAnchor: {
      cwd: "/repo",
      savedState: null,
    },
  });
});

test("removeRunPanelTabFromSnapshot removes pane and updates active tab", () => {
  const snapshot = upsertRunPanelTabInSnapshot(
    upsertRunPanelTabInSnapshot(createSnapshot(), {
      tab: {
        id: "run-tab-1",
        title: "构建",
        sessionId: "run-session-1",
        scriptId: "script-1",
        createdAt: 10,
        endedAt: null,
        exitCode: null,
      },
      cwd: "/repo",
    }),
    {
      tab: {
        id: "run-tab-2",
        title: "测试",
        sessionId: "run-session-2",
        scriptId: "script-2",
        createdAt: 20,
        endedAt: null,
        exitCode: null,
      },
      cwd: "/repo",
    },
  );

  const next = removeRunPanelTabFromSnapshot(snapshot, "run-tab-2");

  assert.equal(next.ui?.runPanel?.activeTabId, "run-tab-1");
  assert.equal(next.ui?.runPanel?.tabs.length, 1);
  assert.equal(next.ui?.runPanel?.tabs[0]?.id, "run-tab-1");
  assert.equal(next.panes["run:run-tab-2"], undefined);
});

test("syncRunPanelTabsInSnapshot prunes stale sessions and closes empty panel", () => {
  const snapshot = upsertRunPanelTabInSnapshot(createSnapshot(), {
    tab: {
      id: "run-tab-1",
      title: "构建",
      sessionId: "run-session-1",
      scriptId: "script-1",
      createdAt: 10,
      endedAt: null,
      exitCode: null,
    },
    cwd: "/repo",
  });

  const next = syncRunPanelTabsInSnapshot(snapshot, []);

  assert.deepEqual(next.ui?.runPanel?.tabs, []);
  assert.equal(next.ui?.runPanel?.activeTabId, null);
  assert.equal(next.ui?.runPanel?.open, false);
  assert.equal(next.panes["run:run-tab-1"], undefined);
});

test("markRunPanelTabExitedInSnapshot stores exit result on matching session", () => {
  const snapshot = upsertRunPanelTabInSnapshot(createSnapshot(), {
    tab: {
      id: "run-tab-1",
      title: "构建",
      sessionId: "run-session-1",
      scriptId: "script-1",
      createdAt: 10,
      endedAt: null,
      exitCode: null,
    },
    cwd: "/repo",
  });

  const next = markRunPanelTabExitedInSnapshot(snapshot, "run-session-1", {
    endedAt: 99,
    exitCode: 1,
  });

  assert.equal(next.ui?.runPanel?.tabs[0]?.endedAt, 99);
  assert.equal(next.ui?.runPanel?.tabs[0]?.exitCode, 1);
});

test("createDefaultLayoutSnapshot creates a version 2 snapshot without legacy workspace bridge", () => {
  const snapshot = createDefaultLayoutSnapshot("/repo", "project-1", {
    defaultRunPanelOpen: true,
    defaultRunPanelHeight: 320,
    defaultFileExplorerPanelOpen: true,
    defaultFileExplorerShowHidden: true,
  });

  assert.equal(snapshot.version, 2);
  assert.equal(snapshot.projectId, "project-1");
  assert.equal(snapshot.projectPath, "/repo");
  assert.equal(snapshot.tabs.length, 1);
  assert.equal(snapshot.activeTabId, snapshot.tabs[0]?.id);
  assert.equal(snapshot.tabs[0]?.root.type, "leaf");
  assert.equal(snapshot.panes[snapshot.tabs[0]?.activePaneId ?? ""]?.kind, "terminal");
  assert.equal(snapshot.ui?.runPanel?.height, 320);
  assert.equal(snapshot.ui?.runPanel?.open, false);
  assert.equal(snapshot.ui?.fileExplorerPanel?.showHidden, true);
});

test("updateRightSidebarStateInSnapshot mirrors file and git panel visibility", () => {
  const snapshot = updateRightSidebarStateInSnapshot(createSnapshot(), (current) => ({
    ...current,
    open: true,
    tab: "git",
    width: 640,
  }));

  assert.equal(snapshot.ui?.rightSidebar?.open, true);
  assert.equal(snapshot.ui?.rightSidebar?.tab, "git");
  assert.equal(snapshot.ui?.rightSidebar?.width, 640);
  assert.equal(snapshot.ui?.fileExplorerPanel?.open, false);
  assert.equal(snapshot.ui?.gitPanel?.open, true);
});

test("upsertFilePreviewPaneInSnapshot stores preview pane descriptor in right sidebar", () => {
  const snapshot = upsertFilePreviewPaneInSnapshot(createSnapshot(), {
    paneId: "right-sidebar:file-preview",
    relativePath: "docs/README.md",
    dirty: true,
  });

  assert.deepEqual(snapshot.panes["right-sidebar:file-preview"], {
    id: "right-sidebar:file-preview",
    kind: "filePreview",
    placement: "rightSidebar",
    title: "README.md",
    relativePath: "docs/README.md",
    dirty: true,
  });
});

test("removePaneFromSnapshot deletes a tool pane without touching terminal tree", () => {
  const snapshot = upsertFilePreviewPaneInSnapshot(createSnapshot(), {
    paneId: "right-sidebar:file-preview",
    relativePath: "docs/README.md",
    dirty: false,
  });

  const next = removePaneFromSnapshot(snapshot, "right-sidebar:file-preview");

  assert.equal(next.panes["right-sidebar:file-preview"], undefined);
  assert.equal(next.panes["pane-1"]?.kind, "terminal");
});

test("setFileExplorerShowHiddenInSnapshot preserves panel state while updating visibility flag", () => {
  const snapshot = updateRightSidebarStateInSnapshot(createSnapshot(), (current) => ({
    ...current,
    open: true,
    tab: "files",
  }));

  const next = setFileExplorerShowHiddenInSnapshot(snapshot, true);

  assert.equal(next.ui?.fileExplorerPanel?.showHidden, true);
  assert.equal(next.ui?.fileExplorerPanel?.open, true);
  assert.equal(next.ui?.rightSidebar?.open, true);
});

test("selectRightSidebarPreviewPane returns the stored preview descriptor", () => {
  const snapshot = upsertFilePreviewPaneInSnapshot(createSnapshot(), {
    paneId: "right-sidebar:file-preview",
    relativePath: "docs/README.md",
    dirty: false,
  });

  assert.deepEqual(selectRightSidebarPreviewPane(snapshot, "right-sidebar:file-preview"), {
    id: "right-sidebar:file-preview",
    kind: "filePreview",
    placement: "rightSidebar",
    title: "README.md",
    relativePath: "docs/README.md",
    dirty: false,
  });
});

test("upsertGitDiffPaneInSnapshot stores git selection in right sidebar pane", () => {
  const snapshot = upsertGitDiffPaneInSnapshot(createSnapshot(), {
    paneId: "right-sidebar:git-diff",
    relativePath: "src/main.ts",
    oldRelativePath: "src/old-main.ts",
    category: "staged",
  });

  assert.deepEqual(snapshot.panes["right-sidebar:git-diff"], {
    id: "right-sidebar:git-diff",
    kind: "gitDiff",
    placement: "rightSidebar",
    title: "main.ts",
    relativePath: "src/main.ts",
    oldRelativePath: "src/old-main.ts",
    category: "staged",
    comparison: "staged",
  });
});

test("selectRightSidebarGitDiffPane returns stored git diff descriptor", () => {
  const snapshot = upsertGitDiffPaneInSnapshot(createSnapshot(), {
    paneId: "right-sidebar:git-diff",
    relativePath: "src/main.ts",
    oldRelativePath: null,
    category: "unstaged",
  });

  assert.deepEqual(selectRightSidebarGitDiffPane(snapshot, "right-sidebar:git-diff"), {
    id: "right-sidebar:git-diff",
    kind: "gitDiff",
    placement: "rightSidebar",
    title: "main.ts",
    relativePath: "src/main.ts",
    oldRelativePath: null,
    category: "unstaged",
    comparison: "workingTree",
  });
});
