import { randomUUID } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { delimiter } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import {
  clearAgentPidPrimitive,
  sendAgentPidPrimitive,
  sendStatusPrimitive,
} from "./devhaven-agent-hook.mjs";

function normalizeOptional(value) {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

export function resolveWrapperCleanPath(env = process.env) {
  const wrapperBin = normalizeOptional(env.DEVHAVEN_WRAPPER_BIN_PATH);
  const currentPath = normalizeOptional(env.PATH) ?? "";
  if (!wrapperBin) {
    return currentPath;
  }
  return currentPath
    .split(delimiter)
    .filter((entry) => entry && entry !== wrapperBin)
    .join(delimiter);
}

export function resolveRealCommand(env = process.env, name = "claude") {
  const explicit = normalizeOptional(
    name === "claude" ? env.DEVHAVEN_REAL_CLAUDE_BIN : env.DEVHAVEN_REAL_CODEX_BIN,
  );
  if (explicit) {
    return explicit;
  }
  const cleanPath = resolveWrapperCleanPath(env);
  const result = spawnSync("which", [name], {
    env: {
      ...env,
      PATH: cleanPath,
    },
    encoding: "utf8",
  });
  return normalizeOptional(result.stdout);
}

function hasExplicitSessionControl(argv) {
  return argv.some((arg) =>
    arg === "--resume" ||
    arg === "--continue" ||
    arg === "-c" ||
    arg === "-r" ||
    arg === "--session-id" ||
    arg.startsWith("--resume=") ||
    arg.startsWith("--continue=") ||
    arg.startsWith("--session-id="),
  );
}

function quoteForJsonCommand(value) {
  return value.replaceAll("\\", "\\\\").replaceAll("\"", "\\\"");
}

export function buildClaudeHooksSettings(env = process.env) {
  const nodeBin = normalizeOptional(env.DEVHAVEN_NODE_BIN) ?? process.execPath;
  const hookPath = normalizeOptional(env.DEVHAVEN_CLAUDE_HOOK_PATH);
  if (!hookPath) {
    return null;
  }

  const commandFor = (subcommand) =>
    `"${quoteForJsonCommand(nodeBin)}" "${quoteForJsonCommand(hookPath)}" ${subcommand}`;

  return JSON.stringify({
    hooks: {
      SessionStart: [
        {
          matcher: "",
          hooks: [{ type: "command", command: commandFor("session-start") }],
        },
      ],
      Stop: [
        {
          matcher: "",
          hooks: [{ type: "command", command: commandFor("stop") }],
        },
      ],
      Notification: [
        {
          matcher: "",
          hooks: [{ type: "command", command: commandFor("notification") }],
        },
      ],
      UserPromptSubmit: [
        {
          matcher: "",
          hooks: [{ type: "command", command: commandFor("prompt-submit") }],
        },
      ],
      PreToolUse: [
        {
          matcher: "",
          hooks: [{ type: "command", command: commandFor("pre-tool-use") }],
        },
      ],
      SessionEnd: [
        {
          matcher: "",
          hooks: [{ type: "command", command: commandFor("session-end") }],
        },
      ],
    },
  });
}

export function buildWrappedClaudeSpawn(argv = process.argv.slice(2), env = process.env) {
  const args = [...argv];
  const sessionId = normalizeOptional(env.CLAUDE_SESSION_ID) ?? randomUUID();
  if (!hasExplicitSessionControl(args)) {
    args.unshift("--session-id", sessionId);
  }
  const settings = buildClaudeHooksSettings(env);
  if (settings) {
    args.unshift("--settings", settings);
  }
  const command = resolveRealCommand(env, "claude");
  if (!command) {
    throw new Error("无法解析真实 claude 可执行文件，请确认 claude 已安装且 PATH 可用。");
  }
  return {
    command,
    args,
    sessionId,
  };
}

export async function runWrappedClaude({
  argv = process.argv.slice(2),
  env = process.env,
  spawnImpl = spawn,
} = {}) {
  const { command, args, sessionId } = buildWrappedClaudeSpawn(argv, env);
  const cwd = process.cwd();
  const child = spawnImpl(command, args, {
    cwd,
    env: {
      ...env,
      CLAUDE_SESSION_ID: sessionId,
    },
    stdio: "inherit",
  });

  if (typeof child.pid === "number" && child.pid > 0) {
    void sendAgentPidPrimitive({
      env: {
        ...env,
        CLAUDE_SESSION_ID: sessionId,
      },
      key: "claude-code",
      pid: child.pid,
    }).catch(() => {
      // ignore primitive registration failure
    });
  }

  return await new Promise((resolve, reject) => {
    child.once("error", async (error) => {
      try {
        await clearAgentPidPrimitive({
          env: {
            ...env,
            CLAUDE_SESSION_ID: sessionId,
          },
          key: "claude-code",
        });
        await sendStatusPrimitive({
          env: {
            ...env,
            CLAUDE_SESSION_ID: sessionId,
          },
          key: "claude-code",
          value: "Failed",
          icon: "xmark.octagon.fill",
          color: "#FF5F57",
        });
      } catch {
        // ignore primitive failure
      }
      reject(error);
    });
    child.once("exit", (code, signal) => {
      void clearAgentPidPrimitive({
        env: {
          ...env,
          CLAUDE_SESSION_ID: sessionId,
        },
        key: "claude-code",
      }).catch(() => {
        // ignore primitive failure
      });
      void sendStatusPrimitive({
        env: {
          ...env,
          CLAUDE_SESSION_ID: sessionId,
        },
        key: "claude-code",
        value: typeof code === "number" && code === 0 ? "Stopped" : "Failed",
        icon: typeof code === "number" && code === 0 ? "pause.circle.fill" : "xmark.octagon.fill",
        color: typeof code === "number" && code === 0 ? "#8E8E93" : "#FF5F57",
      }).catch(() => {
        // ignore primitive failure
      });
      resolve(typeof code === "number" ? code : signal ? 1 : 0);
    });
  });
}

async function runCli() {
  const exitCode = await runWrappedClaude();
  if (typeof exitCode === "number") {
    process.exitCode = exitCode;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  runCli().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  });
}
