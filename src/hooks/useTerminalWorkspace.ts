import { useCallback, useEffect, useRef, useState, type Dispatch, type RefObject, type SetStateAction } from "react";

import type { TerminalQuickCommandDispatch } from "../models/quickCommands";
import type { TerminalWorkspaceSummary } from "../models/terminal";
import type { Project } from "../models/types";
import { deleteTerminalWorkspace, listTerminalWorkspaceSummaries } from "../services/terminalWorkspace";
import { gitWorktreeList, type GitWorktreeListItem } from "../services/gitWorktree";
import {
  isSamePath,
  isWorktreeProject,
  normalizePathForCompare,
  resolveWorktreeSourceProjectByPath,
  resolveWorktreeVirtualProjectByPath,
} from "../utils/worktreeHelpers";

type UseTerminalWorkspaceParams = {
  projects: Project[];
  projectMap: Map<string, Project>;
  isLoading: boolean;
  showToast: (message: string, variant?: "success" | "error") => void;
  syncProjectWorktrees: (projectId: string, gitItems: GitWorktreeListItem[]) => Promise<void>;
  searchInputRef: RefObject<HTMLInputElement | null>;
};

export type UseTerminalWorkspaceReturn = {
  showTerminalWorkspace: boolean;
  setShowTerminalWorkspace: Dispatch<SetStateAction<boolean>>;
  terminalOpenProjects: Project[];
  setTerminalOpenProjects: Dispatch<SetStateAction<Project[]>>;
  terminalActiveProjectId: string | null;
  setTerminalActiveProjectId: Dispatch<SetStateAction<string | null>>;
  selectTerminalProject: (projectId: string) => void;
  registerTerminalWorkspacePersistence: (
    projectId: string,
    persistWorkspace: (() => Promise<void>) | null,
  ) => void;
  terminalQuickCommandDispatch: TerminalQuickCommandDispatch | null;
  terminalGitWorktreesByProjectId: Record<string, GitWorktreeListItem[]>;
  setTerminalGitWorktreesByProjectId: Dispatch<SetStateAction<Record<string, GitWorktreeListItem[]>>>;
  terminalOpenProjectsRef: RefObject<Project[]>;
  terminalActiveProjectIdRef: RefObject<string | null>;
  terminalGitWorktreesByProjectIdRef: RefObject<Record<string, GitWorktreeListItem[]>>;
  openTerminalWorkspace: (project: Project) => void;
  dispatchTerminalQuickCommand: (action: Omit<TerminalQuickCommandDispatch, "seq">) => void;
  handleRunProjectScript: (projectId: string, scriptId: string) => Promise<void>;
  handleStopProjectScript: (projectId: string, scriptId: string) => Promise<void>;
  handleOpenTerminal: (project: Project) => void;
  handleCloseTerminalProject: (projectId: string) => void;
  syncTerminalProjectWorktrees: (projectId: string, options?: { showToast?: boolean }) => Promise<void>;
  removeWorktreeFromGitCache: (projectId: string, worktreePath: string) => void;
};

/** 管理终端工作区状态、恢复、脚本派发与 worktree 同步缓存。 */
export function useTerminalWorkspace({
  projects,
  projectMap,
  isLoading,
  showToast,
  syncProjectWorktrees,
  searchInputRef,
}: UseTerminalWorkspaceParams): UseTerminalWorkspaceReturn {
  const [showTerminalWorkspace, setShowTerminalWorkspace] = useState(false);
  const [terminalOpenProjects, setTerminalOpenProjects] = useState<Project[]>([]);
  const [terminalActiveProjectId, setTerminalActiveProjectId] = useState<string | null>(null);
  const [terminalQuickCommandDispatch, setTerminalQuickCommandDispatch] =
    useState<TerminalQuickCommandDispatch | null>(null);
  const [terminalGitWorktreesByProjectId, setTerminalGitWorktreesByProjectId] = useState<
    Record<string, GitWorktreeListItem[]>
  >({});

  const terminalQuickCommandDispatchSeqRef = useRef(0);
  const terminalOpenProjectsRef = useRef<Project[]>(terminalOpenProjects);
  const terminalActiveProjectIdRef = useRef<string | null>(terminalActiveProjectId);
  const terminalGitWorktreesByProjectIdRef = useRef<Record<string, GitWorktreeListItem[]>>(terminalGitWorktreesByProjectId);
  const lastTerminalVisibleRef = useRef(showTerminalWorkspace);
  const terminalRestoreCheckedRef = useRef(false);
  const worktreeAutoSyncedProjectIdsRef = useRef<Set<string>>(new Set());
  const worktreeSyncingProjectIdsRef = useRef<Set<string>>(new Set());
  const terminalWorkspacePersistenceRef = useRef(new Map<string, () => Promise<void>>());
  const terminalProjectSwitchSeqRef = useRef(0);

  const registerTerminalWorkspacePersistence = useCallback(
    (projectId: string, persistWorkspace: (() => Promise<void>) | null) => {
      const normalizedProjectId = projectId.trim();
      if (!normalizedProjectId) {
        return;
      }
      if (persistWorkspace) {
        terminalWorkspacePersistenceRef.current.set(normalizedProjectId, persistWorkspace);
        return;
      }
      terminalWorkspacePersistenceRef.current.delete(normalizedProjectId);
    },
    [],
  );

  const persistTerminalWorkspaceIfNeeded = useCallback(async (projectId: string | null) => {
    const normalizedProjectId = projectId?.trim();
    if (!normalizedProjectId) {
      return;
    }
    const persistWorkspace = terminalWorkspacePersistenceRef.current.get(normalizedProjectId);
    if (!persistWorkspace) {
      return;
    }
    try {
      await persistWorkspace();
    } catch (error) {
      console.error("切换项目前保存终端工作区失败。", error);
    }
  }, []);

  const selectTerminalProject = useCallback(
    (projectId: string) => {
      const nextProjectId = projectId.trim();
      if (!nextProjectId) {
        return;
      }
      setShowTerminalWorkspace(true);
      const currentActiveProjectId = terminalActiveProjectIdRef.current;
      if (currentActiveProjectId === nextProjectId) {
        return;
      }

      const switchSeq = terminalProjectSwitchSeqRef.current + 1;
      terminalProjectSwitchSeqRef.current = switchSeq;

      void (async () => {
        await persistTerminalWorkspaceIfNeeded(currentActiveProjectId);
        if (terminalProjectSwitchSeqRef.current !== switchSeq) {
          return;
        }
        setTerminalActiveProjectId(nextProjectId);
      })();
    },
    [persistTerminalWorkspaceIfNeeded],
  );

  const openTerminalWorkspace = useCallback(
    (project: Project) => {
      setShowTerminalWorkspace(true);
      setTerminalOpenProjects((prev) => {
        let next = prev;
        const ensureMutable = () => {
          if (next === prev) {
            next = [...next];
          }
        };
        const upsert = (item: Project) => {
          const index = next.findIndex((existing) => existing.id === item.id);
          ensureMutable();
          if (index >= 0) {
            next[index] = item;
          } else {
            next.push(item);
          }
        };

        if (isWorktreeProject(project)) {
          const sourceProject = resolveWorktreeSourceProjectByPath(projects, project.path);
          if (sourceProject) {
            upsert(sourceProject);
          }
        }

        upsert(project);

        return next;
      });
      selectTerminalProject(project.id);
    },
    [projects, selectTerminalProject],
  );

  const dispatchTerminalQuickCommand = useCallback((action: Omit<TerminalQuickCommandDispatch, "seq">) => {
    const seq = terminalQuickCommandDispatchSeqRef.current + 1;
    terminalQuickCommandDispatchSeqRef.current = seq;
    setTerminalQuickCommandDispatch({ ...action, seq });
  }, []);

  const handleRunProjectScript = useCallback(
    async (projectId: string, scriptId: string) => {
      const project = projectMap.get(projectId);
      if (!project) {
        showToast("项目不存在或已移除", "error");
        return;
      }
      const script = (project.scripts ?? []).find((item) => item.id === scriptId);
      if (!script) {
        showToast("命令不存在或已被删除", "error");
        return;
      }

      openTerminalWorkspace(project);
      dispatchTerminalQuickCommand({
        type: "run",
        projectId: project.id,
        projectPath: project.path,
        scriptId,
      });
    },
    [dispatchTerminalQuickCommand, openTerminalWorkspace, projectMap, showToast],
  );

  const handleStopProjectScript = useCallback(
    async (projectId: string, scriptId: string) => {
      const project = projectMap.get(projectId);
      if (!project) {
        showToast("项目不存在或已移除", "error");
        return;
      }
      const script = (project.scripts ?? []).find((item) => item.id === scriptId);
      if (!script) {
        showToast("命令不存在或已被删除", "error");
        return;
      }

      openTerminalWorkspace(project);
      dispatchTerminalQuickCommand({
        type: "stop",
        projectId: project.id,
        projectPath: project.path,
        scriptId,
      });
    },
    [dispatchTerminalQuickCommand, openTerminalWorkspace, projectMap, showToast],
  );

  const handleOpenTerminal = useCallback(
    (project: Project) => {
      openTerminalWorkspace(project);
    },
    [openTerminalWorkspace],
  );

  const handleCloseTerminalProject = useCallback(
    (projectId: string) => {
      const currentProjects = terminalOpenProjectsRef.current;
      const closingProject = currentProjects.find((item) => item.id === projectId);
      if (!closingProject) {
        return;
      }

      const closingPaths = new Set<string>([closingProject.path]);
      if (!isWorktreeProject(closingProject)) {
        for (const item of closingProject.worktrees ?? []) {
          closingPaths.add(item.path);
        }
      }

      const nextProjects = currentProjects.filter((item) => !closingPaths.has(item.path));
      setTerminalOpenProjects(nextProjects);

      if (nextProjects.length === 0) {
        setTerminalActiveProjectId(null);
        setShowTerminalWorkspace(false);
      } else {
        const currentActive = terminalActiveProjectIdRef.current;
        const nextActive =
          currentActive === projectId || !currentActive || !nextProjects.some((item) => item.id === currentActive)
            ? nextProjects[0].id
            : currentActive;
        setTerminalActiveProjectId(nextActive);
      }

      // 先卸载终端 pane（清理 PTY/定时保存），再异步删除持久化工作区，避免竞态把 workspace 又写回去。
      window.setTimeout(() => {
        void Promise.all(Array.from(closingPaths).map((path) => deleteTerminalWorkspace(path))).catch((error) => {
          console.error("删除终端工作区失败。", error);
          showToast("关闭项目失败，请重试", "error");
        });
      }, 0);
    },
    [showToast],
  );

  const syncTerminalProjectWorktrees = useCallback(
    async (projectId: string, options?: { showToast?: boolean }) => {
      const sourceProject = projectMap.get(projectId);
      if (!sourceProject) {
        if (options?.showToast) {
          showToast("项目不存在或已移除", "error");
        }
        return;
      }

      if (worktreeSyncingProjectIdsRef.current.has(projectId)) {
        return;
      }
      worktreeSyncingProjectIdsRef.current.add(projectId);

      try {
        let gitItems: GitWorktreeListItem[] | null = null;
        try {
          gitItems = await gitWorktreeList(sourceProject.path);
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          // 非 Git 项目：同步为空列表，避免保留过期记录。
          if (message.includes("不是 Git 仓库")) {
            gitItems = [];
          } else {
            if (options?.showToast) {
              showToast(message || "同步 worktree 失败", "error");
            }
            console.error("同步 worktree 失败。", error);
            return;
          }
        }

        setTerminalGitWorktreesByProjectId((prev) => ({ ...prev, [projectId]: gitItems ?? [] }));

        const trackedWorktrees = sourceProject.worktrees ?? [];
        const trackedByPath = new Map(trackedWorktrees.map((item) => [normalizePathForCompare(item.path), item]));

        const gitPathSet = new Set((gitItems ?? []).map((item) => normalizePathForCompare(item.path)));
        const trackedPathSet = new Set(trackedWorktrees.map((item) => normalizePathForCompare(item.path)));

        const removedPaths = trackedWorktrees
          .map((item) => normalizePathForCompare(item.path))
          .filter((path) => path && !gitPathSet.has(path));

        // 若 worktree 已在 Git 中移除，但仍在终端里打开，先关闭避免“幽灵项目”无法再从列表操作。
        for (const removedPath of removedPaths) {
          const opened = terminalOpenProjectsRef.current.find(
            (item) => isWorktreeProject(item) && normalizePathForCompare(item.path) === removedPath,
          );
          if (opened) {
            handleCloseTerminalProject(opened.id);
          }
        }

        const addedCount = Array.from(gitPathSet).filter((path) => !trackedPathSet.has(path)).length;
        const removedCount = removedPaths.length;
        const updatedCount = (gitItems ?? []).reduce((count, item) => {
          const tracked = trackedByPath.get(normalizePathForCompare(item.path));
          return tracked && tracked.branch !== item.branch ? count + 1 : count;
        }, 0);

        await syncProjectWorktrees(projectId, gitItems ?? []);

        if (options?.showToast) {
          if (addedCount === 0 && removedCount === 0 && updatedCount === 0) {
            showToast("worktree 已是最新", "success");
          } else {
            showToast(`已同步 worktree：新增 ${addedCount} · 移除 ${removedCount} · 更新 ${updatedCount}`, "success");
          }
        }
      } finally {
        worktreeSyncingProjectIdsRef.current.delete(projectId);
      }
    },
    [handleCloseTerminalProject, projectMap, showToast, syncProjectWorktrees],
  );

  const removeWorktreeFromGitCache = useCallback((projectId: string, worktreePath: string) => {
    setTerminalGitWorktreesByProjectId((prev) => {
      const current = prev[projectId];
      if (!current) {
        return prev;
      }
      const next = current.filter((item) => !isSamePath(item.path, worktreePath));
      return { ...prev, [projectId]: next };
    });
  }, []);

  useEffect(() => {
    if (isLoading || terminalRestoreCheckedRef.current) {
      return;
    }

    terminalRestoreCheckedRef.current = true;
    if (terminalOpenProjectsRef.current.length > 0) {
      return;
    }

    let cancelled = false;

    void (async () => {
      let summaries: TerminalWorkspaceSummary[] = [];
      try {
        summaries = await listTerminalWorkspaceSummaries();
      } catch (error) {
        console.error("读取终端工作区列表失败。", error);
        return;
      }

      if (cancelled || summaries.length === 0) {
        return;
      }

      const restoredProjects: Project[] = [];
      const openedProjectIds = new Set<string>();
      let restoredActiveProjectId: string | null = null;
      let latestUpdatedAt = Number.NEGATIVE_INFINITY;

      const pushProject = (project: Project) => {
        if (openedProjectIds.has(project.id)) {
          return;
        }
        openedProjectIds.add(project.id);
        restoredProjects.push(project);
      };

      for (const summary of summaries) {
        const rootProject = projects.find(
          (item) => !isWorktreeProject(item) && isSamePath(item.path, summary.projectPath),
        );

        if (rootProject) {
          pushProject(rootProject);
          if ((summary.updatedAt ?? Number.NEGATIVE_INFINITY) >= latestUpdatedAt) {
            latestUpdatedAt = summary.updatedAt ?? Number.NEGATIVE_INFINITY;
            restoredActiveProjectId = rootProject.id;
          }
          continue;
        }

        const sourceProject = resolveWorktreeSourceProjectByPath(projects, summary.projectPath);
        const worktreeProject = resolveWorktreeVirtualProjectByPath(projects, summary.projectPath);
        if (!sourceProject || !worktreeProject) {
          continue;
        }

        pushProject(sourceProject);
        pushProject(worktreeProject);

        if ((summary.updatedAt ?? Number.NEGATIVE_INFINITY) >= latestUpdatedAt) {
          latestUpdatedAt = summary.updatedAt ?? Number.NEGATIVE_INFINITY;
          restoredActiveProjectId = worktreeProject.id;
        }
      }

      if (cancelled || restoredProjects.length === 0) {
        return;
      }

      setTerminalOpenProjects(restoredProjects);
      setTerminalActiveProjectId(restoredActiveProjectId ?? restoredProjects[0].id);
    })();

    return () => {
      cancelled = true;
    };
  }, [isLoading, projects]);

  useEffect(() => {
    setTerminalOpenProjects((prev) =>
      prev.map((project) => {
        if (isWorktreeProject(project)) {
          return project;
        }
        return projectMap.get(project.id) ?? project;
      }),
    );
  }, [projectMap]);

  useEffect(() => {
    if (!showTerminalWorkspace) {
      return;
    }

    const rootProjects = terminalOpenProjects.filter((project) => !isWorktreeProject(project));
    const rootIds = new Set(rootProjects.map((project) => project.id));

    // 清理已关闭项目的缓存。
    setTerminalGitWorktreesByProjectId((prev) => {
      const entries = Object.entries(prev);
      if (entries.length === 0) {
        return prev;
      }
      let changed = false;
      const next: Record<string, GitWorktreeListItem[]> = {};
      for (const [key, value] of entries) {
        if (rootIds.has(key)) {
          next[key] = value;
        } else {
          changed = true;
        }
      }
      return changed ? next : prev;
    });

    for (const project of rootProjects) {
      if (worktreeAutoSyncedProjectIdsRef.current.has(project.id)) {
        continue;
      }
      worktreeAutoSyncedProjectIdsRef.current.add(project.id);
      void syncTerminalProjectWorktrees(project.id).catch(() => {
        worktreeAutoSyncedProjectIdsRef.current.delete(project.id);
      });
    }
  }, [showTerminalWorkspace, syncTerminalProjectWorktrees, terminalOpenProjects]);

  useEffect(() => {
    const wasVisible = lastTerminalVisibleRef.current;
    lastTerminalVisibleRef.current = showTerminalWorkspace;
    if (!wasVisible || showTerminalWorkspace) {
      return;
    }
    // 终端隐藏后，把焦点移回主界面搜索框，避免继续把输入写入后台 xterm。
    requestAnimationFrame(() => {
      searchInputRef.current?.focus();
    });
  }, [searchInputRef, showTerminalWorkspace]);

  useEffect(() => {
    if (showTerminalWorkspace) {
      return;
    }
    // 终端隐藏后清空 Git worktree 缓存与同步标记，避免下次打开显示旧数据。
    worktreeAutoSyncedProjectIdsRef.current = new Set();
    worktreeSyncingProjectIdsRef.current = new Set();
    setTerminalGitWorktreesByProjectId({});
  }, [showTerminalWorkspace]);

  useEffect(() => {
    terminalOpenProjectsRef.current = terminalOpenProjects;
  }, [terminalOpenProjects]);

  useEffect(() => {
    terminalActiveProjectIdRef.current = terminalActiveProjectId;
  }, [terminalActiveProjectId]);

  useEffect(() => {
    terminalGitWorktreesByProjectIdRef.current = terminalGitWorktreesByProjectId;
  }, [terminalGitWorktreesByProjectId]);

  return {
    showTerminalWorkspace,
    setShowTerminalWorkspace,
    terminalOpenProjects,
    setTerminalOpenProjects,
    terminalActiveProjectId,
    setTerminalActiveProjectId,
    selectTerminalProject,
    registerTerminalWorkspacePersistence,
    terminalQuickCommandDispatch,
    terminalGitWorktreesByProjectId,
    setTerminalGitWorktreesByProjectId,
    terminalOpenProjectsRef,
    terminalActiveProjectIdRef,
    terminalGitWorktreesByProjectIdRef,
    openTerminalWorkspace,
    dispatchTerminalQuickCommand,
    handleRunProjectScript,
    handleStopProjectScript,
    handleOpenTerminal,
    handleCloseTerminalProject,
    syncTerminalProjectWorktrees,
    removeWorktreeFromGitCache,
  };
}
