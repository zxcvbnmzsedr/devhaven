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

function parseMaybeJson(value) {
  const trimmed = normalizeOptional(value);
  if (!trimmed) {
    return null;
  }
  if (!(trimmed.startsWith("{") || trimmed.startsWith("["))) {
    return null;
  }
  try {
    return JSON.parse(trimmed);
  } catch {
    return null;
  }
}

function firstText(...values) {
  for (const value of values) {
    if (typeof value === "string" && value.trim()) {
      return value.trim();
    }
  }
  return null;
}

export function summarizeNotifyPayload(payload) {
  if (!payload || typeof payload !== "object") {
    return {
      title: "Codex",
      message: "Codex 需要你的关注",
      level: "attention",
      status: "waiting",
    };
  }

  const type = firstText(payload.type, payload.event, payload.kind)?.toLowerCase() ?? "";
  const title = firstText(payload.title, "Codex");
  const message =
    firstText(
      payload.message,
      payload.summary,
      payload.body,
      payload.text,
      payload.last_assistant_message,
      payload.lastAssistantMessage,
    ) ??
    (type.includes("complete")
      ? "Codex 已完成一轮处理"
      : type.includes("error") || type.includes("fail")
        ? "Codex 执行失败"
        : "Codex 需要你的关注");

  if (type.includes("error") || type.includes("fail")) {
    return {
      title,
      message,
      level: "error",
      status: "failed",
    };
  }

  if (type.includes("complete")) {
    return {
      title,
      message,
      level: "info",
      status: "completed",
    };
  }

  return {
    title,
    message,
    level: "attention",
    status: "waiting",
  };
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
    const payload = parseMaybeJson(process.argv[3]);
    const summary = summarizeNotifyPayload(payload);
    const agentSessionId =
      normalizeOptional(process.env.CODEX_SESSION_ID) ??
      normalizeOptional(payload?.session_id) ??
      normalizeOptional(payload?.sessionId);
    await sendAgentNotification({
      title: summary.title,
      message: summary.message,
      level: summary.level,
      agentSessionId,
    });
    await sendAgentSessionEvent({
      provider: "codex",
      status: summary.status,
      message: summary.message,
      agentSessionId,
      cwd: process.cwd(),
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
