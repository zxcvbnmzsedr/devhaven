import { useCallback, useMemo, useRef, useState, type Dispatch, type RefObject, type SetStateAction } from "react";

import type { DateFilter, GitFilter } from "../models/filters";
import { DATE_FILTER_OPTIONS } from "../models/filters";
import type { HeatmapData } from "../models/heatmap";
import type { TagData, Project } from "../models/types";
import { swiftDateToJsDate } from "../models/types";
import { formatDateKey, parseGitDaily } from "../utils/gitDaily";

type UseProjectFilterParams = {
  visibleProjects: Project[];
  favoriteProjectPathSet: Set<string>;
  appTags: TagData[];
  onLocateProject: (projectId: string) => void;
};

export type UseProjectFilterReturn = {
  searchText: string;
  setSearchText: Dispatch<SetStateAction<string>>;
  dateFilter: DateFilter;
  setDateFilter: Dispatch<SetStateAction<DateFilter>>;
  gitFilter: GitFilter;
  setGitFilter: Dispatch<SetStateAction<GitFilter>>;
  selectedTags: Set<string>;
  setSelectedTags: Dispatch<SetStateAction<Set<string>>>;
  selectedDirectory: string | null;
  setSelectedDirectory: Dispatch<SetStateAction<string | null>>;
  heatmapFilteredProjectIds: Set<string>;
  setHeatmapFilteredProjectIds: Dispatch<SetStateAction<Set<string>>>;
  heatmapSelectedDateKey: string | null;
  setHeatmapSelectedDateKey: Dispatch<SetStateAction<string | null>>;
  searchInputRef: RefObject<HTMLInputElement | null>;
  hiddenTags: Set<string>;
  filteredProjects: Project[];
  heatmapActiveProjects: Array<{
    projectId: string;
    projectName: string;
    projectPath: string;
    commitCount: number;
  }>;
  handleSelectTag: (tag: string) => void;
  handleSelectDirectory: (directory: string | null) => void;
  handleSelectHeatmapDate: (entry: HeatmapData | null) => void;
  handleLocateHeatmapProject: (projectId: string) => void;
};

/** 管理搜索、标签、目录、时间与热力图筛选逻辑。 */
export function useProjectFilter({
  visibleProjects,
  favoriteProjectPathSet,
  appTags,
  onLocateProject,
}: UseProjectFilterParams): UseProjectFilterReturn {
  const [searchText, setSearchText] = useState("");
  const [dateFilter, setDateFilter] = useState<DateFilter>("all");
  const [gitFilter, setGitFilter] = useState<GitFilter>("all");
  const [selectedTags, setSelectedTags] = useState<Set<string>>(new Set());
  const [selectedDirectory, setSelectedDirectory] = useState<string | null>(null);
  const [heatmapFilteredProjectIds, setHeatmapFilteredProjectIds] = useState<Set<string>>(new Set());
  const [heatmapSelectedDateKey, setHeatmapSelectedDateKey] = useState<string | null>(null);
  const searchInputRef = useRef<HTMLInputElement>(null);

  const hiddenTags = useMemo(
    () => new Set(appTags.filter((tag) => tag.hidden).map((tag) => tag.name)),
    [appTags],
  );

  const filteredProjects = useMemo(() => {
    const hasSelectedTags = selectedTags.size > 0 && !selectedTags.has("全部");
    const selectedTagList = hasSelectedTags ? Array.from(selectedTags) : [];
    const trimmedSearch = searchText.trim().toLowerCase();
    const hasHeatmapFilter = heatmapFilteredProjectIds.size > 0;
    const dateOption = DATE_FILTER_OPTIONS.find((option) => option.value === dateFilter);
    const cutoff = dateOption?.days ? Date.now() - dateOption.days * 24 * 60 * 60 * 1000 : null;

    // 单次遍历合并筛选，减少中间数组分配与重复计算。
    const result: Project[] = [];
    for (const project of visibleProjects) {
      if (selectedDirectory && !project.path.startsWith(selectedDirectory)) {
        continue;
      }

      let hasHiddenTag = false;
      let hasSelectedHiddenTag = false;
      for (const tag of project.tags) {
        if (!hiddenTags.has(tag)) {
          continue;
        }
        hasHiddenTag = true;
        if (hasSelectedTags && selectedTags.has(tag)) {
          hasSelectedHiddenTag = true;
          break;
        }
      }
      if (hasHiddenTag && !hasSelectedHiddenTag) {
        continue;
      }

      if (hasHeatmapFilter) {
        if (!heatmapFilteredProjectIds.has(project.id)) {
          continue;
        }
      } else if (hasSelectedTags) {
        let hasAllSelectedTags = true;
        for (const tag of selectedTagList) {
          if (!project.tags.includes(tag)) {
            hasAllSelectedTags = false;
            break;
          }
        }
        if (!hasAllSelectedTags) {
          continue;
        }
      }

      if (
        trimmedSearch &&
        !project.name.toLowerCase().includes(trimmedSearch) &&
        !project.path.toLowerCase().includes(trimmedSearch)
      ) {
        continue;
      }

      if (cutoff !== null && swiftDateToJsDate(project.mtime).getTime() < cutoff) {
        continue;
      }

      const commitCount = project.git_commits ?? 0;
      if (gitFilter === "gitOnly" && commitCount <= 0) {
        continue;
      }
      if (gitFilter === "nonGitOnly" && commitCount !== 0) {
        continue;
      }

      result.push(project);
    }

    result.sort((left, right) => {
      const leftFavorite = favoriteProjectPathSet.has(left.path);
      const rightFavorite = favoriteProjectPathSet.has(right.path);
      if (leftFavorite !== rightFavorite) {
        return leftFavorite ? -1 : 1;
      }
      return right.mtime - left.mtime;
    });

    return result;
  }, [
    dateFilter,
    favoriteProjectPathSet,
    gitFilter,
    heatmapFilteredProjectIds,
    hiddenTags,
    searchText,
    selectedDirectory,
    selectedTags,
    visibleProjects,
  ]);

  const heatmapActiveProjects = useMemo(() => {
    if (!heatmapSelectedDateKey) {
      return [];
    }
    // 未选中日期时直接短路，避免对全部项目解析 git_daily。
    const activeProjects: Array<{
      projectId: string;
      projectName: string;
      projectPath: string;
      commitCount: number;
    }> = [];

    for (const project of visibleProjects) {
      const commitCount = parseGitDaily(project.git_daily)[heatmapSelectedDateKey] ?? 0;
      if (commitCount <= 0) {
        continue;
      }
      activeProjects.push({
        projectId: project.id,
        projectName: project.name,
        projectPath: project.path,
        commitCount,
      });
    }

    activeProjects.sort((left, right) => {
      if (left.commitCount !== right.commitCount) {
        return right.commitCount - left.commitCount;
      }
      return left.projectName.localeCompare(right.projectName);
    });
    return activeProjects;
  }, [heatmapSelectedDateKey, visibleProjects]);

  const handleSelectTag = useCallback((tag: string) => {
    if (tag === "全部") {
      setSelectedTags(new Set());
      return;
    }
    setSelectedTags(new Set([tag]));
  }, []);

  const handleSelectDirectory = useCallback((directory: string | null) => {
    setSelectedDirectory(directory);
  }, []);

  const handleSelectHeatmapDate = useCallback((entry: HeatmapData | null) => {
    if (!entry) {
      setHeatmapFilteredProjectIds(new Set());
      setHeatmapSelectedDateKey(null);
      return;
    }
    setHeatmapFilteredProjectIds(new Set(entry.projectIds));
    setHeatmapSelectedDateKey(formatDateKey(entry.date));
  }, []);

  const handleLocateHeatmapProject = useCallback(
    (projectId: string) => {
      onLocateProject(projectId);
    },
    [onLocateProject],
  );

  return {
    searchText,
    setSearchText,
    dateFilter,
    setDateFilter,
    gitFilter,
    setGitFilter,
    selectedTags,
    setSelectedTags,
    selectedDirectory,
    setSelectedDirectory,
    heatmapFilteredProjectIds,
    setHeatmapFilteredProjectIds,
    heatmapSelectedDateKey,
    setHeatmapSelectedDateKey,
    searchInputRef,
    hiddenTags,
    filteredProjects,
    heatmapActiveProjects,
    handleSelectTag,
    handleSelectDirectory,
    handleSelectHeatmapDate,
    handleLocateHeatmapProject,
  };
}
