import type { ReactNode } from "react";
import type { CodexSessionView } from "../models/codex";

export type CodexSessionSectionProps = {
  sessions: CodexSessionView[];
  isLoading: boolean;
  error: string | null;
  onOpenSession: (session: CodexSessionView) => void;
  title?: string;
  emptyText?: string;
  showHeader?: boolean;
  headerStatusText?: string;
  headerRightSlot?: ReactNode;
  variant?: "sidebar" | "monitor";
};

/** 侧栏 Codex CLI 会话区块。 */
export default function CodexSessionSection({
  sessions,
  isLoading,
  error,
  onOpenSession,
  title = "CLI 会话",
  emptyText = "未发现 Codex 会话",
  showHeader = true,
  headerStatusText,
  headerRightSlot,
  variant = "sidebar",
}: CodexSessionSectionProps) {
  const grouped = groupSessionsByProject(sessions);
  const headerStatus =
    headerStatusText ?? (isLoading ? "同步中..." : grouped.length > 0 ? `${grouped.length} 个` : "暂无");
  const shouldShowHeader = showHeader;
  const resolvedEmptyText = emptyText;
  const isMonitor = variant === "monitor";
  const listClassName = isMonitor
    ? "flex flex-col gap-2.5"
    : "flex flex-col gap-1.5 px-2 pb-2";
  const emptyClassName = isMonitor
    ? "text-fs-caption text-sidebar-secondary"
    : "px-4 pb-2 text-fs-caption text-sidebar-secondary";
  const rowClassName = isMonitor
    ? "flex w-full items-start gap-2 rounded-xl border border-[rgba(148,163,184,0.16)] bg-[rgba(15,23,42,0.6)] px-2.5 py-2 text-left text-sidebar-title transition-colors duration-150 hover:border-[rgba(99,102,241,0.35)] hover:bg-[rgba(30,41,59,0.8)] disabled:cursor-not-allowed disabled:opacity-50"
    : "flex w-full items-start gap-2 rounded-lg px-2 py-1.5 text-left text-sidebar-title transition-colors duration-150 hover:bg-sidebar-hover disabled:cursor-not-allowed disabled:opacity-50";

  return (
    <section className={isMonitor ? "" : "pb-3"}>
      {shouldShowHeader ? (
        <div className="section-header">
          <span className="section-title">{title}</span>
          <div className="inline-flex items-center gap-2">
            <span className="text-[11px] text-sidebar-secondary">{headerStatus}</span>
            {headerRightSlot}
          </div>
        </div>
      ) : null}
      {error ? (
        <div className={emptyClassName}>{`会话读取失败：${error}`}</div>
      ) : sessions.length === 0 ? (
        resolvedEmptyText ? (
          <div className={emptyClassName}>{resolvedEmptyText}</div>
        ) : null
      ) : (
        <div className={listClassName}>
          {grouped.map((group) => {
            const session = group.session;
            const projectName = session.projectName ?? "未匹配项目";
            const statusText = resolveStatusText(session.state, group.runningCount);
            const statusClassName = resolveStatusClassName(session.state);
            const disabled = !session.projectId;
            return (
              <button
                key={group.key}
                className={rowClassName}
                type="button"
                onClick={() => onOpenSession(session)}
                disabled={disabled}
                title={disabled ? "无法匹配项目" : session.cwd}
              >
                <div className="flex min-w-0 flex-1 flex-col gap-0.5">
                  <div className="flex min-w-0 items-center gap-1.5 text-fs-caption">
                    <span
                      className={`h-2 w-2 rounded-full ${resolveDotClassName(session.state)}`}
                      aria-hidden="true"
                    />
                    <span className="min-w-0 flex-1 truncate font-semibold">{projectName}</span>
                    <span className={`text-[11px] ${statusClassName}`}>{statusText}</span>
                  </div>
                  <div className="truncate text-[11px] text-sidebar-secondary" title={session.cwd}>
                    {session.cwd || "未知路径"}
                  </div>
                  {session.details ? (
                    <div className="truncate text-[11px] text-sidebar-secondary" title={session.details}>
                      {session.details}
                    </div>
                  ) : null}
                </div>
                <div className="mt-0.5 whitespace-nowrap text-[11px] text-sidebar-secondary">
                  {formatTime(group.lastActivityAt)}
                </div>
              </button>
            );
          })}
        </div>
      )}
    </section>
  );
}

type CodexSessionGroup = {
  key: string;
  session: CodexSessionView;
  runningCount: number;
  lastActivityAt: number;
};

function groupSessionsByProject(sessions: CodexSessionView[]): CodexSessionGroup[] {
  const map = new Map<string, CodexSessionGroup>();

  for (const session of sessions) {
    const key = session.projectId ?? session.cwd ?? session.id;
    const existing = map.get(key);
    if (!existing) {
      map.set(key, {
        key,
        session,
        runningCount: session.isRunning ? 1 : 0,
        lastActivityAt: session.lastActivityAt ?? 0,
      });
      continue;
    }
    if (session.isRunning) {
      existing.runningCount += 1;
    }
    const activity = session.lastActivityAt ?? 0;
    if (activity > existing.lastActivityAt) {
      existing.lastActivityAt = activity;
      existing.session = session;
    }
  }

  return Array.from(map.values()).sort((a, b) => b.lastActivityAt - a.lastActivityAt);
}

function resolveStatusText(state: CodexSessionView["state"], runningCount: number) {
  if (state === "working") {
    return runningCount > 1 ? `运行中 (${runningCount})` : "运行中";
  }
  if (state === "needs-attention") {
    return "待处理";
  }
  if (state === "error") {
    return "异常";
  }
  if (state === "completed") {
    return "已完成";
  }
  if (state === "offline") {
    return "离线";
  }
  return "空闲";
}

function resolveStatusClassName(state: CodexSessionView["state"]) {
  if (state === "working") {
    return "text-success";
  }
  if (state === "needs-attention") {
    return "text-accent";
  }
  if (state === "error") {
    return "text-warning";
  }
  return "text-sidebar-secondary";
}

function resolveDotClassName(state: CodexSessionView["state"]) {
  if (state === "working") {
    return "bg-success";
  }
  if (state === "needs-attention") {
    return "bg-accent";
  }
  if (state === "error") {
    return "bg-warning";
  }
  return "bg-sidebar-secondary";
}

function formatTime(timestamp: number) {
  if (!timestamp) {
    return "--";
  }
  return new Date(timestamp).toLocaleTimeString("zh-CN", {
    hour: "2-digit",
    minute: "2-digit",
  });
}
