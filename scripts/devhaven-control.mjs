import process from "node:process";
import { pathToFileURL } from "node:url";

const DEFAULT_CONTROL_ENDPOINT = "http://127.0.0.1:3210/api/cmd";

function normalizeEndpoint(value) {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim().replace(/\/+$/, "");
  return trimmed.length > 0 ? trimmed : null;
}

export function resolveControlEndpoint(options = {}) {
  const explicit = normalizeEndpoint(options.endpoint);
  if (explicit) {
    return explicit;
  }
  const fromEnv = normalizeEndpoint(options.env?.DEVHAVEN_CONTROL_ENDPOINT ?? process.env.DEVHAVEN_CONTROL_ENDPOINT);
  if (fromEnv) {
    return fromEnv;
  }
  return DEFAULT_CONTROL_ENDPOINT;
}

export function buildCommandUrl(endpoint, command) {
  const normalizedEndpoint = resolveControlEndpoint({ endpoint });
  const trimmedCommand = String(command ?? "").trim();
  if (!trimmedCommand) {
    throw new Error("command 不能为空");
  }
  return `${normalizedEndpoint}/${trimmedCommand}`;
}

export async function postDevHavenCommand({
  endpoint,
  command,
  payload = {},
  fetchImpl = globalThis.fetch,
}) {
  if (typeof fetchImpl !== "function") {
    throw new Error("当前 Node 运行时不支持 fetch，请使用 Node 18+。");
  }
  const response = await fetchImpl(buildCommandUrl(endpoint, command), {
    method: "POST",
    headers: {
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  const text = await response.text();
  const data = text ? JSON.parse(text) : null;
  if (!response.ok) {
    const message = data?.message || `控制面请求失败: ${response.status}`;
    throw new Error(message);
  }
  return data;
}

function parseCliArgs(argv) {
  const args = [...argv];
  const command = args.shift();
  if (!command) {
    throw new Error("用法：node scripts/devhaven-control.mjs <command> [--endpoint <url>] [json-payload]");
  }

  let endpoint = null;
  const payloadParts = [];
  while (args.length > 0) {
    const token = args.shift();
    if (token === "--endpoint") {
      endpoint = args.shift() ?? null;
      continue;
    }
    payloadParts.push(token);
  }
  const payload = payloadParts.length > 0 ? JSON.parse(payloadParts.join(" ")) : {};
  return { command, endpoint, payload };
}

async function runCli() {
  const { command, endpoint, payload } = parseCliArgs(process.argv.slice(2));
  const result = await postDevHavenCommand({
    endpoint,
    command,
    payload,
  });
  process.stdout.write(`${JSON.stringify(result ?? {}, null, 2)}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  runCli().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  });
}
