import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceSessionPathResolverTests: XCTestCase {
    func testSessionIndexUsesNormalizedPath() {
        let resolver = makeResolver()

        XCTAssertEqual(
            resolver.sessionIndex(
                for: "/tmp/worktree/",
                indexByNormalizedPath: ["/private/tmp/worktree": 2]
            ),
            2
        )
    }

    func testSessionReturnsIndexedSessionWhenIndexIsValid() {
        let sessions = [
            makeSession(projectPath: "/repo-a"),
            makeSession(projectPath: "/private/tmp/worktree", rootProjectPath: "/repo-root"),
        ]
        let resolver = makeResolver()

        let session = resolver.session(
            for: "/tmp/worktree",
            sessions: sessions,
            indexByNormalizedPath: ["/private/tmp/worktree": 1]
        )

        XCTAssertEqual(session?.projectPath, "/private/tmp/worktree")
    }

    func testSessionFallsBackToLastNonQuickRootSessionWhenIndexMissing() {
        let sessions = [
            makeSession(projectPath: "/quick", rootProjectPath: "/repo-root", isQuickTerminal: true),
            makeSession(projectPath: "/repo-root-feature-a", rootProjectPath: "/repo-root"),
            makeSession(projectPath: "/repo-root-feature-b", rootProjectPath: "/repo-root"),
        ]
        let resolver = makeResolver()

        let session = resolver.session(
            for: "/repo-root",
            sessions: sessions,
            indexByNormalizedPath: [:]
        )

        XCTAssertEqual(session?.projectPath, "/repo-root-feature-b")
    }

    func testCanonicalSessionPathUsesIndexedSessionWhenAvailable() {
        let sessions = [
            makeSession(projectPath: "/repo-a"),
            makeSession(projectPath: "/private/tmp/worktree", rootProjectPath: "/repo-root"),
        ]
        let resolver = makeResolver()

        let path = resolver.canonicalSessionPath(
            for: "/tmp/worktree/",
            sessions: sessions,
            indexByNormalizedPath: ["/private/tmp/worktree": 1]
        )

        XCTAssertEqual(path, "/private/tmp/worktree")
    }

    func testCanonicalSessionPathFallsBackToLastNonQuickRootSession() {
        let sessions = [
            makeSession(projectPath: "/repo-root-quick", rootProjectPath: "/repo-root", isQuickTerminal: true),
            makeSession(projectPath: "/repo-root-feature-a", rootProjectPath: "/repo-root"),
            makeSession(projectPath: "/repo-root-feature-b", rootProjectPath: "/repo-root"),
        ]
        let resolver = makeResolver()

        let path = resolver.canonicalSessionPath(
            for: "/repo-root",
            sessions: sessions,
            indexByNormalizedPath: [:]
        )

        XCTAssertEqual(path, "/repo-root-feature-b")
    }

    func testCanonicalSessionPathWithExplicitSessionsDoesNotNeedIndex() {
        let sessions = [
            makeSession(projectPath: "/private/tmp/worktree", rootProjectPath: "/repo-root"),
        ]
        let resolver = makeResolver()

        let path = resolver.canonicalSessionPath(
            for: "/tmp/worktree",
            sessions: sessions
        )

        XCTAssertEqual(path, "/private/tmp/worktree")
    }

    private func makeResolver() -> WorkspaceSessionPathResolver {
        WorkspaceSessionPathResolver(
            normalizePath: { normalizeSessionPathResolverTestPath($0) ?? "" },
            normalizeOptionalPath: { normalizeSessionPathResolverTestPath($0) }
        )
    }

    private func makeSession(
        projectPath: String,
        rootProjectPath: String? = nil,
        isQuickTerminal: Bool = false
    ) -> OpenWorkspaceSessionState {
        OpenWorkspaceSessionState(
            projectPath: projectPath,
            rootProjectPath: rootProjectPath,
            controller: GhosttyWorkspaceController(projectPath: projectPath),
            isQuickTerminal: isQuickTerminal
        )
    }
}

private func normalizeSessionPathResolverTestPath(_ path: String?) -> String? {
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
