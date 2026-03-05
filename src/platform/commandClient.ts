import { invoke } from "@tauri-apps/api/core";

import { isTauriRuntime, resolveWebApiBase } from "./runtime";

type WebCommandResponse<T> = {
  ok: boolean;
  data: T;
  error?: string | null;
};

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

  const data = (await response.json()) as WebCommandResponse<T>;
  if (!response.ok || !data.ok) {
    throw new Error(data.error ?? `命令调用失败: ${command}`);
  }
  return data.data;
}
