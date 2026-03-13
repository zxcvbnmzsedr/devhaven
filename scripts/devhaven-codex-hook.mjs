import process from "node:process";
import { pathToFileURL } from "node:url";

import {
  sendAgentNotification,
  sendAgentSessionEvent,
} from "./devhaven-agent-hook.mjs";

function normalizeOptional(value) {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

async function runCli() {
  const mode = process.argv[2];
  if (!mode) {
    throw new Error("用法：node scripts/devhaven-codex-hook.mjs <session-event|notify> ...");
  }
  if (mode === "session-event") {
    const status = normalizeOptional(process.argv[3]);
    const message = normalizeOptional(process.argv[4]);
    if (!status) {
      throw new Error("session-event 需要状态参数");
    }
    await sendAgentSessionEvent({
      provider: "codex",
      status,
      message,
      agentSessionId: normalizeOptional(process.env.CODEX_SESSION_ID),
      cwd: process.cwd(),
    });
    return;
  }
  if (mode === "notify") {
    const message = normalizeOptional(process.argv[3]) ?? "Codex 需要你的关注";
    await sendAgentNotification({
      title: "Codex",
      message,
      level: "attention",
      agentSessionId: normalizeOptional(process.env.CODEX_SESSION_ID),
    });
    return;
  }
  throw new Error(`未知 Codex hook 模式: ${mode}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  runCli().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  });
}
