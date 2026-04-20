import Foundation

@MainActor
final class WorkspaceProjectProjectionBuilder {
    private let normalizePath: @MainActor (String) -> String
    private let resolveDisplayProject: @MainActor (String, String?) -> Project?
    private let canonicalSessionPath: @MainActor (String?) -> String?
    private let exactSession: @MainActor (String?) -> OpenWorkspaceSessionState?
    private let session: @MainActor (String?) -> OpenWorkspaceSessionState?

    init(
        normalizePath: @escaping @MainActor (String) -> String,
        resolveDisplayProject: @escaping @MainActor (String, String?) -> Project?,
        canonicalSessionPath: @escaping @MainActor (String?) -> String?,
        exactSession: @escaping @MainActor (String?) -> OpenWorkspaceSessionState?,
        session: @escaping @MainActor (String?) -> OpenWorkspaceSessionState?
    ) {
        self.normalizePath = normalizePath
        self.resolveDisplayProject = resolveDisplayProject
        self.canonicalSessionPath = canonicalSessionPath
        self.exactSession = exactSession
        self.session = session
    }

    func selectedProject(
        selectedProjectPath: String?,
        filteredProjects: [Project],
        visibleProjects: [Project]
    ) -> Project? {
        guard let selectedProjectPath else {
            return filteredProjects.first ?? visibleProjects.first
        }
        return resolveDisplayProject(selectedProjectPath, nil)
    }

    func activeWorkspaceProject(activeProjectPath: String?) -> Project? {
        guard let activeProjectPath else {
            return nil
        }
        return resolveDisplayProject(activeProjectPath, nil)
    }

    func mountedWorkspaceProjectPath(
        activeProjectPath: String?,
        hiddenMountedProjectPath: String?
    ) -> String? {
        if let activeProjectPath {
            return canonicalSessionPath(activeProjectPath)
        }
        if let hiddenMountedProjectPath {
            return canonicalSessionPath(hiddenMountedProjectPath)
        }
        return nil
    }

    func activeWorkspaceProjectTreeProject(
        activeProject: Project?,
        activeSession: OpenWorkspaceSessionState?
    ) -> Project? {
        if let activeProject {
            return activeProject
        }
        guard let activeSession,
              let workspaceRootContext = activeSession.workspaceRootContext
        else {
            return nil
        }
        return .workspaceRoot(
            name: workspaceRootContext.workspaceName,
            path: activeSession.projectPath
        )
    }

    func openWorkspaceProjectPaths(sessions: [OpenWorkspaceSessionState]) -> [String] {
        sessions.map { normalizePath($0.projectPath) }
    }

    func openWorkspaceRootProjectPaths(sessions: [OpenWorkspaceSessionState]) -> [String] {
        var paths: [String] = []
        var seen = Set<String>()

        for session in sessions where !session.isQuickTerminal {
            let normalizedRootProjectPath = normalizePath(session.rootProjectPath)
            if seen.insert(normalizedRootProjectPath).inserted {
                paths.append(session.rootProjectPath)
            }
        }

        return paths
    }

    func openWorkspaceProjects(sessions: [OpenWorkspaceSessionState]) -> [Project] {
        sessions.compactMap {
            resolveDisplayProject($0.projectPath, $0.rootProjectPath)
        }
    }

    func availableWorkspaceProjects(
        visibleProjects: [Project],
        openRootProjectPaths: [String]
    ) -> [Project] {
        let openedPaths = Set(openRootProjectPaths.map(normalizePath))
        return visibleProjects.filter { !openedPaths.contains(normalizePath($0.path)) }
    }

    func workspaceAlignmentProjectOptions(visibleProjects: [Project]) -> [Project] {
        visibleProjects.filter { !$0.isQuickTerminal }
    }

    func activeWorkspaceSession(activeProjectPath: String?) -> OpenWorkspaceSessionState? {
        exactSession(activeProjectPath) ?? session(activeProjectPath)
    }
}
