import assert from "node:assert/strict";
import test from "node:test";

import {
  resolveCodexMonitorEmptyText,
  resolveCodexMonitorEnabled,
} from "./codexMonitorActivation.ts";

test("resolveCodexMonitorEnabled keeps monitor disabled until needed", () => {
  assert.equal(
    resolveCodexMonitorEnabled({
      manualEnabled: false,
      terminalWorkspaceVisible: false,
    }),
    false,
  );

  assert.equal(
    resolveCodexMonitorEnabled({
      manualEnabled: true,
      terminalWorkspaceVisible: false,
    }),
    true,
  );

  assert.equal(
    resolveCodexMonitorEnabled({
      manualEnabled: false,
      terminalWorkspaceVisible: true,
    }),
    true,
  );
});

test("resolveCodexMonitorEmptyText distinguishes disabled and enabled states", () => {
  assert.equal(resolveCodexMonitorEmptyText(false), "监控未启用");
  assert.equal(resolveCodexMonitorEmptyText(true), "未发现 Codex 会话");
});
