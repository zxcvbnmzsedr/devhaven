import { memo } from "react";

import type { Project, ProjectScript } from "../models/types";
import type { BranchListItem } from "../models/branch";

export type DetailAutomationTabProps = {
  project: Project;
  scripts: ProjectScript[];
  onRunScript: (scriptId: string) => void;
  onStopScript: (scriptId: string) => void;
  onNewScript: () => void;
  onEditScript: (script: ProjectScript) => void;
  onRemoveScript: (scriptId: string) => void;
  branches: BranchListItem[];
  worktreeError: string | null;
  onRefreshBranches: () => void;
};

function DetailAutomationTab({
  scripts,
  onRunScript,
  onStopScript,
  onNewScript,
  onEditScript,
  onRemoveScript,
  branches,
  worktreeError,
  onRefreshBranches,
}: DetailAutomationTabProps) {
  return (
    <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto p-4">
      <section className="flex flex-col gap-2.5">
        <div className="flex items-center justify-between gap-2">
          <div className="text-[14px] font-semibold">快捷命令</div>
          <button className="btn" onClick={onNewScript}>
            新增
          </button>
        </div>
        {scripts.length === 0 ? (
          <div className="text-fs-caption text-secondary-text">暂无快捷命令</div>
        ) : (
          <div className="flex flex-col gap-2">
            {scripts.map((script) => (
              <div
                key={script.id}
                className="flex items-center justify-between gap-3 rounded-lg border border-border bg-card-bg p-3"
                title={script.start}
              >
                <div className="min-w-0 flex-1">
                  <div className="truncate text-[13px] font-semibold text-text">{script.name}</div>
                  <div className="truncate text-fs-caption text-secondary-text">{script.start}</div>
                </div>
                <div className="flex shrink-0 flex-wrap items-center justify-end gap-2">
                  <button className="btn btn-primary" onClick={() => onRunScript(script.id)}>
                    运行
                  </button>
                  <button className="btn btn-outline" onClick={() => onStopScript(script.id)}>
                    停止
                  </button>
                  <button className="btn" onClick={() => onEditScript(script)}>
                    编辑
                  </button>
                  <button className="btn" onClick={() => onRemoveScript(script.id)}>
                    删除
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      <section className="flex flex-col gap-2.5">
        <div className="text-[14px] font-semibold">分支管理</div>
        <div className="flex flex-wrap gap-2">
          <button className="btn" onClick={onRefreshBranches}>
            刷新
          </button>
        </div>
        {worktreeError ? <div className="text-fs-caption text-error">{worktreeError}</div> : null}
        {branches.length === 0 ? (
          <div className="text-fs-caption text-secondary-text">暂无分支信息或非 Git 项目</div>
        ) : (
          <div className="flex flex-col gap-2.5">
            {branches.map((branch) => (
              <div key={branch.name} className="flex items-center justify-between gap-3 rounded-lg border border-border bg-card-bg p-3">
                <div>
                  <div className="text-[14px] font-semibold">
                    {branch.name}
                    {branch.isMain ? <span className="ml-1.5 text-[11px] text-accent">主分支</span> : null}
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

export default memo(DetailAutomationTab);
