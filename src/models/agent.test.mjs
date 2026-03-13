import assert from "node:assert/strict";
import test from "node:test";

import {
  PANE_AGENT_PROVIDER_LABEL,
  PANE_AGENT_PROVIDERS,
  attachPaneAgentPty,
  buildPaneAgentLaunchCommand,
  canStartPaneAgent,
  clearPaneAgentRuntime,
  consumePaneAgentOutput,
  createPaneAgentRuntimeMap,
  finishPaneAgentRuntime,
  listPaneCreationTemplates,
  movePaneCreationSelection,
  resolvePaneAgentStatus,
  startPaneAgentRuntime,
} from "./agent.ts";

test("pane agent provider registry exposes codex / claude-code / iflow", () => {
  assert.deepEqual(PANE_AGENT_PROVIDERS, ["codex", "claude-code", "iflow"]);
  assert.equal(PANE_AGENT_PROVIDER_LABEL["codex"], "Codex");
  assert.equal(PANE_AGENT_PROVIDER_LABEL["claude-code"], "Claude Code");
  assert.equal(PANE_AGENT_PROVIDER_LABEL["iflow"], "iFlow");
});

test("listPaneCreationTemplates returns shell plus three agent templates", () => {
  assert.deepEqual(listPaneCreationTemplates(), [
    { mode: "shell" },
    { mode: "agent", provider: "codex" },
    { mode: "agent", provider: "claude-code" },
    { mode: "agent", provider: "iflow" },
  ]);
});

test("movePaneCreationSelection cycles through pending pane options with arrow keys", () => {
  assert.equal(movePaneCreationSelection(0, "down", 4), 1);
  assert.equal(movePaneCreationSelection(3, "down", 4), 0);
  assert.equal(movePaneCreationSelection(0, "up", 4), 3);
  assert.equal(movePaneCreationSelection(2, "up", 4), 1);
});

test("buildPaneAgentLaunchCommand builds a wrapped codex command", () => {
  const command = buildPaneAgentLaunchCommand("codex", {
    model: "gpt-5-codex",
    shellFamily: "posix",
  });

  assert.match(command, /\[DevHaven Agent Started\]/);
  assert.match(command, /\[DevHaven Agent Exit:/);
  assert.match(command, /codex --dangerously-bypass-approvals-and-sandbox --model 'gpt-5-codex'/);
});

test("buildPaneAgentLaunchCommand builds a wrapped claude code command", () => {
  const command = buildPaneAgentLaunchCommand("claude-code", {
    model: "claude-sonnet-4-5",
    prompt: "fix auth flow",
    shellFamily: "posix",
  });

  assert.match(command, /\[DevHaven Agent Started\]/);
  assert.match(command, /claude --dangerously-skip-permissions --model 'claude-sonnet-4-5' 'fix auth flow'/);
});

test("buildPaneAgentLaunchCommand builds a wrapped iflow command", () => {
  const command = buildPaneAgentLaunchCommand("iflow", {
    shellFamily: "posix",
  });

  assert.match(command, /\[DevHaven Agent Started\]/);
  assert.match(command, /\biflow\b/);
});

test("pane agent runtime tracks starting -> running -> stopped via output markers", () => {
  let runtime = startPaneAgentRuntime(createPaneAgentRuntimeMap(), "session-1", "codex ...");

  assert.equal(resolvePaneAgentStatus(runtime["session-1"]), "starting");
  assert.equal(canStartPaneAgent(runtime["session-1"]), false);

  runtime = attachPaneAgentPty(runtime, "session-1", "pty-1");
  assert.equal(runtime["session-1"]?.ptyId, "pty-1");

  runtime = consumePaneAgentOutput(runtime, "session-1", "[DevHaven Agent Started]\n");
  assert.equal(resolvePaneAgentStatus(runtime["session-1"]), "running");

  runtime = consumePaneAgentOutput(runtime, "session-1", "\n[DevHaven Agent Exit:0]\n");
  assert.equal(resolvePaneAgentStatus(runtime["session-1"]), "stopped");
  assert.equal(runtime["session-1"]?.exitCode, 0);
  assert.equal(canStartPaneAgent(runtime["session-1"]), true);
});

test("pane agent runtime handles split output markers and non-zero exits", () => {
  let runtime = startPaneAgentRuntime(createPaneAgentRuntimeMap(), "session-1", "codex ...");

  runtime = consumePaneAgentOutput(runtime, "session-1", "[DevHaven Agen");
  runtime = consumePaneAgentOutput(runtime, "session-1", "t Started]\n");
  assert.equal(resolvePaneAgentStatus(runtime["session-1"]), "running");

  runtime = consumePaneAgentOutput(runtime, "session-1", "\n[DevHaven Agent Ex");
  runtime = consumePaneAgentOutput(runtime, "session-1", "it:130]\n");
  assert.equal(resolvePaneAgentStatus(runtime["session-1"]), "failed");
  assert.equal(runtime["session-1"]?.exitCode, 130);
});

test("pane agent runtime can be finished or cleared explicitly", () => {
  let runtime = startPaneAgentRuntime(createPaneAgentRuntimeMap(), "session-1", "codex ...");

  runtime = finishPaneAgentRuntime(runtime, "session-1", {
    error: "命令注入失败",
  });
  assert.equal(resolvePaneAgentStatus(runtime["session-1"]), "failed");
  assert.equal(runtime["session-1"]?.error, "命令注入失败");

  runtime = clearPaneAgentRuntime(runtime, "session-1");
  assert.equal(runtime["session-1"], undefined);
  assert.equal(resolvePaneAgentStatus(runtime["session-1"]), "idle");
});
