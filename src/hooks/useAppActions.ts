import { useCallback, useEffect, useMemo, useRef, type Dispatch, type SetStateAction } from "react";

import type { AppStateFile, ColorData, Project, ProjectListViewMode, TagData } from "../models/types";
import { colorDataToHex } from "../utils/colors";
import { buildGitIdentitySignature } from "../utils/gitIdentity";
import { pickColorForTag } from "../utils/tagColors";
import { copyToClipboard } from "../services/system";

type UseAppActionsParams = {
  appState: AppStateFile;
  isLoading: boolean;
  visibleProjects: Project[];
  projectMap: Map<string, Project>;
  projectListViewMode: ProjectListViewMode;
  tagDialogState: { mode: "new" | "edit"; tag?: TagData } | null;
  setTagDialogState: Dispatch<SetStateAction<{ mode: "new" | "edit"; tag?: TagData } | null>>;
  setSelectedProjects: Dispatch<SetStateAction<Set<string>>>;
  setSelectedProjectId: Dispatch<SetStateAction<string | null>>;
  setHeatmapFilteredProjectIds: Dispatch<SetStateAction<Set<string>>>;
  setSelectedTags: Dispatch<SetStateAction<Set<string>>>;
  moveProjectToRecycleBin: (path: string) => Promise<void>;
  moveProjectsToRecycleBin: (paths: string[]) => Promise<void>;
  restoreProjectFromRecycleBin: (path: string) => Promise<void>;
  refreshProject: (path: string) => Promise<void>;
  addTagToProjects: (projectIds: string[], tag: string) => Promise<void>;
  addTag: (name: string, colorHex?: string) => Promise<void>;
  renameTag: (from: string, to: string) => Promise<void>;
  setTagColor: (name: string, colorHex: string) => Promise<void>;
  updateGitDaily: (paths?: string[]) => Promise<void>;
  updateSettings: (settings: AppStateFile["settings"]) => Promise<void>;
  showToast: (message: string, variant?: "success" | "error") => void;
};

export type UseAppActionsReturn = {
  handleAssignTagToProjects: (tag: string, projectIds: string[]) => Promise<void>;
  handleOpenTagEditor: (tag?: TagData) => void;
  handleMoveProjectToRecycleBin: (project: Project) => Promise<void>;
  handleBulkCopyProjectPaths: (projectIds: string[]) => Promise<void>;
  handleBulkRefreshProjects: (projectIds: string[]) => Promise<void>;
  handleBulkMoveProjectsToRecycleBin: (projectIds: string[]) => Promise<void>;
  handleBulkAssignTagToProjects: (tag: string, projectIds: string[]) => Promise<void>;
  handleRestoreProjectFromRecycleBin: (path: string) => Promise<void>;
  handleTagSubmit: (name: string, colorHex: string) => Promise<void>;
  getTagColor: (tagName: string) => string;
  getTagHex: (color?: ColorData) => string;
  handleCopyPath: (path: string) => Promise<void>;
  handleSaveSettings: (settings: AppStateFile["settings"]) => Promise<void>;
  handleChangeProjectListViewMode: (mode: ProjectListViewMode) => Promise<void>;
};

/** 聚合 App 顶层业务回调与 Git Daily 自动刷新副作用。 */
export function useAppActions({
  appState,
  isLoading,
  visibleProjects,
  projectMap,
  projectListViewMode,
  tagDialogState,
  setTagDialogState,
  setSelectedProjects,
  setSelectedProjectId,
  setHeatmapFilteredProjectIds,
  setSelectedTags,
  moveProjectToRecycleBin,
  moveProjectsToRecycleBin,
  restoreProjectFromRecycleBin,
  refreshProject,
  addTagToProjects,
  addTag,
  renameTag,
  setTagColor,
  updateGitDaily,
  updateSettings,
  showToast,
}: UseAppActionsParams): UseAppActionsReturn {
  const gitDailyRefreshRef = useRef<string | null>(null);
  const gitDailyUpdatingRef = useRef(false);
  const gitIdentitySignatureRef = useRef<string | null>(null);

  const handleAssignTagToProjects = useCallback(
    async (tag: string, projectIds: string[]) => {
      await addTagToProjects(projectIds, tag);
      setSelectedTags(new Set());
    },
    [addTagToProjects, setSelectedTags],
  );

  const handleOpenTagEditor = useCallback(
    (tag?: TagData) => {
      setTagDialogState({ mode: tag ? "edit" : "new", tag });
    },
    [setTagDialogState],
  );

  const handleMoveProjectToRecycleBin = useCallback(
    async (project: Project) => {
      try {
        await moveProjectToRecycleBin(project.path);
        showToast("已移入回收站");
        setSelectedProjects((prev) => {
          if (!prev.has(project.id)) {
            return prev;
          }
          const next = new Set(prev);
          next.delete(project.id);
          return next;
        });
        setSelectedProjectId((prev) => (prev === project.id ? null : prev));
        setHeatmapFilteredProjectIds((prev) => {
          if (!prev.has(project.id)) {
            return prev;
          }
          const next = new Set(prev);
          next.delete(project.id);
          return next;
        });
      } catch (error) {
        console.error("移入回收站失败。", error);
        showToast("移入回收站失败，请稍后重试", "error");
      }
    },
    [moveProjectToRecycleBin, setHeatmapFilteredProjectIds, setSelectedProjectId, setSelectedProjects, showToast],
  );

  const handleBulkCopyProjectPaths = useCallback(
    async (projectIds: string[]) => {
      const targetPaths = Array.from(
        new Set(
          projectIds
            .map((projectId) => projectMap.get(projectId)?.path ?? "")
            .map((path) => path.trim())
            .filter(Boolean),
        ),
      );
      if (targetPaths.length === 0) {
        showToast("未找到可复制的项目路径", "error");
        return;
      }
      try {
        await copyToClipboard(targetPaths.join("\n"));
        showToast(`已复制 ${targetPaths.length} 个项目路径`);
      } catch (error) {
        console.error("批量复制路径失败。", error);
        showToast("批量复制失败，请稍后重试", "error");
      }
    },
    [projectMap, showToast],
  );

  const handleBulkRefreshProjects = useCallback(
    async (projectIds: string[]) => {
      const targetPaths = Array.from(
        new Set(projectIds.map((projectId) => projectMap.get(projectId)?.path ?? "").filter(Boolean)),
      );
      if (targetPaths.length === 0) {
        showToast("未找到可刷新的项目", "error");
        return;
      }
      try {
        for (const path of targetPaths) {
          await refreshProject(path);
        }
        showToast(`已刷新 ${targetPaths.length} 个项目`);
      } catch (error) {
        console.error("批量刷新项目失败。", error);
        showToast("批量刷新失败，请稍后重试", "error");
      }
    },
    [projectMap, refreshProject, showToast],
  );

  const handleBulkMoveProjectsToRecycleBin = useCallback(
    async (projectIds: string[]) => {
      const targetProjectIds = Array.from(new Set(projectIds.filter((projectId) => projectMap.has(projectId))));
      if (targetProjectIds.length === 0) {
        showToast("未找到可移入回收站的项目", "error");
        return;
      }

      const targetPaths = targetProjectIds
        .map((projectId) => projectMap.get(projectId)?.path ?? "")
        .map((path) => path.trim())
        .filter(Boolean);

      try {
        await moveProjectsToRecycleBin(targetPaths);
        const targetIdSet = new Set(targetProjectIds);
        setSelectedProjects((prev) => {
          const next = new Set(prev);
          targetIdSet.forEach((id) => next.delete(id));
          return next;
        });
        setSelectedProjectId((prev) => (prev && targetIdSet.has(prev) ? null : prev));
        setHeatmapFilteredProjectIds((prev) => {
          const next = new Set(prev);
          targetIdSet.forEach((id) => next.delete(id));
          return next;
        });
        showToast(`已移入回收站（${targetProjectIds.length} 个项目）`);
      } catch (error) {
        console.error("批量移入回收站失败。", error);
        showToast("批量移入回收站失败，请稍后重试", "error");
      }
    },
    [moveProjectsToRecycleBin, projectMap, setHeatmapFilteredProjectIds, setSelectedProjectId, setSelectedProjects, showToast],
  );

  const handleBulkAssignTagToProjects = useCallback(
    async (tag: string, projectIds: string[]) => {
      const targetProjectIds = Array.from(new Set(projectIds.filter((projectId) => projectMap.has(projectId))));
      if (targetProjectIds.length === 0) {
        showToast("未找到可打标签的项目", "error");
        return;
      }
      try {
        await addTagToProjects(targetProjectIds, tag);
        setSelectedTags(new Set());
        showToast(`已为 ${targetProjectIds.length} 个项目添加标签`);
      } catch (error) {
        console.error("批量打标签失败。", error);
        showToast("批量打标签失败，请稍后重试", "error");
      }
    },
    [addTagToProjects, projectMap, setSelectedTags, showToast],
  );

  const handleRestoreProjectFromRecycleBin = useCallback(
    async (path: string) => {
      try {
        await restoreProjectFromRecycleBin(path);
        showToast("已从回收站恢复");
      } catch (error) {
        console.error("恢复项目失败。", error);
        showToast("回收站恢复失败，请稍后重试", "error");
      }
    },
    [restoreProjectFromRecycleBin, showToast],
  );

  useEffect(() => {
    if (isLoading) {
      return;
    }
    const missingDaily = visibleProjects.filter((project) => project.git_commits > 0 && !project.git_daily);
    if (missingDaily.length === 0) {
      gitDailyRefreshRef.current = null;
      return;
    }
    const signature = missingDaily
      .map((project) => project.path)
      .sort()
      .join("|");
    if (gitDailyUpdatingRef.current || gitDailyRefreshRef.current === signature) {
      return;
    }
    gitDailyRefreshRef.current = signature;
    gitDailyUpdatingRef.current = true;
    void (async () => {
      try {
        await updateGitDaily(missingDaily.map((project) => project.path));
      } finally {
        gitDailyUpdatingRef.current = false;
      }
    })();
  }, [isLoading, updateGitDaily, visibleProjects]);

  const gitIdentitySignature = useMemo(
    () => buildGitIdentitySignature(appState.settings.gitIdentities),
    [appState.settings.gitIdentities],
  );

  useEffect(() => {
    if (isLoading) {
      return;
    }
    if (gitIdentitySignatureRef.current === null) {
      gitIdentitySignatureRef.current = gitIdentitySignature;
      return;
    }
    if (gitIdentitySignatureRef.current === gitIdentitySignature) {
      return;
    }
    gitIdentitySignatureRef.current = gitIdentitySignature;
    const gitPaths = visibleProjects.filter((project) => project.git_commits > 0).map((project) => project.path);
    if (gitPaths.length === 0) {
      return;
    }
    void updateGitDaily(gitPaths);
  }, [gitIdentitySignature, isLoading, updateGitDaily, visibleProjects]);

  const handleTagSubmit = useCallback(
    async (name: string, colorHex: string) => {
      if (!tagDialogState) {
        return;
      }
      if (tagDialogState.mode === "new") {
        await addTag(name, colorHex);
      } else if (tagDialogState.tag) {
        if (tagDialogState.tag.name !== name) {
          await renameTag(tagDialogState.tag.name, name);
        }
        await setTagColor(name, colorHex);
      }
      setTagDialogState(null);
    },
    [addTag, renameTag, setTagColor, setTagDialogState, tagDialogState],
  );

  const tagsByName = useMemo(() => {
    const map = new Map<string, TagData>();
    appState.tags.forEach((tag) => {
      map.set(tag.name, tag);
    });
    return map;
  }, [appState.tags]);

  const getTagColor = useCallback(
    (tagName: string) => {
      const tag = tagsByName.get(tagName);
      if (tag) {
        return colorDataToHex(tag.color, pickColorForTag(tagName));
      }
      return pickColorForTag(tagName);
    },
    [tagsByName],
  );

  const getTagHex = useCallback((color?: ColorData) => {
    if (!color) {
      return "#4d4d4d";
    }
    const toHex = (value: number) => Math.round(value * 255).toString(16).padStart(2, "0");
    return `#${toHex(color.r)}${toHex(color.g)}${toHex(color.b)}`;
  }, []);

  const handleCopyPath = useCallback(
    async (path: string) => {
      try {
        await copyToClipboard(path);
        showToast("路径已复制");
      } catch (error) {
        console.error("复制路径失败。", error);
        showToast("复制失败，请重试", "error");
      }
    },
    [showToast],
  );

  const handleSaveSettings = useCallback(
    async (settings: AppStateFile["settings"]) => {
      try {
        const previousViteDevPort = appState.settings.viteDevPort;
        await updateSettings(settings);
        if (settings.viteDevPort !== previousViteDevPort) {
          showToast("浏览器访问端口已更新，重启应用后生效（开发态请重启 dev）。");
        }
      } catch (error) {
        console.error("保存设置失败。", error);
        showToast("保存失败，请稍后重试", "error");
      }
    },
    [appState.settings.viteDevPort, showToast, updateSettings],
  );

  const handleChangeProjectListViewMode = useCallback(
    async (mode: ProjectListViewMode) => {
      if (mode === projectListViewMode) {
        return;
      }
      try {
        await updateSettings({ ...appState.settings, projectListViewMode: mode });
      } catch (error) {
        console.error("切换项目视图模式失败。", error);
        showToast("切换失败，请稍后重试", "error");
      }
    },
    [appState.settings, projectListViewMode, showToast, updateSettings],
  );

  return {
    handleAssignTagToProjects,
    handleOpenTagEditor,
    handleMoveProjectToRecycleBin,
    handleBulkCopyProjectPaths,
    handleBulkRefreshProjects,
    handleBulkMoveProjectsToRecycleBin,
    handleBulkAssignTagToProjects,
    handleRestoreProjectFromRecycleBin,
    handleTagSubmit,
    getTagColor,
    getTagHex,
    handleCopyPath,
    handleSaveSettings,
    handleChangeProjectListViewMode,
  };
}
