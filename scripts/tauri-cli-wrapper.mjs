import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const DEFAULT_VITE_PORT = 1420;

function normalizePort(value) {
  const port = Number(value);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    return null;
  }
  return port;
}

function resolvePortFromAppState() {
  try {
    const appStatePath = path.join(os.homedir(), ".devhaven", "app_state.json");
    const appStateRaw = readFileSync(appStatePath, "utf-8");
    const appState = JSON.parse(appStateRaw);
    return normalizePort(appState?.settings?.viteDevPort);
  } catch {
    return null;
  }
}

function resolveVitePort() {
  const envPort = normalizePort(process.env.DEVHAVEN_VITE_PORT);
  if (envPort !== null) {
    return envPort;
  }
  return resolvePortFromAppState() ?? DEFAULT_VITE_PORT;
}

function syncTauriDevUrl(port) {
  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  const tauriConfigPath = path.resolve(scriptDir, "../src-tauri/tauri.conf.json");
  const tauriConfigRaw = readFileSync(tauriConfigPath, "utf-8");
  const tauriConfig = JSON.parse(tauriConfigRaw);
  const expectedDevUrl = `http://localhost:${port}`;

  if (tauriConfig?.build?.devUrl === expectedDevUrl) {
    return;
  }
  tauriConfig.build = {
    ...tauriConfig.build,
    devUrl: expectedDevUrl,
  };
  writeFileSync(tauriConfigPath, `${JSON.stringify(tauriConfig, null, 2)}\n`, "utf-8");
  console.log(`[tauri-wrapper] 已同步 devUrl -> ${expectedDevUrl}`);
}

function main() {
  const args = process.argv.slice(2);
  if (args[0] === "dev") {
    syncTauriDevUrl(resolveVitePort());
  }

  const result = spawnSync("pnpm", ["exec", "tauri", ...args], {
    stdio: "inherit",
    env: process.env,
  });

  if (typeof result.status === "number") {
    process.exit(result.status);
  }
  process.exit(1);
}

main();
