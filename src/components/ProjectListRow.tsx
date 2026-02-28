import { memo, useCallback, useMemo } from "react";

import type { Project } from "../models/types";
import { swiftDateToJsDate } from "../models/types";
import { openInFinder } from "../services/system";
import { formatPathWithTilde } from "../utils/pathDisplay";
import DropdownMenu from "./DropdownMenu";
import { IconCode, IconCopy, IconFolder, IconRefresh, IconStar, IconTrash } from "./Icons";

export type ProjectListRowProps = {
  project: Project;
  isSelected: boolean;
  isFavorite: boolean;
  resolveDragProjectIds: (projectId: string) => string[];
  notePreview: string;
  onSelectProject: (project: Project, event: React.MouseEvent<HTMLDivElement>) => void;
  onOpenTerminal: (project: Project) => void;
  onRunProjectScript: (projectId: string, scriptId: string) => Promise<void>;
  onRefreshProject: (path: string) => void;
  onCopyPath: (path: string) => void;
  onMoveToRecycleBin: (project: Project) => void;
  onToggleFavorite: (path: string) => void;
};

const formatDateTime = (swiftDate: number) => {
  if (!swiftDate) {
    return "--";
  }
  return swiftDateToJsDate(swiftDate).toLocaleString("zh-CN");
};

const resolveLastCommitSummary = (project: Project) => {
  if ((project.git_commits ?? 0) <= 0) {
    return "非 Git 项目";
  }
  const message = (project.git_last_commit_message ?? "").trim();
  return message || "暂无提交摘要";
};

function ProjectListRow({
  project,
  isSelected,
  isFavorite,
  resolveDragProjectIds,
  notePreview,
  onSelectProject,
  onOpenTerminal,
  onRunProjectScript,
  onRefreshProject,
  onCopyPath,
  onMoveToRecycleBin,
  onToggleFavorite,
}: ProjectListRowProps) {
  const displayPath = formatPathWithTilde(project.path);
  const lastCommitSummary = resolveLastCommitSummary(project);
  const scripts = project.scripts ?? [];
  const scriptMenuItems = useMemo(
    () =>
      scripts.length
        ? scripts.map((script) => ({
            key: script.id,
            label: `运行：${script.name}`,
            onClick: () => {
              void onRunProjectScript(project.id, script.id);
            },
          }))
        : [{ key: "empty", label: "暂无快捷命令", disabled: true }],
    [scripts, onRunProjectScript, project.id],
  );

  const handleDragStart = useCallback(
    (event: React.DragEvent<HTMLDivElement>) => {
      const ids = resolveDragProjectIds(project.id);
      event.dataTransfer.setData("application/x-project-ids", JSON.stringify(ids));
      event.dataTransfer.effectAllowed = "copy";
    },
    [project.id, resolveDragProjectIds],
  );
  const handleSelect = useCallback(
    (event: React.MouseEvent<HTMLDivElement>) => {
      onSelectProject(project, event);
    },
    [onSelectProject, project],
  );

  const handleActionClick = useCallback((event: React.MouseEvent, action: () => void) => {
    event.stopPropagation();
    action();
  }, []);

  return (
    <div
      className={`group grid cursor-pointer grid-cols-[minmax(220px,2.2fr)_170px_minmax(180px,2fr)_180px] items-center gap-3 border-b border-divider px-3 py-2.5 text-[13px] transition-colors duration-150 last:border-b-0 ${
        isSelected ? "bg-card-selected-bg" : "hover:bg-card-hover"
      }`}
      onClick={handleSelect}
      onDoubleClick={() => onOpenTerminal(project)}
      draggable
      onDragStart={handleDragStart}
      role="row"
      aria-selected={isSelected}
    >
      <div className="min-w-0">
        <div className="truncate font-semibold text-text" title={project.name}>
          {project.name}
        </div>
        <div className="truncate text-fs-caption text-secondary-text" title={project.path}>
          {displayPath}
        </div>
      </div>
      <div className="truncate text-secondary-text" title={formatDateTime(project.mtime)}>
        {formatDateTime(project.mtime)}
      </div>
      <div className="min-w-0">
        <div className="truncate text-secondary-text" title={lastCommitSummary}>
          {lastCommitSummary}
        </div>
        <div className="truncate text-[11px] text-secondary-text" title={notePreview}>
          备注：{notePreview}
        </div>
      </div>
      <div className="inline-flex items-center gap-1">
        <DropdownMenu label={<IconCode size={16} />} ariaLabel="运行快捷命令" items={scriptMenuItems} />
        <button
          className={`icon-btn ${isFavorite ? "text-amber-500" : "text-titlebar-icon"}`}
          aria-label={isFavorite ? "取消收藏" : "收藏项目"}
          title={isFavorite ? "取消收藏" : "收藏项目"}
          onClick={(event) => handleActionClick(event, () => void onToggleFavorite(project.path))}
        >
          <IconStar size={16} fill={isFavorite ? "currentColor" : "none"} />
        </button>
        <button
          className="icon-btn text-titlebar-icon"
          aria-label="在 Finder 中显示"
          title="在 Finder 中显示"
          onClick={(event) => handleActionClick(event, () => void openInFinder(project.path))}
        >
          <IconFolder size={16} />
        </button>
        <button
          className="icon-btn text-titlebar-icon"
          aria-label="复制路径"
          title="复制路径"
          onClick={(event) => handleActionClick(event, () => void onCopyPath(project.path))}
        >
          <IconCopy size={16} />
        </button>
        <button
          className="icon-btn text-titlebar-icon"
          aria-label="刷新项目"
          title="刷新项目"
          onClick={(event) => handleActionClick(event, () => void onRefreshProject(project.path))}
        >
          <IconRefresh size={16} />
        </button>
        <button
          className="icon-btn text-titlebar-icon"
          aria-label="移入回收站"
          title="移入回收站"
          onClick={(event) => handleActionClick(event, () => void onMoveToRecycleBin(project))}
        >
          <IconTrash size={16} />
        </button>
      </div>
    </div>
  );
}

export default memo(ProjectListRow);
