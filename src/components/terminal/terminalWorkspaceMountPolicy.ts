import type { Project } from "../../models/types";

export type WorkspaceRenderEntry = {
  project: Project;
  isVisible: boolean;
};

export function buildWorkspaceRenderEntries(
  openProjects: Project[],
  activeProjectId: string | null,
): WorkspaceRenderEntry[] {
  if (openProjects.length === 0) {
    return [];
  }

  const resolvedActiveProjectId =
    activeProjectId && openProjects.some((project) => project.id === activeProjectId)
      ? activeProjectId
      : openProjects[0]?.id ?? null;

  return openProjects.map((project) => ({
    project,
    isVisible: project.id === resolvedActiveProjectId,
  }));
}
