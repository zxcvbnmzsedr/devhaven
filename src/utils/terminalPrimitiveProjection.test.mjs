import assert from "node:assert/strict";
import test from "node:test";

import { projectTerminalPrimitives } from "./terminalPrimitiveProjection.ts";

function createTree(overrides = {}) {
  return {
    workspaceId: "project-1",
    projectPath: "/repo",
    panes: [],
    notifications: [],
    statuses: [],
    agentPids: [],
    ...overrides,
  };
}

test("projectTerminalPrimitives keeps latest status and pid by key", () => {
  const projection = projectTerminalPrimitives(
    createTree({
      statuses: [
        { key: "codex", value: "Idle", updatedAt: 10 },
        { key: "codex", value: "Running", updatedAt: 20 },
      ],
      agentPids: [
        { key: "codex", pid: 1001, updatedAt: 11 },
        { key: "codex", pid: 2002, updatedAt: 21 },
      ],
    }),
  );

  assert.equal(projection.statusesByKey.codex.value, "Running");
  assert.equal(projection.agentPidsByKey.codex.pid, 2002);
});

test("projectTerminalPrimitives returns empty maps when tree has no primitives", () => {
  const projection = projectTerminalPrimitives(createTree());

  assert.deepEqual(projection.statusesByKey, {});
  assert.deepEqual(projection.agentPidsByKey, {});
});

test("projectTerminalPrimitives keeps separate keys for status and pid maps", () => {
  const projection = projectTerminalPrimitives(
    createTree({
      statuses: [
        { key: "codex", value: "Running", updatedAt: 20 },
        { key: "claude", value: "Waiting", updatedAt: 30 },
      ],
      agentPids: [
        { key: "codex", pid: 2002, updatedAt: 21 },
        { key: "claude", pid: 3003, updatedAt: 31 },
      ],
    }),
  );

  assert.deepEqual(Object.keys(projection.statusesByKey).sort(), ["claude", "codex"]);
  assert.deepEqual(Object.keys(projection.agentPidsByKey).sort(), ["claude", "codex"]);
  assert.equal(projection.statusesByKey.claude.value, "Waiting");
  assert.equal(projection.agentPidsByKey.claude.pid, 3003);
});
