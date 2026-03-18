import assert from "node:assert/strict";
import { chmodSync, mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import process from "node:process";
import test from "node:test";

import {
  buildClaudeHooksSettings,
  resolveRealCommand as resolveRealClaudeCommand,
  resolveWrapperCleanPath as resolveClaudeWrapperCleanPath,
  buildWrappedClaudeSpawn,
  runWrappedClaude,
} from "./devhaven-claude-wrapper.mjs";
import {
  dispatchCodexNotificationLifecycle,
  summarizeNotifyPayload,
} from "./devhaven-codex-hook.mjs";
import {
  dispatchClaudeHookLifecycle,
} from "./devhaven-claude-hook.mjs";
import {
  buildCommandUrl,
  postDevHavenCommand,
  resolveControlEndpoint,
} from "./devhaven-control.mjs";
import {
  buildHookContext,
  clearAgentPidPrimitive,
  clearStatusPrimitive,
  sendAgentPidPrimitive,
  sendStatusPrimitive,
  sendTargetedNotification,
} from "./devhaven-agent-hook.mjs";
import {
  buildWrappedCodexSpawn,
  resolveRealCommand as resolveRealCodexCommand,
  resolveWrapperCleanPath as resolveCodexWrapperCleanPath,
  runWrappedCodex,
} from "./devhaven-codex-wrapper.mjs";

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

test("sendTargetedNotification posts to devhaven_notify_target with hook context", async () => {
  const calls = [];
  await sendTargetedNotification({
    env: {
      DEVHAVEN_CONTROL_ENDPOINT: "http://127.0.0.1:3210/api/cmd",
      DEVHAVEN_PROJECT_PATH: "/repo",
      DEVHAVEN_WORKSPACE_ID: "workspace-1",
      DEVHAVEN_PANE_ID: "pane-1",
      DEVHAVEN_SURFACE_ID: "surface-1",
      DEVHAVEN_TERMINAL_SESSION_ID: "session-1",
    },
    title: "Codex",
    message: "需要确认",
    level: "attention",
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

  assert.equal(calls[0].url, "http://127.0.0.1:3210/api/cmd/devhaven_notify_target");
  assert.match(String(calls[0].options.body), /workspace-1/);
  assert.match(String(calls[0].options.body), /需要确认/);
});

test("status and pid primitive helpers post expected commands", async () => {
  const urls = [];
  const fetchImpl = async (url) => {
    urls.push(url);
    return {
      ok: true,
      async text() {
        return JSON.stringify({ ok: true });
      },
    };
  };
  const env = {
    DEVHAVEN_CONTROL_ENDPOINT: "http://127.0.0.1:3210/api/cmd",
    DEVHAVEN_PROJECT_PATH: "/repo",
    DEVHAVEN_WORKSPACE_ID: "workspace-1",
    DEVHAVEN_PANE_ID: "pane-1",
    DEVHAVEN_SURFACE_ID: "surface-1",
    DEVHAVEN_TERMINAL_SESSION_ID: "session-1",
  };

  await sendStatusPrimitive({
    env,
    key: "codex",
    value: "Running",
    fetchImpl,
  });
  await clearStatusPrimitive({
    env,
    key: "codex",
    fetchImpl,
  });
  await sendAgentPidPrimitive({
    env,
    key: "codex",
    pid: 4321,
    fetchImpl,
  });
  await clearAgentPidPrimitive({
    env,
    key: "codex",
    fetchImpl,
  });

  assert.deepEqual(urls, [
    "http://127.0.0.1:3210/api/cmd/devhaven_set_status",
    "http://127.0.0.1:3210/api/cmd/devhaven_clear_status",
    "http://127.0.0.1:3210/api/cmd/devhaven_set_agent_pid",
    "http://127.0.0.1:3210/api/cmd/devhaven_clear_agent_pid",
  ]);
});

test("buildWrappedCodexSpawn prefers explicit real codex bin and forwards args", () => {
  const result = buildWrappedCodexSpawn(["exec", "实现需求"], {
      DEVHAVEN_REAL_CODEX_BIN: "/opt/bin/codex-real",
      DEVHAVEN_NODE_BIN: "/opt/bin/node",
      DEVHAVEN_CODEX_HOOK_PATH: "/repo/scripts/devhaven-codex-hook.mjs",
    });
  assert.equal(result.command, "/opt/bin/codex-real");
  assert.deepEqual(result.args.slice(-2), ["exec", "实现需求"]);
  assert.match(result.args[1], /^notify=\[/);
});

test("resolveWrapperCleanPath removes wrapper shim dir before command lookup", () => {
  const env = {
    PATH: "/shim/bin:/usr/local/bin:/usr/bin",
    DEVHAVEN_WRAPPER_BIN_PATH: "/shim/bin",
  };
  assert.equal(resolveCodexWrapperCleanPath(env), "/usr/local/bin:/usr/bin");
  assert.equal(resolveClaudeWrapperCleanPath(env), "/usr/local/bin:/usr/bin");
});

test("buildWrappedCodexSpawn resolves real binary from PATH when explicit env missing", () => {
  const tempRoot = mkdtempSync(join(tmpdir(), "devhaven-real-codex-"));
  const wrapperBin = join(tempRoot, "wrapper-bin");
  const realBin = join(tempRoot, "real-bin");
  mkdirSync(wrapperBin, { recursive: true });
  mkdirSync(realBin, { recursive: true });
  writeFileSync(join(wrapperBin, "codex"), "#!/bin/sh\nexit 1\n");
  writeFileSync(join(realBin, "codex"), "#!/bin/sh\nexit 0\n");
  chmodSync(join(wrapperBin, "codex"), 0o755);
  chmodSync(join(realBin, "codex"), 0o755);

  try {
    const env = {
      PATH: `${wrapperBin}:${realBin}:/usr/bin:/bin`,
      DEVHAVEN_WRAPPER_BIN_PATH: wrapperBin,
      DEVHAVEN_NODE_BIN: "/opt/bin/node",
      DEVHAVEN_CODEX_HOOK_PATH: "/repo/scripts/devhaven-codex-hook.mjs",
    };
    assert.equal(resolveRealCodexCommand(env, "codex"), join(realBin, "codex"));
    const result = buildWrappedCodexSpawn(["--version"], env);
    assert.equal(result.command, join(realBin, "codex"));
  } finally {
    rmSync(tempRoot, { recursive: true, force: true });
  }
});

test("buildWrappedClaudeSpawn injects hooks settings and session id", () => {
  const result = buildWrappedClaudeSpawn(["--model", "sonnet"], {
    DEVHAVEN_REAL_CLAUDE_BIN: "/opt/bin/claude-real",
    DEVHAVEN_NODE_BIN: "/opt/bin/node",
    DEVHAVEN_CLAUDE_HOOK_PATH: "/repo/scripts/devhaven-claude-hook.mjs",
  });
  assert.equal(result.command, "/opt/bin/claude-real");
  assert.equal(result.args[0], "--settings");
  assert.equal(result.args[2], "--session-id");
  assert.equal(result.args[4], "--model");
  const settings = JSON.parse(result.args[1]);
  assert.ok(settings.hooks.SessionStart);
  assert.ok(settings.hooks.Notification);
});

test("buildWrappedClaudeSpawn resolves real binary from PATH when explicit env missing", () => {
  const tempRoot = mkdtempSync(join(tmpdir(), "devhaven-real-claude-"));
  const wrapperBin = join(tempRoot, "wrapper-bin");
  const realBin = join(tempRoot, "real-bin");
  mkdirSync(wrapperBin, { recursive: true });
  mkdirSync(realBin, { recursive: true });
  writeFileSync(join(wrapperBin, "claude"), "#!/bin/sh\nexit 1\n");
  writeFileSync(join(realBin, "claude"), "#!/bin/sh\nexit 0\n");
  chmodSync(join(wrapperBin, "claude"), 0o755);
  chmodSync(join(realBin, "claude"), 0o755);

  try {
    const env = {
      PATH: `${wrapperBin}:${realBin}:/usr/bin:/bin`,
      DEVHAVEN_WRAPPER_BIN_PATH: wrapperBin,
      DEVHAVEN_NODE_BIN: "/opt/bin/node",
      DEVHAVEN_CLAUDE_HOOK_PATH: "/repo/scripts/devhaven-claude-hook.mjs",
    };
    assert.equal(resolveRealClaudeCommand(env, "claude"), join(realBin, "claude"));
    const result = buildWrappedClaudeSpawn(["--model", "sonnet"], env);
    assert.equal(result.command, join(realBin, "claude"));
  } finally {
    rmSync(tempRoot, { recursive: true, force: true });
  }
});

test("buildClaudeHooksSettings returns null when hook path missing", () => {
  assert.equal(buildClaudeHooksSettings({ DEVHAVEN_NODE_BIN: "/opt/bin/node" }), null);
});

test("summarizeNotifyPayload maps completion notifications to completed state", () => {
  assert.deepEqual(
    summarizeNotifyPayload({
      type: "task_complete",
      message: "任务已完成",
      title: "Codex",
    }),
    {
      title: "Codex",
      message: "任务已完成",
      level: "info",
      status: "completed",
    },
  );
});

test("summarizeNotifyPayload reads Codex hyphen-case last assistant message", () => {
  assert.deepEqual(
    summarizeNotifyPayload({
      title: "Codex",
      "last-assistant-message": "请确认是否继续执行",
    }),
    {
      title: "Codex",
      message: "请确认是否继续执行",
      level: "attention",
      status: "waiting",
    },
  );
});

test("dispatchCodexNotificationLifecycle emits exactly one notification through primitive path", async () => {
  const calls = [];
  await dispatchCodexNotificationLifecycle({
    summary: {
      title: "Codex",
      message: "需要确认",
      level: "attention",
      status: "waiting",
    },
    agentSessionId: "session-1",
    env: { DEVHAVEN_PROJECT_PATH: "/repo" },
    sendTargetedNotificationImpl: async (payload) => {
      calls.push(["notify_target", payload]);
    },
    sendStatusPrimitiveImpl: async (payload) => {
      calls.push(["set_status", payload]);
    },
    sendAgentSessionEventImpl: async (payload) => {
      calls.push(["session_event", payload]);
    },
  });

  assert.deepEqual(
    calls.map(([name]) => name),
    ["notify_target", "set_status", "session_event"],
  );
});

test("dispatchClaudeHookLifecycle notification path avoids legacy duplicate notify writes", async () => {
  const calls = [];
  await dispatchClaudeHookLifecycle({
    hook: "notification",
    payload: {
      title: "Claude",
      message: "需要关注",
    },
    agentSessionId: "session-1",
    env: { DEVHAVEN_PROJECT_PATH: "/repo" },
    sendTargetedNotificationImpl: async (value) => {
      calls.push(["notify_target", value]);
    },
    sendStatusPrimitiveImpl: async (value) => {
      calls.push(["set_status", value]);
    },
    sendAgentSessionEventImpl: async (value) => {
      calls.push(["session_event", value]);
    },
  });

  assert.deepEqual(
    calls.map(([name]) => name),
    ["notify_target", "set_status"],
  );
});

test("runWrappedCodex preserves current shell cwd and still spawns when control plane is unavailable", async () => {
  const originalCwd = process.cwd();
  const tempRoot = mkdtempSync(join(tmpdir(), "devhaven-codex-cwd-"));
  const calls = [];
  const child = {
    once(event, handler) {
      if (event === "exit") {
        setTimeout(() => handler(0, null), 0);
      }
      return child;
    },
  };

  try {
    process.chdir(tempRoot);
    const shellCwd = process.cwd();
    await runWrappedCodex({
      argv: ["--version"],
      env: {
        DEVHAVEN_REAL_CODEX_BIN: "/opt/bin/codex-real",
        DEVHAVEN_PROJECT_PATH: "/repo-root",
        DEVHAVEN_CONTROL_ENDPOINT: "http://127.0.0.1:1/api/cmd",
      },
      spawnImpl(command, args, options) {
        calls.push({ command, args, options });
        return child;
      },
    });

    assert.equal(calls.length, 1);
    assert.equal(calls[0].command, "/opt/bin/codex-real");
    assert.equal(calls[0].options.cwd, shellCwd);
  } finally {
    process.chdir(originalCwd);
    rmSync(tempRoot, { recursive: true, force: true });
  }
});

test("runWrappedClaude preserves current shell cwd", async () => {
  const originalCwd = process.cwd();
  const tempRoot = mkdtempSync(join(tmpdir(), "devhaven-claude-cwd-"));
  const calls = [];
  const child = {
    once(event, handler) {
      if (event === "exit") {
        setTimeout(() => handler(0, null), 0);
      }
      return child;
    },
  };

  try {
    process.chdir(tempRoot);
    const shellCwd = process.cwd();
    await runWrappedClaude({
      argv: ["--version"],
      env: {
        DEVHAVEN_REAL_CLAUDE_BIN: "/opt/bin/claude-real",
        DEVHAVEN_PROJECT_PATH: "/repo-root",
      },
      spawnImpl(command, args, options) {
        calls.push({ command, args, options });
        return child;
      },
    });

    assert.equal(calls.length, 1);
    assert.equal(calls[0].command, "/opt/bin/claude-real");
    assert.equal(calls[0].options.cwd, shellCwd);
  } finally {
    process.chdir(originalCwd);
    rmSync(tempRoot, { recursive: true, force: true });
  }
});
