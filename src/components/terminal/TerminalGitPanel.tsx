import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import type { BranchListItem } from "../../models/branch";
import type { GitChangedFile, GitRepoStatus } from "../../models/gitManagement";
import { listBranches } from "../../services/git";
import {
  gitCheckoutBranch,
  gitCommit,
  gitDiscardFiles,
  gitGetStatus,
  gitStageFiles,
  gitUnstageFiles,
} from "../../services/gitManagement";
import { IconRefresh, IconX } from "../Icons";

export type TerminalGitPanelProps = {
  projectPath: string;
  onClose: () => void;
  embedded?: boolean;
  selected: GitSelectedFile | null;
  onSelect: (next: GitSelectedFile | null) => void;
};

export type GitFileCategory = "staged" | "unstaged" | "untracked";

export type GitSelectedFile = {
  category: GitFileCategory;
  path: string;
  oldPath?: string | null;
};

function formatGitStatusBadge(status: GitChangedFile["status"]): string {
  switch (status) {
    case "added":
      return "A";
    case "deleted":
      return "D";
    case "renamed":
      return "R";
    case "copied":
      return "C";
    case "untracked":
      return "?";
    case "modified":
    default:
      return "M";
  }
}

function formatGitError(err: unknown): string {
  if (err instanceof Error) {
    return err.message || String(err);
  }
  if (typeof err === "string") {
    return err;
  }
  try {
    return JSON.stringify(err);
  } catch {
    return String(err);
  }
}

function describeFile(file: GitChangedFile): string {
  if (file.oldPath) {
    return `${file.oldPath} -> ${file.path}`;
  }
  return file.path;
}

export default function TerminalGitPanel({
  projectPath,
  onClose,
  embedded = false,
  selected,
  onSelect,
}: TerminalGitPanelProps) {
  const [status, setStatus] = useState<GitRepoStatus | null>(null);
  const [branches, setBranches] = useState<BranchListItem[]>([]);

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const refreshInFlightRef = useRef(false);
  const refreshIdRef = useRef(0);

  const [actionBusy, setActionBusy] = useState(false);

  const [commitMessage, setCommitMessage] = useState("");
  const [checkoutBranch, setCheckoutBranchState] = useState("");
  const lastBranchRef = useRef<string>("");

  const effectiveBranch = status?.branch ?? "";
  const canCommit = Boolean(status && status.staged.length > 0 && commitMessage.trim().length > 0);

  const refresh = useCallback(async (options?: { includeBranches?: boolean }) => {
    if (!projectPath) {
      return;
    }
    if (refreshInFlightRef.current) {
      return;
    }
    refreshInFlightRef.current = true;
    const refreshId = refreshIdRef.current + 1;
    refreshIdRef.current = refreshId;

    setLoading(true);
    setError(null);
    try {
      const nextStatus = await gitGetStatus(projectPath);
      const nextBranches = options?.includeBranches ? await listBranches(projectPath) : null;
      if (refreshIdRef.current !== refreshId) {
        return;
      }
      setStatus(nextStatus);
      if (nextBranches) {
        setBranches(nextBranches);
      }
      setCheckoutBranchState((prev) => {
        const last = lastBranchRef.current;
        const shouldSync = !prev.trim() || (last && prev === last);
        return shouldSync ? nextStatus.branch : prev;
      });
      lastBranchRef.current = nextStatus.branch;

      if (selected) {
        const findIn = (category: GitFileCategory, files: GitChangedFile[]) => {
          const matched = files.find((file) => file.path === selected.path);
          return matched
            ? ({
                category,
                path: matched.path,
                oldPath: matched.oldPath ?? null,
              } as const)
            : null;
        };

        const current =
          selected.category === "staged"
            ? findIn("staged", nextStatus.staged)
            : selected.category === "unstaged"
              ? findIn("unstaged", nextStatus.unstaged)
              : findIn("untracked", nextStatus.untracked);

        const fallback =
          current ??
          findIn("staged", nextStatus.staged) ??
          findIn("unstaged", nextStatus.unstaged) ??
          findIn("untracked", nextStatus.untracked);

        if (!fallback) {
          onSelect(null);
        } else if (
          fallback.category !== selected.category ||
          fallback.oldPath !== (selected.oldPath ?? null)
        ) {
          onSelect(fallback);
        }
      }
    } catch (err) {
      if (refreshIdRef.current === refreshId) {
        setError(formatGitError(err));
      }
    } finally {
      if (refreshIdRef.current === refreshId) {
        setLoading(false);
      }
      refreshInFlightRef.current = false;
    }
  }, [onSelect, projectPath, selected]);

  useEffect(() => {
    void refresh({ includeBranches: true });
  }, [refresh]);

  useEffect(() => {
    const timer = window.setInterval(() => {
      void refresh();
    }, 2500);
    return () => window.clearInterval(timer);
  }, [refresh]);

  const runAction = useCallback(
    async (action: () => Promise<void>) => {
      if (actionBusy) {
        return;
      }
      setActionBusy(true);
      setError(null);
      try {
        await action();
        await refresh();
      } catch (err) {
        setError(formatGitError(err));
      } finally {
        setActionBusy(false);
      }
    },
    [actionBusy, refresh],
  );

  const handleStage = useCallback(
    (path: string) => {
      void runAction(async () => {
        await gitStageFiles(projectPath, [path]);
      });
    },
    [projectPath, runAction],
  );

  const handleUnstage = useCallback(
    (path: string) => {
      void runAction(async () => {
        await gitUnstageFiles(projectPath, [path]);
      });
    },
    [projectPath, runAction],
  );

  const handleDiscard = useCallback(
    (path: string) => {
      const ok = window.confirm(`确定丢弃未暂存修改？\n\n${path}`);
      if (!ok) {
        return;
      }
      void runAction(async () => {
        await gitDiscardFiles(projectPath, [path]);
      });
    },
    [projectPath, runAction],
  );

  const handleCommit = useCallback(() => {
    if (!canCommit) {
      return;
    }
    void runAction(async () => {
      await gitCommit(projectPath, commitMessage);
      setCommitMessage("");
    });
  }, [canCommit, commitMessage, projectPath, runAction]);

  const handleCheckout = useCallback(() => {
    const next = checkoutBranch.trim();
    if (!next) {
      return;
    }
    if (next === effectiveBranch) {
      return;
    }
    void runAction(async () => {
      await gitCheckoutBranch(projectPath, next);
    });
  }, [checkoutBranch, effectiveBranch, projectPath, runAction]);

  const stagedFiles = status?.staged ?? [];
  const unstagedFiles = status?.unstaged ?? [];
  const untrackedFiles = status?.untracked ?? [];

  const branchOptions = useMemo(() => {
    const list = branches.map((item) => item.name);
    const unique = Array.from(new Set(list));
    unique.sort((a, b) => a.localeCompare(b));
    return unique;
  }, [branches]);

  return (
    <aside
      className={`flex min-h-0 min-w-0 flex-col bg-[var(--terminal-panel-bg)] ${
        embedded ? "flex-1" : "w-[380px] border-l border-[var(--terminal-divider)]"
      }`}
    >
      {!embedded ? (
        <div className="flex items-start justify-between gap-2 border-b border-[var(--terminal-divider)] px-3 py-2">
          <div className="min-w-0">
            <div className="text-[12px] font-semibold text-[var(--terminal-muted-fg)]">Git</div>
            <div className="mt-0.5 max-w-[300px] truncate text-[10px] text-[var(--terminal-muted-fg)]">
              {projectPath}
            </div>
          </div>
          <button
            className="inline-flex h-7 w-7 items-center justify-center rounded-md border border-transparent text-[var(--terminal-muted-fg)] hover:border-[var(--terminal-divider)] hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--terminal-accent-outline)] focus-visible:outline-offset-2"
            type="button"
            aria-label="关闭 Git 面板"
            title="关闭"
            onClick={onClose}
          >
            <IconX size={14} />
          </button>
        </div>
      ) : null}

      <div className="flex flex-col gap-2 border-b border-[var(--terminal-divider)] px-3 py-2">
        <div className="flex items-center justify-between gap-2">
          <div className="min-w-0 text-[11px] text-[var(--terminal-muted-fg)]">
            <span className="font-semibold text-[var(--terminal-fg)]">{status?.branch ?? "-"}</span>
            {status?.upstream ? (
              <span className="ml-2 truncate text-[10px] text-[var(--terminal-muted-fg)]">
                ↑ {status.upstream}
              </span>
            ) : null}
            {status ? (
              <span className="ml-2 whitespace-nowrap text-[10px] text-[var(--terminal-muted-fg)]">
                +{status.ahead} -{status.behind}
              </span>
            ) : null}
          </div>
          <button
            className="inline-flex h-6 w-6 items-center justify-center rounded-md text-[var(--terminal-muted-fg)] transition-colors hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--terminal-accent-outline)] focus-visible:outline-offset-2 disabled:opacity-50"
            type="button"
            aria-label="刷新 Git 状态"
            title="刷新"
            disabled={loading || actionBusy}
            onClick={() => void refresh({ includeBranches: true })}
          >
            <IconRefresh size={14} />
          </button>
        </div>

        <div className="flex items-center gap-2">
          <select
            className="h-7 min-w-0 flex-1 rounded-md border border-[var(--terminal-divider)] bg-[var(--terminal-bg)] px-2 text-[11px] text-[var(--terminal-fg)] outline-none"
            value={checkoutBranch}
            onChange={(event) => setCheckoutBranchState(event.target.value)}
          >
            {branchOptions.length > 0 ? (
              branchOptions.map((name) => (
                <option key={name} value={name}>
                  {name}
                </option>
              ))
            ) : (
              <option value={effectiveBranch}>{effectiveBranch || "-"}</option>
            )}
          </select>
          <button
            className="inline-flex h-7 items-center justify-center rounded-md border border-[var(--terminal-divider)] bg-transparent px-2 text-[11px] font-semibold text-[var(--terminal-muted-fg)] transition-colors hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)] disabled:cursor-not-allowed disabled:opacity-50"
            type="button"
            disabled={!checkoutBranch.trim() || checkoutBranch.trim() === effectiveBranch || actionBusy}
            onClick={handleCheckout}
            title="切换分支（git checkout）"
          >
            切换
          </button>
        </div>

        <div className="flex flex-col gap-1">
          <textarea
            value={commitMessage}
            placeholder="提交信息（将提交 staged 改动）"
            onChange={(event) => setCommitMessage(event.target.value)}
            rows={2}
            className="w-full resize-none rounded-md border border-[var(--terminal-divider)] bg-[var(--terminal-bg)] px-2 py-1 text-[11px] text-[var(--terminal-fg)] outline-none placeholder:text-[var(--terminal-muted-fg)]"
          />
          <div className="flex items-center justify-between gap-2">
            <div className="text-[10px] text-[var(--terminal-muted-fg)]">
              staged: {stagedFiles.length}
            </div>
            <button
              className="inline-flex h-7 items-center justify-center rounded-md border border-[var(--terminal-divider)] bg-[var(--terminal-hover-bg)] px-2 text-[11px] font-semibold text-[var(--terminal-muted-fg)] transition-colors hover:text-[var(--terminal-fg)] disabled:cursor-not-allowed disabled:opacity-50"
              type="button"
              disabled={!canCommit || actionBusy}
              onClick={handleCommit}
              title="提交（git commit -m）"
            >
              提交
            </button>
          </div>
        </div>

        {error ? (
          <div className="rounded-md border border-[var(--terminal-divider)] bg-[var(--terminal-bg)] px-2 py-1 text-[11px] text-[var(--terminal-muted-fg)]">
            {error}
          </div>
        ) : null}
      </div>

      <div className="flex min-h-0 flex-1 flex-col">
        <div className="min-h-0 flex-1 overflow-auto bg-[var(--terminal-bg)]">
          {loading && !status ? (
            <div className="px-3 py-2 text-[12px] text-[var(--terminal-muted-fg)]">正在读取 Git 状态...</div>
          ) : null}

          {!loading && !status && !error ? (
            <div className="px-3 py-2 text-[12px] text-[var(--terminal-muted-fg)]">暂无状态</div>
          ) : null}

          {status ? (
            <div className="px-2 py-2">
              <div className="mb-2 text-[11px] font-semibold text-[var(--terminal-muted-fg)]">
                已暂存（{stagedFiles.length}）
              </div>
              {stagedFiles.length === 0 ? (
                <div className="px-1 pb-2 text-[11px] text-[var(--terminal-muted-fg)]">无</div>
              ) : (
                <div className="space-y-1 pb-2">
                  {stagedFiles.map((file) => {
                    const active = selected?.category === "staged" && selected.path === file.path;
                    return (
                      <div
                        key={`staged:${file.path}`}
                        className={`flex items-center gap-2 rounded-md px-2 py-1 transition-colors ${
                          active ? "bg-[var(--terminal-hover-bg)]" : "hover:bg-[var(--terminal-hover-bg)]"
                        }`}
                      >
                        <button
                          type="button"
                          className="flex min-w-0 flex-1 items-center gap-2 text-left"
                          onClick={() =>
                            onSelect({ category: "staged", path: file.path, oldPath: file.oldPath ?? null })
                          }
                          title={describeFile(file)}
                        >
                          <span className="w-4 shrink-0 text-[10px] font-semibold text-[var(--terminal-muted-fg)]">
                            {formatGitStatusBadge(file.status)}
                          </span>
                          <span className="min-w-0 truncate text-[11px] text-[var(--terminal-fg)]">
                            {describeFile(file)}
                          </span>
                        </button>
                        <button
                          type="button"
                          className="inline-flex h-6 shrink-0 items-center justify-center rounded-md border border-[var(--terminal-divider)] bg-transparent px-2 text-[10px] font-semibold text-[var(--terminal-muted-fg)] transition-colors hover:bg-[var(--terminal-panel-bg)] hover:text-[var(--terminal-fg)] disabled:cursor-not-allowed disabled:opacity-50"
                          disabled={actionBusy}
                          onClick={() => handleUnstage(file.path)}
                          title="取消暂存"
                        >
                          取消
                        </button>
                      </div>
                    );
                  })}
                </div>
              )}

              <div className="mb-2 mt-2 text-[11px] font-semibold text-[var(--terminal-muted-fg)]">
                未暂存（{unstagedFiles.length}）
              </div>
              {unstagedFiles.length === 0 ? (
                <div className="px-1 pb-2 text-[11px] text-[var(--terminal-muted-fg)]">无</div>
              ) : (
                <div className="space-y-1 pb-2">
                  {unstagedFiles.map((file) => {
                    const active = selected?.category === "unstaged" && selected.path === file.path;
                    return (
                      <div
                        key={`unstaged:${file.path}`}
                        className={`flex items-center gap-2 rounded-md px-2 py-1 transition-colors ${
                          active ? "bg-[var(--terminal-hover-bg)]" : "hover:bg-[var(--terminal-hover-bg)]"
                        }`}
                      >
                        <button
                          type="button"
                          className="flex min-w-0 flex-1 items-center gap-2 text-left"
                          onClick={() =>
                            onSelect({ category: "unstaged", path: file.path, oldPath: file.oldPath ?? null })
                          }
                          title={describeFile(file)}
                        >
                          <span className="w-4 shrink-0 text-[10px] font-semibold text-[var(--terminal-muted-fg)]">
                            {formatGitStatusBadge(file.status)}
                          </span>
                          <span className="min-w-0 truncate text-[11px] text-[var(--terminal-fg)]">
                            {describeFile(file)}
                          </span>
                        </button>
                        <button
                          type="button"
                          className="inline-flex h-6 shrink-0 items-center justify-center rounded-md border border-[var(--terminal-divider)] bg-transparent px-2 text-[10px] font-semibold text-[var(--terminal-muted-fg)] transition-colors hover:bg-[var(--terminal-panel-bg)] hover:text-[var(--terminal-fg)] disabled:cursor-not-allowed disabled:opacity-50"
                          disabled={actionBusy}
                          onClick={() => handleStage(file.path)}
                          title="暂存"
                        >
                          暂存
                        </button>
                        <button
                          type="button"
                          className="inline-flex h-6 shrink-0 items-center justify-center rounded-md border border-[var(--terminal-divider)] bg-transparent px-2 text-[10px] font-semibold text-[var(--terminal-muted-fg)] transition-colors hover:bg-[var(--terminal-panel-bg)] hover:text-[var(--terminal-fg)] disabled:cursor-not-allowed disabled:opacity-50"
                          disabled={actionBusy}
                          onClick={() => handleDiscard(file.path)}
                          title="丢弃未暂存修改"
                        >
                          丢弃
                        </button>
                      </div>
                    );
                  })}
                </div>
              )}

              <div className="mb-2 mt-2 text-[11px] font-semibold text-[var(--terminal-muted-fg)]">
                未跟踪（{untrackedFiles.length}）
              </div>
              {untrackedFiles.length === 0 ? (
                <div className="px-1 pb-2 text-[11px] text-[var(--terminal-muted-fg)]">无</div>
              ) : (
                <div className="space-y-1 pb-2">
                  {untrackedFiles.map((file) => {
                    const active = selected?.category === "untracked" && selected.path === file.path;
                    return (
                      <div
                        key={`untracked:${file.path}`}
                        className={`flex items-center gap-2 rounded-md px-2 py-1 transition-colors ${
                          active ? "bg-[var(--terminal-hover-bg)]" : "hover:bg-[var(--terminal-hover-bg)]"
                        }`}
                      >
                        <button
                          type="button"
                          className="flex min-w-0 flex-1 items-center gap-2 text-left"
                          onClick={() =>
                            onSelect({ category: "untracked", path: file.path, oldPath: file.oldPath ?? null })
                          }
                          title={describeFile(file)}
                        >
                          <span className="w-4 shrink-0 text-[10px] font-semibold text-[var(--terminal-muted-fg)]">
                            {formatGitStatusBadge(file.status)}
                          </span>
                          <span className="min-w-0 truncate text-[11px] text-[var(--terminal-fg)]">
                            {describeFile(file)}
                          </span>
                        </button>
                        <button
                          type="button"
                          className="inline-flex h-6 shrink-0 items-center justify-center rounded-md border border-[var(--terminal-divider)] bg-transparent px-2 text-[10px] font-semibold text-[var(--terminal-muted-fg)] transition-colors hover:bg-[var(--terminal-panel-bg)] hover:text-[var(--terminal-fg)] disabled:cursor-not-allowed disabled:opacity-50"
                          disabled={actionBusy}
                          onClick={() => handleStage(file.path)}
                          title="暂存"
                        >
                          暂存
                        </button>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          ) : null}
        </div>
      </div>
    </aside>
  );
}
