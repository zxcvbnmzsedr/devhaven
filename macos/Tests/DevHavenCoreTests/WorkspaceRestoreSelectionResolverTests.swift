import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceRestoreSelectionResolverTests: XCTestCase {
    func testResolveSelectionUsesCanonicalSessionPathForActiveAndSelectedCandidates() {
        let restoredWorktreePath = "/private/tmp/worktree"
        let restoredRootPath = "/repo"
        let sessions = [
            OpenWorkspaceSessionState(
                projectPath: restoredWorktreePath,
                rootProjectPath: restoredRootPath,
                controller: GhosttyWorkspaceController(projectPath: restoredWorktreePath)
            )
        ]
        let resolver = makeResolver()

        let selection = resolver.resolveSelection(
            activeProjectPathCandidate: "/tmp/worktree",
            selectedProjectPathCandidate: "/repo",
            sessions: sessions,
            currentSelectedProjectPath: nil
        )

        XCTAssertEqual(selection.activeProjectPath, restoredWorktreePath)
        XCTAssertEqual(selection.selectedProjectPath, restoredWorktreePath)
    }

    func testResolveSelectionFallsBackToLastSessionWhenActiveCandidateMissing() {
        let sessions = [
            OpenWorkspaceSessionState(
                projectPath: "/repo-a",
                rootProjectPath: "/repo-a",
                controller: GhosttyWorkspaceController(projectPath: "/repo-a")
            ),
            OpenWorkspaceSessionState(
                projectPath: "/repo-b",
                rootProjectPath: "/repo-b",
                controller: GhosttyWorkspaceController(projectPath: "/repo-b")
            )
        ]
        let resolver = makeResolver()

        let selection = resolver.resolveSelection(
            activeProjectPathCandidate: "/missing",
            selectedProjectPathCandidate: nil,
            sessions: sessions,
            currentSelectedProjectPath: nil
        )

        XCTAssertEqual(selection.activeProjectPath, "/repo-b")
        XCTAssertEqual(selection.selectedProjectPath, "/repo-b")
    }

    func testResolveSelectionFallsBackToDisplayProjectPathForSelectedCandidateOutsideSessions() {
        let sessions = [
            OpenWorkspaceSessionState(
                projectPath: "/repo-a",
                rootProjectPath: "/repo-a",
                controller: GhosttyWorkspaceController(projectPath: "/repo-a")
            )
        ]
        let resolver = makeResolver(
            displayPaths: ["/tmp/worktree": "/private/tmp/worktree"]
        )

        let selection = resolver.resolveSelection(
            activeProjectPathCandidate: "/repo-a",
            selectedProjectPathCandidate: "/tmp/worktree",
            sessions: sessions,
            currentSelectedProjectPath: nil
        )

        XCTAssertEqual(selection.activeProjectPath, "/repo-a")
        XCTAssertEqual(selection.selectedProjectPath, "/private/tmp/worktree")
    }

    func testResolveSelectionUsesRestoredActiveProjectWhenSnapshotSelectionMissing() {
        let sessions = [
            OpenWorkspaceSessionState(
                projectPath: "/repo-a",
                rootProjectPath: "/repo-a",
                controller: GhosttyWorkspaceController(projectPath: "/repo-a")
            )
        ]
        let resolver = makeResolver()

        let selection = resolver.resolveSelection(
            activeProjectPathCandidate: nil,
            selectedProjectPathCandidate: nil,
            sessions: sessions,
            currentSelectedProjectPath: "/sticky-selection"
        )

        XCTAssertEqual(selection.activeProjectPath, "/repo-a")
        XCTAssertEqual(selection.selectedProjectPath, "/repo-a")
    }

    private func makeResolver(
        displayPaths: [String: String] = [:]
    ) -> WorkspaceRestoreSelectionResolver {
        WorkspaceRestoreSelectionResolver(
            sessionPathResolver: WorkspaceSessionPathResolver(
                normalizePath: { normalizeRestoreSelectionTestPath($0) ?? "" },
                normalizeOptionalPath: { normalizeRestoreSelectionTestPath($0) }
            ),
            displayProjectPath: { displayPaths[$0] ?? $0 }
        )
    }
}

private func normalizeRestoreSelectionTestPath(_ path: String?) -> String? {
    guard let path else {
        return nil
    }
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }
    var normalized = trimmed.replacingOccurrences(of: "\\", with: "/")
    while normalized.count > 1 && normalized.hasSuffix("/") {
        normalized.removeLast()
    }
    if normalized == "/tmp/worktree" {
        normalized = "/private/tmp/worktree"
    }
    return normalized
}
