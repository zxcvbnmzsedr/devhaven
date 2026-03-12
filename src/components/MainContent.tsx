import { memo, useCallback, useEffect, useMemo, useRef, useState } from "react";

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

const LIST_INITIAL_BATCH_SIZE = 60;
const LIST_BATCH_SIZE = 60;
const CARD_INITIAL_BATCH_SIZE = 48;
const CARD_BATCH_SIZE = 48;
const LOAD_MORE_THRESHOLD = 240;

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
function MainContent({
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
  const [renderedListCount, setRenderedListCount] = useState(LIST_INITIAL_BATCH_SIZE);
  const [renderedCardCount, setRenderedCardCount] = useState(CARD_INITIAL_BATCH_SIZE);
  const pendingNotePreviewPathsRef = useRef<Set<string>>(new Set());
  const notePreviewByPathRef = useRef<Record<string, string>>(notePreviewByPath);
  const filteredListProjectIdsRef = useRef<string[]>([]);
  const filteredCardProjectIdsRef = useRef<string[]>([]);
  const previousViewModeRef = useRef<ProjectListViewMode>(viewMode);
  const scrollContainerRef = useRef<HTMLDivElement | null>(null);
  const selectedProjectIds = useMemo(() => Array.from(selectedProjects), [selectedProjects]);
  const selectedProjectIdsRef = useRef(selectedProjectIds);
  selectedProjectIdsRef.current = selectedProjectIds;
  const selectedProjectsRef = useRef(selectedProjects);
  selectedProjectsRef.current = selectedProjects;
  const resolveDragProjectIds = useCallback((projectId: string) => {
    const nextSelectedProjects = selectedProjectsRef.current;
    return nextSelectedProjects.has(projectId) ? Array.from(nextSelectedProjects) : [projectId];
  }, []);
  const bulkTagMenuItems = useMemo(
    () =>
      availableTags.length
        ? availableTags.map((tag) => ({
            key: `bulk-tag-${tag}`,
            label: `添加标签：${tag}`,
            onClick: () => {
              void onBulkAssignTagToProjects(tag, selectedProjectIdsRef.current);
            },
          }))
        : [{ key: "bulk-tag-empty", label: "暂无可用标签", disabled: true }],
    [availableTags, onBulkAssignTagToProjects],
  );
  const renderedListProjects = useMemo(
    () => filteredProjects.slice(0, renderedListCount),
    [filteredProjects, renderedListCount],
  );
  const renderedCardProjects = useMemo(
    () => filteredProjects.slice(0, renderedCardCount),
    [filteredProjects, renderedCardCount],
  );
  const hasMoreListProjects = renderedListCount < filteredProjects.length;
  const hasMoreCardProjects = renderedCardCount < filteredProjects.length;
  const loadMoreListProjects = useCallback(() => {
    setRenderedListCount((current) => {
      if (current >= filteredProjects.length) {
        return current;
      }
      return Math.min(current + LIST_BATCH_SIZE, filteredProjects.length);
    });
  }, [filteredProjects.length]);
  const loadMoreCardProjects = useCallback(() => {
    setRenderedCardCount((current) => {
      if (current >= filteredProjects.length) {
        return current;
      }
      return Math.min(current + CARD_BATCH_SIZE, filteredProjects.length);
    });
  }, [filteredProjects.length]);
  const listProjectPaths = useMemo(
    () => (viewMode === "list" ? renderedListProjects.map((project) => project.path) : []),
    [renderedListProjects, viewMode],
  );
  const isNotesPreviewLoading = useMemo(
    () =>
      viewMode === "list" &&
      listProjectPaths.some((path) => notePreviewByPath[path] === undefined),
    [listProjectPaths, notePreviewByPath, viewMode],
  );
  const handleContentScroll = useCallback(
    (event: React.UIEvent<HTMLDivElement>) => {
      const shouldLoadMore =
        (viewMode === "list" && hasMoreListProjects) || (viewMode === "card" && hasMoreCardProjects);
      if (!shouldLoadMore) {
        return;
      }
      const { scrollHeight, scrollTop, clientHeight } = event.currentTarget;
      if (scrollHeight - scrollTop - clientHeight <= LOAD_MORE_THRESHOLD) {
        if (viewMode === "list") {
          loadMoreListProjects();
          return;
        }
        loadMoreCardProjects();
      }
    },
    [hasMoreCardProjects, hasMoreListProjects, loadMoreCardProjects, loadMoreListProjects, viewMode],
  );

  useEffect(() => {
    notePreviewByPathRef.current = notePreviewByPath;
  }, [notePreviewByPath]);

  useEffect(() => {
    const wasListMode = previousViewModeRef.current === "list";
    if (viewMode !== "list") {
      return;
    }
    const nextProjectIds = filteredProjects.map((project) => project.id);
    const previousProjectIds = filteredListProjectIdsRef.current;
    const projectIdsChanged =
      nextProjectIds.length !== previousProjectIds.length ||
      nextProjectIds.some((projectId, index) => projectId !== previousProjectIds[index]);
    if (!projectIdsChanged && wasListMode) {
      return;
    }
    // 仅在列表首次进入或项目 ID 真实变化时重置批次，避免无效重算。
    filteredListProjectIdsRef.current = nextProjectIds;
    setRenderedListCount(Math.min(filteredProjects.length, LIST_INITIAL_BATCH_SIZE));
  }, [filteredProjects, viewMode]);

  useEffect(() => {
    const wasCardMode = previousViewModeRef.current === "card";
    if (viewMode !== "card") {
      return;
    }
    const nextProjectIds = filteredProjects.map((project) => project.id);
    const previousProjectIds = filteredCardProjectIdsRef.current;
    const projectIdsChanged =
      nextProjectIds.length !== previousProjectIds.length ||
      nextProjectIds.some((projectId, index) => projectId !== previousProjectIds[index]);
    if (!projectIdsChanged && wasCardMode) {
      return;
    }
    filteredCardProjectIdsRef.current = nextProjectIds;
    setRenderedCardCount(Math.min(filteredProjects.length, CARD_INITIAL_BATCH_SIZE));
  }, [filteredProjects, viewMode]);

  useEffect(() => {
    previousViewModeRef.current = viewMode;
  }, [viewMode]);

  useEffect(() => {
    if (viewMode !== "list" || !hasMoreListProjects) {
      return;
    }
    const container = scrollContainerRef.current;
    if (!container) {
      return;
    }
    if (container.scrollHeight - container.clientHeight <= LOAD_MORE_THRESHOLD) {
      loadMoreListProjects();
    }
  }, [hasMoreListProjects, loadMoreListProjects, renderedListCount, viewMode]);

  useEffect(() => {
    if (viewMode !== "card" || !hasMoreCardProjects) {
      return;
    }
    const container = scrollContainerRef.current;
    if (!container) {
      return;
    }
    if (container.scrollHeight - container.clientHeight <= LOAD_MORE_THRESHOLD) {
      loadMoreCardProjects();
    }
  }, [hasMoreCardProjects, loadMoreCardProjects, renderedCardCount, viewMode]);

  useEffect(() => {
    if (viewMode !== "list") {
      return;
    }
    if (listProjectPaths.length === 0) {
      return;
    }

    const missingPaths = listProjectPaths.filter(
      (path) =>
        notePreviewByPathRef.current[path] === undefined && !pendingNotePreviewPathsRef.current.has(path),
    );
    if (missingPaths.length === 0) {
      return;
    }

    for (const path of missingPaths) {
      pendingNotePreviewPathsRef.current.add(path);
    }

    void readProjectNotesPreviews(missingPaths)
      .then((entries) => {
        const previews = Object.create(null) as Record<string, string>;
        for (const entry of entries) {
          const value = (entry.notesPreview ?? "").trim();
          previews[entry.path] = value || "—";
        }

        setNotePreviewByPath((previous) => {
          const next = { ...previous };
          for (const path of missingPaths) {
            next[path] = previews[path] ?? "—";
          }
          return next;
        });
      })
      .catch(() => {
        setNotePreviewByPath((previous) => {
          const next = { ...previous };
          for (const path of missingPaths) {
            if (next[path] === undefined) {
              next[path] = "—";
            }
          }
          return next;
        });
      })
      .finally(() => {
        for (const path of missingPaths) {
          pendingNotePreviewPathsRef.current.delete(path);
        }
      });
  }, [listProjectPaths, viewMode]);

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

      <div className="flex min-h-0 flex-1 flex-col overflow-y-auto" ref={scrollContainerRef} onScroll={handleContentScroll}>
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
            <div className="grid grid-cols-[minmax(220px,2.2fr)_170px_minmax(180px,2fr)_180px] items-center gap-3 px-3 text-fs-caption font-semibold text-secondary-text">
              <div>项目</div>
              <div>更新时间</div>
              <div>最近提交 / 备注</div>
              <div className="text-left">操作</div>
            </div>
            <div className="overflow-hidden rounded-xl border border-card-border bg-card-bg">
              {renderedListProjects.map((project) => (
                <ProjectListRow
                  key={project.id}
                  project={project}
                  isSelected={selectedProjects.has(project.id)}
                  isFavorite={favoriteProjectPaths.has(project.path)}
                  resolveDragProjectIds={resolveDragProjectIds}
                  notePreview={notePreviewByPath[project.path] ?? (isNotesPreviewLoading ? "加载中..." : "—")}
                  onSelectProject={onSelectProject}
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
            {renderedCardProjects.map((project) => (
              <ProjectCard
                key={project.id}
                project={project}
                isSelected={selectedProjects.has(project.id)}
                isFavorite={favoriteProjectPaths.has(project.path)}
                resolveDragProjectIds={resolveDragProjectIds}
                onSelectProject={onSelectProject}
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

export default memo(MainContent);
