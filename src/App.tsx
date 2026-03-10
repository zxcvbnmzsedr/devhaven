import { Suspense, lazy, useCallback, useEffect, useMemo } from "react";
import Sidebar from "./components/Sidebar";
import MainContent from "./components/MainContent";
import DetailPanel from "./components/DetailPanel";
import TagEditDialog from "./components/TagEditDialog";
import DashboardModal from "./components/DashboardModal";
import SettingsModal from "./components/SettingsModal";
import GlobalSkillsModal from "./components/GlobalSkillsModal";
import RecycleBinModal from "./components/RecycleBinModal";
import InteractionLockOverlay from "./components/InteractionLockOverlay";
import CommandPalette from "./components/CommandPalette";
import WorktreeCreateDialog from "./components/terminal/WorktreeCreateDialog";
import { useCodexMonitor } from "./hooks/useCodexMonitor";
import { useCodexIntegration } from "./hooks/useCodexIntegration";
import { useCommandPalette } from "./hooks/useCommandPalette";
import { useDisableInputCorrections } from "./hooks/useDisableInputCorrections";
import { useProjectFilter } from "./hooks/useProjectFilter";
import { useProjectSelection } from "./hooks/useProjectSelection";
import { useTerminalWorkspace } from "./hooks/useTerminalWorkspace";
import { useToast } from "./hooks/useToast";
import { useWorktreeManager } from "./hooks/useWorktreeManager";
import { useAppActions } from "./hooks/useAppActions";
import { useAppViewState } from "./hooks/useAppViewState";
import { HEATMAP_CONFIG } from "./models/heatmap";
import { isTauriRuntime } from "./platform/runtime";
import type { ProjectListViewMode } from "./models/types";
import { APP_RESUME_MIN_INACTIVE_MS, dispatchAppResumeEvent } from "./utils/appResume";
import { MAIN_WINDOW_LABEL, shouldBlockReloadShortcut } from "./utils/worktreeHelpers";
import { DevHavenProvider, useDevHavenActions, useDevHavenState } from "./state/DevHavenContext";
import { useHeatmapData } from "./state/useHeatmapData";
const TerminalWorkspaceWindow = lazy(() => import("./components/terminal/TerminalWorkspaceWindow"));

/** 应用主布局，负责筛选、状态联动与面板展示。 */
function AppLayout() {
  const { appState, projects, projectMap, isLoading, error } = useDevHavenState();
  const {
    refresh,
    addDirectory, removeDirectory, addProjects,
    addTag, renameTag, removeTag, toggleTagHidden, setTagColor,
    addTagToProject, addTagToProjects, removeTagFromProject,
    addProjectScript, updateProjectScript, removeProjectScript,
    addProjectWorktree, removeProjectWorktree, syncProjectWorktrees,
    refreshProject, updateGitDaily, updateSettings,
    moveProjectToRecycleBin, moveProjectsToRecycleBin, restoreProjectFromRecycleBin,
    toggleProjectFavorite,
  } = useDevHavenActions();

  const { toast, showToast } = useToast();
  const viewState = useAppViewState({ appState, projects });

  const selection = useProjectSelection({ projectMap, recycleBinSet: viewState.recycleBinSet });
  const filter = useProjectFilter({
    visibleProjects: viewState.visibleProjects,
    favoriteProjectPathSet: viewState.favoriteProjectPathSet,
    appTags: appState.tags,
    onLocateProject: selection.locateProject,
  });
  const heatmapStore = useHeatmapData(viewState.visibleProjects, appState.settings.gitIdentities);
  const sidebarHeatmapData = useMemo(() => heatmapStore.getHeatmapData(HEATMAP_CONFIG.sidebar.days), [heatmapStore]);

  const terminal = useTerminalWorkspace({
    projects,
    projectMap,
    isLoading,
    showToast,
    syncProjectWorktrees,
    searchInputRef: filter.searchInputRef,
  });

  const worktree = useWorktreeManager({
    projects,
    projectMap,
    addProjectWorktree,
    removeProjectWorktree,
    syncProjectWorktrees,
    showToast,
    openTerminalWorkspace: terminal.openTerminalWorkspace,
    handleCloseTerminalProject: terminal.handleCloseTerminalProject,
    syncTerminalProjectWorktrees: terminal.syncTerminalProjectWorktrees,
    removeWorktreeFromGitCache: terminal.removeWorktreeFromGitCache,
    setTerminalGitWorktreesByProjectId: terminal.setTerminalGitWorktreesByProjectId,
    terminalGitWorktreesByProjectIdRef: terminal.terminalGitWorktreesByProjectIdRef,
    terminalOpenProjectsRef: terminal.terminalOpenProjectsRef,
  });

  const codexMonitorStore = useCodexMonitor();
  const codex = useCodexIntegration({
    projects,
    projectMap,
    terminalOpenProjects: terminal.terminalOpenProjects,
    codexMonitorStore,
    showToast,
    openTerminalWorkspace: terminal.openTerminalWorkspace,
  });

  const commandPalette = useCommandPalette({
    showTerminalWorkspace: terminal.showTerminalWorkspace,
    appState,
    visibleProjects: viewState.visibleProjects,
    setSelectedDirectory: filter.setSelectedDirectory,
    setSelectedTags: filter.setSelectedTags,
    setDateFilter: filter.setDateFilter,
    setGitFilter: filter.setGitFilter,
    setHeatmapFilteredProjectIds: filter.setHeatmapFilteredProjectIds,
    setHeatmapSelectedDateKey: filter.setHeatmapSelectedDateKey,
    focusProject: selection.locateProject,
    handleOpenTerminal: terminal.handleOpenTerminal,
    handleRunProjectScript: terminal.handleRunProjectScript,
  });
  const projectListViewMode: ProjectListViewMode = appState.settings.projectListViewMode ?? "card";
  const availableTags = useMemo(() => appState.tags.map((tag) => tag.name), [appState.tags]);

  const appActions = useAppActions({
    appState, isLoading, visibleProjects: viewState.visibleProjects, projectMap, projectListViewMode,
    tagDialogState: viewState.tagDialogState, setTagDialogState: viewState.setTagDialogState,
    setSelectedProjects: selection.setSelectedProjects, setSelectedProjectId: selection.setSelectedProjectId,
    setHeatmapFilteredProjectIds: filter.setHeatmapFilteredProjectIds, setSelectedTags: filter.setSelectedTags,
    moveProjectToRecycleBin, moveProjectsToRecycleBin, restoreProjectFromRecycleBin, refreshProject,
    addTagToProjects, addTag, renameTag, setTagColor, updateGitDaily, updateSettings, showToast,
  });
  useDisableInputCorrections();

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
    if (typeof window === "undefined" || typeof document === "undefined") {
      return;
    }

    let resumeFrame: number | null = null;
    let inactiveAt: number | null = null;
    let resumeDispatchedForInactiveAt: number | null = null;
    let disposed = false;
    let unlistenTauriFocus: (() => void) | null = null;

    const clearScheduledResume = () => {
      if (resumeFrame !== null) {
        window.cancelAnimationFrame(resumeFrame);
        resumeFrame = null;
      }
    };

    const scheduleResumeRecovery = () => {
      if (document.visibilityState === "hidden") {
        return;
      }

      clearScheduledResume();
      resumeFrame = window.requestAnimationFrame(() => {
        resumeFrame = null;
        dispatchAppResumeEvent();
      });
    };

    const markInactive = () => {
      inactiveAt = Date.now();
      resumeDispatchedForInactiveAt = null;
      clearScheduledResume();
    };

    const maybeRecoverFromInactive = () => {
      if (inactiveAt === null || resumeDispatchedForInactiveAt === inactiveAt) {
        return;
      }

      const inactiveMs = Date.now() - inactiveAt;
      if (inactiveMs < APP_RESUME_MIN_INACTIVE_MS) {
        return;
      }

      resumeDispatchedForInactiveAt = inactiveAt;
      scheduleResumeRecovery();
    };

    const handleVisibilityChange = () => {
      if (document.visibilityState === "hidden") {
        markInactive();
        return;
      }

      if (document.visibilityState === "visible") {
        maybeRecoverFromInactive();
      }
    };

    const handleWindowBlur = () => {
      if (document.visibilityState === "hidden") {
        return;
      }
      markInactive();
    };

    const handleWindowFocus = () => {
      if (document.visibilityState === "hidden") {
        return;
      }
      maybeRecoverFromInactive();
    };

    const handlePageShow = (event: PageTransitionEvent) => {
      if (event.persisted) {
        if (inactiveAt === null) {
          inactiveAt = Date.now() - APP_RESUME_MIN_INACTIVE_MS;
          resumeDispatchedForInactiveAt = null;
        }
        scheduleResumeRecovery();
      }
    };

    const registerTauriFocusRecovery = async () => {
      if (!isTauriRuntime()) {
        return;
      }

      try {
        const { getCurrentWindow } = await import("@tauri-apps/api/window");
        const currentWindow = getCurrentWindow();
        unlistenTauriFocus = await currentWindow.onFocusChanged(({ payload: focused }) => {
          if (disposed) {
            return;
          }
          if (focused) {
            handleWindowFocus();
            return;
          }
          handleWindowBlur();
        });
      } catch (error) {
        console.warn("注册 Tauri 窗口焦点恢复监听失败。", error);
      }
    };

    window.addEventListener("pageshow", handlePageShow);
    window.addEventListener("blur", handleWindowBlur);
    window.addEventListener("focus", handleWindowFocus);
    document.addEventListener("visibilitychange", handleVisibilityChange);
    void registerTauriFocusRecovery();

    return () => {
      disposed = true;
      clearScheduledResume();
      window.removeEventListener("pageshow", handlePageShow);
      window.removeEventListener("blur", handleWindowBlur);
      window.removeEventListener("focus", handleWindowFocus);
      document.removeEventListener("visibilitychange", handleVisibilityChange);
      unlistenTauriFocus?.();
    };
  }, []);

  const handleClearHeatmapFilter = useCallback(() => {
    filter.setHeatmapFilteredProjectIds(new Set());
    filter.setHeatmapSelectedDateKey(null);
  }, [filter.setHeatmapFilteredProjectIds, filter.setHeatmapSelectedDateKey]);

  const handleOpenRecycleBin = useCallback(() => {
    viewState.setShowRecycleBin(true);
  }, [viewState.setShowRecycleBin]);

  const handleViewModeChange = useCallback(
    (mode: ProjectListViewMode) => void appActions.handleChangeProjectListViewMode(mode),
    [appActions.handleChangeProjectListViewMode],
  );

  const handleOpenDashboard = useCallback(() => {
    viewState.setShowDashboard(true);
  }, [viewState.setShowDashboard]);

  const handleOpenSettings = useCallback(() => {
    viewState.setShowSettings(true);
  }, [viewState.setShowSettings]);

  const handleOpenGlobalSkills = useCallback(() => {
    viewState.setShowGlobalSkills(true);
  }, [viewState.setShowGlobalSkills]);

  const handleCloseDetailPanel = useCallback(() => {
    selection.setShowDetailPanel(false);
  }, [selection.setShowDetailPanel]);

  const handleTagDialogSubmit = useCallback(
    (name: string, color: string) => void appActions.handleTagSubmit(name, color),
    [appActions.handleTagSubmit],
  );

  const handleTerminalCreateWorktree = useCallback(
    (projectId: string) => void worktree.handleRequestCreateWorktree(projectId),
    [worktree.handleRequestCreateWorktree],
  );

  const handleTerminalOpenWorktree = useCallback(
    (projectId: string, worktreePath: string) => void worktree.handleOpenWorktreeFromProject(projectId, worktreePath),
    [worktree.handleOpenWorktreeFromProject],
  );

  const handleTerminalDeleteWorktree = useCallback(
    (projectId: string, worktreePath: string) => void worktree.handleDeleteWorktreeFromProject(projectId, worktreePath),
    [worktree.handleDeleteWorktreeFromProject],
  );

  const handleTerminalRetryWorktree = useCallback(
    (projectId: string, worktreePath: string) => void worktree.handleRetryWorktreeFromProject(projectId, worktreePath),
    [worktree.handleRetryWorktreeFromProject],
  );

  const handleTerminalRefreshWorktrees = useCallback(
    (projectId: string) => void terminal.syncTerminalProjectWorktrees(projectId, { showToast: true }),
    [terminal.syncTerminalProjectWorktrees],
  );

  const handleTerminalExit = useCallback(() => {
    terminal.setShowTerminalWorkspace(false);
  }, [terminal.setShowTerminalWorkspace]);

  return (
    <div className="relative h-full bg-background">
      <InteractionLockOverlay />
      <div className="grid h-full grid-cols-[220px_minmax(0,1fr)]">
        <Sidebar
          appState={appState}
          projects={viewState.visibleProjects}
          heatmapData={sidebarHeatmapData}
          heatmapSelectedDateKey={filter.heatmapSelectedDateKey}
          selectedTags={filter.selectedTags}
          selectedDirectory={filter.selectedDirectory}
          heatmapFilteredProjectIds={filter.heatmapFilteredProjectIds}
          heatmapActiveProjects={filter.heatmapActiveProjects}
          onSelectTag={filter.handleSelectTag}
          onClearHeatmapFilter={handleClearHeatmapFilter}
          onSelectHeatmapDate={filter.handleSelectHeatmapDate}
          onLocateHeatmapProject={filter.handleLocateHeatmapProject}
          onSelectDirectory={filter.handleSelectDirectory}
          onOpenTagEditor={appActions.handleOpenTagEditor}
          onToggleTagHidden={toggleTagHidden}
          onRemoveTag={removeTag}
          onAssignTagToProjects={appActions.handleAssignTagToProjects}
          onAddDirectory={addDirectory}
          onRemoveDirectory={removeDirectory}
          onOpenRecycleBin={handleOpenRecycleBin}
          onRefresh={refresh}
          onAddProjects={addProjects}
          isHeatmapLoading={heatmapStore.isLoading}
          codexSessions={codex.codexSessionViews}
          codexSessionsLoading={codexMonitorStore.isLoading}
          codexSessionsError={codexMonitorStore.error}
          onOpenCodexSession={codex.handleOpenCodexSession}
        />
        <MainContent
          projects={viewState.visibleProjects}
          filteredProjects={filter.filteredProjects}
          favoriteProjectPaths={viewState.favoriteProjectPathSet}
          recycleBinCount={viewState.recycleBinCount}
          isLoading={isLoading}
          error={error}
          searchText={filter.searchText}
          onSearchTextChange={filter.setSearchText}
          dateFilter={filter.dateFilter}
          onDateFilterChange={filter.setDateFilter}
          gitFilter={filter.gitFilter}
          onGitFilterChange={filter.setGitFilter}
          viewMode={projectListViewMode}
          onViewModeChange={handleViewModeChange}
          showDetailPanel={selection.showDetailPanel}
          onToggleDetailPanel={selection.handleToggleDetail}
          onOpenDashboard={handleOpenDashboard}
          onOpenSettings={handleOpenSettings}
          onOpenGlobalSkills={handleOpenGlobalSkills}
          availableTags={availableTags}
          selectedProjects={selection.selectedProjects}
          onSelectProject={selection.handleSelectProject}
          onClearSelectedProjects={selection.handleClearSelectedProjects}
          onBulkCopyProjectPaths={appActions.handleBulkCopyProjectPaths}
          onBulkRefreshProjects={appActions.handleBulkRefreshProjects}
          onBulkMoveToRecycleBin={appActions.handleBulkMoveProjectsToRecycleBin}
          onBulkAssignTagToProjects={appActions.handleBulkAssignTagToProjects}
          onTagSelected={filter.handleSelectTag}
          onRemoveTagFromProject={removeTagFromProject}
          onRefreshProject={refreshProject}
          onCopyPath={appActions.handleCopyPath}
          onOpenTerminal={terminal.handleOpenTerminal}
          onRunProjectScript={terminal.handleRunProjectScript}
          onMoveToRecycleBin={appActions.handleMoveProjectToRecycleBin}
          onToggleFavorite={toggleProjectFavorite}
          getTagColor={appActions.getTagColor}
          searchInputRef={filter.searchInputRef}
        />
      </div>

      <DetailPanel
        isOpen={selection.showDetailPanel}
        project={selection.resolvedSelectedProject}
        tags={appState.tags}
        onClose={handleCloseDetailPanel}
        onAddTagToProject={addTagToProject}
        onRemoveTagFromProject={removeTagFromProject}
        onRunProjectScript={terminal.handleRunProjectScript}
        onStopProjectScript={terminal.handleStopProjectScript}
        onAddProjectScript={addProjectScript}
        onUpdateProjectScript={updateProjectScript}
        onRemoveProjectScript={removeProjectScript}
        sharedScriptsRoot={appState.settings.sharedScriptsRoot}
        getTagColor={appActions.getTagColor}
      />

      <TagEditDialog
        title={viewState.tagDialogState?.mode === "edit" ? "编辑标签" : "新建标签"}
        isOpen={Boolean(viewState.tagDialogState)}
        existingTags={appState.tags}
        initialName={viewState.tagDialogState?.tag?.name ?? ""}
        initialColor={viewState.tagDialogState?.tag ? appActions.getTagHex(viewState.tagDialogState.tag.color) : undefined}
        onClose={() => viewState.setTagDialogState(null)}
        onSubmit={handleTagDialogSubmit}
      />

      {viewState.showRecycleBin ? (
        <RecycleBinModal
          items={viewState.recycleBinItems}
          onClose={() => viewState.setShowRecycleBin(false)}
          onRestore={appActions.handleRestoreProjectFromRecycleBin}
        />
      ) : null}

      {viewState.showDashboard ? (
        <DashboardModal
          projects={viewState.visibleProjects}
          tags={appState.tags}
          heatmapStore={heatmapStore}
          onClose={() => viewState.setShowDashboard(false)}
          onUpdateGitDaily={updateGitDaily}
        />
      ) : null}
      {viewState.showSettings ? (
        <SettingsModal
          settings={appState.settings}
          onClose={() => viewState.setShowSettings(false)}
          onSaveSettings={appActions.handleSaveSettings}
        />
      ) : null}
      {viewState.showGlobalSkills ? <GlobalSkillsModal onClose={() => viewState.setShowGlobalSkills(false)} /> : null}

      <WorktreeCreateDialog
        isOpen={Boolean(worktree.worktreeDialogProjectId)}
        sourceProject={worktree.worktreeDialogSourceProject}
        onClose={() => worktree.setWorktreeDialogProjectId(null)}
        onSubmit={worktree.handleCreateWorktree}
      />

      <CommandPalette
        isOpen={commandPalette.isOpen}
        query={commandPalette.query}
        items={commandPalette.items}
        activeIndex={commandPalette.activeIndex}
        onQueryChange={commandPalette.onQueryChange}
        onActiveIndexChange={commandPalette.onActiveIndexChange}
        onSelectItem={commandPalette.onSelectItem}
        onClose={commandPalette.onClose}
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

      {terminal.terminalOpenProjects.length > 0 ? (
        <div
          className={`absolute inset-0 z-[80] transition-opacity duration-150 ${
            terminal.showTerminalWorkspace ? "opacity-100" : "opacity-0 pointer-events-none"
          }`}
        >
          <Suspense fallback={<div className="h-full w-full bg-[var(--bg)]" />}>
            <TerminalWorkspaceWindow
              openProjects={terminal.terminalOpenProjects}
              activeProjectId={terminal.terminalActiveProjectId}
              quickCommandDispatch={terminal.terminalQuickCommandDispatch}
              onSelectProject={terminal.selectTerminalProject}
              onCloseProject={terminal.handleCloseTerminalProject}
              onCreateWorktree={handleTerminalCreateWorktree}
              onOpenWorktree={handleTerminalOpenWorktree}
              onDeleteWorktree={handleTerminalDeleteWorktree}
              onRetryWorktree={handleTerminalRetryWorktree}
              onRefreshWorktrees={handleTerminalRefreshWorktrees}
              onRegisterPersistWorkspace={terminal.registerTerminalWorkspacePersistence}
              onAddProjectScript={addProjectScript}
              onUpdateProjectScript={updateProjectScript}
              onRemoveProjectScript={removeProjectScript}
              onExit={handleTerminalExit}
              windowLabel={MAIN_WINDOW_LABEL}
              isVisible={terminal.showTerminalWorkspace}
              terminalTheme={appState.settings.terminalTheme}
              sharedScriptsRoot={appState.settings.sharedScriptsRoot}
              terminalUseWebglRenderer={appState.settings.terminalUseWebglRenderer}
              codexProjectStatusById={codex.codexProjectStatusById}
              gitWorktreesByProjectId={terminal.terminalGitWorktreesByProjectId}
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
