import type { CSSProperties } from "react";
import { useEffect, useMemo } from "react";

import type { TerminalQuickCommandDispatch } from "../../models/quickCommands";
import type { Project, ProjectScript, ProjectWorktree } from "../../models/types";
import { isTauriRuntime } from "../../platform/runtime";
import type { GitWorktreeListItem } from "../../services/gitWorktree";
import { useSystemColorScheme } from "../../hooks/useSystemColorScheme";
import { useDevHavenContext } from "../../state/DevHavenContext";
import {
  getTerminalThemePresetByName,
  resolveTerminalThemeName,
} from "../../themes/terminalThemes";
import type { CodexProjectStatus } from "../../utils/codexProjectStatus";
import TerminalWorkspaceView from "./TerminalWorkspaceView";

export type TerminalWorkspaceWindowProps = {
  openProjects: Project[];
  activeProjectId: string | null;
  quickCommandDispatch: TerminalQuickCommandDispatch | null;
  onSelectProject: (projectId: string) => void;
  onCloseProject: (projectId: string) => void;
  onCreateWorktree: (projectId: string) => void;
  onOpenWorktree: (projectId: string, worktreePath: string) => void;
  onDeleteWorktree: (projectId: string, worktreePath: string) => void;
  onRetryWorktree: (projectId: string, worktreePath: string) => void;
  onRefreshWorktrees: (projectId: string) => void;
  onAddProjectScript: (
    projectId: string,
    script: {
      name: string;
      start: string;
      paramSchema?: ProjectScript["paramSchema"];
      templateParams?: ProjectScript["templateParams"];
    },
  ) => Promise<void>;
  onUpdateProjectScript: (projectId: string, script: ProjectScript) => Promise<void>;
  onRemoveProjectScript: (projectId: string, scriptId: string) => Promise<void>;
  onExit?: () => void;
  windowLabel: string;
  isVisible: boolean;
  codexProjectStatusById: Record<string, CodexProjectStatus>;
  gitWorktreesByProjectId: Record<string, GitWorktreeListItem[] | undefined>;
};

type WorktreeRenderItem = {
  path: string;
  branch: string;
  name: string;
  status?: ProjectWorktree["status"];
  initStep?: ProjectWorktree["initStep"];
  initError?: string | null;
};

const EMPTY_PROJECT_SCRIPTS: ProjectScript[] = [];

function normalizeWorktreePath(path: string): string {
  return path.replace(/\\/g, "/").replace(/\/+$/, "");
}

function resolveNameFromPath(path: string): string {
  const normalized = normalizeWorktreePath(path);
  const segments = normalized.split("/").filter(Boolean);
  return segments[segments.length - 1] || path;
}

function toWorktreeRenderItem(worktree: ProjectWorktree): WorktreeRenderItem {
  return {
    path: worktree.path,
    branch: worktree.branch,
    name: worktree.name,
    status: worktree.status,
    initStep: worktree.initStep,
    initError: worktree.initError,
  };
}

function mergeWorktreesToRender(
  trackedWorktrees: ProjectWorktree[],
  gitWorktrees: GitWorktreeListItem[] | undefined,
): WorktreeRenderItem[] {
  if (!gitWorktrees) {
    return trackedWorktrees.map(toWorktreeRenderItem);
  }

  const trackedByPath = new Map(
    trackedWorktrees.map((item) => [normalizeWorktreePath(item.path), item]),
  );
  const merged: WorktreeRenderItem[] = gitWorktrees.map((item) => {
    const tracked = trackedByPath.get(normalizeWorktreePath(item.path));
    return {
      path: item.path,
      branch: item.branch,
      name: tracked?.name || resolveNameFromPath(item.path),
      status: tracked?.status,
      initStep: tracked?.initStep,
      initError: tracked?.initError,
    };
  });

  const existingPaths = new Set(merged.map((item) => normalizeWorktreePath(item.path)));
  for (const tracked of trackedWorktrees) {
    if (tracked.status !== "creating" && tracked.status !== "failed") {
      continue;
    }
    const normalizedPath = normalizeWorktreePath(tracked.path);
    if (existingPaths.has(normalizedPath)) {
      continue;
    }
    existingPaths.add(normalizedPath);
    merged.push(toWorktreeRenderItem(tracked));
  }

  return merged.sort((left, right) => left.path.localeCompare(right.path));
}

function resolveActiveProject(
  openProjects: Project[],
  activeProjectId: string | null,
): Project | null {
  if (openProjects.length === 0) {
    return null;
  }
  if (!activeProjectId) {
    return openProjects[0];
  }
  return openProjects.find((project) => project.id === activeProjectId) ?? openProjects[0];
}

export default function TerminalWorkspaceWindow({
  openProjects,
  activeProjectId,
  quickCommandDispatch,
  onSelectProject,
  onCloseProject,
  onCreateWorktree,
  onOpenWorktree,
  onDeleteWorktree,
  onRetryWorktree,
  onRefreshWorktrees,
  onAddProjectScript,
  onUpdateProjectScript,
  onRemoveProjectScript,
  onExit,
  windowLabel,
  isVisible,
  codexProjectStatusById,
  gitWorktreesByProjectId,
}: TerminalWorkspaceWindowProps) {
  const { appState } = useDevHavenContext();
  const systemScheme = useSystemColorScheme();
  const terminalThemePreset = useMemo(() => {
    const resolvedName = resolveTerminalThemeName(appState.settings.terminalTheme, systemScheme);
    return getTerminalThemePresetByName(resolvedName);
  }, [appState.settings.terminalTheme, systemScheme]);

  const terminalStyle = useMemo(() => {
    return {
      ...terminalThemePreset.uiVars,
      colorScheme: terminalThemePreset.colorScheme,
    } as CSSProperties;
  }, [terminalThemePreset]);

  const activeProject = useMemo(
    () => resolveActiveProject(openProjects, activeProjectId),
    [activeProjectId, openProjects],
  );

  const rootProjects = useMemo(
    () => openProjects.filter((project) => !project.id.startsWith("worktree:")),
    [openProjects],
  );

  const openProjectsByPath = useMemo(() => {
    return new Map(openProjects.map((project) => [project.path, project]));
  }, [openProjects]);

  useEffect(() => {
    if (!isTauriRuntime()) {
      return;
    }

    const setWindowTitle = async (title: string) => {
      try {
        const { getCurrentWindow } = await import("@tauri-apps/api/window");
        await getCurrentWindow().setTitle(title);
      } catch {
        // ignore
      }
    };

    // 仅在终端可见时更新窗口标题；隐藏时恢复默认标题，避免主界面停留在“xx - 终端”。
    if (!isVisible) {
      void setWindowTitle("DevHaven");
      return;
    }
    if (!activeProject) {
      return;
    }
    void setWindowTitle(`${activeProject.name} - 终端`);
  }, [activeProject, isVisible]);

  if (openProjects.length === 0) {
    return (
      <div className="flex h-full items-center justify-center text-[var(--terminal-muted-fg)]">
        未找到项目
      </div>
    );
  }

  return (
    <div className="flex h-full bg-[var(--terminal-bg)] text-[var(--terminal-fg)]" style={terminalStyle}>
      <aside className="w-[220px] shrink-0 border-r border-[var(--terminal-divider)] bg-[var(--terminal-panel-bg)]">
        <div className="flex items-center justify-between gap-2 px-3 py-2">
          <div className="text-[12px] font-semibold text-[var(--terminal-muted-fg)]">已打开项目</div>
          {onExit ? (
            <button
              className="inline-flex h-7 items-center justify-center rounded-md border border-[var(--terminal-divider)] px-2 text-[12px] font-semibold text-[var(--terminal-muted-fg)] transition-colors duration-150 hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)]"
              onClick={onExit}
            >
              返回
            </button>
          ) : null}
        </div>
        <div className="flex flex-col gap-1 p-2">
          {rootProjects.map((project) => {
            const isActive = (activeProject?.id ?? "") === project.id;
            const codexStatus = codexProjectStatusById[project.id] ?? null;
            const codexRunningCount = codexStatus?.runningCount ?? 0;
            const trackedWorktrees = project.worktrees ?? [];
            const gitWorktrees = gitWorktreesByProjectId[project.id];
            const worktreesToRender = mergeWorktreesToRender(trackedWorktrees, gitWorktrees);

            const hasWorktrees = worktreesToRender.length > 0;
            return (
              <div key={project.id} className="flex flex-col gap-1" title={project.path}>
                <div
                  className={`group relative flex items-center gap-2 rounded-md px-2.5 py-2 text-left text-[12px] font-semibold transition-colors ${
                    isActive
                      ? "bg-[var(--terminal-accent-bg)] text-[var(--terminal-fg)]"
                      : "text-[var(--terminal-muted-fg)] hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)]"
                  }`}
                >
                  <button
                    className="min-w-0 flex-1 truncate pr-6 text-left"
                    title={project.name}
                    onClick={() => onSelectProject(project.id)}
                  >
                    {project.name}
                  </button>
                  <div className="absolute right-1.5 top-1/2 flex -translate-y-1/2 items-center gap-1">
                    {codexRunningCount > 0 ? (
                      <span
                        className="inline-flex h-2.5 w-2.5 shrink-0 rounded-full bg-[var(--terminal-accent)]"
                        title={`Codex 运行中（${codexRunningCount} 个会话）`}
                        aria-label={`Codex 运行中（${codexRunningCount} 个会话）`}
                      >
                        <span className="sr-only">Codex 运行中</span>
                      </span>
                    ) : null}
                    <button
                      className="hidden h-6 w-6 items-center justify-center rounded-md border border-transparent text-[var(--terminal-muted-fg)] transition-colors hover:border-[var(--terminal-divider)] hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)] group-hover:inline-flex group-focus-within:inline-flex"
                      onClick={(event) => {
                        event.preventDefault();
                        event.stopPropagation();
                        onRefreshWorktrees(project.id);
                      }}
                      aria-label={`刷新 ${project.name} worktree`}
                      title="刷新 worktree"
                      type="button"
                    >
                      ↻
                    </button>
                    <button
                      className="hidden h-6 w-6 items-center justify-center rounded-md border border-transparent text-[var(--terminal-muted-fg)] transition-colors hover:border-[var(--terminal-divider)] hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)] group-hover:inline-flex group-focus-within:inline-flex"
                      onClick={(event) => {
                        event.preventDefault();
                        event.stopPropagation();
                        onCreateWorktree(project.id);
                      }}
                      aria-label={`为 ${project.name} 创建 worktree`}
                      title="创建 worktree"
                      type="button"
                    >
                      +
                    </button>
                    <button
                      className="hidden h-6 w-6 items-center justify-center rounded-md border border-transparent text-[var(--terminal-muted-fg)] transition-colors hover:border-[var(--terminal-divider)] hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)] group-hover:inline-flex group-focus-within:inline-flex"
                      onClick={(event) => {
                        event.preventDefault();
                        event.stopPropagation();
                        onCloseProject(project.id);
                      }}
                      aria-label={`关闭 ${project.name}`}
                      title="关闭项目"
                      type="button"
                    >
                      ×
                    </button>
                  </div>
                </div>

                {hasWorktrees ? (
                  <div className="flex flex-col gap-1 pl-3">
                    {worktreesToRender.map((worktree) => {
                      const openedProject = openProjectsByPath.get(worktree.path);
                      const codexWorktreeStatus =
                        openedProject ? codexProjectStatusById[`worktree:${worktree.path}`] ?? null : null;
                      const codexWorktreeRunningCount = codexWorktreeStatus?.runningCount ?? 0;
                      const isWorktreeActive = activeProject?.path === worktree.path;
                      const isCreating = worktree.status === "creating";
                      const isFailed = worktree.status === "failed";
                      const isQueued = isCreating && worktree.initStep === "pending";
                      const canOpen = !isCreating && !isFailed;
                      return (
                        <div
                          key={worktree.path}
                          className={`group flex items-center gap-2 rounded-md px-2 py-1.5 text-[11px] transition-colors ${
                            isWorktreeActive
                              ? "bg-[var(--terminal-accent-bg)] text-[var(--terminal-fg)]"
                              : "text-[var(--terminal-muted-fg)] hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)]"
                          }`}
                          title={worktree.path}
                        >
                          <button
                            className={`min-w-0 flex-1 truncate text-left ${
                              canOpen ? "" : "opacity-60 cursor-not-allowed"
                            }`}
                            disabled={!canOpen}
                            onClick={() => {
                              if (!canOpen) {
                                return;
                              }
                              if (openedProject) {
                                onSelectProject(openedProject.id);
                                return;
                              }
                              onOpenWorktree(project.id, worktree.path);
                            }}
                          >
                            ↳ {worktree.name}
                          </button>
                          <span className="shrink-0 rounded border border-[var(--terminal-divider)] px-1.5 py-0.5 text-[10px] text-[var(--terminal-muted-fg)]">
                            {worktree.branch}
                          </span>
                          {codexWorktreeRunningCount > 0 ? (
                            <span
                              className="inline-flex h-2.5 w-2.5 shrink-0 rounded-full bg-[var(--terminal-accent)]"
                              title={`Codex 运行中（${codexWorktreeRunningCount} 个会话）`}
                              aria-label={`Codex 运行中（${codexWorktreeRunningCount} 个会话）`}
                            >
                              <span className="sr-only">Codex 运行中</span>
                            </span>
                          ) : null}
                          {isCreating ? (
                            <span className="shrink-0 rounded border border-[var(--terminal-divider)] px-1.5 py-0.5 text-[10px] text-[var(--terminal-muted-fg)]">
                              {isQueued ? "排队中" : "创建中"}
                            </span>
                          ) : null}
                          {isFailed ? (
                            <span className="shrink-0 rounded border border-[rgba(239,68,68,0.35)] px-1.5 py-0.5 text-[10px] text-[rgba(239,68,68,0.9)]">
                              失败
                            </span>
                          ) : null}
                          {isFailed ? (
                            <button
                              className="inline-flex h-5 items-center justify-center rounded-md border border-transparent px-1.5 text-[10px] text-[var(--terminal-muted-fg)] opacity-0 transition-opacity hover:border-[var(--terminal-divider)] hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)] group-hover:opacity-100"
                              onClick={(event) => {
                                event.preventDefault();
                                event.stopPropagation();
                                onRetryWorktree(project.id, worktree.path);
                              }}
                              title={worktree.initError || "重试创建"}
                              type="button"
                            >
                              重试
                            </button>
                          ) : null}
                          <button
                            className="inline-flex h-5 items-center justify-center rounded-md border border-transparent px-1.5 text-[10px] text-[var(--terminal-muted-fg)] opacity-0 transition-opacity hover:border-[rgba(239,68,68,0.35)] hover:bg-[rgba(239,68,68,0.15)] hover:text-[rgba(239,68,68,0.9)] group-hover:opacity-100 disabled:cursor-not-allowed disabled:opacity-40"
                            onClick={(event) => {
                              event.preventDefault();
                              event.stopPropagation();
                              if (isCreating) {
                                return;
                              }
                              onDeleteWorktree(project.id, worktree.path);
                            }}
                            title={isCreating ? "创建中（不可取消）" : "删除 worktree"}
                            type="button"
                            disabled={isCreating}
                          >
                            {isCreating ? "创建中" : "删除"}
                          </button>
                        </div>
                      );
                    })}
                  </div>
                ) : null}
              </div>
            );
          })}
        </div>
      </aside>
      <main className="relative min-w-0 flex-1">
        {openProjects.map((project) => {
          const isActive = (activeProject?.id ?? "") === project.id;
          const projectQuickCommandDispatch =
            quickCommandDispatch &&
            quickCommandDispatch.projectPath === project.path &&
            quickCommandDispatch.projectId === project.id
              ? quickCommandDispatch
              : null;
          return (
            <div
              key={project.id}
              className={`absolute inset-0 ${
                isActive ? "opacity-100" : "opacity-0 pointer-events-none"
              }`}
            >
              <TerminalWorkspaceView
                projectId={project.id}
                projectPath={project.path}
                projectName={project.name}
                isActive={isVisible && isActive}
                quickCommandDispatch={projectQuickCommandDispatch}
                windowLabel={windowLabel}
                xtermTheme={terminalThemePreset.xterm}
                codexRunningCount={codexProjectStatusById[project.id]?.runningCount ?? 0}
                scripts={project.scripts ?? EMPTY_PROJECT_SCRIPTS}
                onAddProjectScript={onAddProjectScript}
                onUpdateProjectScript={onUpdateProjectScript}
                onRemoveProjectScript={onRemoveProjectScript}
              />
            </div>
          );
        })}
      </main>
    </div>
  );
}
