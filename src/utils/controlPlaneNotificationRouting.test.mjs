import assert from "node:assert/strict";
import test from "node:test";

import { resolveNotificationProject } from "./controlPlaneNotificationRouting.ts";

function createProject(overrides = {}) {
  return {
    id: "project-1",
    name: "repo-main",
    path: "/repo/main",
    tags: ["infra"],
    scripts: [{ id: "s1", name: "dev", start: "pnpm dev" }],
    worktrees: [],
    mtime: 0,
    size: 0,
    checksum: "checksum",
    git_commits: 1,
    git_last_commit: 0,
    created: 0,
    checked: 0,
    ...overrides,
  };
}

test("resolveNotificationProject prefers exact project path", () => {
  const project = createProject({ id: "project-alpha", path: "/repo/alpha" });
  const resolved = resolveNotificationProject([project], {
    id: "n1",
    message: "Codex 已完成",
    projectPath: "/repo/alpha",
    workspaceId: "other-workspace",
    createdAt: 1,
    read: false,
  });

  assert.equal(resolved?.id, "project-alpha");
  assert.equal(resolved?.path, "/repo/alpha");
});

test("resolveNotificationProject resolves worktree path to virtual worktree project", () => {
  const sourceProject = createProject({
    id: "project-main",
    path: "/repo/main",
    tags: ["backend"],
    worktrees: [
      {
        id: "worktree:/repo/feature-x",
        name: "feature-x",
        path: "/repo/feature-x",
        branch: "feature/x",
        inheritConfig: true,
        created: 1,
      },
    ],
  });

  const resolved = resolveNotificationProject([sourceProject], {
    id: "n2",
    message: "Codex 需要确认输入",
    projectPath: "/repo/feature-x",
    createdAt: 2,
    read: false,
  });

  assert.equal(resolved?.id, "worktree:/repo/feature-x");
  assert.equal(resolved?.path, "/repo/feature-x");
  assert.deepEqual(resolved?.tags, ["backend"]);
  assert.equal(resolved?.scripts?.[0]?.id, "s1");
});

test("resolveNotificationProject falls back to workspace id when project path is missing", () => {
  const project = createProject({ id: "project-beta", path: "/repo/beta" });
  const resolved = resolveNotificationProject([project], {
    id: "n3",
    message: "Codex 已结束",
    workspaceId: "project-beta",
    createdAt: 3,
    read: false,
  });

  assert.equal(resolved?.id, "project-beta");
});
