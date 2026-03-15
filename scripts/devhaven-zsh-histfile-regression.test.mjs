import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync } from "node:fs";
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

test("zsh keeps user ZDOTDIR/HISTFILE semantics under DevHaven integration", (t) => {
  if (!hasShell("zsh")) {
    t.skip("zsh 不可用，跳过回归测试");
  }

  const tempRoot = mkdtempSync(join(tmpdir(), "devhaven-zsh-hist-regression-"));
  const homeDir = join(tempRoot, "home");
  mkdirSync(homeDir, { recursive: true });

  const result = spawnSync("zsh", ["-ic", "print -r -- \"$ZDOTDIR|$HISTFILE\""], {
    cwd: REPO_ROOT,
    env: {
      HOME: homeDir,
      PATH: "/usr/bin:/bin",
      ZDOTDIR: ZSH_INTEGRATION_DIR,
      DEVHAVEN_USER_ZDOTDIR: homeDir,
      DEVHAVEN_SHELL_INTEGRATION_DIR: ZSH_INTEGRATION_DIR,
    },
    encoding: "utf8",
  });

  try {
    assert.equal(result.status, 0, result.stderr || result.stdout);
    const seen = parseLastNonEmptyLine(result.stdout);
    const expected = `${homeDir}|${join(homeDir, ".zsh_history")}`;
    assert.equal(
      seen,
      expected,
      [
        "zsh shell 语义回归：期望集成后仍使用用户 HOME 的 ZDOTDIR/HISTFILE。",
        `expected: ${expected}`,
        `actual:   ${seen}`,
      ].join("\n"),
    );
  } finally {
    rmSync(tempRoot, { recursive: true, force: true });
  }
});
