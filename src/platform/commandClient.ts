import { invoke } from "@tauri-apps/api/core";

import { isTauriRuntime, resolveWebApiBase } from "./runtime.ts";

type LegacyWebCommandResponse<T> = {
  ok: boolean;
  data: T;
  error?: string | null;
};

type StructuredWebCommandError = {
  code?: string;
  message?: string;
  error?: string;
  details?: unknown;
};

function tryParseJson(text: string): unknown {
  if (!text.trim()) {
    return null;
  }
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

function resolveWebCommandError(command: string, payload: unknown): Error {
  if (payload && typeof payload === "object") {
    const structured = payload as StructuredWebCommandError;
    const message = structured.message ?? structured.error ?? `命令调用失败: ${command}`;
    if (structured.code) {
      return new Error(`[${structured.code}] ${message}`);
    }
    return new Error(message);
  }

  if (typeof payload === "string" && payload.trim()) {
    return new Error(payload);
  }

  return new Error(`命令调用失败: ${command}`);
}

/** 统一命令调用入口：Tauri 走 invoke，浏览器走 HTTP。 */
export async function invokeCommand<T>(command: string, payload?: Record<string, unknown>): Promise<T> {
  if (isTauriRuntime()) {
    return invoke<T>(command, payload);
  }

  const response = await fetch(`${resolveWebApiBase()}/api/cmd/${command}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify(payload ?? {}),
  });

  const rawText = await response.text();
  const parsed = tryParseJson(rawText);

  if (!response.ok) {
    throw resolveWebCommandError(command, parsed);
  }

  if (
    parsed &&
    typeof parsed === "object" &&
    "ok" in parsed &&
    "data" in parsed
  ) {
    const legacy = parsed as LegacyWebCommandResponse<T>;
    if (!legacy.ok) {
      throw resolveWebCommandError(command, legacy);
    }
    return legacy.data;
  }

  return parsed as T;
}
