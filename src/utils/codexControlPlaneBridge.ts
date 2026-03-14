import type { CodexAgentEvent } from "../models/codex";

type ControlPlaneProjectTarget = {
  id: string;
  path: string;
  name: string;
};

export type CodexControlPlaneUpdate = {
  agentSessionEvent: {
    agentSessionId: string | null;
    workspaceId: string;
    projectPath: string;
    provider: "codex";
    status: "running" | "waiting" | "completed" | "failed" | "stopped";
    cwd: string | null;
    message: string | null;
  } | null;
  notification: {
    agentSessionId: string | null;
    workspaceId: string;
    projectPath: string;
    title: string;
    message: string;
    level: "info" | "attention" | "error";
  } | null;
};

function normalizeMessage(value: string | null | undefined): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

export function buildCodexControlPlaneUpdate(
  event: CodexAgentEvent,
  project: ControlPlaneProjectTarget,
): CodexControlPlaneUpdate {
  const agentSessionId = normalizeMessage(event.sessionId) ?? null;
  const cwd = normalizeMessage(event.workingDirectory) ?? project.path;
  const message = normalizeMessage(event.details);

  switch (event.type) {
    case "agent-start":
    case "agent-active":
      return {
        agentSessionEvent: {
          agentSessionId,
          workspaceId: project.id,
          projectPath: project.path,
          provider: "codex",
          status: "running",
          cwd,
          message,
        },
        notification: null,
      };
    case "agent-stop":
    case "agent-idle":
      return {
        agentSessionEvent: {
          agentSessionId,
          workspaceId: project.id,
          projectPath: project.path,
          provider: "codex",
          status: "stopped",
          cwd,
          message,
        },
        notification: null,
      };
    case "task-complete":
      return {
        agentSessionEvent: {
          agentSessionId,
          workspaceId: project.id,
          projectPath: project.path,
          provider: "codex",
          status: "completed",
          cwd,
          message,
        },
        notification: {
          agentSessionId,
          workspaceId: project.id,
          projectPath: project.path,
          title: "Codex 已完成",
          message: project.name,
          level: "info",
        },
      };
    case "task-error":
      return {
        agentSessionEvent: {
          agentSessionId,
          workspaceId: project.id,
          projectPath: project.path,
          provider: "codex",
          status: "failed",
          cwd,
          message,
        },
        notification: {
          agentSessionId,
          workspaceId: project.id,
          projectPath: project.path,
          title: "Codex 执行失败",
          message: project.name,
          level: "error",
        },
      };
    case "needs-attention":
      return {
        agentSessionEvent: {
          agentSessionId,
          workspaceId: project.id,
          projectPath: project.path,
          provider: "codex",
          status: "waiting",
          cwd,
          message,
        },
        notification: {
          agentSessionId,
          workspaceId: project.id,
          projectPath: project.path,
          title: "Codex 需要处理",
          message: project.name,
          level: "attention",
        },
      };
  }
}
