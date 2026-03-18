import assert from "node:assert/strict";
import test from "node:test";

import { sendSystemNotification } from "./system.ts";

class MockNotification {
  static permission = "granted";
  static instances = [];
  static async requestPermission() {
    return MockNotification.permission;
  }

  constructor(title, options) {
    this.title = title;
    this.options = options;
    this.onclick = null;
    this.onclose = null;
    this.onerror = null;
    this.closed = false;
    MockNotification.instances.push(this);
  }

  close() {
    this.closed = true;
    if (typeof this.onclose === "function") {
      this.onclose();
    }
  }
}

test("sendSystemNotification uses Notification API first and wires click callback", async () => {
  const originalWindow = globalThis.window;
  const originalNotification = globalThis.Notification;
  MockNotification.permission = "granted";
  MockNotification.instances = [];
  globalThis.window = { __TAURI_INTERNALS__: {}, Notification: MockNotification };
  globalThis.Notification = MockNotification;

  let clicked = 0;
  try {
    await sendSystemNotification({
      title: "Codex 已完成",
      body: "DevHaven",
      tag: "notification-n1",
      onClick: () => {
        clicked += 1;
      },
    });

    assert.equal(MockNotification.instances.length, 1);
    const notification = MockNotification.instances[0];
    assert.equal(notification.title, "Codex 已完成");
    assert.equal(notification.options?.body, "DevHaven");
    assert.equal(notification.options?.tag, "notification-n1");
    assert.equal(typeof notification.onclick, "function");

    await notification.onclick?.({ preventDefault() {} });

    assert.equal(clicked, 1);
    assert.equal(notification.closed, true);
  } finally {
    if (originalWindow === undefined) {
      delete globalThis.window;
    } else {
      globalThis.window = originalWindow;
    }
    if (originalNotification === undefined) {
      delete globalThis.Notification;
    } else {
      globalThis.Notification = originalNotification;
    }
  }
});
