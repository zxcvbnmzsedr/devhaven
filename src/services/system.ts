import { invokeCommand } from "../platform/commandClient.ts";
import { isTauriRuntime } from "../platform/runtime.ts";

export type SystemNotificationRequest = {
  title: string;
  body?: string;
  tag?: string;
  onClick?: (() => void | Promise<void>) | null;
};

const activeNotifications = new Set<Notification>();

async function trySendWebNotification(request: SystemNotificationRequest): Promise<boolean> {
  if (typeof window === "undefined" || typeof Notification === "undefined") {
    console.info("[codex-debug] Notification API unavailable");
    return false;
  }

  try {
    let permission = Notification.permission;
    if (permission === "default") {
      permission = await Notification.requestPermission();
    }
    if (permission !== "granted") {
      console.info("[codex-debug] Notification permission not granted", { permission });
      return false;
    }

    const title = request.title.trim();
    if (!title) {
      return false;
    }

    const body = request.body?.trim();
    const tag = request.tag?.trim();
    const options: NotificationOptions = {};
    if (body) {
      options.body = body;
    }
    if (tag) {
      options.tag = tag;
    }
    const notification = new Notification(title, Object.keys(options).length > 0 ? options : undefined);
    activeNotifications.add(notification);
    const release = () => {
      activeNotifications.delete(notification);
    };
    notification.onclose = release;
    notification.onerror = release;
    if (request.onClick) {
      notification.onclick = (event) => {
        event.preventDefault?.();
        notification.close();
        void request.onClick?.();
      };
    }
    console.info("[codex-debug] web notification dispatched", {
      title,
      body,
      tag,
      isTauriRuntime: isTauriRuntime(),
    });
    return true;
  } catch (error) {
    console.warn("系统通知发送失败。", error);
    return false;
  }
}

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

/** 发送系统通知。优先使用 Web Notification API，以便保留点击回调；不可用时再回退到原生命令。 */
export async function sendSystemNotification(request: SystemNotificationRequest) {
  console.info("[codex-debug] sendSystemNotification called", {
    title: request.title,
    body: request.body,
    tag: request.tag,
    hasClickHandler: Boolean(request.onClick),
  });

  if (await trySendWebNotification(request)) {
    return;
  }

  if (!isTauriRuntime()) {
    return;
  }

  try {
    await invokeCommand("send_system_notification", {
      params: {
        title: request.title,
        body: request.body,
      },
    });
    console.info("[codex-debug] tauri fallback system notification dispatched", {
      title: request.title,
      body: request.body,
    });
  } catch (error) {
    console.warn("Tauri 系统通知发送失败。", error);
  }
}
