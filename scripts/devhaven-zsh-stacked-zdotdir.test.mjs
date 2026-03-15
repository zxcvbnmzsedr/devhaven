import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join } from "node:path";
import { tmpdir } from "node:os";
import test from "node:test";

const REPO_ROOT = new URL("../", import.meta.url).pathname;
const ZSH_INTEGRATION_DIR = join(REPO_ROOT, "scripts/shell-integration/zsh");

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

test("zsh stacked ZDOTDIR scenario preserves user-selected history location", (t) => {
  if (!hasShell("zsh")) {
    t.skip("zsh 不可用，跳过 stacked ZDOTDIR 回归测试");
  }

  const tempRoot = mkdtempSync(join(tmpdir(), "devhaven-zsh-stacked-zdotdir-"));
  const homeDir = join(tempRoot, "home");
  const userBootstrapDir = join(tempRoot, "user-bootstrap");
  const userResolvedDir = join(tempRoot, "user-resolved");
  mkdirSync(homeDir, { recursive: true });
  mkdirSync(userBootstrapDir, { recursive: true });
  mkdirSync(userResolvedDir, { recursive: true });

  writeFileSync(
    join(userBootstrapDir, ".zshenv"),
    `export ZDOTDIR="${userResolvedDir}"\n`,
    "utf8",
  );

  const result = spawnSync("zsh", ["-ic", "print -r -- \"$ZDOTDIR|$HISTFILE\""], {
    cwd: REPO_ROOT,
    env: {
      HOME: homeDir,
      PATH: "/usr/bin:/bin",
      ZDOTDIR: ZSH_INTEGRATION_DIR,
      DEVHAVEN_USER_ZDOTDIR: userBootstrapDir,
      DEVHAVEN_SHELL_INTEGRATION_DIR: ZSH_INTEGRATION_DIR,
    },
    encoding: "utf8",
  });

  try {
    assert.equal(result.status, 0, result.stderr || result.stdout);
    const seen = parseLastNonEmptyLine(result.stdout);
    const expected = `${userResolvedDir}|${join(userResolvedDir, ".zsh_history")}`;
    assert.equal(
      seen,
      expected,
      [
        "stacked ZDOTDIR 回归：用户 .zshenv 修改 ZDOTDIR 后，history 应跟随用户目录。",
        `expected: ${expected}`,
        `actual:   ${seen}`,
      ].join("\n"),
    );
  } finally {
    rmSync(tempRoot, { recursive: true, force: true });
  }
});
