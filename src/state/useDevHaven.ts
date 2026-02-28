import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import type { AppStateFile, Project, ProjectScript, ProjectWorktree, TagData } from "../models/types";
import { jsDateToSwiftDate } from "../models/types";
import {
  buildProjects,
  discoverProjects,
  loadAppState,
  loadProjects,
  saveAppState,
  saveProjects,
} from "../services/appStorage";
import { collectGitDaily } from "../services/gitDaily";
import { pickColorForTag } from "../utils/tagColors";
import { buildTemplateParams, mergeScriptParamSchema } from "../utils/scriptTemplate";

const DEFAULT_SHARED_SCRIPTS_ROOT = "~/.devhaven/scripts";

const emptyState: AppStateFile = {
  version: 4,
  tags: [],
  directories: [],
  recycleBin: [],
  favoriteProjectPaths: [],
  settings: {
    editorOpenTool: {
      commandPath: "",
      arguments: [],
    },
    terminalOpenTool: {
      commandPath: "",
      arguments: [],
    },
    terminalUseWebglRenderer: true,
    terminalTheme: "DevHaven Dark",
    gitIdentities: [],
    projectListViewMode: "card",
    sharedScriptsRoot: DEFAULT_SHARED_SCRIPTS_ROOT,
  },
};

function normalizeAppState(state: AppStateFile): AppStateFile {
  const directories = normalizePathList(state.directories);
  const settings = normalizeSettings(state.settings);
  return {
    ...state,
    directories,
    recycleBin: normalizePathList(state.recycleBin),
    favoriteProjectPaths: normalizePathList(state.favoriteProjectPaths),
    settings,
  };
}

export type DevHavenState = {
  appState: AppStateFile;
  projects: Project[];
  isLoading: boolean;
  error: string | null;
};

export type DevHavenActions = {
  refresh: () => Promise<void>;
  addProjects: (paths: string[]) => Promise<void>;
  refreshProject: (path: string) => Promise<void>;
  updateGitDaily: (paths?: string[]) => Promise<void>;
  addProjectScript: (
    projectId: string,
    script: {
      name: string;
      start: string;
      paramSchema?: ProjectScript["paramSchema"];
      templateParams?: ProjectScript["templateParams"];
    },
  ) => Promise<void>;
  updateProjectScript: (projectId: string, script: ProjectScript) => Promise<void>;
  removeProjectScript: (projectId: string, scriptId: string) => Promise<void>;
  addProjectWorktree: (projectId: string, worktree: ProjectWorktree) => Promise<void>;
  removeProjectWorktree: (projectId: string, worktreePath: string) => Promise<void>;
  syncProjectWorktrees: (projectId: string, worktrees: Array<{ path: string; branch: string }>) => Promise<void>;
  addDirectory: (path: string) => Promise<void>;
  removeDirectory: (path: string) => Promise<void>;
  moveProjectToRecycleBin: (path: string) => Promise<void>;
  moveProjectsToRecycleBin: (paths: string[]) => Promise<void>;
  restoreProjectFromRecycleBin: (path: string) => Promise<void>;
  toggleProjectFavorite: (path: string) => Promise<void>;
  updateSettings: (settings: AppStateFile["settings"]) => Promise<void>;
  updateTags: (tags: TagData[]) => Promise<void>;
  addTag: (name: string, colorHex?: string) => Promise<void>;
  renameTag: (from: string, to: string) => Promise<void>;
  removeTag: (name: string) => Promise<void>;
  toggleTagHidden: (name: string) => Promise<void>;
  setTagColor: (name: string, colorHex: string) => Promise<void>;
  addTagToProject: (projectId: string, tag: string) => Promise<void>;
  addTagToProjects: (projectIds: string[], tag: string) => Promise<void>;
  removeTagFromProject: (projectId: string, tag: string) => Promise<void>;
};

export type DevHavenStore = DevHavenState &
  DevHavenActions & {
    projectMap: Map<string, Project>;
  };

/** 项目管理主 Hook，封装状态、缓存与业务操作。 */
export function useDevHaven(): DevHavenStore {
  const [appState, setAppState] = useState<AppStateFile>(emptyState);
  const [projects, setProjects] = useState<Project[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const appStateRef = useRef<AppStateFile>(appState);
  const projectsRef = useRef<Project[]>(projects);

  useEffect(() => {
    appStateRef.current = appState;
  }, [appState]);

  useEffect(() => {
    projectsRef.current = projects;
  }, [projects]);

  const projectMap = useMemo(() => new Map(projects.map((project) => [project.id, project])), [projects]);

  const handleError = useCallback((err: unknown) => {
    setError(err instanceof Error ? err.message : String(err));
  }, []);

  const commitAppState = useCallback(
    async (updater: AppStateFile | ((currentState: AppStateFile) => AppStateFile)) => {
      const currentState = appStateRef.current;
      const nextState =
        typeof updater === "function"
          ? (updater as (state: AppStateFile) => AppStateFile)(currentState)
          : updater;
      if (nextState === currentState) {
        return currentState;
      }
      appStateRef.current = nextState;
      setAppState(nextState);
      await saveAppState(nextState);
      return nextState;
    },
    [],
  );

  const commitProjects = useCallback(async (nextProjects: Project[]) => {
    projectsRef.current = nextProjects;
    setProjects(nextProjects);
    await saveProjects(nextProjects);
  }, []);

  const commitAppStateAndProjects = useCallback(async (nextState: AppStateFile, nextProjects: Project[]) => {
    appStateRef.current = nextState;
    projectsRef.current = nextProjects;
    setAppState(nextState);
    setProjects(nextProjects);
    await Promise.all([saveAppState(nextState), saveProjects(nextProjects)]);
  }, []);

  /** 将项目中的标签同步到全局标签配置，并持久化。 */
  const syncTagsFromProjects = useCallback(
    async (state: AppStateFile, nextProjects: Project[]) => {
      const existing = new Map(state.tags.map((tag) => [tag.name, tag]));
      let changed = false;

      for (const project of nextProjects) {
        for (const tag of project.tags) {
          if (!existing.has(tag)) {
            existing.set(tag, {
              name: tag,
              color: hexToColorData(pickColorForTag(tag)),
              hidden: false,
            });
            changed = true;
          }
        }
      }

      if (!changed) {
        return state;
      }

      const nextState = {
        ...state,
        tags: Array.from(existing.values()),
      };

      await commitAppState(nextState);
      return nextState;
    },
    [commitAppState],
  );

  /** 刷新应用状态与项目列表，必要时触发扫描与构建。 */
  const refresh = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      const [state, cachedProjects] = await Promise.all([loadAppState(), loadProjects()]);
      const resolvedState = normalizeAppState(state ?? emptyState);
      const resolvedProjects = (cachedProjects ?? []).map(normalizeProject);
      appStateRef.current = resolvedState;
      setAppState(resolvedState);
      if (resolvedState.directories.length === 0) {
        projectsRef.current = resolvedProjects;
        setProjects(resolvedProjects);
        await syncTagsFromProjects(resolvedState, resolvedProjects);
        return;
      }
      const paths = await discoverProjects(resolvedState.directories);
      const updatedProjects = await buildProjects(paths, resolvedProjects);
      const normalizedProjects = updatedProjects.map(normalizeProject);
      projectsRef.current = normalizedProjects;
      setProjects(normalizedProjects);
      await saveProjects(normalizedProjects);
      await syncTagsFromProjects(resolvedState, normalizedProjects);
    } catch (err) {
      handleError(err);
    } finally {
      setIsLoading(false);
    }
  }, [handleError, syncTagsFromProjects]);

  /** 将指定路径直接合并进项目列表并更新标签。 */
  const addProjects = useCallback(
    async (paths: string[]) => {
      const uniquePaths = Array.from(new Set(paths.map((path) => path.trim()).filter(Boolean)));
      if (uniquePaths.length === 0) {
        return;
      }
      try {
        const currentProjects = projectsRef.current;
        const currentState = appStateRef.current;
        const updatedProjects = await buildProjects(uniquePaths, currentProjects);
        const nextProjects = mergeProjectsByPath(currentProjects, updatedProjects);
        await commitProjects(nextProjects);
        await syncTagsFromProjects(currentState, nextProjects);
      } catch (err) {
        handleError(err);
      }
    },
    [commitProjects, handleError, syncTagsFromProjects],
  );

  /** 重新扫描指定项目路径并更新缓存。 */
  const refreshProject = useCallback(
    async (path: string) => {
      if (!path) {
        return;
      }
      try {
        const currentProjects = projectsRef.current;
        const currentState = appStateRef.current;
        const updatedProjects = await buildProjects([path], currentProjects);
        const nextProjects = mergeProjectsByPath(currentProjects, updatedProjects);
        await commitProjects(nextProjects);
        await syncTagsFromProjects(currentState, nextProjects);
      } catch (err) {
        handleError(err);
      }
    },
    [commitProjects, handleError, syncTagsFromProjects],
  );

  /** 更新项目的 Git 每日提交统计（支持指定路径）。 */
  const updateGitDaily = useCallback(
    async (paths?: string[]) => {
      const currentState = appStateRef.current;
      const currentProjects = projectsRef.current;
      const hiddenPaths = new Set(currentState.recycleBin);
      let targetPaths: string[] = [];
      if (paths && paths.length > 0) {
        targetPaths = paths.filter((path) => !hiddenPaths.has(path));
      } else {
        targetPaths = currentProjects
          .filter((project) => project.git_commits > 0 && !hiddenPaths.has(project.path))
          .map((project) => project.path);
      }
      if (targetPaths.length === 0) {
        return;
      }
      try {
        const results = await collectGitDaily(targetPaths, currentState.settings.gitIdentities);
        if (results.length === 0) {
          return;
        }
        const byPath = new Map(results.map((result) => [result.path, result]));
        const nextProjects = currentProjects.map((project) => {
          const match = byPath.get(project.path);
          if (!match || match.error) {
            return project;
          }
          return { ...project, git_daily: match.gitDaily ?? null };
        });
        await commitProjects(nextProjects);
      } catch (err) {
        handleError(err);
      }
    },
    [commitProjects, handleError],
  );

  const createScriptId = () => {
    if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
      return crypto.randomUUID();
    }
    return `${Date.now()}_${Math.random().toString(16).slice(2)}`;
  };

  /** 为项目新增快捷命令并持久化。 */
  const addProjectScript = useCallback(
    async (
      projectId: string,
      script: {
        name: string;
        start: string;
        paramSchema?: ProjectScript["paramSchema"];
        templateParams?: ProjectScript["templateParams"];
      },
    ) => {
      const name = script.name.trim();
      const start = script.start.trim();
      if (!projectId || !name || !start) {
        return;
      }

      const normalizedScript = normalizeProjectScript({
        id: createScriptId(),
        name,
        start,
        paramSchema: script.paramSchema,
        templateParams: script.templateParams,
      });
      const nextScript: ProjectScript = {
        ...normalizedScript,
      };
      const nextProjects = projects.map((project) =>
        project.id === projectId ? { ...project, scripts: [...(project.scripts ?? []), nextScript] } : project,
      );
      await commitProjects(nextProjects);
    },
    [commitProjects, projects],
  );

  /** 更新项目快捷命令并持久化。 */
  const updateProjectScript = useCallback(
    async (projectId: string, script: ProjectScript) => {
      const name = script.name.trim();
      const start = script.start.trim();
      if (!projectId || !script.id || !name || !start) {
        return;
      }

      const nextScript = normalizeProjectScript({
        ...script,
        name,
        start,
      });

      const nextProjects = projects.map((project) => {
        if (project.id !== projectId) {
          return project;
        }
        const scripts = project.scripts ?? [];
        return {
          ...project,
          scripts: scripts.map((item) => (item.id === script.id ? nextScript : item)),
        };
      });
      await commitProjects(nextProjects);
    },
    [commitProjects, projects],
  );

  /** 删除项目快捷命令并持久化。 */
  const removeProjectScript = useCallback(
    async (projectId: string, scriptId: string) => {
      if (!projectId || !scriptId) {
        return;
      }
      const nextProjects = projects.map((project) =>
        project.id === projectId
          ? { ...project, scripts: (project.scripts ?? []).filter((item) => item.id !== scriptId) }
          : project,
      );
      await commitProjects(nextProjects);
    },
    [commitProjects, projects],
  );

  /** 为项目新增/更新 worktree 子项并持久化（按 path 幂等）。 */
  const addProjectWorktree = useCallback(
    async (projectId: string, worktree: ProjectWorktree) => {
      if (!projectId) {
        return;
      }
      const normalizedPath = worktree.path.trim();
      const normalizedBranch = worktree.branch.trim();
      if (!normalizedPath || !normalizedBranch) {
        return;
      }

      const nextWorktree: ProjectWorktree = {
        id: worktree.id?.trim() || createScriptId(),
        name: worktree.name?.trim() || normalizedPath.split("/").pop() || normalizedPath,
        path: normalizedPath,
        branch: normalizedBranch,
        baseBranch: worktree.baseBranch?.trim() || undefined,
        inheritConfig: worktree.inheritConfig,
        created: Number.isFinite(worktree.created) ? worktree.created : jsDateToSwiftDate(new Date()),
        status: worktree.status,
        initStep: worktree.initStep,
        initMessage: worktree.initMessage,
        initError: worktree.initError,
        initJobId: worktree.initJobId,
        updatedAt: worktree.updatedAt,
      };

      const currentProjects = projectsRef.current;
      const nextProjects = currentProjects.map((project) => {
        if (project.id !== projectId) {
          return project;
        }
        const current = project.worktrees ?? [];
        const existingIndex = current.findIndex((item) => item.path === normalizedPath);
        if (existingIndex >= 0) {
          const worktrees = [...current];
          worktrees[existingIndex] = {
            ...worktrees[existingIndex],
            ...nextWorktree,
            baseBranch: nextWorktree.baseBranch ?? worktrees[existingIndex].baseBranch,
          };
          return { ...project, worktrees };
        }
        return { ...project, worktrees: [...current, nextWorktree] };
      });

      await commitProjects(nextProjects);
    },
    [commitProjects],
  );

  /** 删除项目 worktree 子项并持久化。 */
  const removeProjectWorktree = useCallback(
    async (projectId: string, worktreePath: string) => {
      const normalizedPath = worktreePath.trim();
      if (!projectId || !normalizedPath) {
        return;
      }

      const currentProjects = projectsRef.current;
      const nextProjects = currentProjects.map((project) => {
        if (project.id !== projectId) {
          return project;
        }
        return {
          ...project,
          worktrees: (project.worktrees ?? []).filter((item) => item.path !== normalizedPath),
        };
      });

      await commitProjects(nextProjects);
    },
    [commitProjects],
  );

  /** 根据 Git worktree 列表同步指定项目的 worktrees（一次性写盘，按 path 幂等）。 */
  const syncProjectWorktrees = useCallback(
    async (projectId: string, worktrees: Array<{ path: string; branch: string }>) => {
      if (!projectId) {
        return;
      }

      const now = jsDateToSwiftDate(new Date());
      const currentProjects = projectsRef.current;
      const projectIndex = currentProjects.findIndex((project) => project.id === projectId);
      if (projectIndex < 0) {
        return;
      }

      const project = currentProjects[projectIndex];
      const existingWorktrees = project.worktrees ?? [];
      const nextWorktrees = buildSyncedWorktrees(existingWorktrees, worktrees, now);
      if (areWorktreeListsEqual(existingWorktrees, nextWorktrees)) {
        return;
      }

      const nextProjects = [...currentProjects];
      nextProjects[projectIndex] = { ...project, worktrees: nextWorktrees };
      await commitProjects(nextProjects);
    },
    [commitProjects],
  );

  /** 添加需要扫描的工作目录并持久化。 */
  const addDirectory = useCallback(
    async (path: string) => {
      const normalizedPath = path.trim();
      if (!normalizedPath) {
        return;
      }
      await commitAppState((currentState) => {
        const nextDirectories = Array.from(new Set([...currentState.directories, normalizedPath]));
        return { ...currentState, directories: nextDirectories };
      });
    },
    [commitAppState],
  );

  /** 移除工作目录并持久化。 */
  const removeDirectory = useCallback(
    async (path: string) => {
      await commitAppState((currentState) => ({
        ...currentState,
        directories: currentState.directories.filter((item) => item !== path),
      }));
    },
    [commitAppState],
  );

  /** 将项目路径移入回收站并持久化。 */
  const moveProjectsToRecycleBin = useCallback(
    async (paths: string[]) => {
      const normalizedPaths = normalizePathList(paths);
      if (normalizedPaths.length === 0) {
        return;
      }
      await commitAppState((currentState) => ({
        ...currentState,
        recycleBin: Array.from(new Set([...currentState.recycleBin, ...normalizedPaths])),
      }));
    },
    [commitAppState],
  );

  /** 将项目路径移入回收站并持久化。 */
  const moveProjectToRecycleBin = useCallback(
    async (path: string) => {
      await moveProjectsToRecycleBin([path]);
    },
    [moveProjectsToRecycleBin],
  );

  /** 从回收站恢复项目路径并持久化。 */
  const restoreProjectFromRecycleBin = useCallback(
    async (path: string) => {
      if (!path) {
        return;
      }
      await commitAppState((currentState) => ({
        ...currentState,
        recycleBin: currentState.recycleBin.filter((item) => item !== path),
      }));
    },
    [commitAppState],
  );

  /** 切换项目收藏状态并持久化。 */
  const toggleProjectFavorite = useCallback(
    async (path: string) => {
      const normalizedPath = path.trim();
      if (!normalizedPath) {
        return;
      }

      await commitAppState((currentState) => {
        const favorites = new Set(currentState.favoriteProjectPaths ?? []);
        if (favorites.has(normalizedPath)) {
          favorites.delete(normalizedPath);
        } else {
          favorites.add(normalizedPath);
        }
        return { ...currentState, favoriteProjectPaths: Array.from(favorites) };
      });
    },
    [commitAppState],
  );

  /** 批量更新标签配置并持久化。 */
  const updateTags = useCallback(
    async (tags: TagData[]) => {
      await commitAppState((currentState) => ({ ...currentState, tags }));
    },
    [commitAppState],
  );

  /** 更新应用设置并持久化。 */
  const updateSettings = useCallback(
    async (settings: AppStateFile["settings"]) => {
      await commitAppState((currentState) => ({
        ...currentState,
        settings: normalizeSettings(settings),
      }));
    },
    [commitAppState],
  );

  /** 新建标签并自动分配颜色。 */
  const addTag = useCallback(
    async (name: string, colorHex?: string) => {
      const normalized = name.trim();
      if (!normalized) {
        return;
      }
      await commitAppState((currentState) => {
        if (currentState.tags.some((tag) => tag.name === normalized)) {
          return currentState;
        }
        return {
          ...currentState,
          tags: [
            ...currentState.tags,
            {
              name: normalized,
              color: hexToColorData(colorHex ?? pickColorForTag(normalized)),
              hidden: false,
            },
          ],
        };
      });
    },
    [commitAppState],
  );

  /** 重命名标签，同时更新项目上的标签引用。 */
  const renameTag = useCallback(
    async (from: string, to: string) => {
      const normalized = to.trim();
      if (!normalized || from === normalized) {
        return;
      }
      const currentState = appStateRef.current;
      if (currentState.tags.some((tag) => tag.name === normalized)) {
        return;
      }

      const currentProjects = projectsRef.current;
      const nextTags = currentState.tags.map((tag) =>
        tag.name === from ? { ...tag, name: normalized } : tag,
      );
      const nextProjects = currentProjects.map((project) =>
        project.tags.includes(from)
          ? { ...project, tags: project.tags.map((tag) => (tag === from ? normalized : tag)) }
          : project,
      );

      const nextState = { ...currentState, tags: nextTags };
      await commitAppStateAndProjects(nextState, nextProjects);
    },
    [commitAppStateAndProjects],
  );

  /** 删除标签并同步移除项目引用。 */
  const removeTag = useCallback(
    async (name: string) => {
      const currentState = appStateRef.current;
      const currentProjects = projectsRef.current;
      const nextTags = currentState.tags.filter((tag) => tag.name !== name);
      const nextProjects = currentProjects.map((project) => ({
        ...project,
        tags: project.tags.filter((tag) => tag !== name),
      }));
      const nextState = { ...currentState, tags: nextTags };
      await commitAppStateAndProjects(nextState, nextProjects);
    },
    [commitAppStateAndProjects],
  );

  /** 切换标签的隐藏状态。 */
  const toggleTagHidden = useCallback(
    async (name: string) => {
      await commitAppState((currentState) => ({
        ...currentState,
        tags: currentState.tags.map((tag) =>
          tag.name === name ? { ...tag, hidden: !tag.hidden } : tag,
        ),
      }));
    },
    [commitAppState],
  );

  /** 更新标签颜色配置。 */
  const setTagColor = useCallback(
    async (name: string, colorHex: string) => {
      await commitAppState((currentState) => ({
        ...currentState,
        tags: currentState.tags.map((tag) =>
          tag.name === name ? { ...tag, color: hexToColorData(colorHex) } : tag,
        ),
      }));
    },
    [commitAppState],
  );

  /** 为指定项目添加标签并同步全局标签。 */
  const addTagToProjects = useCallback(
    async (projectIds: string[], tag: string) => {
      const normalizedTag = tag.trim();
      const idSet = new Set(projectIds.map((id) => id.trim()).filter(Boolean));
      if (!normalizedTag || idSet.size === 0) {
        return;
      }
      const currentProjects = projectsRef.current;
      const currentState = appStateRef.current;
      const nextProjects = currentProjects.map((project) =>
        idSet.has(project.id) && !project.tags.includes(normalizedTag)
          ? { ...project, tags: [...project.tags, normalizedTag] }
          : project,
      );
      await commitProjects(nextProjects);
      await syncTagsFromProjects(currentState, nextProjects);
    },
    [commitProjects, syncTagsFromProjects],
  );

  /** 为指定项目添加标签并同步全局标签。 */
  const addTagToProject = useCallback(
    async (projectId: string, tag: string) => {
      await addTagToProjects([projectId], tag);
    },
    [addTagToProjects],
  );

  /** 从指定项目移除标签。 */
  const removeTagFromProject = useCallback(
    async (projectId: string, tag: string) => {
      const currentProjects = projectsRef.current;
      const nextProjects = currentProjects.map((project) =>
        project.id === projectId ? { ...project, tags: project.tags.filter((item) => item !== tag) } : project,
      );
      await commitProjects(nextProjects);
    },
    [commitProjects],
  );

  useEffect(() => {
    void refresh();
  }, [refresh]);

  return {
    appState,
    projects,
    isLoading,
    error,
    projectMap,
    refresh,
    addProjects,
    refreshProject,
    updateGitDaily,
    addProjectScript,
    updateProjectScript,
    removeProjectScript,
    addProjectWorktree,
    removeProjectWorktree,
    syncProjectWorktrees,
    addDirectory,
    removeDirectory,
    moveProjectToRecycleBin,
    moveProjectsToRecycleBin,
    restoreProjectFromRecycleBin,
    toggleProjectFavorite,
    updateSettings,
    updateTags,
    addTag,
    renameTag,
    removeTag,
    toggleTagHidden,
    setTagColor,
    addTagToProject,
    addTagToProjects,
    removeTagFromProject,
  };
}

/** 将 Hex 颜色转换为可存储的 RGBA 结构。 */
function hexToColorData(hex: string) {
  const value = hex.replace("#", "");
  if (value.length !== 6) {
    return { r: 0.3, g: 0.3, b: 0.3, a: 1 };
  }
  const r = parseInt(value.slice(0, 2), 16) / 255;
  const g = parseInt(value.slice(2, 4), 16) / 255;
  const b = parseInt(value.slice(4, 6), 16) / 255;
  return { r, g, b, a: 1 };
}

/** 按路径合并新旧项目，保留未更新的旧项目。 */
function mergeProjectsByPath(existing: Project[], updates: Project[]) {
  const updatesByPath = new Map(updates.map((project) => [project.path, project]));
  const existingPaths = new Set(existing.map((project) => project.path));
  const nextProjects = existing.map((project) => updatesByPath.get(project.path) ?? project);
  for (const project of updates) {
    if (!existingPaths.has(project.path)) {
      nextProjects.push(project);
    }
  }
  return nextProjects;
}

function buildSyncedWorktrees(
  existingWorktrees: ProjectWorktree[],
  gitWorktrees: Array<{ path: string; branch: string }>,
  now: number,
): ProjectWorktree[] {
  const normalizedGitWorktrees = normalizeGitWorktrees(gitWorktrees);
  const existingByPath = new Map(existingWorktrees.map((item) => [item.path, item]));
  return normalizedGitWorktrees.map((item) => buildSyncedWorktree(existingByPath.get(item.path), item, now));
}

function normalizeGitWorktrees(worktrees: Array<{ path: string; branch: string }>) {
  return worktrees
    .map((item) => ({ path: item.path.trim(), branch: item.branch.trim() }))
    .filter((item) => item.path && item.branch)
    .sort((left, right) => left.path.localeCompare(right.path));
}

function buildSyncedWorktree(
  existing: ProjectWorktree | undefined,
  item: { path: string; branch: string },
  now: number,
): ProjectWorktree {
  const created = Number.isFinite(existing?.created) ? (existing?.created ?? now) : now;
  return {
    id: existing?.id?.trim() || `worktree:${item.path}`,
    name: existing?.name?.trim() || resolveWorktreeName(item.path),
    path: item.path,
    branch: item.branch,
    baseBranch: existing?.baseBranch,
    inheritConfig: existing?.inheritConfig ?? true,
    created,
    status: existing?.status,
    initStep: existing?.initStep,
    initMessage: existing?.initMessage,
    initError: existing?.initError,
    initJobId: existing?.initJobId,
    updatedAt: existing?.updatedAt,
  };
}

function resolveWorktreeName(path: string): string {
  return (
    path
      .replace(/\\/g, "/")
      .replace(/\/+$/, "")
      .split("/")
      .filter(Boolean)
      .pop() || path
  );
}

function areWorktreeListsEqual(left: ProjectWorktree[], right: ProjectWorktree[]): boolean {
  if (left.length !== right.length) {
    return false;
  }
  return left.every((item, index) => isSameWorktree(item, right[index]));
}

function isSameWorktree(left: ProjectWorktree, right: ProjectWorktree): boolean {
  return (
    left.id === right.id &&
    left.name === right.name &&
    left.path === right.path &&
    left.branch === right.branch &&
    left.baseBranch === right.baseBranch &&
    left.inheritConfig === right.inheritConfig &&
    left.created === right.created &&
    left.status === right.status &&
    left.initStep === right.initStep &&
    left.initMessage === right.initMessage &&
    left.initError === right.initError &&
    left.initJobId === right.initJobId &&
    left.updatedAt === right.updatedAt
  );
}

function normalizeProject(project: Project): Project {
  return {
    ...project,
    scripts: (project.scripts ?? []).map(normalizeProjectScript),
    worktrees: project.worktrees ?? [],
  };
}

function normalizeSettings(settings: AppStateFile["settings"] | null | undefined): AppStateFile["settings"] {
  const sharedScriptsRoot = settings?.sharedScriptsRoot?.trim();
  return {
    editorOpenTool: settings?.editorOpenTool ?? emptyState.settings.editorOpenTool,
    terminalOpenTool: settings?.terminalOpenTool ?? emptyState.settings.terminalOpenTool,
    terminalUseWebglRenderer:
      settings?.terminalUseWebglRenderer ?? emptyState.settings.terminalUseWebglRenderer,
    terminalTheme: settings?.terminalTheme ?? emptyState.settings.terminalTheme,
    gitIdentities: settings?.gitIdentities ?? emptyState.settings.gitIdentities,
    projectListViewMode: settings?.projectListViewMode ?? emptyState.settings.projectListViewMode,
    sharedScriptsRoot: sharedScriptsRoot || DEFAULT_SHARED_SCRIPTS_ROOT,
  };
}

function normalizeProjectScript(script: ProjectScript): ProjectScript {
  const paramSchema = mergeScriptParamSchema(script.start ?? "", script.paramSchema, script.templateParams);
  const templateParams = buildTemplateParams(paramSchema, script.templateParams);
  return {
    id: script.id,
    name: script.name,
    start: script.start,
    paramSchema,
    templateParams,
  };
}

function normalizePathList(paths: string[] | null | undefined): string[] {
  if (!paths) {
    return [];
  }
  return Array.from(new Set(paths.map((path) => path.trim()).filter(Boolean)));
}
