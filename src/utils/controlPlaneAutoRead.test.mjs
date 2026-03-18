import assert from "node:assert/strict";
import test from "node:test";

import {
  collectNewControlPlaneNotifications,
  collectNotificationIdsToMarkRead,
} from "./controlPlaneAutoRead.ts";

test("collectNotificationIdsToMarkRead returns workspace-level plus active-surface unread ids only when workspace is active", () => {
  const tree = {
    workspaceId: "project-1",
    projectPath: "/repo",
    surfaces: [],
    notifications: [
      { id: "n1", message: "工作区级通知", createdAt: 1, read: false },
      { id: "n2", message: "当前 pane 的通知", createdAt: 2, read: false, paneId: "pane-1", surfaceId: "surface-1" },
      { id: "n3", message: "其它 pane 的通知", createdAt: 3, read: false, paneId: "pane-2", surfaceId: "surface-2" },
      { id: "n4", message: "当前会话通知", createdAt: 4, read: false, terminalSessionId: "session-1" },
      { id: "n5", message: "已读通知", createdAt: 5, read: true, paneId: "pane-1", surfaceId: "surface-1" },
    ],
  };

  assert.deepEqual(
    collectNotificationIdsToMarkRead(tree, {
      isActive: false,
      activePaneId: "pane-1",
      activeSurfaceId: "surface-1",
      activeTerminalSessionId: "session-1",
    }),
    [],
  );
  assert.deepEqual(
    collectNotificationIdsToMarkRead(tree, {
      isActive: true,
      activePaneId: "pane-1",
      activeSurfaceId: "surface-1",
      activeTerminalSessionId: "session-1",
    }),
    ["n1", "n2", "n4"],
  );
});

test("collectNotificationIdsToMarkRead handles empty trees", () => {
  assert.deepEqual(
    collectNotificationIdsToMarkRead(null, {
      isActive: true,
      activePaneId: "pane-1",
      activeSurfaceId: "surface-1",
      activeTerminalSessionId: "session-1",
    }),
    [],
  );
});

test("collectNotificationIdsToMarkRead only keeps workspace-level notifications when active surface is unknown", () => {
  const tree = {
    workspaceId: "project-1",
    projectPath: "/repo",
    surfaces: [],
    notifications: [
      { id: "n1", message: "工作区级通知", createdAt: 1, read: false },
      { id: "n2", message: "pane 通知", createdAt: 2, read: false, paneId: "pane-1", surfaceId: "surface-1" },
    ],
  };

  assert.deepEqual(
    collectNotificationIdsToMarkRead(tree, {
      isActive: true,
      activePaneId: null,
      activeSurfaceId: null,
      activeTerminalSessionId: null,
    }),
    ["n1"],
  );
});

test("collectNewControlPlaneNotifications returns only notifications since the event and skips seen ids", () => {
  const tree = {
    workspaceId: "project-1",
    projectPath: "/repo",
    surfaces: [],
    notifications: [
      { id: "n1", message: "旧消息", createdAt: 10, updatedAt: 10, read: true },
      { id: "n2", message: "刚写入", createdAt: 20, updatedAt: 20, read: false },
      { id: "n3", message: "被自动已读但仍应显示", createdAt: 21, updatedAt: 25, read: true },
    ],
  };

  const seenIds = new Set(["n2"]);
  assert.deepEqual(
    collectNewControlPlaneNotifications(tree, { since: 20, seenIds }).map((item) => item.id),
    ["n3"],
  );
});

test("collectNewControlPlaneNotifications prefers explicit notification ids to avoid swallowing later events", () => {
  const tree = {
    workspaceId: "project-1",
    projectPath: "/repo",
    surfaces: [],
    notifications: [
      { id: "n1", message: "第一轮完成", createdAt: 20, updatedAt: 20, read: false },
      { id: "n2", message: "第二轮完成", createdAt: 30, updatedAt: 30, read: false },
    ],
  };

  assert.deepEqual(
    collectNewControlPlaneNotifications(tree, {
      since: 20,
      seenIds: new Set(),
      notificationIds: ["n1"],
    }).map((item) => item.id),
    ["n1"],
  );
});
