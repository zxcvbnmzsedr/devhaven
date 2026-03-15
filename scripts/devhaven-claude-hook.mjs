import process from "node:process";
import { pathToFileURL } from "node:url";

import {
  sendAgentSessionEvent,
  sendStatusPrimitive,
  sendTargetedNotification,
} from "./devhaven-agent-hook.mjs";

async function readJsonFromStdin() {
  if (process.stdin.isTTY) {
    return {};
  }
  let raw = "";
  for await (const chunk of process.stdin) {
    raw += String(chunk);
  }
  const trimmed = raw.trim();
  if (!trimmed) {
    return {};
  }
  return JSON.parse(trimmed);
}

function firstText(...values) {
  for (const value of values) {
    if (typeof value === "string" && value.trim()) {
      return value.trim();
    }
  }
  return null;
}

export async function dispatchClaudeHookLifecycle({
  hook,
  payload,
  agentSessionId,
  env = process.env,
  sendTargetedNotificationImpl = sendTargetedNotification,
  sendStatusPrimitiveImpl = sendStatusPrimitive,
  sendAgentSessionEventImpl = sendAgentSessionEvent,
}) {
  if (hook === "session-start" || hook === "active") {
    await sendStatusPrimitiveImpl({
      key: "claude-code",
      value: "Running",
      icon: "bolt.fill",
      color: "#4C8DFF",
      env,
    }).catch(() => {});
    await sendAgentSessionEventImpl({
      provider: "claude-code",
      status: "running",
      message: firstText(payload.message, payload.cwd, "Claude 会话已启动"),
      agentSessionId,
      cwd: firstText(payload.cwd, process.cwd()),
      env,
    });
    return;
  }

  if (hook === "stop" || hook === "idle" || hook === "session-end") {
    await sendStatusPrimitiveImpl({
      key: "claude-code",
      value: "Stopped",
      icon: "pause.circle.fill",
      color: "#8E8E93",
      env,
    }).catch(() => {});
    await sendAgentSessionEventImpl({
      provider: "claude-code",
      status: "stopped",
      message: firstText(payload.message, "Claude 会话已停止"),
      agentSessionId,
      cwd: firstText(payload.cwd, process.cwd()),
      env,
    });
    return;
  }

  if (hook === "pre-tool-use") {
    await sendStatusPrimitiveImpl({
      key: "claude-code",
      value: "Running",
      icon: "bolt.fill",
      color: "#4C8DFF",
      env,
    }).catch(() => {});
    await sendAgentSessionEventImpl({
      provider: "claude-code",
      status: "running",
      message: firstText(payload.message, payload.tool_name, "Claude 正在执行工具"),
      agentSessionId,
      cwd: firstText(payload.cwd, process.cwd()),
      env,
    });
    return;
  }

  if (hook === "notification" || hook === "notify" || hook === "prompt-submit") {
    await sendTargetedNotificationImpl({
      title: firstText(payload.title, "Claude"),
      message:
        firstText(payload.message, payload.body, payload.text, "Claude 需要你的关注")
        ?? "Claude 需要你的关注",
      level: hook === "prompt-submit" ? "info" : "attention",
      agentSessionId,
      env,
    }).catch(() => {});
    await sendStatusPrimitiveImpl({
      key: "claude-code",
      value: hook === "prompt-submit" ? "Running" : "Waiting",
      icon: hook === "prompt-submit" ? "bolt.fill" : "bell.fill",
      color: "#4C8DFF",
      env,
    }).catch(() => {});
    if (hook === "prompt-submit") {
      await sendAgentSessionEventImpl({
        provider: "claude-code",
        status: "running",
        message: firstText(payload.message, "Claude 已收到新的用户输入"),
        agentSessionId,
        cwd: firstText(payload.cwd, process.cwd()),
        env,
      });
    }
    return;
  }

  throw new Error(`未知 Claude hook: ${hook}`);
}

async function runCli() {
  const hook = process.argv[2];
  if (!hook) {
    throw new Error("用法：node scripts/devhaven-claude-hook.mjs <session-start|active|stop|idle|session-end|notification|notify|prompt-submit|pre-tool-use>");
  }
  const payload = await readJsonFromStdin();
  const agentSessionId = firstText(
    payload.session_id,
    payload.sessionId,
    payload.external_session_id,
    process.env.CLAUDE_SESSION_ID,
  );

  await dispatchClaudeHookLifecycle({
    hook,
    payload,
    agentSessionId,
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  runCli().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  });
}
