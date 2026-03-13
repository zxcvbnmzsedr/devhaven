import process from "node:process";
import { pathToFileURL } from "node:url";

import { postDevHavenCommand, resolveControlEndpoint } from "./devhaven-control.mjs";

function normalizeOptional(value) {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

export function buildHookContext(env = process.env) {
  return {
    projectPath: normalizeOptional(env.DEVHAVEN_PROJECT_PATH),
    workspaceId: normalizeOptional(env.DEVHAVEN_WORKSPACE_ID),
    paneId: normalizeOptional(env.DEVHAVEN_PANE_ID),
    surfaceId: normalizeOptional(env.DEVHAVEN_SURFACE_ID),
    terminalSessionId: normalizeOptional(env.DEVHAVEN_TERMINAL_SESSION_ID),
  };
}

function parseFlags(argv) {
  const args = [...argv];
  const subcommand = args.shift();
  const flags = {};
  while (args.length > 0) {
    const key = args.shift();
    if (!key?.startsWith("--")) {
      continue;
    }
    const value = args[0]?.startsWith("--") ? "true" : (args.shift() ?? "");
    flags[key.slice(2)] = value;
  }
  return { subcommand, flags };
}

export async function sendAgentSessionEvent({
  endpoint,
  env = process.env,
  provider,
  status,
  message = null,
  agentSessionId = null,
  cwd = null,
}) {
  const context = buildHookContext(env);
  return postDevHavenCommand({
    endpoint: resolveControlEndpoint({ endpoint, env }),
    command: "devhaven_agent_session_event",
    payload: {
      ...context,
      agentSessionId,
      provider,
      status,
      message,
      cwd,
    },
  });
}

export async function sendAgentNotification({
  endpoint,
  env = process.env,
  message,
  title = null,
  level = "attention",
  agentSessionId = null,
}) {
  const context = buildHookContext(env);
  return postDevHavenCommand({
    endpoint: resolveControlEndpoint({ endpoint, env }),
    command: "devhaven_notify",
    payload: {
      ...context,
      agentSessionId,
      title,
      message,
      level,
    },
  });
}

async function runCli() {
  const { subcommand, flags } = parseFlags(process.argv.slice(2));
  if (subcommand === "notify") {
    const message = normalizeOptional(flags.message);
    if (!message) {
      throw new Error("notify 需要 --message");
    }
    const result = await sendAgentNotification({
      endpoint: flags.endpoint,
      title: normalizeOptional(flags.title),
      message,
      level: normalizeOptional(flags.level) ?? "attention",
      agentSessionId: normalizeOptional(flags["agent-session-id"]),
    });
    process.stdout.write(`${JSON.stringify(result ?? {}, null, 2)}\n`);
    return;
  }

  if (subcommand === "session-event") {
    const provider = normalizeOptional(flags.provider);
    const status = normalizeOptional(flags.status);
    if (!provider || !status) {
      throw new Error("session-event 需要 --provider 与 --status");
    }
    const result = await sendAgentSessionEvent({
      endpoint: flags.endpoint,
      provider,
      status,
      message: normalizeOptional(flags.message),
      agentSessionId: normalizeOptional(flags["agent-session-id"]),
      cwd: normalizeOptional(flags.cwd),
    });
    process.stdout.write(`${JSON.stringify(result ?? {}, null, 2)}\n`);
    return;
  }

  throw new Error(
    "用法：node scripts/devhaven-agent-hook.mjs <notify|session-event> [--endpoint <url>] ...",
  );
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  runCli().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  });
}
