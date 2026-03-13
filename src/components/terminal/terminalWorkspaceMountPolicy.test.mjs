import test from "node:test";
import assert from "node:assert/strict";

import { buildWorkspaceRenderEntries } from "./terminalWorkspaceMountPolicy.ts";

function createProject(id, path, name) {
  return {
    id,
    path,
    name,
    scripts: [],
    worktrees: [],
  };
}

test("buildWorkspaceRenderEntries keeps all open projects mounted and only marks active project visible", () => {
  const entries = buildWorkspaceRenderEntries(
    [
      createProject("project-1", "/repo/a", "A"),
      createProject("project-2", "/repo/b", "B"),
      createProject("project-3", "/repo/c", "C"),
    ],
    "project-2",
  );

  assert.deepEqual(
    entries.map((entry) => ({ id: entry.project.id, isVisible: entry.isVisible })),
    [
      { id: "project-1", isVisible: false },
      { id: "project-2", isVisible: true },
      { id: "project-3", isVisible: false },
    ],
  );
});

test("buildWorkspaceRenderEntries falls back to first open project when active id is missing", () => {
  const entries = buildWorkspaceRenderEntries(
    [
      createProject("project-1", "/repo/a", "A"),
      createProject("project-2", "/repo/b", "B"),
    ],
    "missing-project",
  );

  assert.deepEqual(
    entries.map((entry) => ({ id: entry.project.id, isVisible: entry.isVisible })),
    [
      { id: "project-1", isVisible: true },
      { id: "project-2", isVisible: false },
    ],
  );
});
