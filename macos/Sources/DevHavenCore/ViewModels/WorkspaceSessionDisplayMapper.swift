import Foundation

@MainActor
final class WorkspaceSessionDisplayMapper {
    private let normalizePath: @MainActor (String) -> String
    private let resolveDisplayProject: @MainActor (String, String?) -> Project?

    init(
        normalizePath: @escaping @MainActor (String) -> String,
        resolveDisplayProject: @escaping @MainActor (String, String?) -> Project?
    ) {
        self.normalizePath = normalizePath
        self.resolveDisplayProject = resolveDisplayProject
    }

    func displayProjectPath(
        for projectPath: String,
        rootProjectPath: String? = nil,
        fallbackPath: String? = nil
    ) -> String {
        resolveDisplayProject(projectPath, rootProjectPath)?.path ?? fallbackPath ?? projectPath
    }

    func normalizedTransientDisplayProject(
        _ project: Project?,
        fallbackPath: String
    ) -> Project? {
        guard let project else {
            return nil
        }
        if project.isDirectoryWorkspace {
            return Project.directoryWorkspace(at: fallbackPath)
        }
        return project
    }

    func normalizedRestoreSnapshot(
        _ snapshot: ProjectWorkspaceRestoreSnapshot
    ) -> ProjectWorkspaceRestoreSnapshot {
        let normalizedProjectPath = normalizePath(snapshot.projectPath)
        let normalizedRootProjectPath = normalizePath(snapshot.rootProjectPath)
        return ProjectWorkspaceRestoreSnapshot(
            projectPath: normalizedProjectPath,
            rootProjectPath: normalizedRootProjectPath,
            isQuickTerminal: snapshot.isQuickTerminal,
            transientDisplayProject: normalizedTransientDisplayProject(
                snapshot.transientDisplayProject,
                fallbackPath: normalizedProjectPath
            ),
            workspaceRootContext: snapshot.workspaceRootContext,
            workspaceAlignmentGroupID: snapshot.workspaceAlignmentGroupID,
            workspaceId: snapshot.workspaceId,
            selectedTabId: snapshot.selectedTabId,
            selectedPresentedTab: snapshot.selectedPresentedTab,
            nextTabNumber: snapshot.nextTabNumber,
            nextPaneNumber: snapshot.nextPaneNumber,
            editorTabs: snapshot.editorTabs,
            editorPresentation: snapshot.editorPresentation,
            tabs: snapshot.tabs
        )
    }

    func restoredSessionState(
        from snapshot: ProjectWorkspaceRestoreSnapshot,
        controller: GhosttyWorkspaceController,
        workspaceRootContext: WorkspaceRootSessionContext?
    ) -> OpenWorkspaceSessionState {
        OpenWorkspaceSessionState(
            projectPath: displayProjectPath(
                for: snapshot.projectPath,
                rootProjectPath: snapshot.rootProjectPath,
                fallbackPath: snapshot.projectPath
            ),
            rootProjectPath: displayProjectPath(
                for: snapshot.rootProjectPath,
                rootProjectPath: snapshot.rootProjectPath,
                fallbackPath: snapshot.rootProjectPath
            ),
            controller: controller,
            isQuickTerminal: snapshot.isQuickTerminal,
            transientDisplayProject: normalizedTransientDisplayProject(
                snapshot.transientDisplayProject,
                fallbackPath: snapshot.projectPath
            ),
            workspaceRootContext: workspaceRootContext,
            workspaceAlignmentGroupID: snapshot.workspaceAlignmentGroupID
        )
    }
}
