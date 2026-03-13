import test from "node:test";
import assert from "node:assert/strict";

import { buildMountedWorkspaceEntries } from "./terminalWorkspaceMountModel.ts";

function createProject(id, path, name = id) {
  return {
    id,
    path,
    name,
    tags: [],
    scripts: [],
    favorite: false,
    worktrees: [],
  };
}

test("buildMountedWorkspaceEntries keeps all open projects mounted and only marks active one visible", () => {
  const projectA = createProject("project-a", "/repo/a", "A");
  const projectB = createProject("project-b", "/repo/b", "B");

  const entries = buildMountedWorkspaceEntries({
    openProjects: [projectA, projectB],
    activeProjectId: "project-b",
    quickCommandDispatch: null,
    workspaceVisible: true,
  });

  assert.equal(entries.length, 2);
  assert.deepEqual(
    entries.map((entry) => ({
      id: entry.project.id,
      isCurrent: entry.isCurrent,
      isVisible: entry.isVisible,
    })),
    [
      { id: "project-a", isCurrent: false, isVisible: false },
      { id: "project-b", isCurrent: true, isVisible: true },
    ],
  );
});

test("buildMountedWorkspaceEntries only forwards quick command dispatch to matching mounted project", () => {
  const projectA = createProject("project-a", "/repo/a", "A");
  const projectB = createProject("project-b", "/repo/b", "B");
  const dispatch = {
    seq: 3,
    type: "run",
    projectId: "project-a",
    projectPath: "/repo/a",
    scriptId: "script-1",
  };

  const entries = buildMountedWorkspaceEntries({
    openProjects: [projectA, projectB],
    activeProjectId: "project-b",
    quickCommandDispatch: dispatch,
    workspaceVisible: true,
  });

  assert.equal(entries[0].quickCommandDispatch, dispatch);
  assert.equal(entries[1].quickCommandDispatch, null);
  assert.equal(entries[0].isVisible, false);
  assert.equal(entries[1].isVisible, true);
});
