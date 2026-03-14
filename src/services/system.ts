import { invokeCommand } from "../platform/commandClient";
import { isTauriRuntime } from "../platform/runtime";

/** 在系统文件管理器中定位路径。 */
export async function openInFinder(path: string) {
  await invokeCommand("open_in_finder", { path });
}

/** 将内容写入系统剪贴板。 */
export async function copyToClipboard(content: string) {
  if (typeof navigator !== "undefined" && navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(content);
      return;
    } catch (error) {
      console.warn("浏览器剪贴板写入失败，尝试使用系统命令。", error);
    }
  }
  await invokeCommand("copy_to_clipboard", { content });
}

/** 发送系统通知。 */
export async function sendSystemNotification(title: string, body?: string) {
  console.info("[codex-debug] sendSystemNotification called", { title, body });
  if (isTauriRuntime()) {
    try {
      await invokeCommand("send_system_notification", { params: { title, body } });
      console.info("[codex-debug] tauri system notification dispatched", { title, body });
      return;
    } catch (error) {
      console.warn("Tauri 系统通知发送失败，回退到浏览器通知。", error);
    }
  }
  if (typeof window === "undefined" || typeof Notification === "undefined") {
    console.info("[codex-debug] Notification API unavailable");
    return;
  }
  try {
    let permission = Notification.permission;
    if (permission === "default") {
      permission = await Notification.requestPermission();
    }
    if (permission !== "granted") {
      console.info("[codex-debug] Notification permission not granted", { permission });
      return;
    }
    const options = body ? { body } : undefined;
    new Notification(title, options);
    console.info("[codex-debug] system notification dispatched", { title, body });
  } catch (error) {
    console.warn("系统通知发送失败。", error);
  }
}
