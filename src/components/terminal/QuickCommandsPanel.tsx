import type { PointerEvent as ReactPointerEvent, RefObject } from "react";

import type { QuickCommandJob } from "../../models/quickCommands";
import type { ProjectScript } from "../../models/types";
import {
  toScriptExecutionStateFromQuickState,
  type ScriptExecutionState,
  type ScriptLocalPhase,
  type ScriptRuntime,
} from "../../hooks/useQuickCommandRuntime";
import { IconX } from "../Icons";

type QuickCommandsPanelProps = {
  scripts: ProjectScript[];
  scriptRuntimeById: Record<string, ScriptRuntime>;
  quickCommandJobByScriptId: Record<string, QuickCommandJob>;
  scriptLocalPhaseById: Record<string, ScriptLocalPhase>;
  panelMessage: string | null;
  panelPosition: { x: number; y: number };
  isScriptRuntimeValid: (runtime: ScriptRuntime) => boolean;
  onRun: (script: ProjectScript) => void;
  onStop: (scriptId: string) => void;
  onClose: () => void;
  onDragStart: (event: ReactPointerEvent<HTMLDivElement>) => void;
  panelRef: RefObject<HTMLDivElement | null>;
};

export default function QuickCommandsPanel({
  scripts,
  scriptRuntimeById,
  quickCommandJobByScriptId,
  scriptLocalPhaseById,
  panelMessage,
  panelPosition,
  isScriptRuntimeValid,
  onRun,
  onStop,
  onClose,
  onDragStart,
  panelRef,
}: QuickCommandsPanelProps) {
  return (
    <div
      ref={panelRef}
      className="absolute z-20 w-[260px] select-none rounded-lg border border-[var(--terminal-divider)] bg-[var(--terminal-panel-bg)] shadow-lg"
      style={{ transform: `translate3d(${panelPosition.x}px, ${panelPosition.y}px, 0)` }}
    >
      <div
        className="flex cursor-move items-center justify-between gap-2 border-b border-[var(--terminal-divider)] px-3 py-2 text-[12px] font-semibold text-[var(--terminal-muted-fg)]"
        onPointerDown={onDragStart}
      >
        <span className="truncate">快捷命令</span>
        <button
          className="inline-flex h-6 w-6 items-center justify-center rounded-md border border-transparent text-[var(--terminal-muted-fg)] hover:border-[var(--terminal-divider)] hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)]"
          type="button"
          title="关闭"
          onClick={(event) => {
            event.preventDefault();
            event.stopPropagation();
            onClose();
          }}
        >
          <IconX size={12} />
        </button>
      </div>
      <div className="max-h-[360px] overflow-y-auto p-2">
        {panelMessage ? (
          <div className="px-2 pb-2 text-[11px] font-semibold text-[var(--terminal-muted-fg)]">{panelMessage}</div>
        ) : null}
        {scripts.length === 0 ? (
          <div className="px-2 py-2 text-[12px] text-[var(--terminal-muted-fg)]">暂无快捷命令，请在项目详情面板中配置</div>
        ) : (
          <div className="flex flex-col gap-1">
            {scripts.map((script) => {
              const runtime = scriptRuntimeById[script.id] ?? null;
              const runtimeValid = runtime ? isScriptRuntimeValid(runtime) : false;
              const quickJob = quickCommandJobByScriptId[script.id] ?? null;
              const localPhase = scriptLocalPhaseById[script.id] ?? null;
              const executionState: ScriptExecutionState = quickJob
                ? toScriptExecutionStateFromQuickState(quickJob.state)
                : localPhase ?? (runtimeValid ? "running" : "idle");
              const isRunning = executionState === "running";
              const isStarting = executionState === "starting";
              const isStoppingSoft = executionState === "stoppingSoft";
              const isStoppingHard = executionState === "stoppingHard";
              const canStop = isRunning || isStarting || isStoppingSoft || isStoppingHard;
              const disableRun = isStarting || isStoppingSoft || isStoppingHard;
              const statusText = isStoppingHard
                ? "强制停止中"
                : isStoppingSoft
                  ? "停止中"
                  : isStarting
                    ? "启动中"
                    : isRunning
                      ? "运行中"
                      : null;
              return (
                <div
                  key={script.id}
                  className="flex items-center justify-between gap-2 rounded-md border border-[var(--terminal-divider)] bg-[var(--terminal-bg)] px-2.5 py-2"
                  title={script.start}
                >
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-[12px] font-semibold text-[var(--terminal-fg)]">{script.name}</div>
                    <div className="truncate text-[11px] text-[var(--terminal-muted-fg)]">{script.start}</div>
                  </div>
                  <div className="flex shrink-0 items-center gap-1.5">
                    {statusText ? (
                      <span className="inline-flex items-center gap-1 text-[10px] font-semibold text-[var(--terminal-muted-fg)]">
                        <span
                          className={`h-2 w-2 rounded-full ${
                            isStoppingHard ? "bg-[rgba(239,68,68,0.9)]" : "bg-[var(--terminal-accent)]"
                          }`}
                          aria-hidden="true"
                        />
                        <span className="whitespace-nowrap">{statusText}</span>
                      </span>
                    ) : null}
                    <button
                      className="inline-flex h-7 items-center justify-center rounded-md border border-[var(--terminal-divider)] bg-[var(--terminal-hover-bg)] px-2 text-[11px] font-semibold text-[var(--terminal-muted-fg)] transition-colors duration-150 hover:text-[var(--terminal-fg)]"
                      type="button"
                      disabled={disableRun}
                      onClick={() => onRun(script)}
                    >
                      {isStarting ? "启动中" : "运行"}
                    </button>
                    <button
                      className="inline-flex h-7 items-center justify-center rounded-md border border-[var(--terminal-divider)] bg-transparent px-2 text-[11px] font-semibold text-[var(--terminal-muted-fg)] transition-colors duration-150 hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)] disabled:cursor-not-allowed disabled:opacity-50"
                      type="button"
                      disabled={!canStop}
                      onClick={() => onStop(script.id)}
                    >
                      {isStoppingSoft || isStoppingHard ? "停止中" : "停止"}
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
