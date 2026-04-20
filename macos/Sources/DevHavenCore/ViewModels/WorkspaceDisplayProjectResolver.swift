import Foundation

@MainActor
final class WorkspaceDisplayProjectResolver {
    private struct LookupKey: Hashable {
        let path: String
        let rootProjectPath: String?
    }

    private struct CacheEntry {
        let project: Project?
    }

    private let normalizePath: @MainActor (String) -> String
    private let normalizeOptionalPath: @MainActor (String?) -> String?
    private let projects: @MainActor () -> [Project]
    private let projectsByNormalizedPath: @MainActor () -> [String: Project]
    private let workspaceSessionWithoutNormalizing: @MainActor (String?) -> OpenWorkspaceSessionState?
    private let workspaceSession: @MainActor (String?) -> OpenWorkspaceSessionState?
    private let buildWorktreeVirtualProject: @MainActor (Project, ProjectWorktree) -> Project

    private var cacheByLookupKey: [LookupKey: CacheEntry] = [:]

    init(
        normalizePath: @escaping @MainActor (String) -> String,
        normalizeOptionalPath: @escaping @MainActor (String?) -> String?,
        projects: @escaping @MainActor () -> [Project],
        projectsByNormalizedPath: @escaping @MainActor () -> [String: Project],
        workspaceSessionWithoutNormalizing: @escaping @MainActor (String?) -> OpenWorkspaceSessionState?,
        workspaceSession: @escaping @MainActor (String?) -> OpenWorkspaceSessionState?,
        buildWorktreeVirtualProject: @escaping @MainActor (Project, ProjectWorktree) -> Project
    ) {
        self.normalizePath = normalizePath
        self.normalizeOptionalPath = normalizeOptionalPath
        self.projects = projects
        self.projectsByNormalizedPath = projectsByNormalizedPath
        self.workspaceSessionWithoutNormalizing = workspaceSessionWithoutNormalizing
        self.workspaceSession = workspaceSession
        self.buildWorktreeVirtualProject = buildWorktreeVirtualProject
    }

    func clearCache() {
        cacheByLookupKey.removeAll()
    }

    func resolveProject(for path: String, rootProjectPath: String? = nil) -> Project? {
        let lookupKey = LookupKey(path: path, rootProjectPath: rootProjectPath)
        if let cachedEntry = cacheByLookupKey[lookupKey] {
            return cachedEntry.project
        }

        let normalizedPath = normalizePath(path)
        let projectsByNormalizedPath = projectsByNormalizedPath()
        let resolvedProject: Project?

        if let project = projectsByNormalizedPath[normalizedPath] {
            resolvedProject = project
        } else {
            let rootProject = resolveRootProject(
                for: normalizedPath,
                rootProjectPath: rootProjectPath,
                projectsByNormalizedPath: projectsByNormalizedPath
            )

            if let rootProject,
               let worktree = rootProject.worktrees.first(where: { normalizePath($0.path) == normalizedPath }) {
                resolvedProject = buildWorktreeVirtualProject(rootProject, worktree)
            } else if let session = workspaceSessionWithoutNormalizing(normalizedPath)
                        ?? workspaceSession(normalizedPath) {
                resolvedProject = session.transientDisplayProject
            } else {
                resolvedProject = nil
            }
        }

        cacheByLookupKey[lookupKey] = CacheEntry(project: resolvedProject)
        return resolvedProject
    }

    private func resolveRootProject(
        for normalizedPath: String,
        rootProjectPath: String?,
        projectsByNormalizedPath: [String: Project]
    ) -> Project? {
        if let rootProjectPath {
            return normalizeOptionalPath(rootProjectPath).flatMap { projectsByNormalizedPath[$0] }
        }

        return projects().first(where: { project in
            project.worktrees.contains(where: { normalizePath($0.path) == normalizedPath })
        })
    }
}
