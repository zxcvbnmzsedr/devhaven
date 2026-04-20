import Foundation

struct WorkspaceRestoreSelectionResult: Equatable {
    let activeProjectPath: String?
    let selectedProjectPath: String?
}

@MainActor
final class WorkspaceRestoreSelectionResolver {
    private let sessionPathResolver: WorkspaceSessionPathResolver
    private let displayProjectPath: @MainActor (String) -> String

    init(
        sessionPathResolver: WorkspaceSessionPathResolver,
        displayProjectPath: @escaping @MainActor (String) -> String
    ) {
        self.sessionPathResolver = sessionPathResolver
        self.displayProjectPath = displayProjectPath
    }

    func resolveSelection(
        activeProjectPathCandidate: String?,
        selectedProjectPathCandidate: String?,
        sessions: [OpenWorkspaceSessionState],
        currentSelectedProjectPath: String?
    ) -> WorkspaceRestoreSelectionResult {
        let restoredActiveProjectPath = activeProjectPathCandidate.flatMap {
            sessionPathResolver.canonicalSessionPath(for: $0, sessions: sessions)
        } ?? sessions.last?.projectPath

        let restoredSelectedProjectPath = selectedProjectPathCandidate.flatMap { candidate in
            if let workspaceSessionPath = sessionPathResolver.canonicalSessionPath(for: candidate, sessions: sessions) {
                return workspaceSessionPath
            }
            return displayProjectPath(candidate)
        } ?? restoredActiveProjectPath ?? currentSelectedProjectPath

        return WorkspaceRestoreSelectionResult(
            activeProjectPath: restoredActiveProjectPath,
            selectedProjectPath: restoredSelectedProjectPath
        )
    }
}
