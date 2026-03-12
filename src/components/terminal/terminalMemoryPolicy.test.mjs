import assert from "node:assert/strict";
import test from "node:test";

import {
  countVisibleTerminalPanes,
  shouldEnableTerminalWebgl,
} from "./terminalMemoryPolicy.ts";

test("countVisibleTerminalPanes counts tree panes and active run pane", () => {
  assert.equal(
    countVisibleTerminalPanes({
      activePaneKinds: ["terminal", "filePreview", "run"],
      hasVisibleRunPanelTab: true,
    }),
    3,
  );
});

test("shouldEnableTerminalWebgl only enables for a single visible pane in an active workspace", () => {
  assert.equal(
    shouldEnableTerminalWebgl({
      terminalUseWebglRenderer: true,
      workspaceVisible: true,
      visibleTerminalPaneCount: 1,
    }),
    true,
  );

  assert.equal(
    shouldEnableTerminalWebgl({
      terminalUseWebglRenderer: true,
      workspaceVisible: true,
      visibleTerminalPaneCount: 2,
    }),
    false,
  );

  assert.equal(
    shouldEnableTerminalWebgl({
      terminalUseWebglRenderer: true,
      workspaceVisible: false,
      visibleTerminalPaneCount: 1,
    }),
    false,
  );
});
