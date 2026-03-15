import type {
  ControlPlaneAgentSession,
  ControlPlaneAgentStatus,
  ControlPlaneNotification,
  ControlPlaneStatusPrimitive,
  ControlPlaneTree,
  ControlPlanePaneNode,
  ControlPlaneWorkspaceTree,
  WorkspaceAttentionProjection,
} from "../models/controlPlane";
import { projectTerminalPrimitives } from "./terminalPrimitiveProjection.ts";

export type ControlPlaneAttentionLevel =
  | "idle"
  | "running"
  | "waiting"
  | "error"
  | "completed";

export type ControlPlaneWorkspaceProjection = {
  unreadCount: number;
  latestMessage: string | null;
  attention: ControlPlaneAttentionLevel;
  activeAgentCount: number;
  waitingAgentCount: number;
  errorAgentCount: number;
};

export type ControlPlaneSurfaceProjection = {
  unreadCount: number;
  latestMessage: string | null;
  attention: ControlPlaneAttentionLevel;
  hasUnread: boolean;
};

export type PaneAttentionProjection = {
  status: ControlPlaneAgentStatus;
  unreadCount: number;
  tone: "idle" | "info" | "attention" | "error" | "success";
  lastMessage: string | null;
};

function toAttention(status: ControlPlaneAgentStatus | null | undefined): ControlPlaneAttentionLevel {
  switch (status) {
    case "failed":
      return "error";
    case "waiting":
      return "waiting";
    case "running":
      return "running";
    case "completed":
      return "completed";
    default:
      return "idle";
  }
}

function compareByUpdatedAtDesc<
  T extends {
    updatedAt?: number | null;
    createdAt?: number | null;
  },
>(left: T, right: T) {
  const leftTs = left.updatedAt ?? left.createdAt ?? 0;
  const rightTs = right.updatedAt ?? right.createdAt ?? 0;
  return rightTs - leftTs;
}

function pickLatestNotification(
  notifications: ControlPlaneNotification[],
): ControlPlaneNotification | null {
  if (notifications.length === 0) {
    return null;
  }
  return [...notifications].sort(compareByUpdatedAtDesc)[0] ?? null;
}

function pickLatestSession(
  sessions: ControlPlaneAgentSession[],
): ControlPlaneAgentSession | null {
  if (sessions.length === 0) {
    return null;
  }
  return [...sessions].sort(compareByUpdatedAtDesc)[0] ?? null;
}

function resolveLatestMessage(
  notifications: ControlPlaneNotification[],
  sessions: ControlPlaneAgentSession[],
  primitiveStatuses: ControlPlaneStatusPrimitive[] = [],
): string | null {
  const latestNotification = pickLatestNotification(notifications);
  if (latestNotification?.message) {
    return latestNotification.message;
  }
  return (
    pickLatestSession(sessions)?.message
    ?? [...primitiveStatuses].sort(compareByUpdatedAtDesc)[0]?.value
    ?? null
  );
}

function normalizePrimitiveStatusValue(value: string | null | undefined): ControlPlaneAgentStatus {
  const normalized = String(value ?? "").trim().toLowerCase();
  if (normalized.includes("fail") || normalized.includes("error")) {
    return "failed";
  }
  if (normalized.includes("wait") || normalized.includes("input") || normalized.includes("need")) {
    return "waiting";
  }
  if (normalized.includes("run") || normalized.includes("progress")) {
    return "running";
  }
  if (normalized.includes("complete") || normalized.includes("done") || normalized.includes("success")) {
    return "completed";
  }
  return "idle";
}

function pickLatestPrimitiveStatusForSurface(
  statuses: ControlPlaneStatusPrimitive[],
  surface: ControlPlanePaneNode,
): ControlPlaneStatusPrimitive | null {
  const matched = statuses.filter((status) =>
    (status.surfaceId && status.surfaceId === surface.surfaceId)
    || (status.paneId && status.paneId === surface.paneId)
  );
  if (matched.length === 0) {
    return null;
  }
  return [...matched].sort(compareByUpdatedAtDesc)[0] ?? null;
}

export function deriveAttentionTone(input: {
  status: ControlPlaneAgentStatus;
  unreadCount: number;
}): PaneAttentionProjection["tone"] {
  if (input.status === "failed") {
    return "error";
  }
  if (input.unreadCount > 0 || input.status === "waiting") {
    return "attention";
  }
  if (input.status === "completed") {
    return "success";
  }
  if (input.status === "running") {
    return "info";
  }
  return "idle";
}

export function projectControlPlaneSurface(
  surface: ControlPlanePaneNode,
  tree?: ControlPlaneWorkspaceTree | ControlPlaneTree | null,
): ControlPlaneSurfaceProjection {
  const latestPrimitiveStatus = pickLatestPrimitiveStatusForSurface(tree?.statuses ?? [], surface);
  const notifications = surface.unreadCount
    ? [
        {
          id: `${surface.surfaceId}:latest`,
          message: surface.agentSession?.message ?? latestPrimitiveStatus?.value ?? "",
          createdAt: surface.agentSession?.updatedAt ?? latestPrimitiveStatus?.updatedAt ?? 0,
          read: surface.unreadCount === 0,
        },
      ]
    : [];
  const sessions = surface.agentSession ? [surface.agentSession] : [];
  const status = surface.agentSession?.status ?? normalizePrimitiveStatusValue(latestPrimitiveStatus?.value);

  return {
    unreadCount: Math.max(0, surface.unreadCount ?? 0),
    latestMessage: resolveLatestMessage(
      notifications,
      sessions,
      latestPrimitiveStatus ? [latestPrimitiveStatus] : [],
    ),
    attention: toAttention(status),
    hasUnread: (surface.unreadCount ?? 0) > 0,
  };
}

export function projectControlPlaneWorkspace(
  tree: ControlPlaneWorkspaceTree | null | undefined,
): ControlPlaneWorkspaceProjection {
  if (!tree) {
    return {
      unreadCount: 0,
      latestMessage: null,
      attention: "idle",
      activeAgentCount: 0,
      waitingAgentCount: 0,
      errorAgentCount: 0,
    };
  }

  const sessions = tree.surfaces
    .map((surface) => surface.agentSession)
    .filter((session): session is ControlPlaneAgentSession => Boolean(session));
  const primitiveStatuses = Object.values(projectTerminalPrimitives(tree).statusesByKey);
  const primitiveAgentStatuses = primitiveStatuses.map((status) => ({
    status: normalizePrimitiveStatusValue(status.value),
    message: status.value,
  }));
  const unreadCount = tree.notifications.filter((notification) => !notification.read).length;

  let attention: ControlPlaneAttentionLevel = "idle";
  if (
    sessions.some((session) => session.status === "failed")
    || primitiveAgentStatuses.some((status) => status.status === "failed")
  ) {
    attention = "error";
  } else if (
    sessions.some((session) => session.status === "waiting")
    || primitiveAgentStatuses.some((status) => status.status === "waiting")
  ) {
    attention = "waiting";
  } else if (
    sessions.some((session) => session.status === "running")
    || primitiveAgentStatuses.some((status) => status.status === "running")
  ) {
    attention = "running";
  } else if (
    sessions.some((session) => session.status === "completed")
    || primitiveAgentStatuses.some((status) => status.status === "completed")
  ) {
    attention = "completed";
  }

  return {
    unreadCount,
    latestMessage: resolveLatestMessage(tree.notifications, sessions, primitiveStatuses),
    attention,
    activeAgentCount:
      sessions.filter((session) => session.status === "running" || session.status === "waiting").length
      + primitiveAgentStatuses.filter((status) =>
        status.status === "running" || status.status === "waiting",
      ).length,
    waitingAgentCount:
      sessions.filter((session) => session.status === "waiting").length
      + primitiveAgentStatuses.filter((status) => status.status === "waiting").length,
    errorAgentCount:
      sessions.filter((session) => session.status === "failed").length
      + primitiveAgentStatuses.filter((status) => status.status === "failed").length,
  };
}

export function countRunningProviderSessions(
  tree: ControlPlaneWorkspaceTree | ControlPlaneTree | null | undefined,
  provider: string,
): number {
  if (!tree) {
    return 0;
  }
  const surfaces = "surfaces" in tree ? tree.surfaces : tree.panes;
  const sessionCount = surfaces.reduce((count, surface) => {
    const session = surface.agentSession;
    if (!session) {
      return count;
    }
    return count + (session.provider === provider && session.status === "running" ? 1 : 0);
  }, 0);
  if (sessionCount > 0) {
    return sessionCount;
  }
  const primitiveStatus = projectTerminalPrimitives(tree).statusesByKey[provider];
  return primitiveStatus && normalizePrimitiveStatusValue(primitiveStatus.value) === "running" ? 1 : 0;
}

export function resolveDisplayedControlPlaneMessage(
  surface: ControlPlaneSurfaceProjection | null | undefined,
  workspace: ControlPlaneWorkspaceProjection | null | undefined,
): string | null {
  return surface?.latestMessage ?? workspace?.latestMessage ?? null;
}

export function buildWorkspaceAttentionProjection(
  tree: ControlPlaneWorkspaceTree | ControlPlaneTree,
): WorkspaceAttentionProjection {
  const workspaceTree: ControlPlaneWorkspaceTree = "surfaces" in tree
    ? tree
    : {
        workspaceId: tree.workspaceId,
        projectPath: tree.projectPath,
        surfaces: tree.panes,
        notifications: tree.notifications,
      };
  const projection = projectControlPlaneWorkspace(workspaceTree);
  const status: ControlPlaneAgentStatus =
    projection.attention === "error"
      ? "failed"
      : projection.attention === "waiting"
        ? "waiting"
        : projection.attention === "running"
          ? "running"
          : projection.attention === "completed"
            ? "completed"
            : "idle";
  return {
    workspaceId: tree.workspaceId,
    projectPath: tree.projectPath,
    unreadCount: projection.unreadCount,
    status,
    lastMessage: projection.latestMessage,
    tone: deriveAttentionTone({
      status,
      unreadCount: projection.unreadCount,
    }),
  };
}

export function buildPaneAttentionMap(
  tree: ControlPlaneWorkspaceTree | ControlPlaneTree,
): Record<string, PaneAttentionProjection> {
  const surfaces = "surfaces" in tree ? tree.surfaces : tree.panes;
  const entries = surfaces.map((surface) => {
    const latestPrimitiveStatus = pickLatestPrimitiveStatusForSurface(tree.statuses ?? [], surface);
    const status = surface.agentSession?.status
      ?? normalizePrimitiveStatusValue(latestPrimitiveStatus?.value);
    const projection = projectControlPlaneSurface(surface, tree);
    return [
      surface.paneId,
      {
        status,
        unreadCount: projection.unreadCount,
        tone: deriveAttentionTone({
          status,
          unreadCount: projection.unreadCount,
        }),
        lastMessage: projection.latestMessage ?? latestPrimitiveStatus?.value ?? null,
      },
    ] as const;
  });
  return Object.fromEntries(entries.filter(([paneId]) => typeof paneId === "string" && paneId.length > 0));
}
