import { useCallback, useEffect, useMemo, useRef, useState, type Dispatch, type RefObject, type SetStateAction } from "react";
import { listenEvent } from "../platform/eventClient";

import type { WorktreeCreateSubmitPayload, WorktreeCreateSubmitResult } from "../components/terminal/WorktreeCreateDialog";
import type { Project, ProjectWorktree } from "../models/types";
import { jsDateToSwiftDate } from "../models/types";
import { gitDeleteBranch, gitWorktreeList, gitWorktreeRemove, type GitWorktreeListItem } from "../services/gitWorktree";
import { gitIsRepo } from "../services/gitManagement";
import { deleteTerminalWorkspace } from "../services/terminalWorkspace";
import {
  listenWorktreeInitProgress,
  worktreeInitCreate,
  type WorktreeInitProgressPayload,
} from "../services/worktreeInit";
import type { InteractionLockState } from "../services/interactionLock";
import {
  buildReadyWorktree,
  buildTrackedWorktreeFromGitItem,
  buildWorktreeVirtualProject,
  createWorktreeProjectId,
  isWorktreeProject,
  isSamePath,
  normalizePathForCompare,
  resolveErrorMessage,
  resolveNameFromPath,
} from "../utils/worktreeHelpers";
import { confirmRuntime } from "../platform/runtime";

type UseWorktreeManagerParams = {
  projects: Project[];
  projectMap: Map<string, Project>;
  addProjectWorktree: (projectId: string, worktree: ProjectWorktree) => Promise<void>;
  removeProjectWorktree: (projectId: string, worktreePath: string) => Promise<void>;
  syncProjectWorktrees: (projectId: string, gitItems: GitWorktreeListItem[]) => Promise<void>;
  showToast: (message: string, variant?: "success" | "error") => void;
  openTerminalWorkspace: (project: Project) => void;
  handleCloseTerminalProject: (projectId: string) => void;
  syncTerminalProjectWorktrees: (projectId: string, options?: { showToast?: boolean }) => Promise<void>;
  removeWorktreeFromGitCache: (projectId: string, worktreePath: string) => void;
  setTerminalGitWorktreesByProjectId: Dispatch<SetStateAction<Record<string, GitWorktreeListItem[]>>>;
  terminalGitWorktreesByProjectIdRef: RefObject<Record<string, GitWorktreeListItem[]>>;
  terminalOpenProjectsRef: RefObject<Project[]>;
};

export type UseWorktreeManagerReturn = {
  worktreeDialogProjectId: string | null;
  setWorktreeDialogProjectId: Dispatch<SetStateAction<string | null>>;
  worktreeDialogSourceProject: Project | null;
  handleRequestCreateWorktree: (projectId: string) => Promise<void>;
  handleOpenWorktreeFromProject: (projectId: string, worktreePath: string) => Promise<void>;
  handleCreateWorktree: (payload: WorktreeCreateSubmitPayload) => Promise<WorktreeCreateSubmitResult>;
  handleRetryWorktreeFromProject: (projectId: string, worktreePath: string) => Promise<void>;
  handleDeleteWorktreeFromProject: (projectId: string, worktreePath: string) => Promise<void>;
};

/** 管理 worktree 弹窗、创建进度监听、重试/删除/打开全流程。 */
export function useWorktreeManager({
  projects,
  projectMap,
  addProjectWorktree,
  removeProjectWorktree,
  syncProjectWorktrees,
  showToast,
  openTerminalWorkspace,
  handleCloseTerminalProject,
  syncTerminalProjectWorktrees,
  removeWorktreeFromGitCache,
  setTerminalGitWorktreesByProjectId,
  terminalGitWorktreesByProjectIdRef,
  terminalOpenProjectsRef,
}: UseWorktreeManagerParams): UseWorktreeManagerReturn {
  const [worktreeDialogProjectId, setWorktreeDialogProjectId] = useState<string | null>(null);

  const worktreeRecoveryCheckedProjectIdsRef = useRef<Set<string>>(new Set());
  const worktreeInitAutoOpenByJobIdRef = useRef<
    Map<string, { projectId: string; worktreePath: string; branch: string; autoOpen: boolean }>
  >(new Map());
  const worktreeInitAutoOpenPendingByProjectBranchRef = useRef<Map<string, { autoOpen: boolean }>>(new Map());
  const worktreeInitProgressSeenByProjectBranchRef = useRef<Set<string>>(new Set());

  const worktreeDialogSourceProject = useMemo(() => {
    if (!worktreeDialogProjectId) {
      return null;
    }
    return projectMap.get(worktreeDialogProjectId) ?? null;
  }, [projectMap, worktreeDialogProjectId]);

  useEffect(() => {
    if (!worktreeDialogProjectId) {
      return;
    }
    if (!projectMap.has(worktreeDialogProjectId)) {
      setWorktreeDialogProjectId(null);
    }
  }, [projectMap, worktreeDialogProjectId]);

  const handleRequestCreateWorktree = useCallback(
    async (projectId: string) => {
      const sourceProject = projectMap.get(projectId);
      if (!sourceProject) {
        showToast("项目不存在或已移除", "error");
        return;
      }
      try {
        const isRepo = await gitIsRepo(sourceProject.path);
        if (!isRepo) {
          showToast("该项目不是 Git 仓库，无法创建 worktree", "error");
          return;
        }
        setWorktreeDialogProjectId(projectId);
      } catch (error) {
        console.error("校验 Git 仓库失败。", error);
        showToast("无法校验项目 Git 状态，请重试", "error");
      }
    },
    [projectMap, showToast],
  );

  const handleOpenWorktreeFromProject = useCallback(
    async (projectId: string, worktreePath: string) => {
      const sourceProject = projectMap.get(projectId);
      if (!sourceProject) {
        showToast("项目不存在或已移除", "error");
        return;
      }
      const normalizedPath = worktreePath.trim();
      const worktree = (sourceProject.worktrees ?? []).find((item) => item.path === normalizedPath);
      if (!worktree) {
        // worktree 列表以 Git 为准：当记录未同步时，尝试从缓存/仓库读取并补录。
        const cached = terminalGitWorktreesByProjectIdRef.current?.[projectId];
        const cachedMatch = cached?.find(
          (item) => normalizePathForCompare(item.path) === normalizePathForCompare(normalizedPath),
        );
        try {
          const gitItems = cached ?? (await gitWorktreeList(sourceProject.path));
          setTerminalGitWorktreesByProjectId((prev) => ({ ...prev, [projectId]: gitItems }));
          await syncProjectWorktrees(projectId, gitItems);

          const match =
            cachedMatch ??
            gitItems.find((item) => normalizePathForCompare(item.path) === normalizePathForCompare(normalizedPath));
          if (!match) {
            showToast("worktree 不存在或已移除", "error");
            return;
          }

          openTerminalWorkspace(
            buildWorktreeVirtualProject(sourceProject, {
              id: createWorktreeProjectId(match.path),
              name: resolveNameFromPath(match.path),
              path: match.path,
              branch: match.branch,
              inheritConfig: true,
              created: jsDateToSwiftDate(new Date()),
            }),
          );
          return;
        } catch (error) {
          console.error("打开 worktree 失败。", error);
          const message = error instanceof Error ? error.message : String(error);
          showToast(message || "打开 worktree 失败", "error");
          return;
        }
      }
      if (worktree.status === "creating") {
        showToast("该 worktree 正在创建中，请稍候", "error");
        return;
      }
      if (worktree.status === "failed") {
        showToast(worktree.initError || "该 worktree 创建失败，请先重试", "error");
        return;
      }
      openTerminalWorkspace(buildWorktreeVirtualProject(sourceProject, worktree));
    },
    [openTerminalWorkspace, projectMap, setTerminalGitWorktreesByProjectId, showToast, syncProjectWorktrees, terminalGitWorktreesByProjectIdRef],
  );

  const handleCreateWorktree = useCallback(
    async (payload: WorktreeCreateSubmitPayload): Promise<WorktreeCreateSubmitResult> => {
      const sourceProject = projectMap.get(payload.sourceProjectId);
      if (!sourceProject) {
        throw new Error("项目不存在或已移除");
      }

      try {
        if (payload.mode === "create") {
          const key = `${sourceProject.id}|${payload.branch}`;
          worktreeInitAutoOpenPendingByProjectBranchRef.current.set(key, { autoOpen: payload.autoOpen });
          try {
            const created = await worktreeInitCreate({
              projectId: sourceProject.id,
              projectPath: payload.sourceProjectPath,
              branch: payload.branch,
              createBranch: payload.createBranch,
              baseBranch: payload.baseBranch,
            });

            // 任务入队后立即关闭弹窗；后续成功/失败提示由 worktree-init-progress 事件驱动。
            setWorktreeDialogProjectId(null);

            return {
              mode: "create",
              jobId: created.jobId,
              worktreePath: created.worktreePath,
              branch: created.branch,
              baseBranch: created.baseBranch,
            };
          } catch (error) {
            worktreeInitAutoOpenPendingByProjectBranchRef.current.delete(key);
            worktreeInitProgressSeenByProjectBranchRef.current.delete(key);
            throw error;
          }
        }

        const now = jsDateToSwiftDate(new Date());
        const nextWorktree = buildReadyWorktree(payload.worktreePath, payload.branch, now);

        await addProjectWorktree(sourceProject.id, nextWorktree);
        // 若当前已加载 Git worktree 列表，则同步更新缓存，避免列表显示旧数据。
        setTerminalGitWorktreesByProjectId((prev) => {
          if (!(sourceProject.id in prev)) {
            return prev;
          }
          const current = prev[sourceProject.id] ?? [];
          if (current.some((item) => isSamePath(item.path, payload.worktreePath))) {
            return prev;
          }
          const next = [...current, { path: payload.worktreePath, branch: payload.branch }].sort((left, right) =>
            left.path.localeCompare(right.path),
          );
          return { ...prev, [sourceProject.id]: next };
        });
        setWorktreeDialogProjectId(null);
        showToast("已有 worktree 已添加");

        if (payload.autoOpen) {
          openTerminalWorkspace(buildWorktreeVirtualProject(sourceProject, nextWorktree));
        }

        return {
          mode: "open-existing",
        };
      } catch (error) {
        // 创建任务场景下，失败 toast 通常由 worktree-init-progress 事件驱动；
        // 这里避免重复提示。
        if (payload.mode !== "create") {
          showToast(resolveErrorMessage(error) || "创建 worktree 失败", "error");
        }
        throw error;
      }
    },
    [addProjectWorktree, openTerminalWorkspace, projectMap, setTerminalGitWorktreesByProjectId, showToast],
  );

  // 恢复处于 "creating" 悬挂状态的 worktree：检查 git 实际状态并更新。
  const recoverCreatingWorktrees = useCallback(
    async (targetProjects: Project[], options?: { skipCheckedGuard?: boolean }) => {
      for (const project of targetProjects) {
        if (isWorktreeProject(project)) {
          continue;
        }
        if (!options?.skipCheckedGuard && worktreeRecoveryCheckedProjectIdsRef.current.has(project.id)) {
          continue;
        }

        const pendingWorktrees = (project.worktrees ?? []).filter((item) => item.status === "creating");
        if (pendingWorktrees.length === 0) {
          continue;
        }

        worktreeRecoveryCheckedProjectIdsRef.current.add(project.id);
        let gitItems: GitWorktreeListItem[] = [];
        try {
          gitItems = await gitWorktreeList(project.path);
        } catch (error) {
          console.warn("恢复 worktree 创建状态时读取 Git 列表失败。", error);
        }
        const gitPathSet = new Set(gitItems.map((item) => normalizePathForCompare(item.path)));

        for (const item of pendingWorktrees) {
          const existsInGit = gitPathSet.has(normalizePathForCompare(item.path));
          const now = jsDateToSwiftDate(new Date());
          await addProjectWorktree(project.id, {
            ...item,
            status: existsInGit ? "ready" : "failed",
            initStep: existsInGit ? "ready" : "failed",
            initMessage: existsInGit ? "检测到该 worktree 已创建完成" : "创建进度中断，请点击\u201c重试\u201d继续",
            initError: existsInGit ? null : "创建任务在应用重启后中断",
            updatedAt: now,
          });
        }
      }
    },
    [addProjectWorktree],
  );

  // 挂载时恢复：首次检查每个项目的悬挂 worktree。
  useEffect(() => {
    void recoverCreatingWorktrees(projects);
  }, [projects, recoverCreatingWorktrees]);

  // 交互锁释放时恢复：后端任务完成后锁释放，此时重新检查所有 "creating" 的 worktree，
  // 以修复因事件丢失导致的悬挂状态。
  const recoverOnLockReleaseRef = useRef(() => {
    void recoverCreatingWorktrees(projects, { skipCheckedGuard: true });
  });
  useEffect(() => {
    recoverOnLockReleaseRef.current = () => {
      void recoverCreatingWorktrees(projects, { skipCheckedGuard: true });
    };
  });

  useEffect(() => {
    let unlisten: (() => void) | null = null;
    const register = async () => {
      try {
        unlisten = await listenEvent<InteractionLockState>("interaction-lock", (event) => {
          if (!event.payload.locked) {
            recoverOnLockReleaseRef.current();
          }
        });
      } catch (error) {
        console.warn("监听交互锁事件失败。", error);
      }
    };

    void register();
    return () => {
      unlisten?.();
    };
  }, []);

  const handleWorktreeInitProgress = useCallback(
    async (payload: WorktreeInitProgressPayload) => {
      const sourceProject = projectMap.get(payload.projectId);
      if (!sourceProject) {
        return;
      }

      const autoOpenKey = `${payload.projectId}|${payload.branch}`;
      worktreeInitProgressSeenByProjectBranchRef.current.add(autoOpenKey);
      const pendingAutoOpenByBranch = worktreeInitAutoOpenPendingByProjectBranchRef.current.get(autoOpenKey);
      if (pendingAutoOpenByBranch && !worktreeInitAutoOpenByJobIdRef.current.has(payload.jobId)) {
        worktreeInitAutoOpenPendingByProjectBranchRef.current.delete(autoOpenKey);
        worktreeInitAutoOpenByJobIdRef.current.set(payload.jobId, {
          projectId: payload.projectId,
          worktreePath: payload.worktreePath,
          branch: payload.branch,
          autoOpen: pendingAutoOpenByBranch.autoOpen,
        });
      }

      const normalizedPath = normalizePathForCompare(payload.worktreePath);
      const existing = (sourceProject.worktrees ?? []).find(
        (item) => normalizePathForCompare(item.path) === normalizedPath,
      );

      if (payload.step === "cancelled") {
        worktreeInitAutoOpenPendingByProjectBranchRef.current.delete(autoOpenKey);
        worktreeInitAutoOpenByJobIdRef.current.delete(payload.jobId);
        await removeProjectWorktree(sourceProject.id, payload.worktreePath);
        removeWorktreeFromGitCache(sourceProject.id, payload.worktreePath);
        showToast("worktree 创建已取消");
        return;
      }

      const now = jsDateToSwiftDate(new Date());
      const status = payload.step === "failed" ? "failed" : payload.step === "ready" ? "ready" : "creating";

      const nextWorktree: ProjectWorktree = {
        id: existing?.id ?? createWorktreeProjectId(payload.worktreePath),
        name: existing?.name ?? resolveNameFromPath(payload.worktreePath),
        path: payload.worktreePath,
        branch: payload.branch,
        baseBranch: existing?.baseBranch ?? payload.baseBranch,
        inheritConfig: existing?.inheritConfig ?? true,
        created: existing?.created ?? now,
        status,
        initStep: payload.step,
        initMessage: payload.message,
        initError: payload.step === "failed" ? (payload.error ?? payload.message) : (payload.error ?? null),
        initJobId: payload.jobId,
        updatedAt: now,
      };

      await addProjectWorktree(sourceProject.id, nextWorktree);

      if (payload.step === "failed") {
        worktreeInitAutoOpenPendingByProjectBranchRef.current.delete(autoOpenKey);
        worktreeInitAutoOpenByJobIdRef.current.delete(payload.jobId);
        showToast(nextWorktree.initError || "worktree 创建失败", "error");
        return;
      }

      if (payload.step !== "ready") {
        return;
      }

      const pendingAutoOpen = worktreeInitAutoOpenByJobIdRef.current.get(payload.jobId);
      worktreeInitAutoOpenByJobIdRef.current.delete(payload.jobId);

      await syncTerminalProjectWorktrees(sourceProject.id).catch((error) => {
        console.error("同步 worktree 失败。", error);
      });

      // 创建成功后再次写入 ready 状态，规避并发同步时被旧快照回写为 creating。
      const hasSetupWarning = Boolean(payload.error?.trim());
      await addProjectWorktree(sourceProject.id, {
        ...nextWorktree,
        status: "ready",
        initStep: "ready",
        initMessage: hasSetupWarning ? "创建完成（环境初始化存在告警）" : (payload.message || "创建完成"),
        initError: payload.error ?? null,
        updatedAt: jsDateToSwiftDate(new Date()),
      });

      if (hasSetupWarning) {
        const warningText = payload.error ?? "";
        const warningSummary = warningText.split("\n")[0] || warningText;
        showToast(`worktree 创建完成，但环境初始化失败：${warningSummary}`, "error");
      } else {
        showToast("worktree 创建成功");
      }

      if (pendingAutoOpen?.autoOpen) {
        openTerminalWorkspace(buildWorktreeVirtualProject(sourceProject, nextWorktree));
      }
    },
    [
      addProjectWorktree,
      openTerminalWorkspace,
      projectMap,
      removeProjectWorktree,
      removeWorktreeFromGitCache,
      showToast,
      syncTerminalProjectWorktrees,
    ],
  );

  // 使用 ref 持有最新的 handler，避免每次 projectMap 等依赖变化时重新注册监听器。
  // 频繁 unlisten/listen 会在异步注册间隙丢失后端事件（尤其是 ready），导致 worktree 卡在 creating 状态。
  const handleWorktreeInitProgressRef = useRef(handleWorktreeInitProgress);
  useEffect(() => {
    handleWorktreeInitProgressRef.current = handleWorktreeInitProgress;
  });

  useEffect(() => {
    let unlisten: (() => void) | null = null;
    const registerListener = async () => {
      try {
        unlisten = await listenWorktreeInitProgress((event) => {
          void handleWorktreeInitProgressRef.current(event.payload);
        });
      } catch (error) {
        console.error("监听 worktree 初始化进度失败。", error);
      }
    };

    void registerListener();
    return () => {
      unlisten?.();
    };
  }, []);

  const handleRetryWorktreeFromProject = useCallback(
    async (projectId: string, worktreePath: string) => {
      const sourceProject = projectMap.get(projectId);
      if (!sourceProject) {
        showToast("项目不存在或已移除", "error");
        return;
      }

      const normalizedPath = normalizePathForCompare(worktreePath);
      const worktree = (sourceProject.worktrees ?? []).find(
        (item) => normalizePathForCompare(item.path) === normalizedPath,
      );
      if (!worktree) {
        showToast("worktree 不存在或已移除", "error");
        return;
      }

      try {
        const createBranch = Boolean(worktree.baseBranch?.trim());
        const key = `${sourceProject.id}|${worktree.branch}`;
        worktreeInitAutoOpenPendingByProjectBranchRef.current.set(key, { autoOpen: false });
        worktreeInitProgressSeenByProjectBranchRef.current.delete(key);

        try {
          await worktreeInitCreate({
            projectId: sourceProject.id,
            projectPath: sourceProject.path,
            branch: worktree.branch,
            createBranch,
            baseBranch: createBranch ? worktree.baseBranch : undefined,
            targetPath: worktree.path,
          });
        } catch (error) {
          const seenProgress = worktreeInitProgressSeenByProjectBranchRef.current.has(key);
          worktreeInitAutoOpenPendingByProjectBranchRef.current.delete(key);
          worktreeInitProgressSeenByProjectBranchRef.current.delete(key);
          const message = error instanceof Error ? error.message : String(error);
          if (!seenProgress) {
            showToast(message || "重试创建 worktree 失败", "error");
          }
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        showToast(message || "重试创建 worktree 失败", "error");
      }
    },
    [projectMap, showToast],
  );

  const handleDeleteWorktreeFromProject = useCallback(
    async (projectId: string, worktreePath: string) => {
      const sourceProject = projectMap.get(projectId);
      if (!sourceProject) {
        showToast("项目不存在或已移除", "error");
        return;
      }

      const normalizedPath = worktreePath.trim();
      const trackedWorktree = (sourceProject.worktrees ?? []).find((item) => item.path === normalizedPath);
      const cached = terminalGitWorktreesByProjectIdRef.current?.[projectId];
      const cachedMatch = cached?.find((item) => isSamePath(item.path, normalizedPath));
      const worktree =
        trackedWorktree ??
        (cachedMatch ? buildTrackedWorktreeFromGitItem(cachedMatch, jsDateToSwiftDate(new Date())) : null);
      if (!worktree) {
        showToast("worktree 不存在或已移除", "error");
        return;
      }
      const shouldDeleteManagedBranch = Boolean(trackedWorktree?.baseBranch?.trim());

      const removeRecordOnly = async () => {
        await removeProjectWorktree(sourceProject.id, worktree.path);
        await deleteTerminalWorkspace(worktree.path).catch(() => undefined);
        showToast("worktree 记录已移除", "success");
      };

      const confirmRemoveRecordOnly = async () => {
        const removeOnly = await confirmRuntime("是否仅从 DevHaven 列表中移除该 worktree 记录？（不会执行 Git 删除）", {
          title: "移除 worktree 记录",
          kind: "warning",
          okLabel: "移除记录",
          cancelLabel: "取消",
        });
        if (removeOnly) {
          await removeRecordOnly();
        }
      };

      if (worktree.status === "creating") {
        showToast("该 worktree 正在创建中，无法取消，请等待完成后再操作", "error");
        return;
      }

      const confirmed = await confirmRuntime(
        `确定要删除该 worktree 吗？\n\n分支：${worktree.branch}\n路径：${worktree.path}\n\n将执行 git worktree remove 并删除该目录${shouldDeleteManagedBranch ? "，并删除对应本地分支" : ""}。`,
        {
          title: "删除 worktree",
          kind: "warning",
          okLabel: "删除",
          cancelLabel: "取消",
        },
      );
      if (!confirmed) {
        return;
      }

      const openedWorktree = terminalOpenProjectsRef.current?.find((item) => item.path === worktree.path);
      if (openedWorktree) {
        handleCloseTerminalProject(openedWorktree.id);
        // 给 unmount / PTY 清理一个 tick，避免 Windows 等平台目录占用导致删除失败。
        await new Promise<void>((resolve) => window.setTimeout(resolve, 150));
      }

      try {
        await gitWorktreeRemove({
          path: sourceProject.path,
          worktreePath: worktree.path,
          force: false,
        });
      } catch (error) {
        const message = resolveErrorMessage(error);
        const forceConfirmed = await confirmRuntime(`删除失败：${message || "未知错误"}\n\n是否尝试"强制删除"？（可能丢失未提交修改）`, {
          title: "删除 worktree",
          kind: "warning",
          okLabel: "强制删除",
          cancelLabel: "取消",
        });
        if (!forceConfirmed) {
          await confirmRemoveRecordOnly();
          return;
        }
        try {
          await gitWorktreeRemove({
            path: sourceProject.path,
            worktreePath: worktree.path,
            force: true,
          });
        } catch (forceError) {
          const forceMessage = resolveErrorMessage(forceError);
          showToast(forceMessage || "强制删除 worktree 失败", "error");
          await confirmRemoveRecordOnly();
          return;
        }
      }

      let branchDeleteError: string | null = null;
      if (shouldDeleteManagedBranch) {
        try {
          await gitDeleteBranch({
            path: sourceProject.path,
            branch: worktree.branch,
            force: false,
          });
        } catch (error) {
          branchDeleteError = resolveErrorMessage(error);
        }
      }

      await removeProjectWorktree(sourceProject.id, worktree.path);
      await deleteTerminalWorkspace(worktree.path).catch(() => undefined);
      removeWorktreeFromGitCache(projectId, worktree.path);
      if (branchDeleteError) {
        showToast(`worktree 已删除，但分支删除失败：${branchDeleteError}`, "error");
      } else if (shouldDeleteManagedBranch) {
        showToast("worktree 与对应分支已删除", "success");
      } else {
        showToast("worktree 已删除", "success");
      }
      void syncTerminalProjectWorktrees(projectId).catch(() => undefined);
    },
    [
      handleCloseTerminalProject,
      projectMap,
      removeProjectWorktree,
      removeWorktreeFromGitCache,
      showToast,
      syncTerminalProjectWorktrees,
      terminalGitWorktreesByProjectIdRef,
      terminalOpenProjectsRef,
    ],
  );

  return {
    worktreeDialogProjectId,
    setWorktreeDialogProjectId,
    worktreeDialogSourceProject,
    handleRequestCreateWorktree,
    handleOpenWorktreeFromProject,
    handleCreateWorktree,
    handleRetryWorktreeFromProject,
    handleDeleteWorktreeFromProject,
  };
}
