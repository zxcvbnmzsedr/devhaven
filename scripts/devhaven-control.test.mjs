import assert from "node:assert/strict";
import test from "node:test";

import {
  buildCommandUrl,
  postDevHavenCommand,
  resolveControlEndpoint,
} from "./devhaven-control.mjs";
import { buildHookContext } from "./devhaven-agent-hook.mjs";

test("resolveControlEndpoint prefers explicit value then env then default", () => {
  assert.equal(
    resolveControlEndpoint({
      endpoint: "http://127.0.0.1:9999/api/cmd",
      env: { DEVHAVEN_CONTROL_ENDPOINT: "http://127.0.0.1:3210/api/cmd" },
    }),
    "http://127.0.0.1:9999/api/cmd",
  );
  assert.equal(
    resolveControlEndpoint({
      env: { DEVHAVEN_CONTROL_ENDPOINT: "http://127.0.0.1:3210/api/cmd" },
    }),
    "http://127.0.0.1:3210/api/cmd",
  );
});

test("buildCommandUrl appends command after endpoint", () => {
  assert.equal(
    buildCommandUrl("http://127.0.0.1:3210/api/cmd", "devhaven_tree"),
    "http://127.0.0.1:3210/api/cmd/devhaven_tree",
  );
});

test("postDevHavenCommand sends JSON payload to command endpoint", async () => {
  const calls = [];
  const result = await postDevHavenCommand({
    endpoint: "http://127.0.0.1:3210/api/cmd",
    command: "devhaven_notify",
    payload: { message: "hello" },
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return {
        ok: true,
        async text() {
          return JSON.stringify({ ok: true });
        },
      };
    },
  });

  assert.deepEqual(result, { ok: true });
  assert.equal(calls[0].url, "http://127.0.0.1:3210/api/cmd/devhaven_notify");
  assert.match(String(calls[0].options.body), /hello/);
});

test("buildHookContext reads DEVHAVEN context ids from environment", () => {
  assert.deepEqual(
    buildHookContext({
      DEVHAVEN_PROJECT_PATH: "/repo",
      DEVHAVEN_WORKSPACE_ID: "workspace-1",
      DEVHAVEN_PANE_ID: "pane-1",
      DEVHAVEN_SURFACE_ID: "surface-1",
      DEVHAVEN_TERMINAL_SESSION_ID: "session-1",
    }),
    {
      projectPath: "/repo",
      workspaceId: "workspace-1",
      paneId: "pane-1",
      surfaceId: "surface-1",
      terminalSessionId: "session-1",
    },
  );
});
