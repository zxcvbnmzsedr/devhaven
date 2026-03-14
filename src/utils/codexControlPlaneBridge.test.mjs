import assert from "node:assert/strict";
import test from "node:test";

import { buildCodexControlPlaneUpdate } from "./codexControlPlaneBridge.ts";

test("needs-attention event maps to waiting agent session and attention notification", () => {
  const update = buildCodexControlPlaneUpdate(
    {
      type: "needs-attention",
      agent: "codex",
      timestamp: 10,
      sessionId: "codex-session-1",
      workingDirectory: "/repo",
      details: "需要人工确认",
    },
    {
      id: "project-1",
      path: "/repo",
      name: "DevHaven",
    },
  );

  assert.deepEqual(update, {
    agentSessionEvent: {
      agentSessionId: "codex-session-1",
      workspaceId: "project-1",
      projectPath: "/repo",
      provider: "codex",
      status: "waiting",
      cwd: "/repo",
      message: "需要人工确认",
    },
    notification: {
      agentSessionId: "codex-session-1",
      workspaceId: "project-1",
      projectPath: "/repo",
      title: "Codex 需要处理",
      message: "DevHaven",
      level: "attention",
    },
  });
});

test("task-complete event maps to completed agent session and info notification", () => {
  const update = buildCodexControlPlaneUpdate(
    {
      type: "task-complete",
      agent: "codex",
      timestamp: 20,
      sessionId: "codex-session-2",
      workingDirectory: "/repo",
      details: "构建完成",
    },
    {
      id: "project-1",
      path: "/repo",
      name: "DevHaven",
    },
  );

  assert.equal(update.agentSessionEvent?.status, "completed");
  assert.equal(update.notification?.level, "info");
  assert.equal(update.notification?.title, "Codex 已完成");
  assert.equal(update.notification?.message, "DevHaven");
});

test("agent-idle event only updates session state without notification", () => {
  const update = buildCodexControlPlaneUpdate(
    {
      type: "agent-idle",
      agent: "codex",
      timestamp: 30,
      sessionId: "codex-session-3",
      workingDirectory: "/repo",
      details: null,
    },
    {
      id: "project-1",
      path: "/repo",
      name: "DevHaven",
    },
  );

  assert.deepEqual(update, {
    agentSessionEvent: {
      agentSessionId: "codex-session-3",
      workspaceId: "project-1",
      projectPath: "/repo",
      provider: "codex",
      status: "stopped",
      cwd: "/repo",
      message: null,
    },
    notification: null,
  });
});
