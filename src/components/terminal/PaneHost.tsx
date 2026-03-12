import type { ReactNode } from "react";
import type { ITheme } from "xterm";

import TerminalPane from "./TerminalPane";
import TerminalFilePreviewPanel from "./TerminalFilePreviewPanel";
import TerminalGitFileViewPanel from "./TerminalGitFileViewPanel";
import type { GitSelectedFile } from "./TerminalGitPanel";

type TerminalSessionPaneHostProps = {
  kind: "terminal" | "run";
  className?: string;
  sessionId: string;
  cwd: string;
  savedState?: string | null;
  windowLabel: string;
  clientId: string;
  useWebgl: boolean;
  theme: ITheme;
  isActive: boolean;
  onActivate: (sessionId: string) => void;
  onExit: (sessionId: string, code?: number | null) => void;
  onPtyReady?: (sessionId: string, ptyId: string) => void;
  preserveSessionOnUnmount?: boolean;
};

type FilePreviewPaneHostProps = {
  kind: "filePreview";
  className?: string;
  projectPath: string;
  relativePath: string | null;
  onClose: () => void;
  onDirtyChange?: (dirty: boolean) => void;
  emptyMessage?: string;
};

type GitDiffPaneHostProps = {
  kind: "gitDiff";
  className?: string;
  projectPath: string;
  selected: GitSelectedFile | null;
  onCloseSelected: () => void;
  emptyMessage?: string;
};

type ToolPaneHostProps = {
  kind: "tool" | "overlay";
  className?: string;
  active?: boolean;
  emptyMessage?: string;
  children?: ReactNode;
};

export type PaneHostProps =
  | TerminalSessionPaneHostProps
  | FilePreviewPaneHostProps
  | GitDiffPaneHostProps
  | ToolPaneHostProps;

function renderEmptyState(message: string) {
  return (
    <div className="flex min-h-0 flex-1 items-center justify-center bg-[var(--terminal-bg)] text-[12px] text-[var(--terminal-muted-fg)]">
      {message}
    </div>
  );
}

export default function PaneHost(props: PaneHostProps) {
  if (props.kind === "terminal" || props.kind === "run") {
    const { className, ...terminalProps } = props;
    return (
      <div className={className ?? "flex h-full w-full min-h-0 min-w-0 flex-1"}>
        <TerminalPane {...terminalProps} />
      </div>
    );
  }

  if (props.kind === "filePreview") {
    const { className, projectPath, relativePath, onClose, onDirtyChange, emptyMessage } = props;
    return (
      <div className={className ?? "flex min-h-0 min-w-0 flex-1 flex-col"}>
        {relativePath ? (
          <TerminalFilePreviewPanel
            embedded
            projectPath={projectPath}
            relativePath={relativePath}
            onClose={onClose}
            onDirtyChange={onDirtyChange}
          />
        ) : emptyMessage ? (
          renderEmptyState(emptyMessage)
        ) : null}
      </div>
    );
  }

  if (props.kind === "gitDiff") {
    const { className, projectPath, selected, onCloseSelected, emptyMessage } = props;
    return (
      <div className={className ?? "flex min-h-0 min-w-0 flex-1 flex-col"}>
        {selected || !emptyMessage ? (
          <TerminalGitFileViewPanel
            projectPath={projectPath}
            selected={selected}
            onCloseSelected={onCloseSelected}
          />
        ) : (
          renderEmptyState(emptyMessage)
        )}
      </div>
    );
  }

  const { className, active = true, emptyMessage, children } = props as ToolPaneHostProps;
  const hasChildren = children !== undefined && children !== null;
  return (
    <div
      className={`${className ?? "flex min-h-0 min-w-0 flex-1 flex-col"} ${
        active ? "opacity-100" : "pointer-events-none opacity-0"
      }`}
    >
      {hasChildren || emptyMessage ? (
        children ?? renderEmptyState(emptyMessage ?? "")
      ) : null}
    </div>
  );
}
