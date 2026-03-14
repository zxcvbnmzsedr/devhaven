import { useCallback, useEffect, useMemo, useRef } from "react";

import type { CodexAgentEvent, CodexSessionView } from "../models/codex";
import type { Project } from "../models/types";
import type { CodexMonitorStore } from "./useCodexMonitor";
import {
  emitAgentSessionEvent,
  listenControlPlaneChanged,
  loadControlPlaneTree,
  notifyControlPlane,
} from "../services/controlPlane";
import { sendSystemNotification } from "../services/system";
import { collectNewControlPlaneNotifications } from "../utils/controlPlaneAutoRead";
import { buildCodexProjectStatusById, type CodexProjectStatus } from "../utils/codexProjectStatus";
import { buildCodexControlPlaneUpdate } from "../utils/codexControlPlaneBridge";
import {
  buildCodexProjectMatchCandidates,
  buildCodexSessionViews,
  matchProjectByCwd,
  parseWorktreePathFromProjectId,
  resolveWorktreeVirtualProjectByPath,
} from "../utils/worktreeHelpers";

type UseCodexIntegrationParams = {
  projects: Project[];
  projectMap: Map<string, Project>;
  terminalOpenProjects: Project[];
  codexMonitorStore: CodexMonitorStore;
  showToast: (message: string, variant?: "success" | "error") => void;
  openTerminalWorkspace: (project: Project) => void;
};

export type UseCodexIntegrationReturn = {
  codexSessionViews: CodexSessionView[];
  codexProjectStatusById: Record<string, CodexProjectStatus>;
  handleOpenCodexSession: (session: CodexSessionView) => void;
};

/** 管理 Codex 会话与项目映射、通知提示和打开会话行为。 */
export function useCodexIntegration({
  projects,
  projectMap,
  terminalOpenProjects,
  codexMonitorStore,
  showToast,
  openTerminalWorkspace,
}: UseCodexIntegrationParams): UseCodexIntegrationReturn {
  const codexEventSnapshotRef = useRef<Set<string>>(new Set());
  const codexControlPlaneNotificationIdsRef = useRef<Set<string>>(new Set());

  const codexProjectMatchCandidates = useMemo(
    () => buildCodexProjectMatchCandidates(projects, terminalOpenProjects),
    [projects, terminalOpenProjects],
  );

  const codexSessionViews = useMemo(
    () => buildCodexSessionViews(codexMonitorStore.sessions, codexProjectMatchCandidates),
    [codexMonitorStore.sessions, codexProjectMatchCandidates],
  );

  const codexProjectStatusById = useMemo(
    () => buildCodexProjectStatusById(codexSessionViews),
    [codexSessionViews],
  );

  const resolveProjectFromCodexProjectId = useCallback(
    (projectId: string): Project | null => {
      const worktreePath = parseWorktreePathFromProjectId(projectId);
      if (worktreePath) {
        return resolveWorktreeVirtualProjectByPath(projects, worktreePath);
      }
      return projectMap.get(projectId) ?? null;
    },
    [projectMap, projects],
  );

  const resolveProjectFromCodexEvent = useCallback(
    (event: CodexAgentEvent): Project | null => {
      const bySession =
        event.sessionId
          ? codexSessionViews.find((session) => session.id === event.sessionId && session.projectId)
          : null;
      if (bySession?.projectId) {
        const resolved = resolveProjectFromCodexProjectId(bySession.projectId);
        if (resolved) {
          return resolved;
        }
      }

      if (event.workingDirectory) {
        return matchProjectByCwd(event.workingDirectory, codexProjectMatchCandidates);
      }

      return null;
    },
    [codexProjectMatchCandidates, codexSessionViews, resolveProjectFromCodexProjectId],
  );

  const handleOpenCodexSession = useCallback(
    (session: CodexSessionView) => {
      if (!session.projectId) {
        showToast("未能匹配到项目", "error");
        return;
      }
      const project = resolveProjectFromCodexProjectId(session.projectId);
      if (!project) {
        showToast("项目不存在或已移除", "error");
        return;
      }
      openTerminalWorkspace(project);
    },
    [openTerminalWorkspace, resolveProjectFromCodexProjectId, showToast],
  );

  useEffect(() => {
    let disposed = false;
    let unlisten: (() => void) | null = null;
    console.warn("[codex-debug] useCodexIntegration control-plane listener effect mounted");

    const rememberNotificationId = (notificationId: string) => {
      const seen = codexControlPlaneNotificationIdsRef.current;
      seen.add(notificationId);
      while (seen.size > 300) {
        const first = seen.values().next().value;
        if (!first) {
          break;
        }
        seen.delete(first);
      }
    };

    const resolveToastVariant = (message: string): "success" | "error" => {
      if (message.includes("失败") || message.includes("错误") || message.includes("需要处理")) {
        return "error";
      }
      return "success";
    };

    const resolveSystemNotification = (message: string) => {
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
    };

    const isCodexTree = (tree: Awaited<ReturnType<typeof loadControlPlaneTree>>) => {
      if (!tree) {
        return false;
      }
      return (
        tree.surfaces.some((surface) => surface.agentSession?.provider === "codex")
        || tree.notifications.some((notification) => notification.message.includes("Codex"))
      );
    };

    void listenControlPlaneChanged((event) => {
      const payload = event.payload;
      console.info("[codex-debug] control-plane-changed", payload);
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
      const workspaceId = payload.workspaceId;
      const updatedAt = payload.updatedAt;

      void (async () => {
        try {
          console.info("[codex-debug] loading control-plane tree for notification", {
            projectPath,
            workspaceId,
            updatedAt,
          });
          const tree = await loadControlPlaneTree({
            projectPath,
            workspaceId,
          });
          console.info("[codex-debug] loaded control-plane tree", tree);
          if (disposed || !isCodexTree(tree)) {
            console.info("[codex-debug] skip control-plane notification sync", {
              disposed,
              isCodexTree: isCodexTree(tree),
            });
            return;
          }
          const notifications = collectNewControlPlaneNotifications(tree, {
            since: updatedAt,
            seenIds: codexControlPlaneNotificationIdsRef.current,
          });
          console.info("[codex-debug] collected new control-plane notifications", notifications);
          for (const notification of notifications) {
            rememberNotificationId(notification.id);
            console.info("[codex-debug] forwarding control-plane notification to toast/system", notification);
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
          console.warn("[codex-debug] control-plane listener resolved after dispose");
          stop();
          return;
        }
        console.warn("[codex-debug] control-plane listener registered");
        unlisten = stop;
      })
      .catch((error) => {
        if (!disposed) {
          console.warn("[codex-debug] 监听控制面变更失败。", error);
        }
      });

    return () => {
      disposed = true;
      console.warn("[codex-debug] useCodexIntegration control-plane listener cleanup");
      unlisten?.();
    };
  }, [showToast]);

  useEffect(() => {
    if (codexMonitorStore.agentEvents.length === 0) {
      return;
    }

    const seen = codexEventSnapshotRef.current;
    const events = [...codexMonitorStore.agentEvents].reverse();
    for (const event of events) {
      const eventKey = [event.type, event.sessionId ?? "", String(event.timestamp), event.details ?? ""].join("|");
      if (seen.has(eventKey)) {
        continue;
      }
      seen.add(eventKey);
      if (seen.size > 300) {
        const first = seen.values().next().value;
        if (first) {
          seen.delete(first);
        }
      }

      const project = resolveProjectFromCodexEvent(event);
      const projectName = project?.name ?? "未匹配项目";
      let controlPlaneNotificationHandled = false;
      console.info("[codex-debug] monitor agent event", {
        event,
        projectId: project?.id ?? null,
        projectName,
      });
      if (project) {
        const controlPlaneUpdate = buildCodexControlPlaneUpdate(event, {
          id: project.id,
          path: project.path,
          name: project.name,
        });
        console.info("[codex-debug] mapped control-plane update", controlPlaneUpdate);
        if (controlPlaneUpdate.agentSessionEvent) {
          void emitAgentSessionEvent(controlPlaneUpdate.agentSessionEvent).catch((error) => {
            console.warn("桥接 Codex agent session 到控制面失败。", error);
          });
        }
        if (controlPlaneUpdate.notification) {
          controlPlaneNotificationHandled = true;
          void notifyControlPlane(controlPlaneUpdate.notification).catch((error) => {
            console.warn("桥接 Codex 通知到控制面失败。", error);
          });
        }
      }

      if (controlPlaneNotificationHandled) {
        console.info("[codex-debug] monitor event notification delegated to control-plane listener", event.type);
        continue;
      }

      if (event.type === "task-complete") {
        console.info("[codex-debug] showing direct completion toast", projectName);
        showToast(`Codex 已完成：${projectName}`);
        void sendSystemNotification("Codex 已完成", projectName);
      } else if (event.type === "task-error") {
        console.info("[codex-debug] showing direct error toast", projectName);
        showToast(`Codex 执行失败：${projectName}`, "error");
        void sendSystemNotification("Codex 执行失败", projectName);
      } else if (event.type === "needs-attention") {
        console.info("[codex-debug] showing direct attention toast", projectName);
        showToast(`Codex 需要你处理：${projectName}`, "error");
        void sendSystemNotification("Codex 需要处理", projectName);
      }
    }
  }, [codexMonitorStore.agentEvents, resolveProjectFromCodexEvent, showToast]);

  return {
    codexSessionViews,
    codexProjectStatusById,
    handleOpenCodexSession,
  };
}
