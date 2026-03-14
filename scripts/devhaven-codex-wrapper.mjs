import { spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { delimiter } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { sendAgentSessionEvent } from "./devhaven-agent-hook.mjs";

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

export function resolveRealCommand(env = process.env, name = "codex") {
  const explicit = normalizeOptional(
    name === "codex" ? env.DEVHAVEN_REAL_CODEX_BIN : env.DEVHAVEN_REAL_CLAUDE_BIN,
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

export function buildWrappedCodexSpawn(argv = process.argv.slice(2), env = process.env) {
  const args = [...argv];
  const hasNotifyOverride = args.some((arg, index) => {
    if (arg === "-c" || arg === "--config") {
      const next = args[index + 1];
      return typeof next === "string" && next.trim().startsWith("notify=");
    }
    return arg.startsWith("notify=");
  });

  const hookPath = normalizeOptional(env.DEVHAVEN_CODEX_HOOK_PATH);
  const nodeBin = normalizeOptional(env.DEVHAVEN_NODE_BIN) ?? process.execPath;
  if (!hasNotifyOverride && hookPath && nodeBin) {
    args.unshift(
      "-c",
      `notify=["${nodeBin.replaceAll('"', '\\"')}","${hookPath.replaceAll('"', '\\"')}","notify"]`,
    );
  }
  const command = resolveRealCommand(env, "codex");
  if (!command) {
    throw new Error("无法解析真实 codex 可执行文件，请确认 codex 已安装且 PATH 可用。");
  }
  return {
    command,
    args,
  };
}

export async function runWrappedCodex({
  argv = process.argv.slice(2),
  env = process.env,
  spawnImpl = spawn,
} = {}) {
  const agentSessionId =
    normalizeOptional(env.DEVHAVEN_AGENT_SESSION_ID) ??
    normalizeOptional(env.CODEX_SESSION_ID) ??
    randomUUID();
  const cwd = process.cwd();

  try {
    await sendAgentSessionEvent({
      env: {
        ...env,
        CODEX_SESSION_ID: agentSessionId ?? env.CODEX_SESSION_ID,
      },
      provider: "codex",
      status: "running",
      message: "Codex 已启动",
      agentSessionId,
      cwd,
    });
  } catch {
    // best effort: control plane 不可用时仍允许真实 codex 启动
  }

  const { command, args } = buildWrappedCodexSpawn(argv, env);
  const child = spawnImpl(command, args, {
    cwd,
    env: {
      ...env,
      CODEX_SESSION_ID: agentSessionId ?? env.CODEX_SESSION_ID,
    },
    stdio: "inherit",
  });

  return await new Promise((resolve, reject) => {
    child.once("error", async (error) => {
      try {
        await sendAgentSessionEvent({
          env,
          provider: "codex",
          status: "failed",
          message: error instanceof Error ? error.message : String(error),
          agentSessionId,
          cwd,
        });
      } catch {
        // ignore notify failure
      }
      reject(error);
    });

    child.once("exit", async (code, signal) => {
      const exitCode = typeof code === "number" ? code : signal ? 1 : 0;
      const status = exitCode === 0 ? "stopped" : "failed";
      const message =
        exitCode === 0
          ? "Codex 已退出"
          : `Codex 退出异常（code=${code ?? "null"} signal=${signal ?? "none"}）`;
      try {
        await sendAgentSessionEvent({
          env,
          provider: "codex",
          status,
          message,
          agentSessionId,
          cwd,
        });
      } catch {
        // ignore notify failure
      }
      resolve(exitCode);
    });
  });
}

async function runCli() {
  const exitCode = await runWrappedCodex();
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
