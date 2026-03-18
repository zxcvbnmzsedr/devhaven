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
  title?: string | null;
  subtitle?: string | null;
  body?: string | null;
  message: string;
  level?: string | null;
  paneId?: string | null;
  surfaceId?: string | null;
  terminalSessionId?: string | null;
  workspaceId?: string | null;
  projectPath?: string | null;
  agentSessionId?: string | null;
  createdAt: number;
  updatedAt?: number | null;
  read: boolean;
};

export type ControlPlaneStatusPrimitive = {
  key: string;
  value: string;
  icon?: string | null;
  color?: string | null;
  paneId?: string | null;
  surfaceId?: string | null;
  terminalSessionId?: string | null;
  createdAt: number;
  updatedAt: number;
};

export type ControlPlaneAgentPidPrimitive = {
  key: string;
  pid: number;
  paneId?: string | null;
  surfaceId?: string | null;
  terminalSessionId?: string | null;
  updatedAt: number;
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
  statuses?: ControlPlaneStatusPrimitive[];
  agentPids?: ControlPlaneAgentPidPrimitive[];
};

export type ControlPlaneWorkspaceTree = {
  workspaceId: string;
  projectPath: string;
  surfaces: ControlPlanePaneNode[];
  notifications: ControlPlaneNotification[];
  statuses?: ControlPlaneStatusPrimitive[];
  agentPids?: ControlPlaneAgentPidPrimitive[];
};

export type ControlPlaneChangedPayload = {
  projectPath?: string | null;
  workspaceId?: string | null;
  notificationId?: string | null;
  notification?: ControlPlaneNotification | null;
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
