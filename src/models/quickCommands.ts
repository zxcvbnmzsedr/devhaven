export type QuickCommandState =
  | "queued"
  | "starting"
  | "running"
  | "stoppingSoft"
  | "stoppingHard"
  | "exited"
  | "failed"
  | "cancelled"
  | (string & {});

export type QuickCommandJob = {
  jobId: string;
  projectId: string;
  projectPath: string;
  scriptId: string;
  command: string;
  windowLabel?: string | null;
  state: QuickCommandState;
  createdAt: number;
  updatedAt: number;
  exitCode?: number | null;
  error?: string | null;
};

export type QuickCommandSnapshot = {
  jobs: QuickCommandJob[];
  updatedAt: number;
};

export type QuickCommandEventType = "started" | "stateChanged" | "exited" | "workspaceRestored" | (string & {});

export type QuickCommandEvent = {
  type: QuickCommandEventType;
  job: QuickCommandJob;
  snapshot: QuickCommandSnapshot;
};

export type QuickCommandStateChangedPayload = {
  jobId: string;
  scriptId: string;
  projectId: string;
  projectPath: string;
  state: QuickCommandState;
  updatedAt: number;
  exitCode?: number | null;
  error?: string | null;
};

export type QuickCommandRuntimeProjection = {
  projectPath: string;
  jobs: QuickCommandJob[];
  updatedAt: number;
};

export type StartQuickCommandRequest = {
  projectId: string;
  projectPath: string;
  scriptId: string;
  command: string;
  windowLabel?: string;
};

export type StopQuickCommandRequest = {
  jobId: string;
  force?: boolean;
};

export type FinishQuickCommandRequest = {
  jobId: string;
  exitCode?: number | null;
  error?: string | null;
};

export type ListQuickCommandsRequest = {
  projectPath?: string;
};

export type TerminalQuickCommandActionType = "run" | "stop";

export type TerminalQuickCommandDispatch = {
  seq: number;
  type: TerminalQuickCommandActionType;
  projectId: string;
  projectPath: string;
  scriptId: string;
};

export function buildQuickCommandRuntimeProjection(
  snapshot: QuickCommandSnapshot,
  projectPath?: string | null,
): QuickCommandRuntimeProjection {
  const normalizedPath = (projectPath ?? "").trim();
  return {
    projectPath: normalizedPath,
    jobs: normalizedPath
      ? snapshot.jobs.filter((job) => job.projectPath === normalizedPath)
      : [...snapshot.jobs],
    updatedAt: snapshot.updatedAt,
  };
}
