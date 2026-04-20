import Foundation

@MainActor
final class WorkspaceSessionPathResolver {
    private let normalizePath: @MainActor (String) -> String
    private let normalizeOptionalPath: @MainActor (String?) -> String?

    init(
        normalizePath: @escaping @MainActor (String) -> String,
        normalizeOptionalPath: @escaping @MainActor (String?) -> String?
    ) {
        self.normalizePath = normalizePath
        self.normalizeOptionalPath = normalizeOptionalPath
    }

    func sessionIndex(
        for path: String,
        indexByNormalizedPath: [String: Int]
    ) -> Int? {
        indexByNormalizedPath[normalizePath(path)]
    }

    func session(
        for path: String?,
        sessions: [OpenWorkspaceSessionState],
        indexByNormalizedPath: [String: Int]
    ) -> OpenWorkspaceSessionState? {
        guard let normalizedPath = normalizeOptionalPath(path) else {
            return nil
        }
        if let index = indexByNormalizedPath[normalizedPath],
           sessions.indices.contains(index) {
            return sessions[index]
        }
        return fallbackSession(forNormalizedPath: normalizedPath, in: sessions)
    }

    func canonicalSessionPath(
        for path: String?,
        sessions: [OpenWorkspaceSessionState],
        indexByNormalizedPath: [String: Int]? = nil
    ) -> String? {
        guard let normalizedPath = normalizeOptionalPath(path) else {
            return nil
        }
        if let indexByNormalizedPath,
           let index = indexByNormalizedPath[normalizedPath],
           sessions.indices.contains(index) {
            return sessions[index].projectPath
        }
        if let matchedProjectPath = sessions.first(where: {
            normalizePath($0.projectPath) == normalizedPath
        })?.projectPath {
            return matchedProjectPath
        }
        return fallbackSession(forNormalizedPath: normalizedPath, in: sessions)?.projectPath
    }

    private func fallbackSession(
        forNormalizedPath normalizedPath: String,
        in sessions: [OpenWorkspaceSessionState]
    ) -> OpenWorkspaceSessionState? {
        sessions.last(where: {
            !$0.isQuickTerminal &&
                normalizePath($0.rootProjectPath) == normalizedPath
        })
    }
}
