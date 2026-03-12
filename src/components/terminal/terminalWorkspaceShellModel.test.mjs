import test from "node:test";
import assert from "node:assert/strict";

import {
  appendTerminalTabToSnapshot,
  updateRightSidebarStateInSnapshot,
  upsertFilePreviewPaneInSnapshot,
  upsertGitDiffPaneInSnapshot,
  upsertRunPanelTabInSnapshot,
} from "../../models/terminal.ts";
import { createDefaultLayoutSnapshot } from "../../utils/terminalLayout.ts";
import { buildTerminalWorkspaceShellModel } from "./terminalWorkspaceShellModel.ts";

function createSnapshot() {
  const snapshot = createDefaultLayoutSnapshot("/repo", "project-1", {
    defaultRunPanelHeight: 240,
  });
  return appendTerminalTabToSnapshot(snapshot, {
    tabId: "tab-2",
    paneId: "pane-2",
    sessionId: "session-2",
    title: "终端 2",
    cwd: "/repo",
  });
}

test("buildTerminalWorkspaceShellModel derives active projections and run panel fallback state", () => {
  const snapshotWithSidebar = updateRightSidebarStateInSnapshot(createSnapshot(), (current) => ({
        ...current,
        open: true,
        tab: "git",
        width: 640,
      }));
  const baseSnapshot = {
    ...snapshotWithSidebar,
    ui: {
      ...(snapshotWithSidebar.ui ?? {}),
      runConfiguration: {
        selectedScriptId: "script-2",
      },
    },
  };
  const snapshot = upsertRunPanelTabInSnapshot(baseSnapshot, {
    tab: {
      id: "run-1",
      title: "构建",
      sessionId: "run-session-1",
      scriptId: "script-1",
      createdAt: 10,
      endedAt: null,
      exitCode: null,
    },
    cwd: "/repo",
  });

  const model = buildTerminalWorkspaceShellModel(snapshot, {
    isGitRepo: false,
    defaultFileExplorerPanelOpen: false,
    defaultFileExplorerShowHidden: false,
    minRunPanelHeight: 140,
    minRightSidebarWidth: 360,
    maxRightSidebarWidth: 960,
  });

  assert.equal(model.activeTabProjection?.tab.id, "tab-2");
  assert.deepEqual(model.headerTabs, baseSnapshot.tabs.map((tab) => ({ id: tab.id, title: tab.title })));
  assert.equal(model.activeTabId, "tab-2");
  assert.equal(model.activeWorkspaceTab?.id, "tab-2");
  assert.equal(model.activePaneProjections["pane-2"]?.sessionId, "session-2");
  assert.equal(model.selectedRunConfigurationId, "script-2");
  assert.equal(model.runPanelOpen, true);
  assert.equal(model.runPanelActiveTabId, "run-1");
  assert.equal(model.runPanelHeight, 240);
  assert.equal(model.rightSidebarOpen, true);
  assert.equal(model.rightSidebarWidth, 640);
  assert.equal(model.rightSidebarTab, "files");
});

test("buildTerminalWorkspaceShellModel derives preview and git selection from panes", () => {
  const snapshot = upsertGitDiffPaneInSnapshot(
    upsertFilePreviewPaneInSnapshot(createSnapshot(), {
      paneId: "right-sidebar:file-preview",
      relativePath: "docs/README.md",
      dirty: true,
    }),
    {
      paneId: "right-sidebar:git-diff",
      relativePath: "src/main.ts",
      oldRelativePath: "src/old-main.ts",
      category: "staged",
    },
  );

  const model = buildTerminalWorkspaceShellModel(snapshot, {
    isGitRepo: true,
    defaultFileExplorerPanelOpen: false,
    defaultFileExplorerShowHidden: false,
    minRunPanelHeight: 140,
    minRightSidebarWidth: 360,
    maxRightSidebarWidth: 960,
  });

  assert.equal(model.previewFilePath, "docs/README.md");
  assert.equal(model.previewDirty, true);
  assert.deepEqual(model.gitSelected, {
    category: "staged",
    path: "src/main.ts",
    oldPath: "src/old-main.ts",
  });
});
