import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import test from "node:test";

const REPO_ROOT = new URL("../", import.meta.url).pathname;
const ZSH_INTEGRATION_DIR = join(REPO_ROOT, "scripts/shell-integration/zsh");

test("zsh integration restores wrapper bin path even when user .zshenv overrides ZDOTDIR", () => {
  const tempRoot = mkdtempSync(join(tmpdir(), "devhaven-zsh-integration-"));
  const userBootstrap = join(tempRoot, "user-bootstrap");
  const userResolved = join(tempRoot, "user-resolved");
  const wrapperBin = join(tempRoot, "wrapper-bin");
  mkdirSync(userBootstrap, { recursive: true });
  mkdirSync(userResolved, { recursive: true });
  mkdirSync(wrapperBin, { recursive: true });

  writeFileSync(
    join(userBootstrap, ".zshenv"),
    `export ZDOTDIR="${userResolved}"\nexport PATH="/custom/bootstrap:$PATH"\n`,
  );
  writeFileSync(join(userResolved, ".zprofile"), "export PATH=\"/custom/profile:$PATH\"\n");
  writeFileSync(join(userResolved, ".zshrc"), "export PATH=\"/custom/rc:$PATH\"\n");
  writeFileSync(join(userResolved, ".zlogin"), "export PATH=\"/custom/login:$PATH\"\n");

  const result = spawnSync("zsh", ["-ilc", "print -r -- $PATH"], {
    cwd: REPO_ROOT,
    env: {
      HOME: tempRoot,
      PATH: "/usr/bin:/bin",
      ZDOTDIR: ZSH_INTEGRATION_DIR,
      DEVHAVEN_USER_ZDOTDIR: userBootstrap,
      DEVHAVEN_SHELL_INTEGRATION_DIR: ZSH_INTEGRATION_DIR,
      DEVHAVEN_WRAPPER_BIN_PATH: wrapperBin,
    },
    encoding: "utf8",
  });

  try {
    assert.equal(result.status, 0, result.stderr || result.stdout);
    const output = (result.stdout || "").trim();
    assert.match(output, new RegExp(`^${wrapperBin.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`));
  } finally {
    rmSync(tempRoot, { recursive: true, force: true });
  }
});

test("zsh bootstrap script can prepend wrapper PATH as a standalone primitive", () => {
  const tempRoot = mkdtempSync(join(tmpdir(), "devhaven-zsh-bootstrap-"));
  const wrapperBin = join(tempRoot, "wrapper-bin");
  mkdirSync(wrapperBin, { recursive: true });

  const result = spawnSync("zsh", ["-fc", "source \"$DEVHAVEN_SHELL_INTEGRATION_DIR/devhaven-zsh-bootstrap.zsh\"; _devhaven_run_zsh_bootstrap; print -r -- $PATH"], {
    cwd: REPO_ROOT,
    env: {
      HOME: tempRoot,
      PATH: "/usr/bin:/bin",
      DEVHAVEN_SHELL_INTEGRATION_DIR: ZSH_INTEGRATION_DIR,
      DEVHAVEN_WRAPPER_BIN_PATH: wrapperBin,
    },
    encoding: "utf8",
  });

  try {
    assert.equal(result.status, 0, result.stderr || result.stdout);
    const output = (result.stdout || "").trim();
    assert.match(output, new RegExp(`^${wrapperBin.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`));
  } finally {
    rmSync(tempRoot, { recursive: true, force: true });
  }
});
