export type ControlPlaneAgentStatus =
  | "idle"
  | "running"
  | "waiting"
  | "failed"
  | "completed"
  | "stopped";

export type ControlPlaneAgentSession = {
  agentSessionId: string;
  provider: string;
  status: ControlPlaneAgentStatus;
  message?: string | null;
  updatedAt: number;
};

export type ControlPlaneNotification = {
  id: string;
  message: string;
  createdAt: number;
  read: boolean;
};

export type ControlPlanePaneNode = {
  paneId: string;
  surfaceId: string;
  terminalSessionId?: string | null;
  unreadCount?: number;
  agentSession?: ControlPlaneAgentSession | null;
};

export type ControlPlaneTree = {
  workspaceId: string;
  projectPath: string;
  panes: ControlPlanePaneNode[];
  notifications: ControlPlaneNotification[];
};

export type ControlPlaneWorkspaceTree = {
  workspaceId: string;
  projectPath: string;
  surfaces: ControlPlanePaneNode[];
  notifications: ControlPlaneNotification[];
};

export type ControlPlaneChangedPayload = {
  projectPath?: string | null;
  workspaceId?: string | null;
  reason?: string | null;
  updatedAt?: number | null;
};

export type ControlPlaneAttentionTone = "idle" | "info" | "attention" | "error" | "success";

export type WorkspaceAttentionProjection = {
  workspaceId: string;
  projectPath: string;
  unreadCount: number;
  status: ControlPlaneAgentStatus;
  lastMessage: string | null;
  tone: ControlPlaneAttentionTone;
};
