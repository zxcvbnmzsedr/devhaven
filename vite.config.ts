import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import UnoCSS from "unocss/vite";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

// @ts-expect-error process is a nodejs global
const host = process.env.TAURI_DEV_HOST;
const DEFAULT_VITE_DEV_PORT = 1420;
const DEFAULT_WEB_PROXY_TARGET = "http://127.0.0.1:3210";

type AppStateSettings = {
  viteDevPort?: number;
};

function normalizePort(port: number): number | null {
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    return null;
  }
  return port;
}

function readAppStateSettings(): AppStateSettings | null {
  try {
    const appStatePath = path.join(os.homedir(), ".devhaven", "app_state.json");
    const appStateRaw = fs.readFileSync(appStatePath, "utf-8");
    const appState = JSON.parse(appStateRaw) as { settings?: AppStateSettings };
    return appState.settings ?? null;
  } catch {
    return null;
  }
}

const appStateSettings = readAppStateSettings();

function resolveViteDevPort(): number {
  // 环境变量优先，便于临时覆盖调试端口。
  const envPort = Number.parseInt(process.env.DEVHAVEN_VITE_PORT ?? "", 10);
  const normalizedEnvPort = normalizePort(envPort);
  if (normalizedEnvPort !== null) {
    return normalizedEnvPort;
  }

  const settingsPort = normalizePort(Number(appStateSettings?.viteDevPort));
  if (settingsPort !== null) {
    return settingsPort;
  }
  return DEFAULT_VITE_DEV_PORT;
}

function resolveApiProxyTarget(): string {
  // 可通过 DEVHAVEN_WEB_API_TARGET 覆盖，例如 http://127.0.0.1:4321
  const envTarget = process.env.DEVHAVEN_WEB_API_TARGET?.trim();
  return envTarget || DEFAULT_WEB_PROXY_TARGET;
}

const apiProxyTarget = resolveApiProxyTarget();

// https://vite.dev/config/
export default defineConfig(async () => ({
  plugins: [react(), UnoCSS()],
  build: {
    // Monaco workers are intentionally large; keep warning threshold aligned with actual max chunk size.
    chunkSizeWarningLimit: 8192,
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (!id.includes("node_modules")) {
            return undefined;
          }
          if (id.includes("monaco-editor") || id.includes("@monaco-editor")) {
            return "vendor-monaco";
          }
          if (id.includes("xterm") || id.includes("xterm-addon")) {
            return "vendor-xterm";
          }
          if (id.includes("@tauri-apps")) {
            return "vendor-tauri";
          }
          if (id.includes("react") || id.includes("scheduler")) {
            return "vendor-react";
          }
          return "vendor";
        },
      },
    },
  },

  // Vite options tailored for Tauri development and only applied in `tauri dev` or `tauri build`
  //
  // 1. prevent Vite from obscuring rust errors
  clearScreen: false,
  // 2. use relative base path for production builds
  base: "./",
  // 2. tauri 需要固定端口，端口冲突时直接失败，避免静默切换到其它端口。
  server: {
    port: resolveViteDevPort(),
    strictPort: true,
    host: host || false,
    proxy: {
      "/api": {
        target: apiProxyTarget,
        changeOrigin: true,
        ws: true,
      },
    },
    hmr: host
      ? {
          protocol: "ws",
          host,
          port: 1421,
        }
      : undefined,
    watch: {
      // 3. tell Vite to ignore watching `src-tauri`
      ignored: ["**/src-tauri/**"],
    },
  },
}));
