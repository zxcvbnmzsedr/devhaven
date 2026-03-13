import type { TerminalQuickCommandDispatch } from "../../models/quickCommands";
import type { Project } from "../../models/types";

export type MountedWorkspaceEntry = {
  project: Project;
  isCurrent: boolean;
  isVisible: boolean;
  quickCommandDispatch: TerminalQuickCommandDispatch | null;
};

type BuildMountedWorkspaceEntriesParams = {
  openProjects: Project[];
  activeProjectId: string | null;
  quickCommandDispatch: TerminalQuickCommandDispatch | null;
  workspaceVisible: boolean;
};

/** 生成需要保持挂载的工作区列表：所有已打开项目都保活，仅当前项目可见/可交互。 */
export function buildMountedWorkspaceEntries({
  openProjects,
  activeProjectId,
  quickCommandDispatch,
  workspaceVisible,
}: BuildMountedWorkspaceEntriesParams): MountedWorkspaceEntry[] {
  return openProjects.map((project, index) => {
    const isCurrent = activeProjectId ? project.id === activeProjectId : index === 0;
    const dispatchMatchesProject =
      Boolean(
        quickCommandDispatch &&
          quickCommandDispatch.projectId === project.id &&
          quickCommandDispatch.projectPath === project.path,
      );

    return {
      project,
      isCurrent,
      isVisible: workspaceVisible && isCurrent,
      quickCommandDispatch: dispatchMatchesProject ? quickCommandDispatch : null,
    };
  });
}
