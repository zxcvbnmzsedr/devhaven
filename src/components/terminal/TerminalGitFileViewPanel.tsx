import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import type { GitDiffContents } from "../../models/gitManagement";
import { gitGetDiffContents } from "../../services/gitManagement";
import { copyToClipboard } from "../../services/system";
import { detectLanguage } from "../../utils/detectLanguage";
import { IconCopy, IconX } from "../Icons";
import TerminalFilePreviewPanel from "./TerminalFilePreviewPanel";
import type { GitSelectedFile } from "./TerminalGitPanel";
import TerminalMonacoDiffViewer from "./TerminalMonacoDiffViewer";

type ViewMode = "file" | "diff";

function getFileName(relativePath: string): string {
  const normalized = relativePath.replace(/\\/g, "/");
  const parts = normalized.split("/");
  return parts[parts.length - 1] || normalized;
}

function ViewModeSwitch({
  mode,
  onChange,
}: {
  mode: ViewMode;
  onChange: (next: ViewMode) => void;
}) {
  return (
    <div className="inline-flex overflow-hidden rounded-md border border-[var(--terminal-divider)] bg-[var(--terminal-bg)]">
      <button
        type="button"
        className={`px-2 py-1 text-[11px] font-semibold transition-colors ${
          mode === "file"
            ? "bg-[var(--terminal-hover-bg)] text-[var(--terminal-fg)]"
            : "text-[var(--terminal-muted-fg)] hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)]"
        }`}
        onClick={() => onChange("file")}
      >
        文件
      </button>
      <button
        type="button"
        className={`px-2 py-1 text-[11px] font-semibold transition-colors ${
          mode === "diff"
            ? "bg-[var(--terminal-hover-bg)] text-[var(--terminal-fg)]"
            : "text-[var(--terminal-muted-fg)] hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)]"
        }`}
        onClick={() => onChange("diff")}
      >
        对比
      </button>
    </div>
  );
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

export type TerminalGitFileViewPanelProps = {
  projectPath: string;
  selected: GitSelectedFile | null;
  onCloseSelected: () => void;
};

export default function TerminalGitFileViewPanel({
  projectPath,
  selected,
  onCloseSelected,
}: TerminalGitFileViewPanelProps) {
  const [viewMode, setViewMode] = useState<ViewMode>("diff");
  const lastPathRef = useRef<string | null>(null);
  const [fileDirty, setFileDirty] = useState(false);

  const [diffContents, setDiffContents] = useState<GitDiffContents | null>(null);
  const [diffLoading, setDiffLoading] = useState(false);
  const [diffError, setDiffError] = useState<string | null>(null);
  const requestIdRef = useRef(0);

  const relativePath = selected?.path ?? null;
  const fileName = useMemo(() => (relativePath ? getFileName(relativePath) : ""), [relativePath]);

  useEffect(() => {
    const nextPath = selected?.path ?? null;
    if (nextPath && lastPathRef.current !== nextPath) {
      setViewMode("diff");
      setFileDirty(false);
    }
    lastPathRef.current = nextPath;
  }, [selected?.path]);

  const switcher = useMemo(() => {
    return <ViewModeSwitch mode={viewMode} onChange={setViewMode} />;
  }, [viewMode]);

  useEffect(() => {
    if (!selected) {
      setDiffContents(null);
      setDiffLoading(false);
      setDiffError(null);
      return;
    }
    if (viewMode !== "diff") {
      // Reload on next time user switches to diff to reflect any edits.
      return;
    }

    const requestId = requestIdRef.current + 1;
    requestIdRef.current = requestId;
    setDiffLoading(true);
    setDiffError(null);
    setDiffContents(null);

    const staged = selected.category === "staged";
    const oldRelativePath = selected.oldPath ?? null;

    gitGetDiffContents(projectPath, selected.path, staged, oldRelativePath)
      .then((contents) => {
        if (requestIdRef.current !== requestId) {
          return;
        }
        setDiffContents(contents);
      })
      .catch((err) => {
        if (requestIdRef.current !== requestId) {
          return;
        }
        setDiffError(formatGitError(err));
      })
      .finally(() => {
        if (requestIdRef.current === requestId) {
          setDiffLoading(false);
        }
      });
  }, [projectPath, selected, viewMode]);

  const handleSwitchToDiff = useCallback(() => {
    setViewMode("diff");
  }, []);

  const handleSwitchToFile = useCallback(() => {
    setViewMode("file");
  }, []);

  if (!selected) {
    return (
      <div className="flex min-h-0 flex-1 items-center justify-center bg-[var(--terminal-bg)] text-[12px] text-[var(--terminal-muted-fg)]">
        选择文件以查看对比/编辑
      </div>
    );
  }

  return (
    <div className="relative min-h-0 flex-1 overflow-hidden">
      <div
        className={`absolute inset-0 flex min-h-0 min-w-0 ${
          viewMode === "file" ? "opacity-100" : "opacity-0 pointer-events-none"
        }`}
      >
        <TerminalFilePreviewPanel
          embedded
          projectPath={projectPath}
          relativePath={selected.path}
          onClose={onCloseSelected}
          onDirtyChange={setFileDirty}
          headerAddon={
            <ViewModeSwitch
              mode={viewMode}
              onChange={(next) => (next === "diff" ? handleSwitchToDiff() : handleSwitchToFile())}
            />
          }
        />
      </div>

      <div
        className={`absolute inset-0 flex min-h-0 min-w-0 ${
          viewMode === "diff" ? "opacity-100" : "opacity-0 pointer-events-none"
        }`}
      >
        <aside className="flex min-h-0 min-w-0 flex-1 flex-col bg-[var(--terminal-panel-bg)]">
          <div className="flex items-center justify-between gap-2 border-b border-[var(--terminal-divider)] px-3 py-2">
            <div
              className="min-w-0 truncate text-[11px] font-semibold text-[var(--terminal-muted-fg)]"
              title={relativePath ?? ""}
            >
              {fileName}
              {fileDirty ? <span className="ml-2 text-[10px] text-[var(--terminal-accent)]">未保存</span> : null}
            </div>
            <div className="flex shrink-0 items-center gap-1">
              {switcher}
              <button
                type="button"
                className="inline-flex h-6 w-6 items-center justify-center rounded-md text-[var(--terminal-muted-fg)] transition-colors hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--terminal-accent-outline)] focus-visible:outline-offset-2"
                aria-label="复制相对路径"
                title="复制相对路径"
                onClick={() => copyToClipboard(relativePath ?? "")}
              >
                <IconCopy size={14} />
              </button>
              <button
                type="button"
                className="inline-flex h-6 w-6 items-center justify-center rounded-md text-[var(--terminal-muted-fg)] transition-colors hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--terminal-accent-outline)] focus-visible:outline-offset-2"
                aria-label="关闭对比"
                title="关闭"
                onClick={() => {
                  if (fileDirty && !window.confirm("当前文件有未保存修改，确定关闭？")) {
                    return;
                  }
                  onCloseSelected();
                }}
              >
                <IconX size={14} />
              </button>
            </div>
          </div>

          <div className="min-h-0 flex-1 overflow-hidden bg-[var(--terminal-bg)]">
            {diffLoading ? (
              <div className="px-3 py-2 text-[11px] text-[var(--terminal-muted-fg)]">正在加载对比...</div>
            ) : diffError ? (
              <div className="px-3 py-2 text-[11px] text-[var(--terminal-muted-fg)]">
                <div className="whitespace-pre-wrap">对比加载失败：{diffError}</div>
              </div>
            ) : diffContents ? (
              <div className="flex h-full flex-col">
                {diffContents.originalTruncated || diffContents.modifiedTruncated ? (
                  <div className="border-b border-[var(--terminal-divider)] px-3 py-2 text-[10px] text-[var(--terminal-muted-fg)]">
                    文件内容过长，已截断展示（对比结果可能不完整）。
                  </div>
                ) : null}
                <div className="min-h-0 flex-1">
                  <TerminalMonacoDiffViewer
                    original={diffContents.original}
                    modified={diffContents.modified}
                    language={detectLanguage(selected.path)}
                  />
                </div>
              </div>
            ) : (
              <div className="px-3 py-2 text-[11px] text-[var(--terminal-muted-fg)]">无对比内容</div>
            )}
          </div>
        </aside>
      </div>
    </div>
  );
}
