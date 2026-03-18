import type { CSSProperties, KeyboardEvent } from "react";
import { memo, useCallback, useEffect, useMemo, useRef, useState } from "react";

import type { TerminalQuickCommandDispatch } from "../../models/quickCommands";
import type { Project, ProjectScript, ProjectWorktree } from "../../models/types";
import { isTauriRuntime, resolveRuntimeClientId } from "../../platform/runtime";
import type { GitWorktreeListItem } from "../../services/gitWorktree";
import { terminateTerminalSessions } from "../../services/terminal";
import { useSystemColorScheme } from "../../hooks/useSystemColorScheme";
import {
  getTerminalThemePresetByName,
  resolveTerminalThemeName,
} from "../../themes/terminalThemes";
import type { ControlPlaneWorkspaceTree } from "../../models/controlPlane";
import {
  listenControlPlaneChanged,
  loadControlPlaneTree,
} from "../../services/controlPlane";
import {
  projectControlPlaneWorkspace,
} from "../../utils/controlPlaneProjection";
import { buildMountedWorkspaceEntries } from "./terminalWorkspaceMountModel";
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
  onRegisterPersistWorkspace: (
    projectId: string,
    persistWorkspace: (() => Promise<void>) | null,
  ) => void;
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
  terminalTheme: string;
  sharedScriptsRoot: string;
  terminalUseWebglRenderer: boolean;
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

function handleRowActivationKeyDown(
  event: KeyboardEvent<HTMLDivElement>,
  onActivate: () => void,
) {
  if (event.target !== event.currentTarget) {
    return;
  }
  if (event.key !== "Enter" && event.key !== " ") {
    return;
  }
  event.preventDefault();
  onActivate();
}

function TerminalWorkspaceWindow({
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
  onRegisterPersistWorkspace,
  onAddProjectScript,
  onUpdateProjectScript,
  onRemoveProjectScript,
  onExit,
  windowLabel,
  isVisible,
  terminalTheme,
  sharedScriptsRoot,
  terminalUseWebglRenderer,
  gitWorktreesByProjectId,
}: TerminalWorkspaceWindowProps) {
  const workspaceSessionIdsRef = useRef(new Map<string, string[]>());
  const runtimeClientIdRef = useRef(resolveRuntimeClientId());
  const systemScheme = useSystemColorScheme();
  const terminalThemePreset = useMemo(() => {
    const resolvedName = resolveTerminalThemeName(terminalTheme, systemScheme);
    return getTerminalThemePresetByName(resolvedName);
  }, [terminalTheme, systemScheme]);

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
  const registerWorkspaceSessionIds = useCallback((projectId: string, sessionIds: string[]) => {
    workspaceSessionIdsRef.current.set(projectId, sessionIds);
  }, []);
  const handleCloseProject = useCallback(
    (projectId: string) => {
      const closingProject = openProjects.find((project) => project.id === projectId) ?? null;
      const closingPaths = new Set<string>();
      if (closingProject) {
        closingPaths.add(closingProject.path);
        if (!closingProject.id.startsWith("worktree:")) {
          for (const worktree of closingProject.worktrees ?? []) {
            closingPaths.add(worktree.path);
          }
        }
      }
      const closingProjectIds =
        closingPaths.size > 0
          ? openProjects.filter((project) => closingPaths.has(project.path)).map((project) => project.id)
          : [projectId];
      const sessionIds = Array.from(
        new Set(closingProjectIds.flatMap((id) => workspaceSessionIdsRef.current.get(id) ?? [])),
      );
      if (sessionIds.length > 0) {
        void terminateTerminalSessions(windowLabel, sessionIds, runtimeClientIdRef.current).catch((error) => {
          console.error("关闭项目关联终端失败。", error);
        });
      }
      closingProjectIds.forEach((id) => workspaceSessionIdsRef.current.delete(id));
      onCloseProject(projectId);
    },
    [onCloseProject, openProjects, windowLabel],
  );
  const mountedWorkspaceEntries = useMemo(
    () =>
      buildMountedWorkspaceEntries({
        openProjects,
        activeProjectId: activeProject?.id ?? null,
        quickCommandDispatch,
        workspaceVisible: isVisible,
      }),
    [activeProject?.id, isVisible, openProjects, quickCommandDispatch],
  );
  const [controlPlaneTreeByProjectId, setControlPlaneTreeByProjectId] = useState<
    Record<string, ControlPlaneWorkspaceTree | null>
  >({});

  useEffect(() => {
    let cancelled = false;

    const loadTrees = async () => {
      const entries = await Promise.all(
        openProjects.map(async (project) => {
          try {
            const tree = await loadControlPlaneTree({
              workspaceId: project.id,
              projectPath: project.path,
            });
            return [project.id, tree] as const;
          } catch (error) {
            console.warn("读取控制平面快照失败。", error);
            return [project.id, null] as const;
          }
        }),
      );
      if (cancelled) {
        return;
      }
      setControlPlaneTreeByProjectId(Object.fromEntries(entries));
    };

    void loadTrees();

    return () => {
      cancelled = true;
    };
  }, [openProjects]);

  useEffect(() => {
    let disposed = false;
    let unlisten: (() => void) | null = null;
    const projectByPath = new Map(openProjects.map((project) => [project.path, project]));

    const refreshTree = async (projectId: string, projectPath: string) => {
      try {
        const tree = await loadControlPlaneTree({
          workspaceId: projectId,
          projectPath,
        });
        if (disposed) {
          return;
        }
        setControlPlaneTreeByProjectId((current) => ({
          ...current,
          [projectId]: tree,
        }));
      } catch (error) {
        console.warn("刷新控制平面快照失败。", error);
      }
    };

    void listenControlPlaneChanged((event) => {
      const projectPath = event.payload.projectPath;
      if (!projectPath) {
        return;
      }
      const matchedProject = projectByPath.get(projectPath);
      if (!matchedProject) {
        return;
      }
      void refreshTree(matchedProject.id, matchedProject.path);
    }).then((nextUnlisten) => {
      if (disposed) {
        nextUnlisten();
        return;
      }
      unlisten = nextUnlisten;
    });

    return () => {
      disposed = true;
      unlisten?.();
    };
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
            const projectControlPlaneTree = controlPlaneTreeByProjectId[project.id] ?? null;
            const controlPlaneProjection = projectControlPlaneWorkspace(projectControlPlaneTree);
            const trackedWorktrees = project.worktrees ?? [];
            const gitWorktrees = gitWorktreesByProjectId[project.id];
            const worktreesToRender = mergeWorktreesToRender(trackedWorktrees, gitWorktrees);
            const handleSelectProjectRow = () => onSelectProject(project.id);

            const hasWorktrees = worktreesToRender.length > 0;
            return (
              <div key={project.id} className="flex flex-col gap-1" title={project.path}>
                <div
                  className={`group relative flex cursor-pointer items-center gap-2 rounded-md px-2.5 py-2 text-left text-[12px] font-semibold transition-colors ${
                    isActive
                      ? "bg-[var(--terminal-accent-bg)] text-[var(--terminal-fg)]"
                      : "text-[var(--terminal-muted-fg)] hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)]"
                  }`}
                  role="button"
                  tabIndex={0}
                  aria-pressed={isActive}
                  onClick={handleSelectProjectRow}
                  onKeyDown={(event) => handleRowActivationKeyDown(event, handleSelectProjectRow)}
                >
                  <div className="min-w-0 flex-1 pr-6" title={project.name}>
                    <div className="truncate">{project.name}</div>
                    {controlPlaneProjection.latestMessage ? (
                      <div className="mt-0.5 truncate text-[10px] font-normal text-[var(--terminal-muted-fg)]">
                        {controlPlaneProjection.latestMessage}
                      </div>
                    ) : null}
                  </div>
                  <div className="absolute right-1.5 top-1/2 flex -translate-y-1/2 items-center gap-1">
                    {controlPlaneProjection.attention !== "idle" ? (
                      <span
                        className={`inline-flex h-2.5 w-2.5 shrink-0 rounded-full ${
                          controlPlaneProjection.attention === "error"
                            ? "bg-[rgba(239,68,68,0.95)]"
                            : controlPlaneProjection.attention === "waiting"
                              ? "bg-[rgba(245,158,11,0.95)]"
                              : controlPlaneProjection.attention === "completed"
                                ? "bg-[rgba(34,197,94,0.95)]"
                                : "bg-[var(--terminal-accent)]"
                        }`}
                        title={`控制平面状态：${controlPlaneProjection.attention}`}
                        aria-label={`控制平面状态：${controlPlaneProjection.attention}`}
                      />
                    ) : null}
                    {controlPlaneProjection.unreadCount > 0 ? (
                      <span
                        className="inline-flex min-w-4 items-center justify-center rounded-full bg-[var(--terminal-accent-bg)] px-1.5 text-[10px] font-semibold text-[var(--terminal-fg)]"
                        title={`未读通知 ${controlPlaneProjection.unreadCount} 条`}
                      >
                        {controlPlaneProjection.unreadCount}
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
                        handleCloseProject(project.id);
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
                      const worktreeControlPlaneProjection = projectControlPlaneWorkspace(
                        openedProject ? controlPlaneTreeByProjectId[openedProject.id] ?? null : null,
                      );
                      const isWorktreeActive = activeProject?.path === worktree.path;
                      const isCreating = worktree.status === "creating";
                      const isFailed = worktree.status === "failed";
                      const isQueued = isCreating && worktree.initStep === "pending";
                      const canOpen = !isCreating && !isFailed;
                      const handleSelectWorktreeRow = () => {
                        if (!canOpen) {
                          return;
                        }
                        if (openedProject) {
                          onSelectProject(openedProject.id);
                          return;
                        }
                        onOpenWorktree(project.id, worktree.path);
                      };
                      return (
                        <div
                          key={worktree.path}
                          className={`group flex items-center gap-2 rounded-md px-2 py-1.5 text-[11px] transition-colors ${
                            isWorktreeActive
                              ? "bg-[var(--terminal-accent-bg)] text-[var(--terminal-fg)]"
                              : "text-[var(--terminal-muted-fg)] hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)]"
                          } ${canOpen ? "cursor-pointer" : ""}`}
                          title={worktree.path}
                          role={canOpen ? "button" : undefined}
                          tabIndex={canOpen ? 0 : -1}
                          aria-pressed={canOpen ? isWorktreeActive : undefined}
                          onClick={handleSelectWorktreeRow}
                          onKeyDown={(event) => handleRowActivationKeyDown(event, handleSelectWorktreeRow)}
                        >
                          <div
                            className={`min-w-0 flex-1 truncate text-left ${
                              canOpen ? "" : "cursor-not-allowed opacity-60"
                            }`}
                          >
                            ↳ {worktree.name}
                          </div>
                          <span className="shrink-0 rounded border border-[var(--terminal-divider)] px-1.5 py-0.5 text-[10px] text-[var(--terminal-muted-fg)]">
                            {worktree.branch}
                          </span>
                          {worktreeControlPlaneProjection.attention !== "idle" ? (
                            <span
                              className={`inline-flex h-2.5 w-2.5 shrink-0 rounded-full ${
                                worktreeControlPlaneProjection.attention === "error"
                                  ? "bg-[rgba(239,68,68,0.95)]"
                                  : worktreeControlPlaneProjection.attention === "waiting"
                                    ? "bg-[rgba(245,158,11,0.95)]"
                                    : worktreeControlPlaneProjection.attention === "completed"
                                      ? "bg-[rgba(34,197,94,0.95)]"
                                      : "bg-[var(--terminal-accent)]"
                              }`}
                              title={`控制平面状态：${worktreeControlPlaneProjection.attention}`}
                              aria-label={`控制平面状态：${worktreeControlPlaneProjection.attention}`}
                            >
                              <span className="sr-only">控制平面状态</span>
                            </span>
                          ) : null}
                          {worktreeControlPlaneProjection.unreadCount > 0 ? (
                            <span
                              className="inline-flex min-w-4 items-center justify-center rounded-full bg-[var(--terminal-accent-bg)] px-1.5 text-[10px] font-semibold text-[var(--terminal-fg)]"
                              title={`未读通知 ${worktreeControlPlaneProjection.unreadCount} 条`}
                            >
                              {worktreeControlPlaneProjection.unreadCount}
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
        {mountedWorkspaceEntries.map(({ project, isVisible: workspaceVisible, quickCommandDispatch: projectDispatch }) => (
          <div
            key={project.id}
            className={`absolute inset-0 ${workspaceVisible ? "" : "pointer-events-none opacity-0"}`}
            aria-hidden={workspaceVisible ? undefined : true}
          >
            <TerminalWorkspaceView
              projectId={project.id}
              projectPath={project.path}
              projectName={project.name}
              isActive={workspaceVisible}
              quickCommandDispatch={projectDispatch}
              windowLabel={windowLabel}
              xtermTheme={terminalThemePreset.xterm}
              sharedScriptsRoot={sharedScriptsRoot}
              terminalUseWebglRenderer={terminalUseWebglRenderer}
              controlPlaneTree={controlPlaneTreeByProjectId[project.id] ?? null}
              scripts={project.scripts ?? EMPTY_PROJECT_SCRIPTS}
              onRegisterPersistWorkspace={onRegisterPersistWorkspace}
              onRegisterWorkspaceSessionIds={registerWorkspaceSessionIds}
              onAddProjectScript={onAddProjectScript}
              onUpdateProjectScript={onUpdateProjectScript}
              onRemoveProjectScript={onRemoveProjectScript}
            />
          </div>
        ))}
      </main>
    </div>
  );
}

export default memo(TerminalWorkspaceWindow);
