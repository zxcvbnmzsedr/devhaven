/** 运行时探测与跨平台能力适配。 */
export function isTauriRuntime(): boolean {
  if (typeof window === "undefined") {
    return false;
  }
  return "__TAURI_INTERNALS__" in window;
}

export function resolveApiBaseUrl(): string {
  if (typeof window === "undefined") {
    return "http://127.0.0.1:3210";
  }

  const explicit = import.meta.env.VITE_DEVHAVEN_API_BASE as string | undefined;
  if (explicit && explicit.trim().length > 0) {
    return explicit.trim().replace(/\/$/, "");
  }

  if (import.meta.env.DEV) {
    // 开发态走同源地址，借助 Vite 代理统一入口为页面端口。
    return window.location.origin;
  }

  return window.location.origin;
}

/** 兼容旧命名，避免调用侧大面积改动。 */
export function resolveWebApiBase(): string {
  return resolveApiBaseUrl();
}

export function resolveRuntimeWindowLabel(): string {
  if (typeof window === "undefined") {
    return "main";
  }
  if (isTauriRuntime()) {
    return "main";
  }
  const query = new URLSearchParams(window.location.search);
  const fromQuery = query.get("windowLabel")?.trim();
  if (fromQuery) {
    return fromQuery;
  }

  const storageKey = "devhaven:web:window-label";
  try {
    const existing = window.sessionStorage.getItem(storageKey)?.trim();
    if (existing) {
      return existing;
    }
    const generated = `web-${Math.random().toString(36).slice(2, 10)}`;
    window.sessionStorage.setItem(storageKey, generated);
    return generated;
  } catch {
    return "main";
  }
}

export async function getAppVersionRuntime(): Promise<string> {
  if (!isTauriRuntime()) {
    const fromEnv = import.meta.env.VITE_APP_VERSION as string | undefined;
    return fromEnv?.trim() || "web";
  }

  const { getVersion } = await import("@tauri-apps/api/app");
  return getVersion();
}

export async function getHomeDirRuntime(): Promise<string> {
  if (isTauriRuntime()) {
    const { homeDir } = await import("@tauri-apps/api/path");
    return homeDir();
  }

  try {
    const response = await fetch(`${resolveApiBaseUrl()}/api/cmd/resolve_home_dir`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({}),
    });
    if (!response.ok) {
      return "~";
    }
    const payload = (await response.json()) as {
      ok?: boolean;
      data?: string;
    };
    if (!payload?.ok || typeof payload.data !== "string" || payload.data.trim().length === 0) {
      return "~";
    }
    return payload.data;
  } catch {
    return "~";
  }
}

export async function openUrlRuntime(url: string): Promise<void> {
  if (isTauriRuntime()) {
    const { openUrl } = await import("@tauri-apps/plugin-opener");
    await openUrl(url);
    return;
  }

  if (typeof window !== "undefined") {
    window.open(url, "_blank", "noopener,noreferrer");
  }
}

export async function openPathRuntime(path: string): Promise<void> {
  if (isTauriRuntime()) {
    const { openPath } = await import("@tauri-apps/plugin-opener");
    await openPath(path);
    return;
  }

  if (typeof window !== "undefined") {
    // 浏览器无法直接打开本地路径，仅尝试作为 URL 打开。
    const normalized = path.startsWith("http://") || path.startsWith("https://") ? path : `file://${path}`;
    window.open(normalized, "_blank", "noopener,noreferrer");
  }
}

export async function pickDirectoriesRuntime(): Promise<string[]> {
  if (isTauriRuntime()) {
    const { open } = await import("@tauri-apps/plugin-dialog");
    const selected = await open({
      directory: true,
      multiple: true,
    });
    if (!selected) {
      return [];
    }
    return Array.isArray(selected) ? selected : [selected];
  }

  if (typeof window === "undefined") {
    return [];
  }

  const raw = window.prompt("请输入目录路径（多个路径用英文逗号分隔）", "");
  if (!raw) {
    return [];
  }
  return raw
    .split(",")
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

export async function confirmRuntime(
  message: string,
  options?: {
    title?: string;
    kind?: "info" | "warning" | "error";
    okLabel?: string;
    cancelLabel?: string;
  },
): Promise<boolean> {
  if (isTauriRuntime()) {
    const { confirm } = await import("@tauri-apps/plugin-dialog");
    return confirm(message, options);
  }

  if (typeof window === "undefined") {
    return false;
  }
  return window.confirm(message);
}
