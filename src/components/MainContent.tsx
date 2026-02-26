import { useEffect, useMemo, useRef, useState } from "react";

import type { Project, ProjectListViewMode } from "../models/types";
import type { DateFilter, GitFilter } from "../models/filters";
import { DATE_FILTER_OPTIONS, GIT_FILTER_OPTIONS } from "../models/filters";
import { readProjectNotesPreviews } from "../services/notes";
import DropdownMenu from "./DropdownMenu";
import ProjectCard from "./ProjectCard";
import ProjectListRow from "./ProjectListRow";
import SearchBar from "./SearchBar";
import {
  IconCalendar,
  IconChartLine,
  IconCode,
  IconList,
  IconSearch,
  IconSettings,
  IconSidebarRight,
  IconSquares,
} from "./Icons";

export type MainContentProps = {
  projects: Project[];
  filteredProjects: Project[];
  favoriteProjectPaths: Set<string>;
  recycleBinCount: number;
  isLoading: boolean;
  error: string | null;
  searchText: string;
  onSearchTextChange: (value: string) => void;
  dateFilter: DateFilter;
  onDateFilterChange: (value: DateFilter) => void;
  gitFilter: GitFilter;
  onGitFilterChange: (value: GitFilter) => void;
  viewMode: ProjectListViewMode;
  onViewModeChange: (value: ProjectListViewMode) => void;
  showDetailPanel: boolean;
  onToggleDetailPanel: () => void;
  onOpenDashboard: () => void;
  onOpenSettings: () => void;
  onOpenGlobalSkills: () => void;
  availableTags: string[];
  selectedProjects: Set<string>;
  onSelectProject: (project: Project, event: React.MouseEvent<HTMLDivElement>) => void;
  onClearSelectedProjects: () => void;
  onBulkCopyProjectPaths: (projectIds: string[]) => Promise<void>;
  onBulkRefreshProjects: (projectIds: string[]) => Promise<void>;
  onBulkMoveToRecycleBin: (projectIds: string[]) => Promise<void>;
  onBulkAssignTagToProjects: (tag: string, projectIds: string[]) => Promise<void>;
  onTagSelected: (tag: string) => void;
  onRemoveTagFromProject: (projectId: string, tag: string) => void;
  onRefreshProject: (path: string) => void;
  onCopyPath: (path: string) => void;
  onOpenTerminal: (project: Project) => void;
  onRunProjectScript: (projectId: string, scriptId: string) => Promise<void>;
  onMoveToRecycleBin: (project: Project) => void;
  onToggleFavorite: (path: string) => void;
  getTagColor: (tag: string) => string;
  searchInputRef: React.RefObject<HTMLInputElement | null>;
};

/** 主内容区，负责搜索过滤与项目列表展示。 */
export default function MainContent({
  projects,
  filteredProjects,
  favoriteProjectPaths,
  recycleBinCount,
  isLoading,
  error,
  searchText,
  onSearchTextChange,
  dateFilter,
  onDateFilterChange,
  gitFilter,
  onGitFilterChange,
  viewMode,
  onViewModeChange,
  showDetailPanel,
  onToggleDetailPanel,
  onOpenDashboard,
  onOpenSettings,
  onOpenGlobalSkills,
  availableTags,
  selectedProjects,
  onSelectProject,
  onClearSelectedProjects,
  onBulkCopyProjectPaths,
  onBulkRefreshProjects,
  onBulkMoveToRecycleBin,
  onBulkAssignTagToProjects,
  onTagSelected,
  onRemoveTagFromProject,
  onRefreshProject,
  onCopyPath,
  onOpenTerminal,
  onRunProjectScript,
  onMoveToRecycleBin,
  onToggleFavorite,
  getTagColor,
  searchInputRef,
}: MainContentProps) {
  const [notePreviewByPath, setNotePreviewByPath] = useState<Record<string, string>>({});
  const [isNotesPreviewLoading, setIsNotesPreviewLoading] = useState(false);
  const previewRequestIdRef = useRef(0);
  const selectedProjectIds = useMemo(() => Array.from(selectedProjects), [selectedProjects]);
  const bulkTagMenuItems = useMemo(
    () =>
      availableTags.length
        ? availableTags.map((tag) => ({
            key: `bulk-tag-${tag}`,
            label: `添加标签：${tag}`,
            onClick: () => {
              void onBulkAssignTagToProjects(tag, selectedProjectIds);
            },
          }))
        : [{ key: "bulk-tag-empty", label: "暂无可用标签", disabled: true }],
    [availableTags, onBulkAssignTagToProjects, selectedProjectIds],
  );
  const listProjectPaths = useMemo(() => filteredProjects.map((project) => project.path), [filteredProjects]);
  const listProjectPathsKey = useMemo(() => listProjectPaths.join("\n"), [listProjectPaths]);

  useEffect(() => {
    if (viewMode !== "list") {
      return;
    }
    if (listProjectPaths.length === 0) {
      setNotePreviewByPath({});
      setIsNotesPreviewLoading(false);
      return;
    }

    const requestId = previewRequestIdRef.current + 1;
    previewRequestIdRef.current = requestId;
    setIsNotesPreviewLoading(true);

    void readProjectNotesPreviews(listProjectPaths)
      .then((entries) => {
        if (previewRequestIdRef.current !== requestId) {
          return;
        }
        const previews = Object.fromEntries(
          listProjectPaths.map((path) => [path, "—"]),
        ) as Record<string, string>;

        for (const entry of entries) {
          const value = (entry.notesPreview ?? "").trim();
          previews[entry.path] = value || "—";
        }

        setNotePreviewByPath(previews);
      })
      .catch(() => {
        if (previewRequestIdRef.current !== requestId) {
          return;
        }
        setNotePreviewByPath(
          Object.fromEntries(listProjectPaths.map((path) => [path, "—"])) as Record<string, string>,
        );
      })
      .finally(() => {
        if (previewRequestIdRef.current === requestId) {
          setIsNotesPreviewLoading(false);
        }
      });
  }, [listProjectPaths, listProjectPathsKey, viewMode]);

  return (
    <section className="flex min-h-0 min-w-0 flex-col bg-background">
      <div className="flex h-search-area-h items-center gap-3 border-b border-search-area-border bg-search-area-bg p-2">
        <button className="icon-btn" aria-label="仪表盘" onClick={onOpenDashboard}>
          <IconChartLine size={18} />
        </button>
        <button
          className={`icon-btn ${showDetailPanel ? "text-accent" : ""}`}
          aria-label="详情面板"
          onClick={onToggleDetailPanel}
        >
          <IconSidebarRight size={18} />
        </button>
        <button className="icon-btn" aria-label="设置" onClick={onOpenSettings}>
          <IconSettings size={18} />
        </button>
        <button className="icon-btn" aria-label="全局 Skills" onClick={onOpenGlobalSkills} title="全局 Skills">
          <IconCode size={18} />
        </button>
        <SearchBar value={searchText} onChange={onSearchTextChange} ref={searchInputRef} />
        <label className="inline-flex items-center gap-1.5 rounded-md border border-search-border bg-search-bg px-2 py-1 text-[12px] font-semibold text-titlebar-icon">
          <IconCalendar size={14} />
          <select
            className="border-none bg-transparent text-[12px] font-semibold text-inherit outline-none"
            value={dateFilter}
            onChange={(event) => onDateFilterChange(event.target.value as DateFilter)}
          >
            {DATE_FILTER_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.title}
              </option>
            ))}
          </select>
        </label>
        <div className="inline-flex items-center gap-1 rounded-lg border border-search-border bg-search-bg p-0.5">
          {GIT_FILTER_OPTIONS.map((option) => (
            <button
              key={option.value}
              className={`rounded-md px-2.5 py-1 text-[12px] font-semibold transition-colors duration-150 ${
                gitFilter === option.value
                  ? "bg-accent text-white"
                  : "text-secondary-text hover:bg-button-hover hover:text-text"
              }`}
              onClick={() => onGitFilterChange(option.value)}
            >
              {option.title}
            </button>
          ))}
        </div>
        <div className="inline-flex items-center gap-1 rounded-lg border border-search-border bg-search-bg p-0.5">
          <button
            className={`inline-flex items-center gap-1 rounded-md px-2 py-1 text-[12px] font-semibold transition-colors duration-150 ${
              viewMode === "card"
                ? "bg-accent text-white"
                : "text-secondary-text hover:bg-button-hover hover:text-text"
            }`}
            onClick={() => onViewModeChange("card")}
            aria-label="卡片模式"
            title="卡片模式"
          >
            <IconSquares size={13} />
            卡片
          </button>
          <button
            className={`inline-flex items-center gap-1 rounded-md px-2 py-1 text-[12px] font-semibold transition-colors duration-150 ${
              viewMode === "list"
                ? "bg-accent text-white"
                : "text-secondary-text hover:bg-button-hover hover:text-text"
            }`}
            onClick={() => onViewModeChange("list")}
            aria-label="列表模式"
            title="列表模式"
          >
            <IconList size={13} />
            列表
          </button>
        </div>
      </div>
      {selectedProjectIds.length > 0 ? (
        <div className="flex flex-wrap items-center gap-2 border-b border-search-area-border bg-[rgba(69,59,231,0.08)] px-3 py-2">
          <span className="text-[12px] font-semibold text-accent">已选 {selectedProjectIds.length} 个项目</span>
          <button className="btn btn-outline !px-2.5 !py-1 text-[12px]" onClick={() => void onBulkCopyProjectPaths(selectedProjectIds)}>
            复制路径
          </button>
          <button className="btn btn-outline !px-2.5 !py-1 text-[12px]" onClick={() => void onBulkRefreshProjects(selectedProjectIds)}>
            批量刷新
          </button>
          <button className="btn btn-outline !px-2.5 !py-1 text-[12px]" onClick={() => void onBulkMoveToRecycleBin(selectedProjectIds)}>
            移入回收站
          </button>
          <DropdownMenu
            label={<span className="text-[12px] font-semibold">批量打标签</span>}
            items={bulkTagMenuItems}
            ariaLabel="批量打标签"
            align="left"
          />
          <button className="btn btn-outline !px-2.5 !py-1 text-[12px]" onClick={onClearSelectedProjects}>
            清除选择
          </button>
        </div>
      ) : null}

      <div className="flex min-h-0 flex-1 flex-col overflow-y-auto">
        {isLoading ? (
          <div className="flex flex-1 flex-col items-center justify-center gap-3 text-secondary-text">
            正在加载项目数据...
          </div>
        ) : error ? (
          <div className="flex flex-1 flex-col items-center justify-center gap-3 text-secondary-text">{error}</div>
        ) : projects.length === 0 ? (
          <div className="flex flex-1 flex-col items-center justify-center gap-3 text-secondary-text">
            {recycleBinCount > 0 ? (
              <>
                <div>当前没有可见项目</div>
                <div>可在左侧回收站恢复隐藏项目</div>
              </>
            ) : (
              <>
                <div>暂未添加项目目录</div>
                <div>请在左侧添加工作目录或直接导入项目</div>
              </>
            )}
          </div>
        ) : filteredProjects.length === 0 ? (
          <div className="flex flex-1 flex-col items-center justify-center gap-3 text-secondary-text">
            <IconSearch className="text-secondary-text" size={36} />
            <div>没有匹配的项目</div>
            <div>尝试修改搜索条件或清除标签筛选</div>
          </div>
        ) : viewMode === "list" ? (
          <div className="flex flex-col gap-3 p-4">
            <div className="grid grid-cols-[minmax(220px,2.2fr)_170px_minmax(180px,2fr)_116px] items-center gap-3 px-3 text-fs-caption font-semibold text-secondary-text">
              <div>项目</div>
              <div>更新时间</div>
              <div>最近提交 / 备注</div>
              <div className="text-right">操作</div>
            </div>
            <div className="overflow-hidden rounded-xl border border-card-border bg-card-bg">
              {filteredProjects.map((project) => (
                <ProjectListRow
                  key={project.id}
                  project={project}
                  isSelected={selectedProjects.has(project.id)}
                  isFavorite={favoriteProjectPaths.has(project.path)}
                  selectedProjectIds={selectedProjects}
                  notePreview={notePreviewByPath[project.path] ?? (isNotesPreviewLoading ? "加载中..." : "—")}
                  onSelect={(event) => onSelectProject(project, event)}
                  onOpenTerminal={onOpenTerminal}
                  onRunProjectScript={onRunProjectScript}
                  onRefreshProject={onRefreshProject}
                  onCopyPath={onCopyPath}
                  onMoveToRecycleBin={onMoveToRecycleBin}
                  onToggleFavorite={onToggleFavorite}
                />
              ))}
            </div>
          </div>
        ) : (
          <div className="grid grid-cols-[repeat(auto-fit,minmax(250px,1fr))] gap-4 p-4">
            {filteredProjects.map((project) => (
              <ProjectCard
                key={project.id}
                project={project}
                isSelected={selectedProjects.has(project.id)}
                isFavorite={favoriteProjectPaths.has(project.path)}
                selectedProjectIds={selectedProjects}
                onSelect={(event) => onSelectProject(project, event)}
                onOpenTerminal={onOpenTerminal}
                onRunProjectScript={onRunProjectScript}
                onTagClick={onTagSelected}
                onRemoveTag={onRemoveTagFromProject}
                getTagColor={getTagColor}
                onRefreshProject={onRefreshProject}
                onCopyPath={onCopyPath}
                onMoveToRecycleBin={onMoveToRecycleBin}
                onToggleFavorite={onToggleFavorite}
              />
            ))}
          </div>
        )}
      </div>
    </section>
  );
}
