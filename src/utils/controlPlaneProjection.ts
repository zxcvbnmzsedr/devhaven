import type {
  ControlPlaneAgentSession,
  ControlPlaneAgentStatus,
  ControlPlaneNotification,
  ControlPlaneTree,
  ControlPlanePaneNode,
  ControlPlaneWorkspaceTree,
  WorkspaceAttentionProjection,
} from "../models/controlPlane";

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
): string | null {
  const latestNotification = pickLatestNotification(notifications);
  if (latestNotification?.message) {
    return latestNotification.message;
  }
  return pickLatestSession(sessions)?.message ?? null;
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
): ControlPlaneSurfaceProjection {
  const notifications = surface.unreadCount
    ? [
        {
          id: `${surface.surfaceId}:latest`,
          message: surface.agentSession?.message ?? "",
          createdAt: surface.agentSession?.updatedAt ?? 0,
          read: surface.unreadCount === 0,
        },
      ]
    : [];
  const sessions = surface.agentSession ? [surface.agentSession] : [];

  return {
    unreadCount: Math.max(0, surface.unreadCount ?? 0),
    latestMessage: resolveLatestMessage(notifications, sessions),
    attention: toAttention(surface.agentSession?.status),
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
  const unreadCount = tree.notifications.filter((notification) => !notification.read).length;

  let attention: ControlPlaneAttentionLevel = "idle";
  if (sessions.some((session) => session.status === "failed")) {
    attention = "error";
  } else if (sessions.some((session) => session.status === "waiting")) {
    attention = "waiting";
  } else if (sessions.some((session) => session.status === "running")) {
    attention = "running";
  } else if (sessions.some((session) => session.status === "completed")) {
    attention = "completed";
  }

  return {
    unreadCount,
    latestMessage: resolveLatestMessage(tree.notifications, sessions),
    attention,
    activeAgentCount: sessions.filter((session) =>
      session.status === "running" || session.status === "waiting",
    ).length,
    waitingAgentCount: sessions.filter((session) => session.status === "waiting").length,
    errorAgentCount: sessions.filter((session) => session.status === "failed").length,
  };
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
    const status = surface.agentSession?.status ?? "idle";
    const projection = projectControlPlaneSurface(surface);
    return [
      surface.paneId,
      {
        status,
        unreadCount: projection.unreadCount,
        tone: deriveAttentionTone({
          status,
          unreadCount: projection.unreadCount,
        }),
        lastMessage: projection.latestMessage,
      },
    ] as const;
  });
  return Object.fromEntries(entries.filter(([paneId]) => typeof paneId === "string" && paneId.length > 0));
}
