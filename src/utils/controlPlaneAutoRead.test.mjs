import assert from "node:assert/strict";
import test from "node:test";

import {
  collectNewControlPlaneNotifications,
  collectNotificationIdsToMarkRead,
} from "./controlPlaneAutoRead.ts";

test("collectNotificationIdsToMarkRead returns unread ids only when workspace is active", () => {
  const tree = {
    workspaceId: "project-1",
    projectPath: "/repo",
    surfaces: [],
    notifications: [
      { id: "n1", message: "第一条", createdAt: 1, read: false },
      { id: "n2", message: "第二条", createdAt: 2, read: true },
      { id: "n3", message: "第三条", createdAt: 3, read: false },
    ],
  };

  assert.deepEqual(collectNotificationIdsToMarkRead(tree, { isActive: false }), []);
  assert.deepEqual(collectNotificationIdsToMarkRead(tree, { isActive: true }), ["n1", "n3"]);
});

test("collectNotificationIdsToMarkRead handles empty trees", () => {
  assert.deepEqual(collectNotificationIdsToMarkRead(null, { isActive: true }), []);
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
