import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join } from "node:path";
import { tmpdir } from "node:os";
import test from "node:test";

const REPO_ROOT = new URL("../", import.meta.url).pathname;
const BASH_INTEGRATION_DIR = join(REPO_ROOT, "scripts/shell-integration");
const TERMINAL_BASH_PROMPT_COMMAND =
  "if [ -n \"${DEVHAVEN_SHELL_INTEGRATION_DIR:-}\" ] && [ -r \"${DEVHAVEN_SHELL_INTEGRATION_DIR}/bash/devhaven-bash-bootstrap.sh\" ]; then . \"${DEVHAVEN_SHELL_INTEGRATION_DIR}/bash/devhaven-bash-bootstrap.sh\"; fi";

function hasShell(shell) {
  const result = spawnSync("which", [shell], { encoding: "utf8" });
  return result.status === 0;
}

function parseLastNonEmptyLine(text) {
  const lines = (text || "")
    .split(/\r?\n/u)
    .map((line) => line.trim())
    .filter(Boolean);
  return lines.at(-1) ?? "";
}

function parseLastPipeDelimitedLine(text) {
  const lines = (text || "")
    .split(/\r?\n/u)
    .map((line) => line.trim())
    .filter(Boolean);
  for (let index = lines.length - 1; index >= 0; index -= 1) {
    if (lines[index].includes("|")) {
      return lines[index];
    }
  }
  return parseLastNonEmptyLine(text);
}

test("bash main startup PROMPT_COMMAND chain preserves HISTFILE and prepends wrapper PATH", (t) => {
  if (!hasShell("bash")) {
    t.skip("bash 不可用，跳过语义测试");
  }

  const tempRoot = mkdtempSync(join(tmpdir(), "devhaven-bash-semantics-"));
  const homeDir = join(tempRoot, "home");
  const wrapperBin = join(tempRoot, "wrapper-bin");
  const customHistory = join(tempRoot, "custom.bash_history");
  const promptLog = join(tempRoot, "prompt.log");
  mkdirSync(homeDir, { recursive: true });
  mkdirSync(wrapperBin, { recursive: true });

  const result = spawnSync(
    "bash",
    ["--noprofile", "--norc", "-i"],
    {
      cwd: REPO_ROOT,
      env: {
        HOME: homeDir,
        PATH: "/usr/bin:/bin",
        DEVHAVEN_SHELL_INTEGRATION_DIR: BASH_INTEGRATION_DIR,
        DEVHAVEN_WRAPPER_BIN_PATH: wrapperBin,
        DEVHAVEN_USER_PROMPT_COMMAND: "echo fired >> \"$DEVHAVEN_PROMPT_LOG\"",
        DEVHAVEN_PROMPT_LOG: promptLog,
        PROMPT_COMMAND: TERMINAL_BASH_PROMPT_COMMAND,
        HISTFILE: customHistory,
      },
      input: "echo \"$PROMPT_COMMAND|$HISTFILE|$PATH\"\nexit\n",
      encoding: "utf8",
    },
  );

  try {
    assert.equal(result.status, 0, result.stderr || result.stdout);
    const seen = parseLastPipeDelimitedLine(result.stdout);
    const [seenPromptCommand, seenHistory, seenPath] = seen.split("|");
    assert.equal(
      seenPromptCommand,
      TERMINAL_BASH_PROMPT_COMMAND,
      [
        "bash 主启动链回归：PROMPT_COMMAND 应保持 terminal.rs 注入的 bootstrap 链路。",
        `expected PROMPT_COMMAND: ${TERMINAL_BASH_PROMPT_COMMAND}`,
        `actual PROMPT_COMMAND:   ${seenPromptCommand ?? "<missing>"}`,
      ].join("\n"),
    );
    assert.equal(
      seenHistory,
      customHistory,
      [
        "bash 主启动链回归：PROMPT_COMMAND 链路执行后不应重写显式 HISTFILE。",
        `expected HISTFILE: ${customHistory}`,
        `actual HISTFILE:   ${seenHistory ?? "<missing>"}`,
      ].join("\n"),
    );
    assert.ok(
      typeof seenPath === "string" && seenPath.startsWith(`${wrapperBin}:`),
      [
        "bash 语义边界：integration 应把 wrapper bin 置于 PATH 最前。",
        `expected PATH prefix: ${wrapperBin}:`,
        `actual PATH:          ${seenPath ?? "<missing>"}`,
      ].join("\n"),
    );
    const promptLogContent = readFileSync(promptLog, "utf8");
    assert.match(
      promptLogContent,
      /fired/u,
      [
        "bash 主启动链回归：应执行 DEVHAVEN_USER_PROMPT_COMMAND。",
        `prompt log content: ${promptLogContent || "<empty>"}`,
      ].join("\n"),
    );
  } finally {
    rmSync(tempRoot, { recursive: true, force: true });
  }
});

test("bash startup falls back to user default HISTFILE when legacy shell-state HISTFILE is injected", (t) => {
  if (!hasShell("bash")) {
    t.skip("bash 不可用，跳过默认 HISTFILE 语义测试");
  }

  const tempRoot = mkdtempSync(join(tmpdir(), "devhaven-bash-default-history-"));
  const homeDir = join(tempRoot, "home");
  const wrapperBin = join(tempRoot, "wrapper-bin");
  const legacyStateDir = join(homeDir, ".devhaven/shell-state/bash");
  const legacyHistory = join(legacyStateDir, ".bash_history");
  mkdirSync(homeDir, { recursive: true });
  mkdirSync(wrapperBin, { recursive: true });
  mkdirSync(legacyStateDir, { recursive: true });

  const result = spawnSync(
    "bash",
    ["--noprofile", "--norc", "-i"],
    {
      cwd: REPO_ROOT,
      env: {
        HOME: homeDir,
        PATH: "/usr/bin:/bin",
        DEVHAVEN_SHELL_INTEGRATION_DIR: BASH_INTEGRATION_DIR,
        DEVHAVEN_WRAPPER_BIN_PATH: wrapperBin,
        PROMPT_COMMAND: TERMINAL_BASH_PROMPT_COMMAND,
        DEVHAVEN_SHELL_STATE_DIR: legacyStateDir,
        HISTFILE: legacyHistory,
      },
      input: "echo \"$HISTFILE|$PATH\"\nexit\n",
      encoding: "utf8",
    },
  );

  try {
    assert.equal(result.status, 0, result.stderr || result.stdout);
    const seen = parseLastPipeDelimitedLine(result.stdout);
    const [seenHistory, seenPath] = seen.split("|");
    const expectedHistory = join(homeDir, ".bash_history");
    assert.equal(
      seenHistory,
      expectedHistory,
      [
        "bash 默认历史语义回归：未显式设置 HISTFILE 时，不应依赖 legacy shell-state 历史路径。",
        `expected HISTFILE: ${expectedHistory}`,
        `actual HISTFILE:   ${seenHistory ?? "<missing>"}`,
      ].join("\n"),
    );
    assert.ok(
      typeof seenPath === "string" && seenPath.startsWith(`${wrapperBin}:`),
      [
        "bash 默认历史语义回归：wrapper PATH 注入应保持生效。",
        `expected PATH prefix: ${wrapperBin}:`,
        `actual PATH:          ${seenPath ?? "<missing>"}`,
      ].join("\n"),
    );
  } finally {
    rmSync(tempRoot, { recursive: true, force: true });
  }
});
