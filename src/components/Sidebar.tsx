import { memo, useMemo } from "react";

import type { HeatmapData } from "../models/heatmap";
import type { CodexSessionView } from "../models/codex";
import { HEATMAP_CONFIG } from "../models/heatmap";
import type { AppStateFile, Project, TagData } from "../models/types";
import { pickDirectoriesRuntime } from "../platform/runtime";
import { colorDataToHex } from "../utils/colors";
import { formatPathWithTilde } from "../utils/pathDisplay";
import CodexSessionSection from "./CodexSessionSection";
import Heatmap from "./Heatmap";
import DropdownMenu from "./DropdownMenu";
import { IconEye, IconEyeOff, IconMoreHorizontal, IconPlusCircle, IconTrash } from "./Icons";
import { openInFinder } from "../services/system";

export type HeatmapActiveProject = {
  projectId: string;
  projectName: string;
  projectPath: string;
  commitCount: number;
};

export type SidebarProps = {
  appState: AppStateFile;
  projects: Project[];
  heatmapData: HeatmapData[];
  heatmapSelectedDateKey: string | null;
  selectedTags: Set<string>;
  selectedDirectory: string | null;
  heatmapFilteredProjectIds: Set<string>;
  heatmapActiveProjects: HeatmapActiveProject[];
  onSelectTag: (tag: string) => void;
  onClearHeatmapFilter: () => void;
  onSelectHeatmapDate: (entry: HeatmapData | null) => void;
  onLocateHeatmapProject: (projectId: string) => void;
  onSelectDirectory: (directory: string | null) => void;
  onOpenTagEditor: (tag?: TagData) => void;
  onToggleTagHidden: (name: string) => void;
  onRemoveTag: (name: string) => void;
  onAssignTagToProjects: (tag: string, projectIds: string[]) => void;
  onAddDirectory: (path: string) => Promise<void>;
  onRemoveDirectory: (path: string) => Promise<void>;
  onOpenRecycleBin: () => void;
  onRefresh: () => Promise<void>;
  onAddProjects: (paths: string[]) => Promise<void>;
  isHeatmapLoading: boolean;
  codexSessions: CodexSessionView[];
  codexSessionsLoading: boolean;
  codexSessionsError: string | null;
  onOpenCodexSession: (session: CodexSessionView) => void;
};

/** 左侧边栏，负责目录、标签与筛选入口。 */
function Sidebar({
  appState,
  projects,
  heatmapData,
  heatmapSelectedDateKey,
  selectedTags,
  selectedDirectory,
  heatmapFilteredProjectIds,
  heatmapActiveProjects,
  onSelectTag,
  onClearHeatmapFilter,
  onSelectHeatmapDate,
  onLocateHeatmapProject,
  onSelectDirectory,
  onOpenTagEditor,
  onToggleTagHidden,
  onRemoveTag,
  onAssignTagToProjects,
  onAddDirectory,
  onRemoveDirectory,
  onOpenRecycleBin,
  onRefresh,
  onAddProjects,
  isHeatmapLoading,
  codexSessions,
  codexSessionsLoading,
  codexSessionsError,
  onOpenCodexSession,
}: SidebarProps) {
  const directoryCounts = useMemo(() => {
    const directories = appState.directories;
    const counts = new Map<string, number>();
    if (directories.length === 0) {
      return counts;
    }

    const directoryCountByIndex = new Array<number>(directories.length).fill(0);
    for (const project of projects) {
      for (let index = 0; index < directories.length; index += 1) {
        if (project.path.startsWith(directories[index])) {
          directoryCountByIndex[index] += 1;
        }
      }
    }

    for (let index = 0; index < directories.length; index += 1) {
      counts.set(directories[index], directoryCountByIndex[index]);
    }

    return counts;
  }, [appState.directories, projects]);

  const tagCounts = useMemo(() => {
    const counts = new Map<string, number>();
    for (const project of projects) {
      if (project.tags.length === 0) {
        counts.set("没有标签", (counts.get("没有标签") ?? 0) + 1);
      }
      for (const tag of project.tags) {
        counts.set(tag, (counts.get(tag) ?? 0) + 1);
      }
    }
    counts.set("全部", projects.length);
    return counts;
  }, [projects]);

  const sortedTags = useMemo(() => {
    return [...appState.tags].sort((a, b) => {
      const countA = tagCounts.get(a.name) ?? 0;
      const countB = tagCounts.get(b.name) ?? 0;
      return countB - countA;
    });
  }, [appState.tags, tagCounts]);

  const handlePickDirectory = async (multiple: boolean, directProject: boolean) => {
    const paths = await pickDirectoriesRuntime();
    if (!paths || paths.length === 0) {
      return;
    }

    const resolvedPaths = multiple ? paths : [paths[0]];
    if (directProject) {
      await onAddProjects(resolvedPaths);
      return;
    }

    for (const path of resolvedPaths) {
      await onAddDirectory(path);
    }
    await onRefresh();
  };

  const handleDirectoryDrop = async (event: React.DragEvent<HTMLDivElement>) => {
    event.preventDefault();
    const paths = Array.from(event.dataTransfer.files)
      .map((file) => (file as File & { path?: string }).path)
      .filter((path): path is string => Boolean(path));
    if (paths.length === 0) {
      return;
    }
    for (const path of paths) {
      await onAddDirectory(path);
    }
    await onRefresh();
  };

  return (
    <aside className="flex min-w-sidebar max-w-sidebar flex-col border-r border-sidebar-border bg-sidebar-bg">
      <div className="flex-1 overflow-y-auto" onDragOver={(event) => event.preventDefault()} onDrop={handleDirectoryDrop}>
        <section className="pb-2">
          <div className="section-header">
            <span className="section-title">目录</span>
            <DropdownMenu
              label={<IconPlusCircle size={16} />}
              items={[
                {
                  label: "添加工作目录（扫描项目）",
                  onClick: () => void handlePickDirectory(false, false),
                },
                {
                  label: "直接添加为项目",
                  onClick: () => void handlePickDirectory(true, true),
                },
                { label: "刷新项目列表", onClick: () => void onRefresh() },
              ]}
            />
          </div>
          <div className="flex flex-col">
            <DirectoryRow
              label="全部"
              count={projects.length}
              selected={selectedDirectory === null}
              onClick={() => onSelectDirectory(null)}
            />
            {appState.directories.map((dir) => (
              <DirectoryRow
                key={dir}
                label={dir.split("/").pop() ?? dir}
                count={directoryCounts.get(dir) ?? 0}
                selected={selectedDirectory === dir}
                onClick={() => onSelectDirectory(dir)}
                onOpen={() => void openInFinder(dir)}
                onRemove={() => void onRemoveDirectory(dir)}
              />
            ))}
          </div>
        </section>

        <section className="pb-2">
          <div className="section-header">
            <span className="section-title">开发热力图</span>
          </div>
          {heatmapFilteredProjectIds.size > 0 ? (
            <div className="flex items-center justify-between gap-2 bg-[rgba(69,59,231,0.1)] px-3 py-2 text-fs-caption text-accent">
              <span>日期筛选已启用</span>
              <button className="text-accent" onClick={onClearHeatmapFilter}>
                清除
              </button>
            </div>
          ) : null}
          {isHeatmapLoading ? (
            <div className="px-3 py-2 text-fs-caption text-secondary-text">正在统计中...</div>
          ) : heatmapData.length > 0 ? (
            <Heatmap
              data={heatmapData}
              config={HEATMAP_CONFIG.sidebar}
              selectedDateKey={heatmapSelectedDateKey}
              onSelectDate={onSelectHeatmapDate}
              className="heatmap-sidebar"
            />
          ) : (
            <div className="px-3 py-2 text-fs-caption text-secondary-text">暂无数据</div>
          )}
          {heatmapSelectedDateKey ? (
            <div className="mt-2 flex flex-col gap-1 px-2">
              <div className="px-1 text-[11px] text-secondary-text">
                {heatmapSelectedDateKey} · {heatmapActiveProjects.length} 个活跃项目
              </div>
              {heatmapActiveProjects.length === 0 ? (
                <div className="px-1 py-1 text-[11px] text-secondary-text">当天无活跃项目</div>
              ) : (
                <div className="max-h-40 overflow-y-auto rounded-md border border-sidebar-border bg-[rgba(255,255,255,0.02)]">
                  {heatmapActiveProjects.map((item) => (
                    <button
                      key={item.projectId}
                      type="button"
                      className="flex w-full items-start gap-2 px-2 py-1.5 text-left hover:bg-sidebar-selected/50"
                      onClick={() => onLocateHeatmapProject(item.projectId)}
                    >
                      <span className="mt-[2px] min-w-6 rounded bg-sidebar-selected px-1 py-[1px] text-center text-[11px] text-accent">
                        {item.commitCount}
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-fs-caption text-text">{item.projectName}</span>
                        <span className="block truncate text-[11px] text-secondary-text">
                          {formatPathWithTilde(item.projectPath)}
                        </span>
                      </span>
                    </button>
                  ))}
                </div>
              )}
            </div>
          ) : null}
        </section>

        <div className="my-2 h-px bg-divider" />

        <CodexSessionSection
          sessions={codexSessions}
          isLoading={codexSessionsLoading}
          error={codexSessionsError}
          onOpenSession={onOpenCodexSession}
        />

        <div className="my-2 h-px bg-divider" />

        <section className="pb-2">
          <div className="section-header">
            <span className="section-title">标签</span>
            <div className="ml-auto inline-flex items-center gap-1.5">
              <button className="icon-btn" onClick={() => onOpenTagEditor()} aria-label="新建标签">
                <IconPlusCircle size={16} />
              </button>
            </div>
          </div>
          <div className="flex flex-col">
            <TagRow
              label="全部"
              count={tagCounts.get("全部") ?? 0}
              selected={selectedTags.size === 0}
              onClick={() => onSelectTag("全部")}
            />
            {sortedTags.map((tag) => (
              <TagRow
                key={tag.name}
                label={tag.name}
                count={tagCounts.get(tag.name) ?? 0}
                selected={selectedTags.has(tag.name)}
                color={colorDataToHex(tag.color)}
                hidden={tag.hidden}
                onClick={() => onSelectTag(tag.name)}
                onToggleHidden={() => onToggleTagHidden(tag.name)}
                onEdit={() => onOpenTagEditor(tag)}
                onRemove={() => onRemoveTag(tag.name)}
                onAssignProjects={(projectIds) => onAssignTagToProjects(tag.name, projectIds)}
              />
            ))}
          </div>
        </section>
      </div>
      <div className="flex items-center justify-start border-t border-divider px-2.5 py-2">
        <button
          className="icon-btn h-8 w-8 text-titlebar-icon"
          onClick={onOpenRecycleBin}
          aria-label="回收站"
          title="回收站"
        >
          <IconTrash size={18} />
        </button>
      </div>
    </aside>
  );
}

export default memo(Sidebar);

type DirectoryRowProps = {
  label: string;
  count: number;
  selected: boolean;
  onClick: () => void;
  onOpen?: () => void;
  onRemove?: () => void;
};

/** 目录行，展示数量与快捷操作。 */
const DirectoryRow = memo(function DirectoryRow({ label, count, selected, onClick, onOpen, onRemove }: DirectoryRowProps) {
  const menuItems = [] as { label: string; onClick: () => void; destructive?: boolean }[];
  if (onOpen) {
    menuItems.push({ label: "在访达中显示", onClick: onOpen });
  }
  if (onRemove) {
    menuItems.push({ label: "移除目录", onClick: onRemove, destructive: true });
  }

  return (
    <div
      className={`tag-row-base tag-row-hover ${selected ? "tag-row-selected" : ""}`}
      onClick={onClick}
    >
      <span>{label}</span>
      <div className="ml-auto inline-flex items-center gap-1.5">
        <span className={`tag-count ${selected ? "bg-sidebar-selected text-text" : ""}`}>{count}</span>
        {menuItems.length > 0 ? (
          <DropdownMenu label={<IconMoreHorizontal size={16} />} items={menuItems} />
        ) : (
          <span className="icon-btn invisible" aria-hidden="true" />
        )}
      </div>
    </div>
  );
});

type TagRowProps = {
  label: string;
  count: number;
  selected: boolean;
  color?: string;
  hidden?: boolean;
  onClick: () => void;
  onToggleHidden?: () => void;
  onEdit?: () => void;
  onRemove?: () => void;
  onAssignProjects?: (projectIds: string[]) => void;
};

/** 标签行，支持隐藏、编辑与拖拽分配。 */
const TagRow = memo(function TagRow({
  label,
  count,
  selected,
  color,
  hidden,
  onClick,
  onToggleHidden,
  onEdit,
  onRemove,
  onAssignProjects,
}: TagRowProps) {
  const menuItems = [] as { label: string; onClick: () => void; destructive?: boolean }[];
  if (onEdit) {
    menuItems.push({ label: "编辑标签", onClick: onEdit });
  }
  if (onRemove) {
    menuItems.push({ label: "删除标签", onClick: onRemove, destructive: true });
  }

  const tagStyle = color
    ? {
        background: selected ? color : `${color}33`,
        color: "#fff",
      }
    : undefined;

  return (
    <div
      className={`group tag-row-base tag-row-hover ${selected ? "tag-row-selected" : ""} ${
        hidden ? "opacity-60" : ""
      }`}
      onClick={onClick}
      onDragOver={(event) => {
        if (onAssignProjects) {
          event.preventDefault();
        }
      }}
      onDrop={(event) => {
        if (!onAssignProjects) {
          return;
        }
        event.preventDefault();
        const payload = event.dataTransfer.getData("application/x-project-ids");
        if (!payload) {
          return;
        }
        try {
          const parsed = JSON.parse(payload) as string[];
          onAssignProjects(parsed);
        } catch {
          return;
        }
      }}
    >
      <span className="inline-flex items-center rounded-md bg-tag-bg px-2 py-1 text-fs-sidebar-tag text-tag-text" style={tagStyle}>
        {label}
      </span>
      <div className="ml-auto inline-flex items-center gap-1.5">
        {onToggleHidden ? (
          <button
            className={`icon-btn ${hidden ? "opacity-100" : "opacity-0 group-hover:opacity-80"}`}
            onClick={(event) => {
              event.stopPropagation();
              onToggleHidden();
            }}
            aria-label={hidden ? "显示标签" : "隐藏标签"}
          >
            {hidden ? <IconEyeOff size={14} /> : <IconEye size={14} />}
          </button>
        ) : (
          <span className="icon-btn invisible" aria-hidden="true" />
        )}
        <span className={`tag-count ${selected ? "bg-sidebar-selected text-text" : ""}`}>{count}</span>
        {menuItems.length > 0 ? (
          <DropdownMenu label={<IconMoreHorizontal size={16} />} items={menuItems} />
        ) : (
          <span className="icon-btn invisible" aria-hidden="true" />
        )}
      </div>
    </div>
  );
});
