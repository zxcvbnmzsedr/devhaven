import assert from "node:assert/strict";
import test from "node:test";

import {
  buildPaneAttentionMap,
  projectControlPlaneWorkspace,
} from "./controlPlaneProjection.ts";

function createWorkspaceTree(overrides = {}) {
  return {
    workspaceId: "project-1",
    projectPath: "/repo",
    surfaces: [],
    notifications: [],
    statuses: [],
    agentPids: [],
    ...overrides,
  };
}

test("workspace projection falls back to primitive statuses when agent sessions are absent", () => {
  const projection = projectControlPlaneWorkspace(
    createWorkspaceTree({
      statuses: [
        {
          key: "codex",
          value: "Waiting",
          paneId: "pane-1",
          surfaceId: "surface-1",
          createdAt: 10,
          updatedAt: 20,
        },
      ],
    }),
  );

  assert.equal(projection.attention, "waiting");
  assert.equal(projection.latestMessage, "Waiting");
  assert.equal(projection.activeAgentCount, 1);
  assert.equal(projection.waitingAgentCount, 1);
});

test("pane attention map falls back to primitive statuses when no agent session is attached", () => {
  const map = buildPaneAttentionMap(
    createWorkspaceTree({
      surfaces: [
        {
          paneId: "pane-1",
          surfaceId: "surface-1",
          terminalSessionId: "session-1",
          unreadCount: 0,
          agentSession: null,
        },
      ],
      statuses: [
        {
          key: "codex",
          value: "Failed",
          paneId: "pane-1",
          surfaceId: "surface-1",
          createdAt: 10,
          updatedAt: 30,
        },
      ],
    }),
  );

  assert.equal(map["pane-1"].status, "failed");
  assert.equal(map["pane-1"].tone, "error");
  assert.equal(map["pane-1"].lastMessage, "Failed");
});

test("workspace projection clears completed attention after notifications are read", () => {
  const projection = projectControlPlaneWorkspace(
    createWorkspaceTree({
      surfaces: [
        {
          paneId: "pane-1",
          surfaceId: "surface-1",
          terminalSessionId: "session-1",
          unreadCount: 0,
          agentSession: {
            agentSessionId: "agent-1",
            provider: "codex",
            status: "completed",
            message: "Codex 已完成一轮处理",
            updatedAt: 30,
          },
        },
      ],
      notifications: [
        {
          id: "n1",
          message: "Codex 已完成一轮处理",
          createdAt: 20,
          updatedAt: 25,
          read: true,
        },
      ],
      statuses: [
        {
          key: "codex",
          value: "Completed",
          paneId: "pane-1",
          surfaceId: "surface-1",
          createdAt: 20,
          updatedAt: 30,
        },
      ],
    }),
  );

  assert.equal(projection.unreadCount, 0);
  assert.equal(projection.attention, "idle");
  assert.equal(projection.latestMessage, "Codex 已完成一轮处理");
});
