import { useEffect, useMemo, useState } from "react";
import { listenEvent } from "../platform/eventClient";

import { getInteractionLockState, type InteractionLockState } from "../services/interactionLock";
import {
  WORKTREE_INIT_CLIENT_LOCK_EVENT,
  listenWorktreeInitProgress,
  worktreeInitStatus,
  type WorktreeInitClientLockPayload,
  type WorktreeInitJobStatus,
  type WorktreeInitProgressPayload,
  type WorktreeInitStep,
} from "../services/worktreeInit";
import { setInteractionLocked } from "../utils/interactionLock";

const INTERACTION_LOCK_EVENT = "interaction-lock";

const TERMINAL_STEPS = new Set<WorktreeInitStep>(["ready", "failed", "cancelled"]);

const WORKTREE_STEP_META: Record<WorktreeInitStep, { label: string; progress: number }> = {
  pending: { label: "准备任务", progress: 8 },
  validating: { label: "校验仓库", progress: 20 },
  checking_branch: { label: "校验分支", progress: 35 },
  creating_worktree: { label: "创建 worktree", progress: 60 },
  preparing_environment: { label: "准备环境", progress: 80 },
  syncing: { label: "同步状态", progress: 92 },
  ready: { label: "创建完成", progress: 100 },
  failed: { label: "创建失败", progress: 100 },
  cancelled: { label: "创建已取消", progress: 100 },
};

type WorktreeProgressSnapshot = {
  jobId: string;
  sourceProjectPath?: string;
  branch: string;
  baseBranch?: string;
  worktreePath?: string;
  step: WorktreeInitStep;
  message: string;
  error?: string | null;
};

function stopAll(event: Event) {
  event.preventDefault();
  event.stopPropagation();
  event.stopImmediatePropagation?.();
}

function fromProgressPayload(payload: WorktreeInitProgressPayload): WorktreeProgressSnapshot {
  return {
    jobId: payload.jobId,
    sourceProjectPath: payload.projectPath,
    branch: payload.branch,
    baseBranch: payload.baseBranch,
    worktreePath: payload.worktreePath,
    step: payload.step,
    message: payload.message,
    error: payload.error,
  };
}

function fromJobStatus(status: WorktreeInitJobStatus): WorktreeProgressSnapshot {
  return {
    jobId: status.jobId,
    sourceProjectPath: status.projectPath,
    branch: status.branch,
    baseBranch: status.baseBranch,
    worktreePath: status.worktreePath,
    step: status.step,
    message: status.message,
    error: status.error,
  };
}

function fromClientLockPayload(payload: WorktreeInitClientLockPayload): WorktreeProgressSnapshot {
  return {
    jobId: "pending-client-request",
    sourceProjectPath: payload.sourceProjectPath,
    branch: payload.branch,
    baseBranch: payload.baseBranch,
    step: "pending",
    message: payload.message || "正在提交创建请求...",
    error: null,
  };
}

export default function InteractionLockOverlay() {
  const [lockState, setLockState] = useState<InteractionLockState>({ locked: false, reason: null });
  const [clientLockPayload, setClientLockPayload] = useState<WorktreeInitClientLockPayload | null>(null);
  const [worktreeProgress, setWorktreeProgress] = useState<WorktreeProgressSnapshot | null>(null);

  const isClientLockActive = Boolean(clientLockPayload?.active);
  const isLocked = lockState.locked || isClientLockActive;
  const isWorktreeCreateLock = lockState.reason === "worktree-create" || isClientLockActive;
  const displayProgress = worktreeProgress ?? (clientLockPayload ? fromClientLockPayload(clientLockPayload) : null);
  const progressStep = displayProgress?.step ?? "pending";
  const progressMeta = WORKTREE_STEP_META[progressStep];
  const progressPercent = displayProgress ? progressMeta.progress : 8;
  const isFailed = progressStep === "failed" || progressStep === "cancelled";
  const phaseText =
    progressStep === "pending"
      ? "排队中"
      : progressStep === "ready"
        ? "已完成"
        : isFailed
          ? "已中断"
          : "执行中";

  const title = useMemo(() => {
    if (isWorktreeCreateLock) {
      return "正在创建 worktree...";
    }
    return "正在处理中...";
  }, [isWorktreeCreateLock]);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      try {
        const snapshot = await getInteractionLockState();
        if (cancelled) {
          return;
        }
        setLockState(snapshot);
        setInteractionLocked(Boolean(snapshot.locked));
      } catch (error) {
        console.warn("读取交互锁状态失败。", error);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    let unlisten: (() => void) | null = null;
    const register = async () => {
      try {
        unlisten = await listenEvent<InteractionLockState>(INTERACTION_LOCK_EVENT, (event) => {
          const next = event.payload;
          setLockState(next);
          setInteractionLocked(Boolean(next.locked));
        });
      } catch (error) {
        console.error("监听交互锁事件失败。", error);
      }
    };

    void register();
    return () => {
      unlisten?.();
    };
  }, []);

  useEffect(() => {
    if (!lockState.locked) {
      return;
    }
    // 后端交互锁生效后，前端预锁即可让位，避免双重状态导致遮罩残留。
    setClientLockPayload(null);
  }, [lockState.locked]);

  useEffect(() => {
    const handleClientLock = (event: Event) => {
      const detail = (event as CustomEvent<WorktreeInitClientLockPayload>).detail;
      if (!detail) {
        return;
      }
      setClientLockPayload(detail.active ? detail : null);
      if (detail.active) {
        setWorktreeProgress((prev) => prev ?? fromClientLockPayload(detail));
      }
    };

    window.addEventListener(WORKTREE_INIT_CLIENT_LOCK_EVENT, handleClientLock as EventListener);
    return () => {
      window.removeEventListener(WORKTREE_INIT_CLIENT_LOCK_EVENT, handleClientLock as EventListener);
    };
  }, []);

  useEffect(() => {
    let unlisten: (() => void) | null = null;
    const register = async () => {
      try {
        unlisten = await listenWorktreeInitProgress((event) => {
          const next = fromProgressPayload(event.payload);
          setWorktreeProgress(next);
          if (TERMINAL_STEPS.has(next.step)) {
            setClientLockPayload(null);
          }
        });
      } catch (error) {
        console.error("监听 worktree 初始化进度失败。", error);
      }
    };

    void register();
    return () => {
      unlisten?.();
    };
  }, []);

  useEffect(() => {
    if (!isLocked || !isWorktreeCreateLock) {
      setWorktreeProgress(null);
      return;
    }

    let cancelled = false;
    void (async () => {
      try {
        const statuses = await worktreeInitStatus();
        if (cancelled || statuses.length === 0) {
          return;
        }
        const current =
          statuses.find((item) => item.isRunning) ?? statuses.find((item) => !TERMINAL_STEPS.has(item.step));
        if (!current) {
          return;
        }
        setWorktreeProgress((prev) => {
          if (prev && prev.jobId === current.jobId && prev.step === current.step) {
            return prev;
          }
          return fromJobStatus(current);
        });
      } catch (error) {
        console.warn("读取 worktree 初始化状态失败。", error);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [isLocked, isWorktreeCreateLock]);

  useEffect(() => {
    if (!isLocked) {
      setInteractionLocked(false);
      document.body.style.cursor = "";
      return;
    }

    setInteractionLocked(true);
    document.body.style.cursor = "wait";

    const stopWheel = (event: WheelEvent) => stopAll(event);
    const stopKey = (event: KeyboardEvent) => stopAll(event);
    const stopPointer = (event: PointerEvent) => stopAll(event);
    const stopMouse = (event: MouseEvent) => stopAll(event);
    const stopTouch = (event: TouchEvent) => stopAll(event);

    window.addEventListener("keydown", stopKey, true);
    window.addEventListener("keyup", stopKey, true);
    window.addEventListener("keypress", stopKey, true);

    window.addEventListener("pointerdown", stopPointer, true);
    window.addEventListener("pointerup", stopPointer, true);
    window.addEventListener("mousedown", stopMouse, true);
    window.addEventListener("mouseup", stopMouse, true);
    window.addEventListener("click", stopMouse, true);
    window.addEventListener("dblclick", stopMouse, true);
    window.addEventListener("contextmenu", stopMouse, true);

    window.addEventListener("touchstart", stopTouch, true);
    window.addEventListener("touchend", stopTouch, true);
    window.addEventListener("touchmove", stopTouch, true);

    window.addEventListener("dragstart", stopAll, true);
    window.addEventListener("drop", stopAll, true);

    window.addEventListener("wheel", stopWheel, { capture: true, passive: false });

    return () => {
      window.removeEventListener("keydown", stopKey, true);
      window.removeEventListener("keyup", stopKey, true);
      window.removeEventListener("keypress", stopKey, true);

      window.removeEventListener("pointerdown", stopPointer, true);
      window.removeEventListener("pointerup", stopPointer, true);
      window.removeEventListener("mousedown", stopMouse, true);
      window.removeEventListener("mouseup", stopMouse, true);
      window.removeEventListener("click", stopMouse, true);
      window.removeEventListener("dblclick", stopMouse, true);
      window.removeEventListener("contextmenu", stopMouse, true);

      window.removeEventListener("touchstart", stopTouch, true);
      window.removeEventListener("touchend", stopTouch, true);
      window.removeEventListener("touchmove", stopTouch, true);

      window.removeEventListener("dragstart", stopAll, true);
      window.removeEventListener("drop", stopAll, true);

      window.removeEventListener("wheel", stopWheel, true);
      document.body.style.cursor = "";
    };
  }, [isLocked]);

  if (!isLocked) {
    return null;
  }

  return (
    <div className="fixed inset-0 z-[200] bg-[rgba(0,0,0,0.65)] flex items-center justify-center" role="alertdialog" aria-modal>
      <div className="w-[min(520px,92vw)] rounded-xl border border-border bg-secondary-background p-5">
        <div className="text-[16px] font-semibold text-text">{title}</div>
        <div className="mt-1 text-fs-caption text-secondary-text">创建完成前将锁定所有交互，请稍候。</div>

        {isWorktreeCreateLock ? (
          <>
            <div className="mt-3 rounded-md border border-border bg-card-bg px-3 py-2 text-fs-caption text-secondary-text">
              当前阶段：{progressMeta.label}（{phaseText}）
              <br />
              详情：{displayProgress?.message || "正在准备创建任务..."}
            </div>
            <div className="mt-3">
              <div className="flex items-center justify-between text-fs-caption text-secondary-text">
                <span>初始化进度</span>
                <span>{progressPercent}%</span>
              </div>
              <div className="mt-1 h-2 overflow-hidden rounded-full bg-[rgba(148,163,184,0.25)]">
                <div
                  className={`h-full transition-all duration-300 ${isFailed ? "bg-[rgba(239,68,68,0.9)]" : "bg-[rgba(59,130,246,0.9)]"}`}
                  style={{ width: `${progressPercent}%` }}
                />
              </div>
            </div>
            {displayProgress ? (
              <div className="mt-3 rounded-md border border-border bg-card-bg px-3 py-2 text-fs-caption text-secondary-text break-all">
                分支：{displayProgress.branch}
                {displayProgress.baseBranch ? (
                  <>
                    <br />
                    基线：{displayProgress.baseBranch}
                  </>
                ) : null}
                <br />
                {displayProgress.worktreePath ? `路径：${displayProgress.worktreePath}` : `源仓库：${displayProgress.sourceProjectPath ?? "-"}`}
                {displayProgress.error ? (
                  <>
                    <br />
                    <span className="text-error">错误：{displayProgress.error}</span>
                  </>
                ) : null}
              </div>
            ) : null}
          </>
        ) : null}

        <div className="mt-3 text-fs-caption text-secondary-text animate-pulse">请勿关闭窗口或退出应用</div>
      </div>
    </div>
  );
}
