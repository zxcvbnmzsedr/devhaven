import type { CommandPaletteItem } from "../components/CommandPalette";
import type { CodexMonitorSession, CodexSessionView } from "../models/codex";
import type { Project, ProjectWorktree } from "../models/types";
import { jsDateToSwiftDate } from "../models/types";
import { resolveRuntimeWindowLabel } from "../platform/runtime";
import type { GitWorktreeListItem } from "../services/gitWorktree";

export const MAIN_WINDOW_LABEL = resolveRuntimeWindowLabel();

export type CommandPaletteAction = CommandPaletteItem & {
  searchText: string;
  run: () => void;
};

export function createWorktreeProjectId(path: string): string {
  return `worktree:${path}`;
}

export function isWorktreeProject(project: Project): boolean {
  return project.id.startsWith("worktree:");
}

export function parseWorktreePathFromProjectId(projectId: string): string | null {
  if (!projectId.startsWith("worktree:")) {
    return null;
  }
  return projectId.slice("worktree:".length);
}

export function resolveNameFromPath(path: string): string {
  const normalized = path.replace(/\\/g, "/").replace(/\/+$/, "");
  const last = normalized.split("/").filter(Boolean).pop();
  return last || normalized || path;
}

export function normalizePathForCompare(path: string): string {
  return path.trim().replace(/\\/g, "/").replace(/\/+$/, "");
}

export function resolveErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export function isSamePath(left: string, right: string): boolean {
  return normalizePathForCompare(left) === normalizePathForCompare(right);
}

export function resolveWorktreeVirtualProjectByPath(projects: Project[], worktreePath: string): Project | null {
  const normalizedTarget = normalizePathForCompare(worktreePath);
  for (const project of projects) {
    if (isWorktreeProject(project)) {
      continue;
    }
    const worktree = (project.worktrees ?? []).find(
      (item) => normalizePathForCompare(item.path) === normalizedTarget,
    );
    if (!worktree) {
      continue;
    }
    return buildWorktreeVirtualProject(project, worktree);
  }
  return null;
}

export function resolveWorktreeSourceProjectByPath(projects: Project[], worktreePath: string): Project | null {
  const normalizedTarget = normalizePathForCompare(worktreePath);
  for (const project of projects) {
    if (isWorktreeProject(project)) {
      continue;
    }
    const hasWorktree = (project.worktrees ?? []).some(
      (item) => normalizePathForCompare(item.path) === normalizedTarget,
    );
    if (hasWorktree) {
      return project;
    }
  }
  return null;
}

export function buildCodexProjectMatchCandidates(
  projects: Project[],
  terminalOpenProjects: Project[],
): Project[] {
  const byId = new Map<string, Project>();

  for (const project of projects) {
    byId.set(project.id, project);
  }

  for (const project of projects) {
    if (isWorktreeProject(project)) {
      continue;
    }
    for (const worktree of project.worktrees ?? []) {
      const virtualProject = buildWorktreeVirtualProject(project, worktree);
      byId.set(virtualProject.id, virtualProject);
    }
  }

  for (const project of terminalOpenProjects) {
    byId.set(project.id, project);
  }

  return Array.from(byId.values());
}

export function buildReadyWorktree(path: string, branch: string, now: number): ProjectWorktree {
  return {
    id: createWorktreeProjectId(path),
    name: resolveNameFromPath(path),
    path,
    branch,
    baseBranch: undefined,
    inheritConfig: true,
    created: now,
    status: "ready",
    initStep: "ready",
    initMessage: "已添加现有 worktree",
    initError: null,
    initJobId: null,
    updatedAt: now,
  };
}

export function buildTrackedWorktreeFromGitItem(item: GitWorktreeListItem, now: number): ProjectWorktree {
  return {
    id: createWorktreeProjectId(item.path),
    name: resolveNameFromPath(item.path),
    path: item.path,
    branch: item.branch,
    inheritConfig: true,
    created: now,
  };
}

export function buildWorktreeVirtualProject(sourceProject: Project, worktree: ProjectWorktree): Project {
  const now = jsDateToSwiftDate(new Date());
  return {
    id: createWorktreeProjectId(worktree.path),
    name: worktree.name || resolveNameFromPath(worktree.path),
    path: worktree.path,
    tags: [...(sourceProject.tags ?? [])],
    scripts: [...(sourceProject.scripts ?? [])],
    worktrees: [],
    mtime: sourceProject.mtime,
    size: sourceProject.size,
    checksum: `worktree:${worktree.path}`,
    git_commits: sourceProject.git_commits,
    git_last_commit: sourceProject.git_last_commit,
    git_daily: sourceProject.git_daily ?? null,
    created: worktree.created || now,
    checked: now,
  };
}

export function matchProjectByCwd(cwd: string, projects: Project[]): Project | null {
  if (!cwd) {
    return null;
  }
  let bestMatch: Project | null = null;
  let bestLength = -1;
  for (const project of projects) {
    if (cwd.startsWith(project.path) && project.path.length > bestLength) {
      bestMatch = project;
      bestLength = project.path.length;
    }
  }
  return bestMatch;
}

export function buildCodexSessionViews(sessions: CodexMonitorSession[], projects: Project[]): CodexSessionView[] {
  return sessions.map((session) => {
    const project = matchProjectByCwd(session.cwd, projects);
    return {
      ...session,
      projectId: project?.id ?? null,
      projectName: project?.name ?? null,
      projectPath: project?.path ?? null,
    };
  });
}

export function shouldBlockReloadShortcut(event: KeyboardEvent): boolean {
  const key = event.key.toLowerCase();
  if (key === "f5" || event.code === "F5") {
    return true;
  }
  if (key !== "r") {
    return false;
  }

  if (!(event.metaKey || event.ctrlKey) || event.shiftKey || event.altKey) {
    return false;
  }

  const activeTarget =
    event.target instanceof Element
      ? event.target
      : document.activeElement instanceof Element
        ? document.activeElement
        : null;

  // 允许终端里的 Ctrl+R 透传给 shell（例如历史命令搜索），避免被误判成页面刷新快捷键。
  if (event.ctrlKey && !event.metaKey && activeTarget?.closest(".terminal-pane, .xterm, .xterm-helper-textarea")) {
    return false;
  }

  return true;
}

export function resolveKeyboardEventTarget(event: KeyboardEvent): Element | null {
  return event.target instanceof Element
    ? event.target
    : document.activeElement instanceof Element
      ? document.activeElement
      : null;
}
