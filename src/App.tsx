import { Suspense, lazy, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { confirm } from "@tauri-apps/plugin-dialog";

import Sidebar from "./components/Sidebar";
import MainContent from "./components/MainContent";
import DetailPanel from "./components/DetailPanel";
import TagEditDialog from "./components/TagEditDialog";
import DashboardModal from "./components/DashboardModal";
import SettingsModal from "./components/SettingsModal";
import GlobalSkillsModal from "./components/GlobalSkillsModal";
import RecycleBinModal from "./components/RecycleBinModal";
import InteractionLockOverlay from "./components/InteractionLockOverlay";
import CommandPalette, { type CommandPaletteItem } from "./components/CommandPalette";
import WorktreeCreateDialog, {
  type WorktreeCreateSubmitPayload,
  type WorktreeCreateSubmitResult,
} from "./components/terminal/WorktreeCreateDialog";
import { useCodexMonitor } from "./hooks/useCodexMonitor";
import type { DateFilter, GitFilter } from "./models/filters";
import { DATE_FILTER_OPTIONS, GIT_FILTER_OPTIONS } from "./models/filters";
import type { HeatmapData } from "./models/heatmap";
import { HEATMAP_CONFIG } from "./models/heatmap";
import type { TerminalQuickCommandDispatch } from "./models/quickCommands";
import type { TerminalWorkspaceSummary } from "./models/terminal";
import type { CodexAgentEvent, CodexMonitorSession, CodexSessionView } from "./models/codex";
import type { ColorData, Project, ProjectListViewMode, ProjectWorktree, TagData } from "./models/types";
import { jsDateToSwiftDate, swiftDateToJsDate } from "./models/types";
import { colorDataToHex } from "./utils/colors";
import { formatDateKey, parseGitDaily } from "./utils/gitDaily";
import { buildGitIdentitySignature } from "./utils/gitIdentity";
import { pickColorForTag } from "./utils/tagColors";
import { buildCodexProjectStatusById } from "./utils/codexProjectStatus";
import { DevHavenProvider, useDevHavenContext } from "./state/DevHavenContext";
import { useHeatmapData } from "./state/useHeatmapData";
import { copyToClipboard, sendSystemNotification } from "./services/system";
import { deleteTerminalWorkspace, listTerminalWorkspaceSummaries } from "./services/terminalWorkspace";
import { gitDeleteBranch, gitWorktreeList, gitWorktreeRemove } from "./services/gitWorktree";
import type { GitWorktreeListItem } from "./services/gitWorktree";
import { gitIsRepo } from "./services/gitManagement";
import {
  worktreeInitCreate,
  listenWorktreeInitProgress,
  type WorktreeInitProgressPayload,
} from "./services/worktreeInit";

const TerminalWorkspaceWindow = lazy(() => import("./components/terminal/TerminalWorkspaceWindow"));
const MAIN_WINDOW_LABEL = "main";

type CommandPaletteAction = CommandPaletteItem & {
  searchText: string;
  run: () => void;
};

function createWorktreeProjectId(path: string): string {
  return `worktree:${path}`;
}

function isWorktreeProject(project: Project): boolean {
  return project.id.startsWith("worktree:");
}

function parseWorktreePathFromProjectId(projectId: string): string | null {
  if (!projectId.startsWith("worktree:")) {
    return null;
  }
  return projectId.slice("worktree:".length);
}

function resolveNameFromPath(path: string): string {
  const normalized = path.replace(/\\/g, "/").replace(/\/+$/, "");
  const last = normalized.split("/").filter(Boolean).pop();
  return last || normalized || path;
}

function normalizePathForCompare(path: string): string {
  return path.trim().replace(/\\/g, "/").replace(/\/+$/, "");
}

function resolveErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function isSamePath(left: string, right: string): boolean {
  return normalizePathForCompare(left) === normalizePathForCompare(right);
}

function resolveWorktreeVirtualProjectByPath(projects: Project[], worktreePath: string): Project | null {
  const normalizedTarget = normalizePathForCompare(worktreePath);
  for (const project of projects) {
    if (isWorktreeProject(project)) {
      continue;
    }
    const worktree = (project.worktrees ?? []).find(
      (item) => normalizePathForCompare(item.path) === normalizedTarget,
    );
    if (!worktree) {
      continue;
    }
    return buildWorktreeVirtualProject(project, worktree);
  }
  return null;
}

function resolveWorktreeSourceProjectByPath(projects: Project[], worktreePath: string): Project | null {
  const normalizedTarget = normalizePathForCompare(worktreePath);
  for (const project of projects) {
    if (isWorktreeProject(project)) {
      continue;
    }
    const hasWorktree = (project.worktrees ?? []).some(
      (item) => normalizePathForCompare(item.path) === normalizedTarget,
    );
    if (hasWorktree) {
      return project;
    }
  }
  return null;
}

function buildCodexProjectMatchCandidates(
  projects: Project[],
  terminalOpenProjects: Project[],
): Project[] {
  const byId = new Map<string, Project>();

  for (const project of projects) {
    byId.set(project.id, project);
  }

  for (const project of projects) {
    if (isWorktreeProject(project)) {
      continue;
    }
    for (const worktree of project.worktrees ?? []) {
      const virtualProject = buildWorktreeVirtualProject(project, worktree);
      byId.set(virtualProject.id, virtualProject);
    }
  }

  for (const project of terminalOpenProjects) {
    byId.set(project.id, project);
  }

  return Array.from(byId.values());
}

function buildReadyWorktree(path: string, branch: string, now: number): ProjectWorktree {
  return {
    id: createWorktreeProjectId(path),
    name: resolveNameFromPath(path),
    path,
    branch,
    baseBranch: undefined,
    inheritConfig: true,
    created: now,
    status: "ready",
    initStep: "ready",
    initMessage: "已添加现有 worktree",
    initError: null,
    initJobId: null,
    updatedAt: now,
  };
}

function buildTrackedWorktreeFromGitItem(
  item: GitWorktreeListItem,
  now: number,
): ProjectWorktree {
  return {
    id: createWorktreeProjectId(item.path),
    name: resolveNameFromPath(item.path),
    path: item.path,
    branch: item.branch,
    inheritConfig: true,
    created: now,
  };
}

function buildWorktreeVirtualProject(sourceProject: Project, worktree: ProjectWorktree): Project {
  const now = jsDateToSwiftDate(new Date());
  return {
    id: createWorktreeProjectId(worktree.path),
    name: worktree.name || resolveNameFromPath(worktree.path),
    path: worktree.path,
    tags: [...(sourceProject.tags ?? [])],
    scripts: [...(sourceProject.scripts ?? [])],
    worktrees: [],
    mtime: sourceProject.mtime,
    size: sourceProject.size,
    checksum: `worktree:${worktree.path}`,
    git_commits: sourceProject.git_commits,
    git_last_commit: sourceProject.git_last_commit,
    git_daily: sourceProject.git_daily ?? null,
    created: worktree.created || now,
    checked: now,
  };
}

function matchProjectByCwd(cwd: string, projects: Project[]): Project | null {
  if (!cwd) {
    return null;
  }
  let bestMatch: Project | null = null;
  let bestLength = -1;
  for (const project of projects) {
    if (cwd.startsWith(project.path) && project.path.length > bestLength) {
      bestMatch = project;
      bestLength = project.path.length;
    }
  }
  return bestMatch;
}

function buildCodexSessionViews(sessions: CodexMonitorSession[], projects: Project[]): CodexSessionView[] {
  return sessions.map((session) => {
    const project = matchProjectByCwd(session.cwd, projects);
    return {
      ...session,
      projectId: project?.id ?? null,
      projectName: project?.name ?? null,
      projectPath: project?.path ?? null,
    };
  });
}

function shouldBlockReloadShortcut(event: KeyboardEvent): boolean {
  const key = event.key.toLowerCase();
  if (key === "f5" || event.code === "F5") {
    return true;
  }
  if (key !== "r") {
    return false;
  }

  if (!(event.metaKey || event.ctrlKey) || event.shiftKey || event.altKey) {
    return false;
  }

  const activeTarget =
    event.target instanceof Element ? event.target : document.activeElement instanceof Element ? document.activeElement : null;

  // 允许终端里的 Ctrl+R 透传给 shell（例如历史命令搜索），避免被误判成页面刷新快捷键。
  if (event.ctrlKey && !event.metaKey && activeTarget?.closest(".terminal-pane, .xterm, .xterm-helper-textarea")) {
    return false;
  }

  return true;
}

function resolveKeyboardEventTarget(event: KeyboardEvent): Element | null {
  return event.target instanceof Element
    ? event.target
    : document.activeElement instanceof Element
      ? document.activeElement
      : null;
}

/** 应用主布局，负责筛选、状态联动与面板展示。 */
function AppLayout() {
  const {
    appState,
    projects,
    projectMap,
    isLoading,
    error,
    refresh,
    addDirectory,
    removeDirectory,
    addProjects,
    addTag,
    renameTag,
    removeTag,
    toggleTagHidden,
    setTagColor,
    addTagToProject,
    addTagToProjects,
    removeTagFromProject,
    addProjectScript,
    updateProjectScript,
    removeProjectScript,
    addProjectWorktree,
    removeProjectWorktree,
    syncProjectWorktrees,
    refreshProject,
    updateGitDaily,
    updateSettings,
    moveProjectToRecycleBin,
    moveProjectsToRecycleBin,
    restoreProjectFromRecycleBin,
    toggleProjectFavorite,
  } = useDevHavenContext();

  const [searchText, setSearchText] = useState("");
  const [dateFilter, setDateFilter] = useState<DateFilter>("all");
  const [gitFilter, setGitFilter] = useState<GitFilter>("all");
  const [selectedTags, setSelectedTags] = useState<Set<string>>(new Set());
  const [selectedDirectory, setSelectedDirectory] = useState<string | null>(null);
  const [selectedProjects, setSelectedProjects] = useState<Set<string>>(new Set());
  const [selectedProjectId, setSelectedProjectId] = useState<string | null>(null);
  const [showDetailPanel, setShowDetailPanel] = useState(false);
  const [toast, setToast] = useState<{ message: string; variant: "success" | "error" } | null>(null);
  const [heatmapFilteredProjectIds, setHeatmapFilteredProjectIds] = useState<Set<string>>(new Set());
  const [heatmapSelectedDateKey, setHeatmapSelectedDateKey] = useState<string | null>(null);
  const [tagDialogState, setTagDialogState] = useState<{ mode: "new" | "edit"; tag?: TagData } | null>(
    null,
  );
  const [showDashboard, setShowDashboard] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [showGlobalSkills, setShowGlobalSkills] = useState(false);
  const [showRecycleBin, setShowRecycleBin] = useState(false);
  const [showTerminalWorkspace, setShowTerminalWorkspace] = useState(false);
  const [isCommandPaletteOpen, setIsCommandPaletteOpen] = useState(false);
  const [commandPaletteQuery, setCommandPaletteQuery] = useState("");
  const [commandPaletteActiveIndex, setCommandPaletteActiveIndex] = useState(0);
  const [terminalOpenProjects, setTerminalOpenProjects] = useState<Project[]>([]);
  const [terminalActiveProjectId, setTerminalActiveProjectId] = useState<string | null>(null);
  const [terminalQuickCommandDispatch, setTerminalQuickCommandDispatch] =
    useState<TerminalQuickCommandDispatch | null>(null);
  const [terminalGitWorktreesByProjectId, setTerminalGitWorktreesByProjectId] = useState<
    Record<string, GitWorktreeListItem[]>
  >({});
  const [worktreeDialogProjectId, setWorktreeDialogProjectId] = useState<string | null>(null);
  const openCommandPalette = useCallback(() => {
    if (showTerminalWorkspace) {
      return;
    }
    setCommandPaletteQuery("");
    setCommandPaletteActiveIndex(0);
    setIsCommandPaletteOpen(true);
  }, [showTerminalWorkspace]);
  const closeCommandPalette = useCallback(() => {
    setIsCommandPaletteOpen(false);
    setCommandPaletteQuery("");
    setCommandPaletteActiveIndex(0);
  }, []);

  useEffect(() => {
    if (!import.meta.env.PROD || typeof window === "undefined") {
      return;
    }

    // 生产环境阻断原生右键刷新入口与刷新快捷键，避免页面重载导致会话状态丢失。
    const handleContextMenu = (event: MouseEvent) => {
      event.preventDefault();
    };

    const handleKeyDown = (event: KeyboardEvent) => {
      if (!shouldBlockReloadShortcut(event)) {
        return;
      }
      event.preventDefault();
      event.stopPropagation();
    };

    window.addEventListener("contextmenu", handleContextMenu, true);
    window.addEventListener("keydown", handleKeyDown, true);
    return () => {
      window.removeEventListener("contextmenu", handleContextMenu, true);
      window.removeEventListener("keydown", handleKeyDown, true);
    };
  }, []);

  useEffect(() => {
    if (typeof window === "undefined") {
      return;
    }

    const handleOpenCommandPalette = (event: KeyboardEvent) => {
      if (event.key.toLowerCase() !== "k") {
        return;
      }
      if (!(event.metaKey || event.ctrlKey) || event.shiftKey || event.altKey) {
        return;
      }

      const activeTarget = resolveKeyboardEventTarget(event);
      if (activeTarget?.closest(".terminal-pane, .xterm, .xterm-helper-textarea")) {
        return;
      }

      event.preventDefault();
      event.stopPropagation();
      if (!isCommandPaletteOpen) {
        openCommandPalette();
      }
    };

    window.addEventListener("keydown", handleOpenCommandPalette, true);
    return () => {
      window.removeEventListener("keydown", handleOpenCommandPalette, true);
    };
  }, [isCommandPaletteOpen, openCommandPalette]);

  useEffect(() => {
    if (isCommandPaletteOpen && showTerminalWorkspace) {
      closeCommandPalette();
    }
  }, [closeCommandPalette, isCommandPaletteOpen, showTerminalWorkspace]);

  const searchInputRef = useRef<HTMLInputElement>(null);
  const lastTerminalVisibleRef = useRef(showTerminalWorkspace);
  const terminalOpenProjectsRef = useRef<Project[]>(terminalOpenProjects);
  const terminalActiveProjectIdRef = useRef<string | null>(terminalActiveProjectId);
  const terminalQuickCommandDispatchSeqRef = useRef(0);
  const terminalGitWorktreesByProjectIdRef = useRef<Record<string, GitWorktreeListItem[]>>(terminalGitWorktreesByProjectId);
  const terminalRestoreCheckedRef = useRef(false);
  const worktreeAutoSyncedProjectIdsRef = useRef<Set<string>>(new Set());
  const worktreeSyncingProjectIdsRef = useRef<Set<string>>(new Set());
  const worktreeRecoveryCheckedProjectIdsRef = useRef<Set<string>>(new Set());
  const toastTimerRef = useRef<number | null>(null);
  const gitDailyRefreshRef = useRef<string | null>(null);
  const gitDailyUpdatingRef = useRef(false);
  const gitIdentitySignatureRef = useRef<string | null>(null);
  const worktreeInitAutoOpenByJobIdRef = useRef<
    Map<string, { projectId: string; worktreePath: string; branch: string; autoOpen: boolean }>
  >(new Map());
  const worktreeInitAutoOpenPendingByProjectBranchRef = useRef<Map<string, { autoOpen: boolean }>>(new Map());
  const worktreeInitProgressSeenByProjectBranchRef = useRef<Set<string>>(new Set());
  const codexEventSnapshotRef = useRef<Set<string>>(new Set());
  const recycleBinPaths = appState.recycleBin ?? [];
  const recycleBinSet = useMemo(() => new Set(recycleBinPaths), [recycleBinPaths]);
  const favoriteProjectPathSet = useMemo(
    () => new Set(appState.favoriteProjectPaths ?? []),
    [appState.favoriteProjectPaths],
  );
  const recycleBinCount = recycleBinPaths.length;
  const visibleProjects = useMemo(
    () => projects.filter((project) => !recycleBinSet.has(project.path)),
    [projects, recycleBinSet],
  );
  const recycleBinItems = useMemo(() => {
    const projectsByPath = new Map(projects.map((project) => [project.path, project]));
    return recycleBinPaths.map((path) => {
      const project = projectsByPath.get(path);
      return {
        path,
        name: project?.name ?? path.split("/").pop() ?? path,
        missing: !project,
      };
    });
  }, [projects, recycleBinPaths]);
  const heatmapStore = useHeatmapData(visibleProjects, appState.settings.gitIdentities);
  const sidebarHeatmapData = useMemo(
    () => heatmapStore.getHeatmapData(HEATMAP_CONFIG.sidebar.days),
    [heatmapStore],
  );
  const codexMonitorStore = useCodexMonitor();
  const codexProjectMatchCandidates = useMemo(
    () => buildCodexProjectMatchCandidates(projects, terminalOpenProjects),
    [projects, terminalOpenProjects],
  );
  const codexSessionViews = useMemo(
    () => buildCodexSessionViews(codexMonitorStore.sessions, codexProjectMatchCandidates),
    [codexMonitorStore.sessions, codexProjectMatchCandidates],
  );
  const codexProjectStatusById = useMemo(
    () => buildCodexProjectStatusById(codexSessionViews),
    [codexSessionViews],
  );
  const worktreeDialogSourceProject = useMemo(() => {
    if (!worktreeDialogProjectId) {
      return null;
    }
    return projectMap.get(worktreeDialogProjectId) ?? null;
  }, [projectMap, worktreeDialogProjectId]);

  const resolveProjectFromCodexProjectId = useCallback(
    (projectId: string): Project | null => {
      const worktreePath = parseWorktreePathFromProjectId(projectId);
      if (worktreePath) {
        return resolveWorktreeVirtualProjectByPath(projects, worktreePath);
      }
      return projectMap.get(projectId) ?? null;
    },
    [projectMap, projects],
  );

  const resolveProjectFromCodexEvent = useCallback(
    (event: CodexAgentEvent): Project | null => {
      const bySession =
        event.sessionId
          ? codexSessionViews.find((session) => session.id === event.sessionId && session.projectId)
          : null;
      if (bySession?.projectId) {
        const resolved = resolveProjectFromCodexProjectId(bySession.projectId);
        if (resolved) {
          return resolved;
        }
      }

      if (event.workingDirectory) {
        return matchProjectByCwd(event.workingDirectory, codexProjectMatchCandidates);
      }

      return null;
    },
    [codexProjectMatchCandidates, codexSessionViews, resolveProjectFromCodexProjectId],
  );

  const hiddenTags = useMemo(
    () => new Set(appState.tags.filter((tag) => tag.hidden).map((tag) => tag.name)),
    [appState.tags],
  );
  const projectListViewMode: ProjectListViewMode =
    appState.settings.projectListViewMode ?? "card";

  useEffect(() => {
    if (!worktreeDialogProjectId) {
      return;
    }
    if (!projectMap.has(worktreeDialogProjectId)) {
      setWorktreeDialogProjectId(null);
    }
  }, [projectMap, worktreeDialogProjectId]);

  const filteredProjects = useMemo(() => {
    let result = [...visibleProjects];

    if (selectedDirectory) {
      result = result.filter((project) => project.path.startsWith(selectedDirectory));
    }

    result = result.filter((project) => {
      const projectHiddenTags = project.tags.filter((tag) => hiddenTags.has(tag));
      if (projectHiddenTags.length === 0) {
        return true;
      }
      if (selectedTags.size > 0 && !selectedTags.has("全部")) {
        return Array.from(selectedTags).some((tag) => projectHiddenTags.includes(tag));
      }
      return false;
    });

    if (heatmapFilteredProjectIds.size > 0) {
      result = result.filter((project) => heatmapFilteredProjectIds.has(project.id));
    } else if (selectedTags.size > 0) {
      if (!selectedTags.has("全部")) {
        const selectedTagList = Array.from(selectedTags);
        result = result.filter((project) => selectedTagList.every((tag) => project.tags.includes(tag)));
      }
    }

    const trimmedSearch = searchText.trim().toLowerCase();
    if (trimmedSearch) {
      result = result.filter(
        (project) =>
          project.name.toLowerCase().includes(trimmedSearch) || project.path.toLowerCase().includes(trimmedSearch),
      );
    }

    const dateOption = DATE_FILTER_OPTIONS.find((option) => option.value === dateFilter);
    if (dateOption?.days) {
      const cutoff = Date.now() - dateOption.days * 24 * 60 * 60 * 1000;
      result = result.filter((project) => swiftDateToJsDate(project.mtime).getTime() >= cutoff);
    }

    if (gitFilter === "gitOnly") {
      result = result.filter((project) => (project.git_commits ?? 0) > 0);
    } else if (gitFilter === "nonGitOnly") {
      result = result.filter((project) => (project.git_commits ?? 0) === 0);
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
    visibleProjects,
    selectedDirectory,
    selectedTags,
    heatmapFilteredProjectIds,
    searchText,
    dateFilter,
    gitFilter,
    hiddenTags,
    favoriteProjectPathSet,
  ]);

  const selectedProject = selectedProjectId ? projectMap.get(selectedProjectId) ?? null : null;
  const resolvedSelectedProject =
    selectedProject && recycleBinSet.has(selectedProject.path) ? null : selectedProject;

  const handleSelectTag = useCallback((tag: string) => {
    if (tag === "全部") {
      setSelectedTags(new Set());
      return;
    }
    setSelectedTags(new Set([tag]));
  }, []);

  const handleSelectProject = useCallback((project: { id: string }, event: React.MouseEvent<HTMLDivElement>) => {
    const isMulti = event.shiftKey || event.metaKey || event.ctrlKey;
    setSelectedProjects((prev) => {
      const next = new Set(prev);
      if (isMulti) {
        if (next.has(project.id)) {
          next.delete(project.id);
        } else {
          next.add(project.id);
        }
      } else {
        next.clear();
        next.add(project.id);
      }
      return next;
    });
    setSelectedProjectId(project.id);
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

  const handleSelectDirectory = useCallback(
    (directory: string | null) => {
      setSelectedDirectory(directory);
    },
    [],
  );

  const heatmapActiveProjects = useMemo(() => {
    if (!heatmapSelectedDateKey) {
      return [];
    }
    return visibleProjects
      .map((project) => ({
        projectId: project.id,
        projectName: project.name,
        projectPath: project.path,
        commitCount: parseGitDaily(project.git_daily)[heatmapSelectedDateKey] ?? 0,
      }))
      .filter((item) => item.commitCount > 0)
      .sort((left, right) => {
        if (left.commitCount !== right.commitCount) {
          return right.commitCount - left.commitCount;
        }
        return left.projectName.localeCompare(right.projectName);
      });
  }, [heatmapSelectedDateKey, visibleProjects]);

  const handleLocateHeatmapProject = useCallback((projectId: string) => {
    setSelectedProjects(new Set([projectId]));
    setSelectedProjectId(projectId);
    setShowDetailPanel(true);
  }, []);

  const handleToggleDetail = useCallback(() => {
    setShowDetailPanel((prev) => {
      const next = !prev;
      if (next && !selectedProjectId && selectedProjects.size > 0) {
        setSelectedProjectId(Array.from(selectedProjects)[0]);
      }
      return next;
    });
  }, [selectedProjectId, selectedProjects]);

  const handleAssignTagToProjects = useCallback(
    async (tag: string, projectIds: string[]) => {
      await addTagToProjects(projectIds, tag);
      setSelectedTags(new Set());
    },
    [addTagToProjects],
  );

  const handleOpenTagEditor = useCallback((tag?: TagData) => {
    setTagDialogState({ mode: tag ? "edit" : "new", tag });
  }, []);

  const showToast = useCallback((message: string, variant: "success" | "error" = "success") => {
    setToast({ message, variant });
    if (toastTimerRef.current) {
      window.clearTimeout(toastTimerRef.current);
    }
    toastTimerRef.current = window.setTimeout(() => {
      setToast(null);
      toastTimerRef.current = null;
    }, 1600);
  }, []);

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
    [moveProjectToRecycleBin, showToast],
  );

  const handleClearSelectedProjects = useCallback(() => {
    setSelectedProjects(new Set());
    setSelectedProjectId(null);
  }, []);

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
    [moveProjectsToRecycleBin, projectMap, showToast],
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
    [addTagToProjects, projectMap, showToast],
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
    return () => {
      if (toastTimerRef.current) {
        window.clearTimeout(toastTimerRef.current);
      }
    };
  }, []);

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
    [addTag, renameTag, setTagColor, tagDialogState],
  );

  /** 获取标签对应的显示颜色。 */
  const getTagColor = useCallback(
    (tagName: string) => {
      const tag = appState.tags.find((item) => item.name === tagName);
      if (tag) {
        return colorDataToHex(tag.color, pickColorForTag(tagName));
      }
      return pickColorForTag(tagName);
    },
    [appState.tags],
  );

  /** 将颜色结构转换为 Hex 字符串，供颜色选择器使用。 */
  const getTagHex = (color?: ColorData) => {
    if (!color) {
      return "#4d4d4d";
    }
    const toHex = (value: number) => Math.round(value * 255).toString(16).padStart(2, "0");
    return `#${toHex(color.r)}${toHex(color.g)}${toHex(color.b)}`;
  };

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

  const openTerminalWorkspace = useCallback(
    (project: Project) => {
      setShowTerminalWorkspace(true);
      setTerminalOpenProjects((prev) => {
        let next = prev;
        const ensureMutable = () => {
          if (next === prev) {
            next = [...next];
          }
        };
        const upsert = (item: Project) => {
          const index = next.findIndex((existing) => existing.id === item.id);
          ensureMutable();
          if (index >= 0) {
            next[index] = item;
          } else {
            next.push(item);
          }
        };

        if (isWorktreeProject(project)) {
          const sourceProject = resolveWorktreeSourceProjectByPath(projects, project.path);
          if (sourceProject) {
            upsert(sourceProject);
          }
        }

        upsert(project);

        return next;
      });
      setTerminalActiveProjectId(project.id);
    },
    [projects],
  );

  const dispatchTerminalQuickCommand = useCallback(
    (action: Omit<TerminalQuickCommandDispatch, "seq">) => {
      const seq = terminalQuickCommandDispatchSeqRef.current + 1;
      terminalQuickCommandDispatchSeqRef.current = seq;
      setTerminalQuickCommandDispatch({ ...action, seq });
    },
    [],
  );

  const handleRunProjectScript = useCallback(
    async (projectId: string, scriptId: string) => {
      const project = projectMap.get(projectId);
      if (!project) {
        showToast("项目不存在或已移除", "error");
        return;
      }
      const script = (project.scripts ?? []).find((item) => item.id === scriptId);
      if (!script) {
        showToast("命令不存在或已被删除", "error");
        return;
      }

      openTerminalWorkspace(project);
      dispatchTerminalQuickCommand({
        type: "run",
        projectId: project.id,
        projectPath: project.path,
        scriptId,
      });
    },
    [dispatchTerminalQuickCommand, projectMap, openTerminalWorkspace, showToast],
  );

  const handleStopProjectScript = useCallback(
    async (projectId: string, scriptId: string) => {
      const project = projectMap.get(projectId);
      if (!project) {
        showToast("项目不存在或已移除", "error");
        return;
      }
      const script = (project.scripts ?? []).find((item) => item.id === scriptId);
      if (!script) {
        showToast("命令不存在或已被删除", "error");
        return;
      }

      openTerminalWorkspace(project);
      dispatchTerminalQuickCommand({
        type: "stop",
        projectId: project.id,
        projectPath: project.path,
        scriptId,
      });
    },
    [dispatchTerminalQuickCommand, projectMap, openTerminalWorkspace, showToast],
  );

  const handleOpenTerminal = useCallback(
    (project: Project) => {
      openTerminalWorkspace(project);
    },
    [openTerminalWorkspace],
  );

  const handleRequestCreateWorktree = useCallback(
    async (projectId: string) => {
      const sourceProject = projectMap.get(projectId);
      if (!sourceProject) {
        showToast("项目不存在或已移除", "error");
        return;
      }
      try {
        const isRepo = await gitIsRepo(sourceProject.path);
        if (!isRepo) {
          showToast("该项目不是 Git 仓库，无法创建 worktree", "error");
          return;
        }
        setWorktreeDialogProjectId(projectId);
      } catch (error) {
        console.error("校验 Git 仓库失败。", error);
        showToast("无法校验项目 Git 状态，请重试", "error");
      }
    },
    [projectMap, showToast],
  );

  const handleOpenWorktreeFromProject = useCallback(
    async (projectId: string, worktreePath: string) => {
      const sourceProject = projectMap.get(projectId);
      if (!sourceProject) {
        showToast("项目不存在或已移除", "error");
        return;
      }
      const normalizedPath = worktreePath.trim();
      const worktree = (sourceProject.worktrees ?? []).find((item) => item.path === normalizedPath);
      if (!worktree) {
        // worktree 列表以 Git 为准：当记录未同步时，尝试从缓存/仓库读取并补录。
        const cached = terminalGitWorktreesByProjectIdRef.current[projectId];
        const cachedMatch = cached?.find(
          (item) => normalizePathForCompare(item.path) === normalizePathForCompare(normalizedPath),
        );
        try {
          const gitItems = cached ?? (await gitWorktreeList(sourceProject.path));
          setTerminalGitWorktreesByProjectId((prev) => ({ ...prev, [projectId]: gitItems }));
          await syncProjectWorktrees(projectId, gitItems);

          const match =
            cachedMatch ??
            gitItems.find((item) => normalizePathForCompare(item.path) === normalizePathForCompare(normalizedPath));
          if (!match) {
            showToast("worktree 不存在或已移除", "error");
            return;
          }

          openTerminalWorkspace(
            buildWorktreeVirtualProject(sourceProject, {
              id: createWorktreeProjectId(match.path),
              name: resolveNameFromPath(match.path),
              path: match.path,
              branch: match.branch,
              inheritConfig: true,
              created: jsDateToSwiftDate(new Date()),
            }),
          );
          return;
        } catch (error) {
          console.error("打开 worktree 失败。", error);
          const message = error instanceof Error ? error.message : String(error);
          showToast(message || "打开 worktree 失败", "error");
          return;
        }
      }
      if (worktree.status === "creating") {
        showToast("该 worktree 正在创建中，请稍候", "error");
        return;
      }
      if (worktree.status === "failed") {
        showToast(worktree.initError || "该 worktree 创建失败，请先重试", "error");
        return;
      }
      openTerminalWorkspace(buildWorktreeVirtualProject(sourceProject, worktree));
    },
    [openTerminalWorkspace, projectMap, showToast, syncProjectWorktrees],
  );

  const handleCreateWorktree = useCallback(
    async (payload: WorktreeCreateSubmitPayload): Promise<WorktreeCreateSubmitResult> => {
      const sourceProject = projectMap.get(payload.sourceProjectId);
      if (!sourceProject) {
        throw new Error("项目不存在或已移除");
      }

      try {
        if (payload.mode === "create") {
          const key = `${sourceProject.id}|${payload.branch}`;
          worktreeInitAutoOpenPendingByProjectBranchRef.current.set(key, { autoOpen: payload.autoOpen });
          try {
            const created = await worktreeInitCreate({
              projectId: sourceProject.id,
              projectPath: payload.sourceProjectPath,
              branch: payload.branch,
              createBranch: payload.createBranch,
              baseBranch: payload.baseBranch,
            });

            // 任务入队后立即关闭弹窗；后续成功/失败提示由 worktree-init-progress 事件驱动。
            setWorktreeDialogProjectId(null);

            return {
              mode: "create",
              jobId: created.jobId,
              worktreePath: created.worktreePath,
              branch: created.branch,
              baseBranch: created.baseBranch,
            };
          } catch (error) {
            worktreeInitAutoOpenPendingByProjectBranchRef.current.delete(key);
            worktreeInitProgressSeenByProjectBranchRef.current.delete(key);
            throw error;
          }
        }

        const now = jsDateToSwiftDate(new Date());
        const nextWorktree = buildReadyWorktree(payload.worktreePath, payload.branch, now);

        await addProjectWorktree(sourceProject.id, nextWorktree);
        // 若当前已加载 Git worktree 列表，则同步更新缓存，避免列表显示旧数据。
        setTerminalGitWorktreesByProjectId((prev) => {
          if (!(sourceProject.id in prev)) {
            return prev;
          }
          const current = prev[sourceProject.id] ?? [];
          if (current.some((item) => isSamePath(item.path, payload.worktreePath))) {
            return prev;
          }
          const next = [...current, { path: payload.worktreePath, branch: payload.branch }].sort((left, right) =>
            left.path.localeCompare(right.path),
          );
          return { ...prev, [sourceProject.id]: next };
        });
        setWorktreeDialogProjectId(null);
        showToast("已有 worktree 已添加");

        if (payload.autoOpen) {
          openTerminalWorkspace(buildWorktreeVirtualProject(sourceProject, nextWorktree));
        }

        return {
          mode: "open-existing",
        };
      } catch (error) {
        // 创建任务场景下，失败 toast 通常由 worktree-init-progress 事件驱动；
        // 这里避免重复提示。
        if (payload.mode !== "create") {
          showToast(resolveErrorMessage(error) || "创建 worktree 失败", "error");
        }
        throw error;
      }
    },
    [addProjectWorktree, openTerminalWorkspace, projectMap, showToast, worktreeInitCreate],
  );

  useEffect(() => {
    for (const project of projects) {
      if (isWorktreeProject(project)) {
        continue;
      }
      if (worktreeRecoveryCheckedProjectIdsRef.current.has(project.id)) {
        continue;
      }

      const pendingWorktrees = (project.worktrees ?? []).filter(
        (item) => item.status === "creating",
      );
      if (pendingWorktrees.length === 0) {
        continue;
      }

      worktreeRecoveryCheckedProjectIdsRef.current.add(project.id);
      void (async () => {
        let gitItems: GitWorktreeListItem[] = [];
        try {
          gitItems = await gitWorktreeList(project.path);
        } catch (error) {
          console.warn("恢复 worktree 创建状态时读取 Git 列表失败。", error);
        }
        const gitPathSet = new Set(
          gitItems.map((item) => normalizePathForCompare(item.path)),
        );

        for (const item of pendingWorktrees) {
          const existsInGit = gitPathSet.has(normalizePathForCompare(item.path));
          const now = jsDateToSwiftDate(new Date());
          await addProjectWorktree(project.id, {
            ...item,
            status: existsInGit ? "ready" : "failed",
            initStep: existsInGit ? "ready" : "failed",
            initMessage: existsInGit
              ? "检测到该 worktree 已创建完成"
              : "创建进度中断，请点击“重试”继续",
            initError: existsInGit ? null : "创建任务在应用重启后中断",
            updatedAt: now,
          });
        }
      })();
    }
  }, [addProjectWorktree, projects]);

  useEffect(() => {
    if (isLoading || terminalRestoreCheckedRef.current) {
      return;
    }

    terminalRestoreCheckedRef.current = true;
    if (terminalOpenProjectsRef.current.length > 0) {
      return;
    }

    let cancelled = false;

    void (async () => {
      let summaries: TerminalWorkspaceSummary[] = [];
      try {
        summaries = await listTerminalWorkspaceSummaries();
      } catch (error) {
        console.error("读取终端工作区列表失败。", error);
        return;
      }

      if (cancelled || summaries.length === 0) {
        return;
      }

      const restoredProjects: Project[] = [];
      const openedProjectIds = new Set<string>();
      let restoredActiveProjectId: string | null = null;
      let latestUpdatedAt = Number.NEGATIVE_INFINITY;

      const pushProject = (project: Project) => {
        if (openedProjectIds.has(project.id)) {
          return;
        }
        openedProjectIds.add(project.id);
        restoredProjects.push(project);
      };

      for (const summary of summaries) {
        const rootProject = projects.find(
          (item) => !isWorktreeProject(item) && isSamePath(item.path, summary.projectPath),
        );

        if (rootProject) {
          pushProject(rootProject);
          if ((summary.updatedAt ?? Number.NEGATIVE_INFINITY) >= latestUpdatedAt) {
            latestUpdatedAt = summary.updatedAt ?? Number.NEGATIVE_INFINITY;
            restoredActiveProjectId = rootProject.id;
          }
          continue;
        }

        const sourceProject = resolveWorktreeSourceProjectByPath(projects, summary.projectPath);
        const worktreeProject = resolveWorktreeVirtualProjectByPath(projects, summary.projectPath);
        if (!sourceProject || !worktreeProject) {
          continue;
        }

        pushProject(sourceProject);
        pushProject(worktreeProject);

        if ((summary.updatedAt ?? Number.NEGATIVE_INFINITY) >= latestUpdatedAt) {
          latestUpdatedAt = summary.updatedAt ?? Number.NEGATIVE_INFINITY;
          restoredActiveProjectId = worktreeProject.id;
        }
      }

      if (cancelled || restoredProjects.length === 0) {
        return;
      }

      setTerminalOpenProjects(restoredProjects);
      setTerminalActiveProjectId(restoredActiveProjectId ?? restoredProjects[0].id);
    })();

    return () => {
      cancelled = true;
    };
  }, [isLoading, projects]);

  useEffect(() => {
    setTerminalOpenProjects((prev) =>
      prev.map((project) => {
        if (isWorktreeProject(project)) {
          return project;
        }
        return projectMap.get(project.id) ?? project;
      }),
    );
  }, [projectMap]);

  const handleCloseTerminalProject = useCallback(
    (projectId: string) => {
      const currentProjects = terminalOpenProjectsRef.current;
      const closingProject = currentProjects.find((item) => item.id === projectId);
      if (!closingProject) {
        return;
      }

      const closingPaths = new Set<string>([closingProject.path]);
      if (!isWorktreeProject(closingProject)) {
        for (const item of closingProject.worktrees ?? []) {
          closingPaths.add(item.path);
        }
      }

      const nextProjects = currentProjects.filter((item) => !closingPaths.has(item.path));
      setTerminalOpenProjects(nextProjects);

      if (nextProjects.length === 0) {
        setTerminalActiveProjectId(null);
        setShowTerminalWorkspace(false);
      } else {
        const currentActive = terminalActiveProjectIdRef.current;
        const nextActive =
          currentActive === projectId || !currentActive || !nextProjects.some((item) => item.id === currentActive)
            ? nextProjects[0].id
            : currentActive;
        setTerminalActiveProjectId(nextActive);
      }

      // 先卸载终端 pane（清理 PTY/定时保存），再异步删除持久化工作区，避免竞态把 workspace 又写回去。
      window.setTimeout(() => {
        void Promise.all(Array.from(closingPaths).map((path) => deleteTerminalWorkspace(path))).catch((error) => {
          console.error("删除终端工作区失败。", error);
          showToast("关闭项目失败，请重试", "error");
        });
      }, 0);
    },
    [showToast],
  );

  const syncTerminalProjectWorktrees = useCallback(
    async (projectId: string, options?: { showToast?: boolean }) => {
      const sourceProject = projectMap.get(projectId);
      if (!sourceProject) {
        if (options?.showToast) {
          showToast("项目不存在或已移除", "error");
        }
        return;
      }

      if (worktreeSyncingProjectIdsRef.current.has(projectId)) {
        return;
      }
      worktreeSyncingProjectIdsRef.current.add(projectId);

      try {
        let gitItems: GitWorktreeListItem[] | null = null;
        try {
          gitItems = await gitWorktreeList(sourceProject.path);
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          // 非 Git 项目：同步为空列表，避免保留过期记录。
          if (message.includes("不是 Git 仓库")) {
            gitItems = [];
          } else {
            if (options?.showToast) {
              showToast(message || "同步 worktree 失败", "error");
            }
            console.error("同步 worktree 失败。", error);
            return;
          }
        }

        setTerminalGitWorktreesByProjectId((prev) => ({ ...prev, [projectId]: gitItems ?? [] }));

        const trackedWorktrees = sourceProject.worktrees ?? [];
        const trackedByPath = new Map(trackedWorktrees.map((item) => [normalizePathForCompare(item.path), item]));

        const gitPathSet = new Set((gitItems ?? []).map((item) => normalizePathForCompare(item.path)));
        const trackedPathSet = new Set(trackedWorktrees.map((item) => normalizePathForCompare(item.path)));

        const removedPaths = trackedWorktrees
          .map((item) => normalizePathForCompare(item.path))
          .filter((path) => path && !gitPathSet.has(path));

        // 若 worktree 已在 Git 中移除，但仍在终端里打开，先关闭避免“幽灵项目”无法再从列表操作。
        for (const removedPath of removedPaths) {
          const opened = terminalOpenProjectsRef.current.find(
            (item) => isWorktreeProject(item) && normalizePathForCompare(item.path) === removedPath,
          );
          if (opened) {
            handleCloseTerminalProject(opened.id);
          }
        }

        const addedCount = Array.from(gitPathSet).filter((path) => !trackedPathSet.has(path)).length;
        const removedCount = removedPaths.length;
        const updatedCount = (gitItems ?? []).reduce((count, item) => {
          const tracked = trackedByPath.get(normalizePathForCompare(item.path));
          return tracked && tracked.branch !== item.branch ? count + 1 : count;
        }, 0);

        await syncProjectWorktrees(projectId, gitItems ?? []);

        if (options?.showToast) {
          if (addedCount === 0 && removedCount === 0 && updatedCount === 0) {
            showToast("worktree 已是最新", "success");
          } else {
            showToast(`已同步 worktree：新增 ${addedCount} · 移除 ${removedCount} · 更新 ${updatedCount}`, "success");
          }
        }
      } finally {
        worktreeSyncingProjectIdsRef.current.delete(projectId);
      }
    },
    [handleCloseTerminalProject, projectMap, showToast, syncProjectWorktrees],
  );

  const removeWorktreeFromGitCache = useCallback((projectId: string, worktreePath: string) => {
    setTerminalGitWorktreesByProjectId((prev) => {
      const current = prev[projectId];
      if (!current) {
        return prev;
      }
      const next = current.filter((item) => !isSamePath(item.path, worktreePath));
      return { ...prev, [projectId]: next };
    });
  }, []);

  const handleWorktreeInitProgress = useCallback(
    async (payload: WorktreeInitProgressPayload) => {
      const sourceProject = projectMap.get(payload.projectId);
      if (!sourceProject) {
        return;
      }

      const autoOpenKey = `${payload.projectId}|${payload.branch}`;
      worktreeInitProgressSeenByProjectBranchRef.current.add(autoOpenKey);
      const pendingAutoOpenByBranch = worktreeInitAutoOpenPendingByProjectBranchRef.current.get(autoOpenKey);
      if (pendingAutoOpenByBranch && !worktreeInitAutoOpenByJobIdRef.current.has(payload.jobId)) {
        worktreeInitAutoOpenPendingByProjectBranchRef.current.delete(autoOpenKey);
        worktreeInitAutoOpenByJobIdRef.current.set(payload.jobId, {
          projectId: payload.projectId,
          worktreePath: payload.worktreePath,
          branch: payload.branch,
          autoOpen: pendingAutoOpenByBranch.autoOpen,
        });
      }

      const normalizedPath = normalizePathForCompare(payload.worktreePath);
      const existing = (sourceProject.worktrees ?? []).find(
        (item) => normalizePathForCompare(item.path) === normalizedPath,
      );

      if (payload.step === "cancelled") {
        worktreeInitAutoOpenPendingByProjectBranchRef.current.delete(autoOpenKey);
        worktreeInitAutoOpenByJobIdRef.current.delete(payload.jobId);
        await removeProjectWorktree(sourceProject.id, payload.worktreePath);
        removeWorktreeFromGitCache(sourceProject.id, payload.worktreePath);
        showToast("worktree 创建已取消");
        return;
      }

      const now = jsDateToSwiftDate(new Date());
      const status =
        payload.step === "failed"
          ? "failed"
          : payload.step === "ready"
            ? "ready"
            : "creating";

      const nextWorktree: ProjectWorktree = {
        id: existing?.id ?? createWorktreeProjectId(payload.worktreePath),
        name: existing?.name ?? resolveNameFromPath(payload.worktreePath),
        path: payload.worktreePath,
        branch: payload.branch,
        baseBranch: existing?.baseBranch ?? payload.baseBranch,
        inheritConfig: existing?.inheritConfig ?? true,
        created: existing?.created ?? now,
        status,
        initStep: payload.step,
        initMessage: payload.message,
        initError: payload.step === "failed" ? (payload.error ?? payload.message) : (payload.error ?? null),
        initJobId: payload.jobId,
        updatedAt: now,
      };

      await addProjectWorktree(sourceProject.id, nextWorktree);

      if (payload.step === "failed") {
        worktreeInitAutoOpenPendingByProjectBranchRef.current.delete(autoOpenKey);
        worktreeInitAutoOpenByJobIdRef.current.delete(payload.jobId);
        showToast(nextWorktree.initError || "worktree 创建失败", "error");
        return;
      }

      if (payload.step !== "ready") {
        return;
      }

      const pendingAutoOpen = worktreeInitAutoOpenByJobIdRef.current.get(payload.jobId);
      worktreeInitAutoOpenByJobIdRef.current.delete(payload.jobId);

      await syncTerminalProjectWorktrees(sourceProject.id).catch((error) => {
        console.error("同步 worktree 失败。", error);
      });

      // 创建成功后再次写入 ready 状态，规避并发同步时被旧快照回写为 creating。
      const hasSetupWarning = Boolean(payload.error?.trim());
      await addProjectWorktree(sourceProject.id, {
        ...nextWorktree,
        status: "ready",
        initStep: "ready",
        initMessage: hasSetupWarning ? "创建完成（环境初始化存在告警）" : (payload.message || "创建完成"),
        initError: payload.error ?? null,
        updatedAt: jsDateToSwiftDate(new Date()),
      });

      if (hasSetupWarning) {
        const warningText = payload.error ?? "";
        const warningSummary = warningText.split("\n")[0] || warningText;
        showToast(`worktree 创建完成，但环境初始化失败：${warningSummary}`, "error");
      } else {
        showToast("worktree 创建成功");
      }

      if (pendingAutoOpen?.autoOpen) {
        openTerminalWorkspace(buildWorktreeVirtualProject(sourceProject, nextWorktree));
      }
    },
    [
      addProjectWorktree,
      openTerminalWorkspace,
      projectMap,
      removeWorktreeFromGitCache,
      removeProjectWorktree,
      showToast,
      syncTerminalProjectWorktrees,
    ],
  );

  useEffect(() => {
    let unlisten: (() => void) | null = null;
    const registerListener = async () => {
      try {
        unlisten = await listenWorktreeInitProgress((event) => {
          void handleWorktreeInitProgress(event.payload);
        });
      } catch (error) {
        console.error("监听 worktree 初始化进度失败。", error);
      }
    };

    void registerListener();
    return () => {
      unlisten?.();
    };
  }, [handleWorktreeInitProgress]);

  useEffect(() => {
    if (!showTerminalWorkspace) {
      return;
    }

    const rootProjects = terminalOpenProjects.filter((project) => !isWorktreeProject(project));
    const rootIds = new Set(rootProjects.map((project) => project.id));

    // 清理已关闭项目的缓存。
    setTerminalGitWorktreesByProjectId((prev) => {
      const entries = Object.entries(prev);
      if (entries.length === 0) {
        return prev;
      }
      let changed = false;
      const next: Record<string, GitWorktreeListItem[]> = {};
      for (const [key, value] of entries) {
        if (rootIds.has(key)) {
          next[key] = value;
        } else {
          changed = true;
        }
      }
      return changed ? next : prev;
    });

    for (const project of rootProjects) {
      if (worktreeAutoSyncedProjectIdsRef.current.has(project.id)) {
        continue;
      }
      worktreeAutoSyncedProjectIdsRef.current.add(project.id);
      void syncTerminalProjectWorktrees(project.id).catch(() => {
        worktreeAutoSyncedProjectIdsRef.current.delete(project.id);
      });
    }
  }, [showTerminalWorkspace, syncTerminalProjectWorktrees, terminalOpenProjects]);

  const handleRetryWorktreeFromProject = useCallback(
    async (projectId: string, worktreePath: string) => {
      const sourceProject = projectMap.get(projectId);
      if (!sourceProject) {
        showToast("项目不存在或已移除", "error");
        return;
      }

      const normalizedPath = normalizePathForCompare(worktreePath);
      const worktree = (sourceProject.worktrees ?? []).find(
        (item) => normalizePathForCompare(item.path) === normalizedPath,
      );
      if (!worktree) {
        showToast("worktree 不存在或已移除", "error");
        return;
      }

      try {
        const createBranch = Boolean(worktree.baseBranch?.trim());
        const key = `${sourceProject.id}|${worktree.branch}`;
        worktreeInitAutoOpenPendingByProjectBranchRef.current.set(key, { autoOpen: false });
        worktreeInitProgressSeenByProjectBranchRef.current.delete(key);

        try {
          await worktreeInitCreate({
            projectId: sourceProject.id,
            projectPath: sourceProject.path,
            branch: worktree.branch,
            createBranch,
            baseBranch: createBranch ? worktree.baseBranch : undefined,
            targetPath: worktree.path,
          });
        } catch (error) {
          const seenProgress = worktreeInitProgressSeenByProjectBranchRef.current.has(key);
          worktreeInitAutoOpenPendingByProjectBranchRef.current.delete(key);
          worktreeInitProgressSeenByProjectBranchRef.current.delete(key);
          const message = error instanceof Error ? error.message : String(error);
          if (!seenProgress) {
            showToast(message || "重试创建 worktree 失败", "error");
          }
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        showToast(message || "重试创建 worktree 失败", "error");
      }
    },
    [projectMap, showToast, worktreeInitCreate],
  );

  const handleDeleteWorktreeFromProject = useCallback(
    async (projectId: string, worktreePath: string) => {
      const sourceProject = projectMap.get(projectId);
      if (!sourceProject) {
        showToast("项目不存在或已移除", "error");
        return;
      }

      const normalizedPath = worktreePath.trim();
      const trackedWorktree = (sourceProject.worktrees ?? []).find((item) => item.path === normalizedPath);
      const cached = terminalGitWorktreesByProjectIdRef.current[projectId];
      const cachedMatch = cached?.find(
        (item) => isSamePath(item.path, normalizedPath),
      );
      const worktree = trackedWorktree ?? (cachedMatch
        ? buildTrackedWorktreeFromGitItem(cachedMatch, jsDateToSwiftDate(new Date()))
        : null);
      if (!worktree) {
        showToast("worktree 不存在或已移除", "error");
        return;
      }
      const shouldDeleteManagedBranch = Boolean(trackedWorktree?.baseBranch?.trim());

      const removeRecordOnly = async () => {
        await removeProjectWorktree(sourceProject.id, worktree.path);
        await deleteTerminalWorkspace(worktree.path).catch(() => undefined);
        showToast("worktree 记录已移除", "success");
      };

      const confirmRemoveRecordOnly = async () => {
        const removeOnly = await confirm(
          "是否仅从 DevHaven 列表中移除该 worktree 记录？（不会执行 Git 删除）",
          {
            title: "移除 worktree 记录",
            kind: "warning",
            okLabel: "移除记录",
            cancelLabel: "取消",
          },
        );
        if (removeOnly) {
          await removeRecordOnly();
        }
      };

      if (worktree.status === "creating") {
        showToast("该 worktree 正在创建中，无法取消，请等待完成后再操作", "error");
        return;
      }

      const confirmed = await confirm(
        `确定要删除该 worktree 吗？\n\n分支：${worktree.branch}\n路径：${worktree.path}\n\n将执行 git worktree remove 并删除该目录${shouldDeleteManagedBranch ? "，并删除对应本地分支" : ""}。`,
        {
          title: "删除 worktree",
          kind: "warning",
          okLabel: "删除",
          cancelLabel: "取消",
        },
      );
      if (!confirmed) {
        return;
      }

      const openedWorktree = terminalOpenProjectsRef.current.find((item) => item.path === worktree.path);
      if (openedWorktree) {
        handleCloseTerminalProject(openedWorktree.id);
        // 给 unmount / PTY 清理一个 tick，避免 Windows 等平台目录占用导致删除失败。
        await new Promise<void>((resolve) => window.setTimeout(resolve, 150));
      }

      try {
        await gitWorktreeRemove({
          path: sourceProject.path,
          worktreePath: worktree.path,
          force: false,
        });
      } catch (error) {
        const message = resolveErrorMessage(error);
        const forceConfirmed = await confirm(
          `删除失败：${message || "未知错误"}\n\n是否尝试“强制删除”？（可能丢失未提交修改）`,
          {
            title: "删除 worktree",
            kind: "warning",
            okLabel: "强制删除",
            cancelLabel: "取消",
          },
        );
        if (!forceConfirmed) {
          await confirmRemoveRecordOnly();
          return;
        }
        try {
          await gitWorktreeRemove({
            path: sourceProject.path,
            worktreePath: worktree.path,
            force: true,
          });
        } catch (forceError) {
          const forceMessage = resolveErrorMessage(forceError);
          showToast(forceMessage || "强制删除 worktree 失败", "error");
          await confirmRemoveRecordOnly();
          return;
        }
      }

      let branchDeleteError: string | null = null;
      if (shouldDeleteManagedBranch) {
        try {
          await gitDeleteBranch({
            path: sourceProject.path,
            branch: worktree.branch,
            force: false,
          });
        } catch (error) {
          branchDeleteError = resolveErrorMessage(error);
        }
      }

      await removeProjectWorktree(sourceProject.id, worktree.path);
      await deleteTerminalWorkspace(worktree.path).catch(() => undefined);
      if (branchDeleteError) {
        showToast(`worktree 已删除，但分支删除失败：${branchDeleteError}`, "error");
      } else if (shouldDeleteManagedBranch) {
        showToast("worktree 与对应分支已删除", "success");
      } else {
        showToast("worktree 已删除", "success");
      }
      void syncTerminalProjectWorktrees(projectId).catch(() => undefined);
    },
    [
      handleCloseTerminalProject,
      projectMap,
      removeProjectWorktree,
      removeWorktreeFromGitCache,
      showToast,
      syncTerminalProjectWorktrees,
    ],
  );

  const handleOpenCodexSession = useCallback(
    (session: CodexSessionView) => {
      if (!session.projectId) {
        showToast("未能匹配到项目", "error");
        return;
      }
      const project = resolveProjectFromCodexProjectId(session.projectId);
      if (!project) {
        showToast("项目不存在或已移除", "error");
        return;
      }
      openTerminalWorkspace(project);
    },
    [openTerminalWorkspace, resolveProjectFromCodexProjectId, showToast],
  );

  useEffect(() => {
    if (codexMonitorStore.agentEvents.length === 0) {
      return;
    }

    const seen = codexEventSnapshotRef.current;
    const events = [...codexMonitorStore.agentEvents].reverse();
    for (const event of events) {
      const eventKey = [
        event.type,
        event.sessionId ?? "",
        String(event.timestamp),
        event.details ?? "",
      ].join("|");
      if (seen.has(eventKey)) {
        continue;
      }
      seen.add(eventKey);
      if (seen.size > 300) {
        const first = seen.values().next().value;
        if (first) {
          seen.delete(first);
        }
      }

      const project = resolveProjectFromCodexEvent(event);
      const projectName = project?.name ?? "未匹配项目";

      if (event.type === "task-complete") {
        showToast(`Codex 已完成：${projectName}`);
        void sendSystemNotification("Codex 已完成", projectName);
      } else if (event.type === "task-error") {
        showToast(`Codex 执行失败：${projectName}`, "error");
        void sendSystemNotification("Codex 执行失败", projectName);
      } else if (event.type === "needs-attention") {
        showToast(`Codex 需要你处理：${projectName}`, "error");
        void sendSystemNotification("Codex 需要处理", projectName);
      }
    }
  }, [codexMonitorStore.agentEvents, resolveProjectFromCodexEvent, showToast]);

  const handleCloseSettings = useCallback(() => {
    setShowSettings(false);
  }, []);

  const handleSaveSettings = useCallback(
    async (settings: typeof appState.settings) => {
      try {
        await updateSettings(settings);
      } catch (error) {
        console.error("保存设置失败。", error);
        showToast("保存失败，请稍后重试", "error");
      }
    },
    [showToast, updateSettings],
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

  const commandPaletteActions = useMemo<CommandPaletteAction[]>(() => {
    const actions: CommandPaletteAction[] = [];
    const appendAction = (
      id: string,
      title: string,
      run: () => void,
      options?: { subtitle?: string; group?: string; keywords?: string[] },
    ) => {
      actions.push({
        id,
        title,
        subtitle: options?.subtitle,
        group: options?.group,
        searchText: [title, options?.subtitle ?? "", ...(options?.keywords ?? [])].join(" ").toLowerCase(),
        run,
      });
    };

    appendAction(
      "filter:clear-all",
      "清除全部筛选",
      () => {
        setSelectedDirectory(null);
        setSelectedTags(new Set());
        setDateFilter("all");
        setGitFilter("all");
        setHeatmapFilteredProjectIds(new Set());
        setHeatmapSelectedDateKey(null);
      },
      { group: "筛选", keywords: ["清空", "reset", "filter"] },
    );

    appendAction(
      "filter:directory:all",
      "筛选目录：全部",
      () => setSelectedDirectory(null),
      { group: "筛选", keywords: ["directory", "目录", "all"] },
    );
    for (const directory of appState.directories) {
      const name = directory.split("/").filter(Boolean).pop() ?? directory;
      appendAction(
        `filter:directory:${directory}`,
        `筛选目录：${name}`,
        () => setSelectedDirectory(directory),
        { group: "筛选", subtitle: directory, keywords: ["directory", "目录", name] },
      );
    }

    for (const option of DATE_FILTER_OPTIONS) {
      appendAction(
        `filter:date:${option.value}`,
        `日期筛选：${option.title}`,
        () => setDateFilter(option.value),
        { group: "筛选", keywords: ["date", "日期", option.shortLabel] },
      );
    }
    for (const option of GIT_FILTER_OPTIONS) {
      appendAction(
        `filter:git:${option.value}`,
        `Git 筛选：${option.title}`,
        () => setGitFilter(option.value),
        { group: "筛选", keywords: ["git", "筛选", option.title] },
      );
    }
    for (const tag of appState.tags) {
      if (tag.hidden) {
        continue;
      }
      appendAction(
        `filter:tag:${tag.name}`,
        `标签筛选：${tag.name}`,
        () => {
          setSelectedTags(new Set([tag.name]));
          setHeatmapFilteredProjectIds(new Set());
          setHeatmapSelectedDateKey(null);
        },
        { group: "筛选", keywords: ["tag", "标签", tag.name] },
      );
    }

    for (const project of visibleProjects) {
      appendAction(
        `project:focus:${project.id}`,
        `打开项目：${project.name}`,
        () => {
          setSelectedProjects(new Set([project.id]));
          setSelectedProjectId(project.id);
          setShowDetailPanel(true);
        },
        { group: "项目", subtitle: project.path, keywords: ["open", "项目", project.name, project.path] },
      );
      appendAction(
        `project:terminal:${project.id}`,
        `打开终端：${project.name}`,
        () => handleOpenTerminal(project),
        { group: "终端", subtitle: project.path, keywords: ["terminal", "终端", project.name, project.path] },
      );

      for (const script of project.scripts ?? []) {
        appendAction(
          `script:run:${project.id}:${script.id}`,
          `运行脚本：${script.name}`,
          () => {
            void handleRunProjectScript(project.id, script.id);
          },
          {
            group: "脚本",
            subtitle: `${project.name} · ${script.start}`,
            keywords: ["run", "script", "脚本", script.name, project.name, script.start],
          },
        );
      }
    }

    return actions;
  }, [appState.directories, appState.tags, handleOpenTerminal, handleRunProjectScript, visibleProjects]);

  const filteredCommandPaletteActions = useMemo(() => {
    const normalizedQuery = commandPaletteQuery.trim().toLowerCase();
    if (!normalizedQuery) {
      return commandPaletteActions.slice(0, 200);
    }
    return commandPaletteActions
      .filter((action) => action.searchText.includes(normalizedQuery))
      .slice(0, 200);
  }, [commandPaletteActions, commandPaletteQuery]);

  const commandPaletteItems = useMemo<CommandPaletteItem[]>(
    () =>
      filteredCommandPaletteActions.map((action) => ({
        id: action.id,
        title: action.title,
        subtitle: action.subtitle,
        group: action.group,
      })),
    [filteredCommandPaletteActions],
  );

  const commandPaletteActionById = useMemo(
    () => new Map(filteredCommandPaletteActions.map((action) => [action.id, action])),
    [filteredCommandPaletteActions],
  );

  useEffect(() => {
    if (!isCommandPaletteOpen) {
      return;
    }
    setCommandPaletteActiveIndex(0);
  }, [commandPaletteQuery, isCommandPaletteOpen]);

  useEffect(() => {
    if (!isCommandPaletteOpen) {
      return;
    }
    setCommandPaletteActiveIndex((prev) => {
      if (commandPaletteItems.length === 0) {
        return 0;
      }
      if (prev < 0 || prev >= commandPaletteItems.length) {
        return 0;
      }
      return prev;
    });
  }, [commandPaletteItems.length, isCommandPaletteOpen]);

  const handleSelectCommandPaletteItem = useCallback(
    (item: CommandPaletteItem) => {
      const action = commandPaletteActionById.get(item.id);
      if (!action) {
        return;
      }
      action.run();
      closeCommandPalette();
    },
    [closeCommandPalette, commandPaletteActionById],
  );

  useEffect(() => {
    const wasVisible = lastTerminalVisibleRef.current;
    lastTerminalVisibleRef.current = showTerminalWorkspace;
    if (!wasVisible || showTerminalWorkspace) {
      return;
    }
    // 终端隐藏后，把焦点移回主界面搜索框，避免继续把输入写入后台 xterm。
    requestAnimationFrame(() => {
      searchInputRef.current?.focus();
    });
  }, [showTerminalWorkspace]);

  useEffect(() => {
    if (showTerminalWorkspace) {
      return;
    }
    // 终端隐藏后清空 Git worktree 缓存与同步标记，避免下次打开显示旧数据。
    worktreeAutoSyncedProjectIdsRef.current = new Set();
    worktreeSyncingProjectIdsRef.current = new Set();
    setTerminalGitWorktreesByProjectId({});
  }, [showTerminalWorkspace]);

  useEffect(() => {
    terminalOpenProjectsRef.current = terminalOpenProjects;
  }, [terminalOpenProjects]);

  useEffect(() => {
    terminalActiveProjectIdRef.current = terminalActiveProjectId;
  }, [terminalActiveProjectId]);

  useEffect(() => {
    terminalGitWorktreesByProjectIdRef.current = terminalGitWorktreesByProjectId;
  }, [terminalGitWorktreesByProjectId]);

  return (
    <div className="relative h-full bg-background">
      <InteractionLockOverlay />
      <div
        className={`grid h-full ${
          showDetailPanel
            ? "grid-cols-[220px_minmax(0,1fr)_380px]"
            : "grid-cols-[220px_minmax(0,1fr)]"
        }`}
      >
        <Sidebar
          appState={appState}
          projects={visibleProjects}
          heatmapData={sidebarHeatmapData}
          heatmapSelectedDateKey={heatmapSelectedDateKey}
          selectedTags={selectedTags}
          selectedDirectory={selectedDirectory}
          heatmapFilteredProjectIds={heatmapFilteredProjectIds}
          heatmapActiveProjects={heatmapActiveProjects}
          onSelectTag={handleSelectTag}
          onClearHeatmapFilter={() => {
            setHeatmapFilteredProjectIds(new Set());
            setHeatmapSelectedDateKey(null);
          }}
          onSelectHeatmapDate={handleSelectHeatmapDate}
          onLocateHeatmapProject={handleLocateHeatmapProject}
          onSelectDirectory={handleSelectDirectory}
          onOpenTagEditor={handleOpenTagEditor}
          onToggleTagHidden={toggleTagHidden}
          onRemoveTag={removeTag}
          onAssignTagToProjects={handleAssignTagToProjects}
          onAddDirectory={addDirectory}
          onRemoveDirectory={removeDirectory}
          onOpenRecycleBin={() => setShowRecycleBin(true)}
          onRefresh={refresh}
          onAddProjects={addProjects}
          isHeatmapLoading={heatmapStore.isLoading}
          codexSessions={codexSessionViews}
          codexSessionsLoading={codexMonitorStore.isLoading}
          codexSessionsError={codexMonitorStore.error}
          onOpenCodexSession={handleOpenCodexSession}
        />
        <MainContent
          projects={visibleProjects}
          filteredProjects={filteredProjects}
          favoriteProjectPaths={favoriteProjectPathSet}
          recycleBinCount={recycleBinCount}
          isLoading={isLoading}
          error={error}
          searchText={searchText}
          onSearchTextChange={setSearchText}
          dateFilter={dateFilter}
          onDateFilterChange={setDateFilter}
          gitFilter={gitFilter}
          onGitFilterChange={setGitFilter}
          viewMode={projectListViewMode}
          onViewModeChange={(mode) => void handleChangeProjectListViewMode(mode)}
          showDetailPanel={showDetailPanel}
          onToggleDetailPanel={handleToggleDetail}
          onOpenDashboard={() => setShowDashboard(true)}
          onOpenSettings={() => setShowSettings(true)}
          onOpenGlobalSkills={() => setShowGlobalSkills(true)}
          availableTags={appState.tags.map((tag) => tag.name)}
          selectedProjects={selectedProjects}
          onSelectProject={handleSelectProject}
          onClearSelectedProjects={handleClearSelectedProjects}
          onBulkCopyProjectPaths={handleBulkCopyProjectPaths}
          onBulkRefreshProjects={handleBulkRefreshProjects}
          onBulkMoveToRecycleBin={handleBulkMoveProjectsToRecycleBin}
          onBulkAssignTagToProjects={handleBulkAssignTagToProjects}
          onTagSelected={handleSelectTag}
          onRemoveTagFromProject={removeTagFromProject}
          onRefreshProject={refreshProject}
          onCopyPath={handleCopyPath}
          onOpenTerminal={handleOpenTerminal}
          onRunProjectScript={handleRunProjectScript}
          onMoveToRecycleBin={handleMoveProjectToRecycleBin}
          onToggleFavorite={toggleProjectFavorite}
          getTagColor={getTagColor}
          searchInputRef={searchInputRef}
        />
        {showDetailPanel ? (
          <DetailPanel
            project={resolvedSelectedProject}
            tags={appState.tags}
            onClose={() => setShowDetailPanel(false)}
            onAddTagToProject={addTagToProject}
            onRemoveTagFromProject={removeTagFromProject}
            onRunProjectScript={handleRunProjectScript}
            onStopProjectScript={handleStopProjectScript}
            onAddProjectScript={addProjectScript}
            onUpdateProjectScript={updateProjectScript}
            onRemoveProjectScript={removeProjectScript}
            sharedScriptsRoot={appState.settings.sharedScriptsRoot}
            getTagColor={getTagColor}
          />
        ) : null}
      </div>

      <TagEditDialog
        title={tagDialogState?.mode === "edit" ? "编辑标签" : "新建标签"}
        isOpen={Boolean(tagDialogState)}
        existingTags={appState.tags}
        initialName={tagDialogState?.tag?.name ?? ""}
        initialColor={tagDialogState?.tag ? getTagHex(tagDialogState.tag.color) : undefined}
        onClose={() => setTagDialogState(null)}
        onSubmit={(name, color) => void handleTagSubmit(name, color)}
      />

      {showRecycleBin ? (
        <RecycleBinModal
          items={recycleBinItems}
          onClose={() => setShowRecycleBin(false)}
          onRestore={handleRestoreProjectFromRecycleBin}
        />
      ) : null}

      {showDashboard ? (
        <DashboardModal
          projects={visibleProjects}
          tags={appState.tags}
          heatmapStore={heatmapStore}
          onClose={() => setShowDashboard(false)}
          onUpdateGitDaily={updateGitDaily}
        />
      ) : null}
      {showSettings ? (
        <SettingsModal
          settings={appState.settings}
          onClose={handleCloseSettings}
          onSaveSettings={handleSaveSettings}
        />
      ) : null}
      {showGlobalSkills ? <GlobalSkillsModal onClose={() => setShowGlobalSkills(false)} /> : null}

      <WorktreeCreateDialog
        isOpen={Boolean(worktreeDialogProjectId)}
        sourceProject={worktreeDialogSourceProject}
        onClose={() => setWorktreeDialogProjectId(null)}
        onSubmit={handleCreateWorktree}
      />

      <CommandPalette
        isOpen={isCommandPaletteOpen}
        query={commandPaletteQuery}
        items={commandPaletteItems}
        activeIndex={commandPaletteActiveIndex}
        onQueryChange={setCommandPaletteQuery}
        onActiveIndexChange={setCommandPaletteActiveIndex}
        onSelectItem={handleSelectCommandPaletteItem}
        onClose={closeCommandPalette}
      />

      {toast ? (
        <div
          className={`fixed left-1/2 bottom-7 -translate-x-1/2 rounded-full px-4 py-2 text-fs-caption border text-text z-[95] backdrop-blur-[6px] ${
            toast.variant === "error"
              ? "bg-[rgba(239,68,68,0.15)] border-[rgba(239,68,68,0.4)]"
              : "bg-[rgba(16,185,129,0.15)] border-[rgba(16,185,129,0.4)]"
          }`}
        >
          {toast.message}
        </div>
      ) : null}

      {terminalOpenProjects.length > 0 ? (
        <div
          className={`absolute inset-0 z-[80] transition-opacity duration-150 ${
            showTerminalWorkspace ? "opacity-100" : "opacity-0 pointer-events-none"
          }`}
        >
          <Suspense fallback={<div className="h-full w-full bg-[var(--bg)]" />}>
            <TerminalWorkspaceWindow
              openProjects={terminalOpenProjects}
              activeProjectId={terminalActiveProjectId}
              quickCommandDispatch={terminalQuickCommandDispatch}
              onSelectProject={setTerminalActiveProjectId}
              onCloseProject={handleCloseTerminalProject}
              onCreateWorktree={(projectId) => void handleRequestCreateWorktree(projectId)}
              onOpenWorktree={(projectId, worktreePath) => void handleOpenWorktreeFromProject(projectId, worktreePath)}
              onDeleteWorktree={(projectId, worktreePath) => void handleDeleteWorktreeFromProject(projectId, worktreePath)}
              onRetryWorktree={(projectId, worktreePath) => void handleRetryWorktreeFromProject(projectId, worktreePath)}
              onRefreshWorktrees={(projectId) => void syncTerminalProjectWorktrees(projectId, { showToast: true })}
              onExit={() => setShowTerminalWorkspace(false)}
              windowLabel={MAIN_WINDOW_LABEL}
              isVisible={showTerminalWorkspace}
              codexProjectStatusById={codexProjectStatusById}
              gitWorktreesByProjectId={terminalGitWorktreesByProjectId}
            />
          </Suspense>
        </div>
      ) : null}
    </div>
  );
}

/** 应用根组件，负责注入全局状态提供者。 */
function App() {
  return (
    <DevHavenProvider>
      <AppLayout />
    </DevHavenProvider>
  );
}

export default App;
