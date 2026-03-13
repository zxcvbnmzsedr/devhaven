import assert from "node:assert/strict";
import test from "node:test";

import {
  buildPaneAttentionMap,
  buildWorkspaceAttentionProjection,
  deriveAttentionTone,
} from "./controlPlaneProjection.ts";

function createTree(overrides = {}) {
  return {
    workspaceId: "project-1",
    projectPath: "/repo",
    panes: [],
    notifications: [],
    ...overrides,
  };
}

test("workspace attention projection aggregates unread count and latest message", () => {
  const projection = buildWorkspaceAttentionProjection(
    createTree({
      notifications: [
        { id: "n1", message: "构建完成", createdAt: 10, read: false },
        { id: "n2", message: "需要确认输入", createdAt: 20, read: false },
      ],
    }),
  );

  assert.equal(projection.unreadCount, 2);
  assert.equal(projection.lastMessage, "需要确认输入");
  assert.equal(projection.tone, "attention");
});

test("workspace attention projection prefers pane waiting state over running state", () => {
  const projection = buildWorkspaceAttentionProjection(
    createTree({
      panes: [
        {
          paneId: "pane-1",
          surfaceId: "pane-1",
          terminalSessionId: "session-1",
          unreadCount: 0,
          agentSession: {
            agentSessionId: "agent-1",
            provider: "claude-code",
            status: "running",
            message: "处理中",
            updatedAt: 30,
          },
        },
        {
          paneId: "pane-2",
          surfaceId: "pane-2",
          terminalSessionId: "session-2",
          unreadCount: 0,
          agentSession: {
            agentSessionId: "agent-2",
            provider: "codex",
            status: "waiting",
            message: "等待确认",
            updatedAt: 40,
          },
        },
      ],
    }),
  );

  assert.equal(projection.status, "waiting");
  assert.equal(projection.lastMessage, "等待确认");
  assert.equal(projection.tone, "attention");
});

test("deriveAttentionTone returns error for failed status even without unread notifications", () => {
  assert.equal(deriveAttentionTone({ status: "failed", unreadCount: 0 }), "error");
  assert.equal(deriveAttentionTone({ status: "completed", unreadCount: 0 }), "success");
  assert.equal(deriveAttentionTone({ status: "idle", unreadCount: 0 }), "idle");
});

test("buildPaneAttentionMap keeps pane-level status and unread counts", () => {
  const map = buildPaneAttentionMap(
    createTree({
      panes: [
        {
          paneId: "pane-1",
          surfaceId: "pane-1",
          terminalSessionId: "session-1",
          unreadCount: 2,
          agentSession: {
            agentSessionId: "agent-1",
            provider: "codex",
            status: "failed",
            message: "命令失败",
            updatedAt: 50,
          },
        },
      ],
    }),
  );

  assert.equal(map["pane-1"].status, "failed");
  assert.equal(map["pane-1"].unreadCount, 2);
  assert.equal(map["pane-1"].tone, "error");
  assert.equal(map["pane-1"].lastMessage, "命令失败");
});
