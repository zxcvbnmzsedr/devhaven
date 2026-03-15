import { useEffect, useRef } from "react";

import {
  listenControlPlaneChanged,
  loadControlPlaneTree,
} from "../services/controlPlane";
import { sendSystemNotification } from "../services/system";
import { collectNewControlPlaneNotifications } from "../utils/controlPlaneAutoRead";

type UseCodexIntegrationParams = {
  showToast: (message: string, variant?: "success" | "error") => void;
};

function isCodexTree(tree: Awaited<ReturnType<typeof loadControlPlaneTree>>) {
  if (!tree) {
    return false;
  }
  return (
    tree.surfaces.some((surface) => surface.agentSession?.provider === "codex")
    || (tree.statuses ?? []).some((status) => status.key === "codex")
    || (tree.agentPids ?? []).some((record) => record.key === "codex")
    || tree.notifications.some((notification) => notification.message.includes("Codex"))
  );
}

function resolveToastVariant(message: string): "success" | "error" {
  if (message.includes("失败") || message.includes("错误") || message.includes("需要处理")) {
    return "error";
  }
  return "success";
}

function resolveSystemNotification(message: string) {
  const separatorIndex = message.indexOf("：");
  if (separatorIndex <= 0) {
    return {
      title: "Codex 通知",
      body: message,
    };
  }
  return {
    title: message.slice(0, separatorIndex),
    body: message.slice(separatorIndex + 1),
  };
}

/** 监听控制面中的 Codex 通知，并转发为 toast / 系统通知。 */
export function useCodexIntegration({ showToast }: UseCodexIntegrationParams) {
  const seenNotificationIdsRef = useRef<Set<string>>(new Set());

  useEffect(() => {
    let disposed = false;
    let unlisten: (() => void) | null = null;

    const rememberNotificationId = (notificationId: string) => {
      const seen = seenNotificationIdsRef.current;
      seen.add(notificationId);
      while (seen.size > 300) {
        const first = seen.values().next().value;
        if (!first) {
          break;
        }
        seen.delete(first);
      }
    };

    void listenControlPlaneChanged((event) => {
      const payload = event.payload;
      if (
        disposed
        || !payload
        || payload.reason !== "notification"
        || !payload.projectPath
        || typeof payload.updatedAt !== "number"
      ) {
        return;
      }
      const projectPath = payload.projectPath;
      const updatedAt = payload.updatedAt;
      const workspaceId = payload.workspaceId ?? undefined;

      void (async () => {
        try {
          const tree = await loadControlPlaneTree({
            projectPath,
            workspaceId,
          });
          if (disposed || !isCodexTree(tree)) {
            return;
          }
          const notifications = collectNewControlPlaneNotifications(tree, {
            since: updatedAt,
            seenIds: seenNotificationIdsRef.current,
          });
          for (const notification of notifications) {
            rememberNotificationId(notification.id);
            showToast(notification.message, resolveToastVariant(notification.message));
            const systemNotification = resolveSystemNotification(notification.message);
            void sendSystemNotification(systemNotification.title, systemNotification.body);
          }
        } catch (error) {
          if (!disposed) {
            console.warn("同步控制面 Codex 通知到 UI 失败。", error);
          }
        }
      })();
    })
      .then((stop) => {
        if (disposed) {
          stop();
          return;
        }
        unlisten = stop;
      })
      .catch((error) => {
        if (!disposed) {
          console.warn("监听控制面 Codex 变更失败。", error);
        }
      });

    return () => {
      disposed = true;
      unlisten?.();
    };
  }, [showToast]);
}
