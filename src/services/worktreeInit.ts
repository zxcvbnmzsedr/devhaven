import { invokeCommand } from "../platform/commandClient";
import { listenEvent } from "../platform/eventClient";

export const WORKTREE_INIT_CLIENT_LOCK_EVENT = "worktree-init-client-lock";

export type WorktreeInitStep =
  | "pending"
  | "validating"
  | "checking_branch"
  | "creating_worktree"
  | "preparing_environment"
  | "syncing"
  | "ready"
  | "failed"
  | "cancelled";

export type WorktreeInitStartRequest = {
  projectId: string;
  projectPath: string;
  branch: string;
  createBranch: boolean;
  baseBranch?: string;
  targetPath?: string;
};

export type WorktreeInitStartResult = {
  jobId: string;
  projectId: string;
  projectPath: string;
  worktreePath: string;
  branch: string;
  baseBranch?: string;
  step: WorktreeInitStep;
  message: string;
};

export type WorktreeInitCreateBlockingResult = {
  jobId: string;
  projectId: string;
  projectPath: string;
  worktreePath: string;
  branch: string;
  baseBranch?: string;
  message: string;
  warning?: string | null;
};

export type WorktreeInitProgressPayload = {
  jobId: string;
  projectId: string;
  projectPath: string;
  worktreePath: string;
  branch: string;
  baseBranch?: string;
  step: WorktreeInitStep;
  message: string;
  error?: string | null;
};

export type WorktreeInitClientLockPayload = {
  active: boolean;
  sourceProjectPath: string;
  branch: string;
  baseBranch?: string;
  message?: string;
};

async function flushUiBeforeBlockingCall(): Promise<void> {
  if (typeof window === "undefined") {
    return;
  }

  await new Promise<void>((resolve) => {
    window.requestAnimationFrame(() => {
      window.requestAnimationFrame(() => {
        window.setTimeout(resolve, 0);
      });
    });
  });
}

export type WorktreeInitCancelResult = {
  jobId: string;
  cancelled: boolean;
};

export type WorktreeInitJobStatus = {
  jobId: string;
  projectId: string;
  projectPath: string;
  worktreePath: string;
  branch: string;
  baseBranch?: string;
  createBranch: boolean;
  step: WorktreeInitStep;
  message: string;
  error?: string | null;
  updatedAt: number;
  isRunning: boolean;
  cancelRequested: boolean;
};

export async function worktreeInitStart(
  request: WorktreeInitStartRequest,
): Promise<WorktreeInitStartResult> {
  return invokeCommand<WorktreeInitStartResult>("worktree_init_start", { request });
}

export async function worktreeInitCreate(
  request: WorktreeInitStartRequest,
): Promise<WorktreeInitStartResult> {
  if (typeof window !== "undefined") {
    window.dispatchEvent(
      new CustomEvent<WorktreeInitClientLockPayload>(WORKTREE_INIT_CLIENT_LOCK_EVENT, {
        detail: {
          active: true,
          sourceProjectPath: request.projectPath,
          branch: request.branch,
          baseBranch: request.baseBranch,
          message: "正在提交创建请求...",
        },
      }),
    );

    await flushUiBeforeBlockingCall();
  }

  try {
    return await invokeCommand<WorktreeInitStartResult>("worktree_init_create", { request });
  } catch (error) {
    if (typeof window !== "undefined") {
      window.dispatchEvent(
        new CustomEvent<WorktreeInitClientLockPayload>(WORKTREE_INIT_CLIENT_LOCK_EVENT, {
          detail: {
            active: false,
            sourceProjectPath: request.projectPath,
            branch: request.branch,
            baseBranch: request.baseBranch,
          },
        }),
      );
    }
    throw error;
  }
}

export async function worktreeInitCreateBlocking(
  request: WorktreeInitStartRequest,
): Promise<WorktreeInitCreateBlockingResult> {
  if (typeof window !== "undefined") {
    window.dispatchEvent(
      new CustomEvent<WorktreeInitClientLockPayload>(WORKTREE_INIT_CLIENT_LOCK_EVENT, {
        detail: {
          active: true,
          sourceProjectPath: request.projectPath,
          branch: request.branch,
          baseBranch: request.baseBranch,
          message: "正在提交创建请求...",
        },
      }),
    );

    // `worktree_init_create_blocking` 在部分环境会让前端主线程短暂无响应。
    // 先让浏览器完成一次渲染，确保全局遮罩与进度条立即可见。
    await flushUiBeforeBlockingCall();
  }

  try {
    return await invokeCommand<WorktreeInitCreateBlockingResult>("worktree_init_create_blocking", { request });
  } finally {
    if (typeof window !== "undefined") {
      window.dispatchEvent(
        new CustomEvent<WorktreeInitClientLockPayload>(WORKTREE_INIT_CLIENT_LOCK_EVENT, {
          detail: {
            active: false,
            sourceProjectPath: request.projectPath,
            branch: request.branch,
            baseBranch: request.baseBranch,
          },
        }),
      );
    }
  }
}

export async function worktreeInitCancel(jobId: string): Promise<WorktreeInitCancelResult> {
  return invokeCommand<WorktreeInitCancelResult>("worktree_init_cancel", { jobId });
}

export async function worktreeInitRetry(jobId: string): Promise<WorktreeInitStartResult> {
  return invokeCommand<WorktreeInitStartResult>("worktree_init_retry", {
    request: { jobId },
  });
}

export async function worktreeInitStatus(query?: {
  projectId?: string;
  projectPath?: string;
}): Promise<WorktreeInitJobStatus[]> {
  return invokeCommand<WorktreeInitJobStatus[]>("worktree_init_status", {
    query: query ?? null,
  });
}

export async function listenWorktreeInitProgress(
  handler: (event: { payload: WorktreeInitProgressPayload }) => void,
) {
  return listenEvent<WorktreeInitProgressPayload>("worktree-init-progress", handler);
}
