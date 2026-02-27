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

export type QuickCommandEvent = {
  type: "started" | "stateChanged" | "exited" | (string & {});
  job: QuickCommandJob;
  snapshot: QuickCommandSnapshot;
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
