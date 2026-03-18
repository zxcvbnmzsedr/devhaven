import type { ControlPlaneNotification } from "../models/controlPlane.ts";
import type { Project, ProjectWorktree } from "../models/types.ts";
import { jsDateToSwiftDate } from "../models/types.ts";

function normalizePath(path: string): string {
  return path.trim().replace(/\\/g, "/").replace(/\/+$/, "");
}

function isSamePath(left: string, right: string): boolean {
  return normalizePath(left) === normalizePath(right);
}

function buildWorktreeVirtualProject(sourceProject: Project, worktree: ProjectWorktree): Project {
  const now = jsDateToSwiftDate(new Date());
  return {
    id: worktree.id,
    name: worktree.name || normalizePath(worktree.path).split("/").filter(Boolean).pop() || worktree.path,
    path: worktree.path,
    tags: [...(sourceProject.tags ?? [])],
    scripts: [...(sourceProject.scripts ?? [])],
    worktrees: [],
    mtime: sourceProject.mtime,
    size: sourceProject.size,
    checksum: `worktree:${worktree.path}`,
    git_commits: sourceProject.git_commits,
    git_last_commit: sourceProject.git_last_commit,
    git_last_commit_message: sourceProject.git_last_commit_message ?? null,
    git_daily: sourceProject.git_daily ?? null,
    created: worktree.created || now,
    checked: now,
  };
}

/**
 * 根据控制面通知解析应打开的项目/工作区。
 * 优先使用精确 projectPath，其次回退到 workspaceId。
 */
export function resolveNotificationProject(
  projects: Project[],
  notification: Pick<ControlPlaneNotification, "projectPath" | "workspaceId">,
): Project | null {
  const projectPath = notification.projectPath?.trim();
  if (projectPath) {
    const directProject = projects.find((project) => isSamePath(project.path, projectPath));
    if (directProject) {
      return directProject;
    }

    for (const project of projects) {
      const matchedWorktree = (project.worktrees ?? []).find((worktree) => isSamePath(worktree.path, projectPath));
      if (matchedWorktree) {
        return buildWorktreeVirtualProject(project, matchedWorktree);
      }
    }
  }

  const workspaceId = notification.workspaceId?.trim();
  if (!workspaceId) {
    return null;
  }

  return projects.find((project) => project.id === workspaceId) ?? null;
}
