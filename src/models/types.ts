export type SwiftDate = number;

export type ColorData = {
  r: number;
  g: number;
  b: number;
  a: number;
};

export type TagData = {
  name: string;
  color: ColorData;
  hidden: boolean;
};

export type OpenToolSettings = {
  commandPath: string;
  arguments: string[];
};

export type ProjectScript = {
  id: string;
  name: string;
  start: string;
  paramSchema?: ScriptParamField[];
  templateParams?: Record<string, string>;
};

export type ScriptParamFieldType = "text" | "number" | "secret";

export type ScriptParamField = {
  key: string;
  label: string;
  type: ScriptParamFieldType;
  required: boolean;
  defaultValue?: string;
  description?: string;
};

export type SharedScriptEntry = {
  id: string;
  name: string;
  absolutePath: string;
  relativePath: string;
  commandTemplate: string;
  params: ScriptParamField[];
};

export type SharedScriptManifestScript = {
  id: string;
  name: string;
  path: string;
  commandTemplate: string;
  params: ScriptParamField[];
};

export type SharedScriptPresetRestoreResult = {
  presetVersion: string;
  addedScripts: number;
  skippedScripts: number;
  createdFiles: number;
};

export type ProjectWorktree = {
  id: string;
  name: string;
  path: string;
  branch: string;
  baseBranch?: string;
  inheritConfig: boolean;
  created: SwiftDate;
  status?: "creating" | "ready" | "failed";
  initStep?:
    | "pending"
    | "validating"
    | "checking_branch"
    | "creating_worktree"
    | "preparing_environment"
    | "syncing"
    | "ready"
    | "failed"
    | "cancelled";
  initMessage?: string;
  initError?: string | null;
  initJobId?: string | null;
  updatedAt?: SwiftDate;
};

export type GitIdentity = {
  name: string;
  email: string;
};

export type GlobalSkillAgent = {
  id: string;
  label: string;
};

export type GlobalSkillSummary = {
  name: string;
  description: string;
  canonicalPath: string;
  paths: string[];
  agents: GlobalSkillAgent[];
};

export type GlobalSkillsSnapshot = {
  agents: GlobalSkillAgent[];
  skills: GlobalSkillSummary[];
};

export type GlobalSkillInstallRequest = {
  source: string;
  skillNames: string[];
  agentIds: string[];
};

export type GlobalSkillUninstallRequest = {
  skillName: string;
  canonicalPath: string;
  paths: string[];
  agentId: string;
};

export type GlobalSkillInstallResult = {
  command: string;
  stdout: string;
  stderr: string;
};

export type ProjectListViewMode = "card" | "list";

export type AppSettings = {
  editorOpenTool: OpenToolSettings;
  terminalOpenTool: OpenToolSettings;
  terminalUseWebglRenderer: boolean;
  terminalTheme: string;
  gitIdentities: GitIdentity[];
  projectListViewMode: ProjectListViewMode;
  sharedScriptsRoot: string;
};

export type AppStateFile = {
  version: number;
  tags: TagData[];
  directories: string[];
  recycleBin: string[];
  favoriteProjectPaths: string[];
  settings: AppSettings;
};

export type Project = {
  id: string;
  name: string;
  path: string;
  tags: string[];
  scripts: ProjectScript[];
  worktrees: ProjectWorktree[];
  mtime: SwiftDate;
  size: number;
  checksum: string;
  git_commits: number;
  git_last_commit: SwiftDate;
  git_last_commit_message?: string | null;
  git_daily?: string | null;
  created: SwiftDate;
  checked: SwiftDate;
};

const APPLE_REFERENCE_EPOCH_MS = Date.UTC(2001, 0, 1, 0, 0, 0, 0);

/** 将 Swift 时间戳（以 2001-01-01 为起点）转为 JS Date。 */
export function swiftDateToJsDate(swiftDate: SwiftDate): Date {
  return new Date(APPLE_REFERENCE_EPOCH_MS + swiftDate * 1000);
}

/** 将 JS Date 转为 Swift 时间戳（以 2001-01-01 为起点）。 */
export function jsDateToSwiftDate(date: Date): SwiftDate {
  return (date.getTime() - APPLE_REFERENCE_EPOCH_MS) / 1000;
}
