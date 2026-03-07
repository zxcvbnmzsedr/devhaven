import React, { createContext, useContext, useMemo } from "react";

import type { DevHavenActions, DevHavenStateValue } from "./useDevHaven";
import { useDevHaven } from "./useDevHaven";

const DevHavenStateContext = createContext<DevHavenStateValue | null>(null);
const DevHavenActionsContext = createContext<DevHavenActions | null>(null);

/** 提供项目管理状态与操作的上下文。 */
export function DevHavenProvider({ children }: { children: React.ReactNode }) {
  const {
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
  } = useDevHaven();

  const stateValue = useMemo<DevHavenStateValue>(
    () => ({
      appState,
      projects,
      isLoading,
      error,
      projectMap,
    }),
    [appState, projects, isLoading, error, projectMap],
  );

  const actionsValue = useMemo<DevHavenActions>(
    () => ({
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
    }),
    [
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
    ],
  );

  return (
    <DevHavenActionsContext.Provider value={actionsValue}>
      <DevHavenStateContext.Provider value={stateValue}>{children}</DevHavenStateContext.Provider>
    </DevHavenActionsContext.Provider>
  );
}

/** 获取项目管理状态上下文，未初始化时抛出错误。 */
export function useDevHavenState() {
  const context = useContext(DevHavenStateContext);
  if (!context) {
    throw new Error("DevHavenStateContext 未初始化");
  }
  return context;
}

/** 获取项目管理动作上下文，未初始化时抛出错误。 */
export function useDevHavenActions() {
  const context = useContext(DevHavenActionsContext);
  if (!context) {
    throw new Error("DevHavenActionsContext 未初始化");
  }
  return context;
}
