export type ExternalAgentProvider = string;

export type AgentSessionLastKnownState =
  | "active"
  | "needs_attention"
  | "completed"
  | "failed"
  | "stopped"
  | "orphaned";

export type AgentRecoverySource = "runtime" | "monitor" | "hook" | "manual";

export type AgentSessionRecord = {
  id: string;
  provider: ExternalAgentProvider;
  projectId?: string | null;
  projectPath: string;
  worktreePath?: string | null;
  cwd: string;
  paneId?: string | null;
  tabId?: string | null;
  windowId?: string | null;
  externalSessionId?: string | null;
  transcriptPath?: string | null;
  rolloutPath?: string | null;
  logPath?: string | null;
  model?: string | null;
  promptDigest?: string | null;
  resumeHint?: string | null;
  lastKnownState: AgentSessionLastKnownState;
  lastSummary?: string | null;
  attentionReason?: string | null;
  lastError?: string | null;
  reconnectable: boolean;
  recoverySource: AgentRecoverySource | string;
  startedAt?: number | null;
  updatedAt: number;
  endedAt?: number | null;
};

export type AgentSessionsFile = {
  version: number;
  sessions: Record<string, AgentSessionRecord>;
};
