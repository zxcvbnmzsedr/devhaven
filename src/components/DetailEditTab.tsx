import { memo } from "react";

import type { Project } from "../models/types";
import ProjectMarkdownSection from "./ProjectMarkdownSection";

export type DetailEditTabProps = {
  project: Project;
  notes: string;
  onNotesChange: (value: string) => void;
  hasProjectNotes: boolean;
  fallbackReadme: { path: string; content: string } | null;
  fallbackReadmeLoading: boolean;
  fallbackReadmePreview: string;
  onInitFromReadme: () => void;
};

function DetailEditTab({
  project,
  notes,
  onNotesChange,
  hasProjectNotes,
  fallbackReadme,
  fallbackReadmeLoading,
  fallbackReadmePreview,
  onInitFromReadme,
}: DetailEditTabProps) {
  const shouldShowReadmeFallback = !hasProjectNotes && notes.trim().length === 0;

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto p-4">
      <section className="flex flex-col gap-2.5">
        <div className="flex items-center justify-between gap-2">
          <div className="text-[14px] font-semibold">备注</div>
          {shouldShowReadmeFallback && fallbackReadme ? (
            <button type="button" className="btn" onClick={onInitFromReadme}>
              用 README 初始化
            </button>
          ) : null}
        </div>
        <textarea
          className="min-h-[120px] resize-y rounded-md border border-border bg-card-bg px-2 py-2 text-text focus:outline-2 focus:outline-accent focus:outline-offset-[-1px]"
          value={notes}
          onChange={(event) => onNotesChange(event.target.value)}
          placeholder="记录项目备注（保存到 PROJECT_NOTES.md）"
        />
        {shouldShowReadmeFallback ? (
          <div className="flex flex-col gap-2 rounded-md border border-border bg-secondary-background p-2.5">
            <div className="text-fs-caption text-secondary-text">
              {fallbackReadmeLoading
                ? "未发现备注，正在读取 README.md..."
                : fallbackReadme
                  ? `未发现备注，当前展示 ${fallbackReadme.path} 作为只读参考`
                  : "未发现备注，也未找到 README.md"}
            </div>
            {fallbackReadme ? (
              fallbackReadmePreview ? (
                <div className="max-h-[220px] overflow-y-auto rounded-md border border-border bg-card-bg px-3 py-2.5 text-fs-caption leading-relaxed text-text">
                  <div
                    className="markdown-content"
                    dangerouslySetInnerHTML={{
                      __html: fallbackReadmePreview,
                    }}
                  />
                </div>
              ) : (
                <div className="text-fs-caption text-secondary-text">README 内容为空</div>
              )
            ) : null}
          </div>
        ) : null}
      </section>

      <section className="flex flex-col gap-2.5">
        <div className="text-[14px] font-semibold">Markdown</div>
        <ProjectMarkdownSection project={project} />
      </section>
    </div>
  );
}

export default memo(DetailEditTab);
