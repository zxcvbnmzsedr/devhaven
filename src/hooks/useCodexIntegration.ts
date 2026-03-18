import { useEffect, useRef } from "react";

import { isTauriRuntime } from "../platform/runtime";
import type { ControlPlaneNotification } from "../models/controlPlane";
import type { Project } from "../models/types";
import {
  listenControlPlaneChanged,
  loadControlPlaneTree,
} from "../services/controlPlane";
import { sendSystemNotification } from "../services/system";
import { collectNewControlPlaneNotifications } from "../utils/controlPlaneAutoRead";
import { resolveNotificationProject } from "../utils/controlPlaneNotificationRouting.ts";

type UseCodexIntegrationParams = {
  showToast: (message: string, variant?: "success" | "error") => void;
  projects: Project[];
  openTerminalWorkspace: (project: Project) => void;
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

function isCodexNotification(notification: ControlPlaneNotification | null | undefined) {
  if (!notification) {
    return false;
  }
  return (
    notification.title?.includes("Codex")
    || notification.message.includes("Codex")
    || notification.body?.includes("Codex")
  );
}

function resolveNotificationMessage(notification: ControlPlaneNotification | null | undefined) {
  if (!notification) {
    return null;
  }
  const displayMessage = notification.message?.trim();
  if (displayMessage) {
    return displayMessage;
  }
  if (notification.title?.trim() && notification.body?.trim()) {
    return `${notification.title.trim()}：${notification.body.trim()}`;
  }
  return notification.body?.trim() || notification.title?.trim() || null;
}

function resolveSystemNotification(notification: ControlPlaneNotification) {
  const title = notification.title?.trim();
  const body = notification.body?.trim() || notification.message?.trim() || "";
  if (title) {
    return {
      title,
      body,
    };
  }
  const message = resolveNotificationMessage(notification) ?? "Codex 通知";
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
export function useCodexIntegration({ showToast, projects, openTerminalWorkspace }: UseCodexIntegrationParams) {
  const seenNotificationIdsRef = useRef<Set<string>>(new Set());
  const projectsRef = useRef<Project[]>(projects);
  const openTerminalWorkspaceRef = useRef(openTerminalWorkspace);

  useEffect(() => {
    projectsRef.current = projects;
    openTerminalWorkspaceRef.current = openTerminalWorkspace;
  }, [openTerminalWorkspace, projects]);

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

    const handleNotificationClick = async (notification: ControlPlaneNotification) => {
      const targetProject = resolveNotificationProject(projectsRef.current, notification);
      if (targetProject) {
        openTerminalWorkspaceRef.current(targetProject);
      }
      if (!isTauriRuntime()) {
        return;
      }
      try {
        const { getCurrentWindow } = await import("@tauri-apps/api/window");
        const currentWindow = getCurrentWindow();
        await currentWindow.show().catch(() => undefined);
        await currentWindow.setFocus().catch(() => undefined);
      } catch (error) {
        if (!disposed) {
          console.warn("通知点击后聚焦窗口失败。", error);
        }
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
      const eventNotification = payload.notification ?? undefined;
      const notificationId = payload.notificationId ?? undefined;
      if (eventNotification && isCodexNotification(eventNotification)) {
        const eventNotificationId = eventNotification.id || notificationId;
        if (eventNotificationId && seenNotificationIdsRef.current.has(eventNotificationId)) {
          return;
        }
        const displayMessage = resolveNotificationMessage(eventNotification) ?? "Codex 需要你的关注";
        if (eventNotificationId) {
          rememberNotificationId(eventNotificationId);
        }
        showToast(displayMessage, resolveToastVariant(displayMessage));
        const systemNotification = resolveSystemNotification(eventNotification);
        void sendSystemNotification({
          title: systemNotification.title,
          body: systemNotification.body,
          tag: eventNotificationId ? `control-plane:${eventNotificationId}` : undefined,
          onClick: () => handleNotificationClick(eventNotification),
        });
        return;
      }

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
            notificationIds: notificationId ? [notificationId] : undefined,
          });
          for (const notification of notifications) {
            rememberNotificationId(notification.id);
            const displayMessage = resolveNotificationMessage(notification) ?? notification.message;
            showToast(displayMessage, resolveToastVariant(displayMessage));
            const systemNotification = resolveSystemNotification(notification);
            void sendSystemNotification({
              title: systemNotification.title,
              body: systemNotification.body,
              tag: `control-plane:${notification.id}`,
              onClick: () => handleNotificationClick(notification),
            });
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
