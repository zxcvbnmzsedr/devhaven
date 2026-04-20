import XCTest
import Darwin
@testable import DevHavenCore

final class WorkspaceGitSelectionResolverTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devhaven-git-selection-resolver-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        rootURL = nil
        try super.tearDownWithError()
    }

    @MainActor
    func testSelectionSnapshotUsesStoredExecutionPathForRootProjectFamily() throws {
        let repositoryURL = rootURL.appendingPathComponent("repo", isDirectory: true)
        let worktreeURL = rootURL.appendingPathComponent("repo-feature", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreeURL, withIntermediateDirectories: true)

        let normalizedRootPath = normalizeGitTestPath(repositoryURL.path)
        let normalizedWorktreePath = normalizeGitTestPath(worktreeURL.path)
        let rootProject = makeProject(
            name: "Repo",
            path: normalizedRootPath,
            isGitRepository: true,
            worktrees: [
                ProjectWorktree(
                    id: "worktree-feature",
                    name: "feature",
                    path: normalizedWorktreePath,
                    branch: "feature/refactor",
                    inheritConfig: true,
                    created: 0,
                    updatedAt: 0
                )
            ]
        )
        let resolver = makeResolver(
            rootProjectByPath: [normalizedRootPath: rootProject],
            currentBranches: [normalizedRootPath: "main"],
            storedExecutionPaths: [normalizedRootPath: normalizedWorktreePath]
        )

        let snapshot = try XCTUnwrap(resolver.selectionSnapshot(for: normalizedRootPath))

        XCTAssertEqual(snapshot.gitContext.repositoryPath, normalizedRootPath)
        XCTAssertEqual(snapshot.commitContext.executionPath, normalizedWorktreePath)
        XCTAssertEqual(snapshot.gitContext.repositoryFamilies.count, 1)
        XCTAssertEqual(snapshot.gitContext.selectedRepositoryFamily?.members.map(\.path), [normalizedRootPath, normalizedWorktreePath])
    }

    @MainActor
    func testSelectionSnapshotPrefersActiveDiscoveredRepositoryFamily() throws {
        let workspaceRootURL = rootURL.appendingPathComponent("workspace-root", isDirectory: true)
        let repoAURL = workspaceRootURL.appendingPathComponent("repo-a", isDirectory: true)
        let repoBURL = workspaceRootURL.appendingPathComponent("repo-b", isDirectory: true)
        try createRepositoryDirectory(at: repoAURL)
        try createRepositoryDirectory(at: repoBURL)

        let normalizedWorkspaceRootPath = normalizeGitTestPath(workspaceRootURL.path)
        let normalizedRepoBPath = normalizeGitTestPath(repoBURL.path)
        let resolver = makeResolver(
            activeProjectPath: normalizedRepoBPath,
            openSessions: [
                OpenWorkspaceSessionState(
                    projectPath: normalizedRepoBPath,
                    rootProjectPath: normalizedWorkspaceRootPath,
                    controller: GhosttyWorkspaceController(projectPath: normalizedRepoBPath)
                )
            ]
        )

        let snapshot = try XCTUnwrap(resolver.selectionSnapshot(for: normalizedWorkspaceRootPath))

        XCTAssertEqual(snapshot.gitContext.repositoryPath, normalizedRepoBPath)
        XCTAssertEqual(snapshot.commitContext.repositoryPath, normalizedRepoBPath)
        XCTAssertEqual(snapshot.commitContext.executionPath, normalizedRepoBPath)
    }

    @MainActor
    func testSelectionForProjectTreePathUsesDeepestMatchingRepositoryMember() throws {
        let workspaceRootURL = rootURL.appendingPathComponent("workspace-root", isDirectory: true)
        let repoAURL = workspaceRootURL.appendingPathComponent("repo-a", isDirectory: true)
        let repoBURL = workspaceRootURL.appendingPathComponent("repo-b", isDirectory: true)
        try createRepositoryDirectory(at: repoAURL)
        try createRepositoryDirectory(at: repoBURL)
        let repoBSourceURL = repoBURL.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: repoBSourceURL, withIntermediateDirectories: true)
        let fileURL = repoBSourceURL.appendingPathComponent("App.swift")
        try "print(\"hi\")\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let normalizedWorkspaceRootPath = normalizeGitTestPath(workspaceRootURL.path)
        let normalizedRepoBPath = normalizeGitTestPath(repoBURL.path)
        let resolver = makeResolver()

        let selection = try XCTUnwrap(
            resolver.selectionForProjectTreePath(fileURL.path, in: normalizedWorkspaceRootPath)
        )

        XCTAssertEqual(selection.executionPath, normalizedRepoBPath)
        XCTAssertTrue(selection.familyID.hasSuffix("/repo-b/.git"))
    }

    private func createRepositoryDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    @MainActor
    private func makeResolver(
        rootProjectByPath: [String: Project] = [:],
        activeProjectPath: String? = nil,
        openSessions: [OpenWorkspaceSessionState] = [],
        currentBranches: [String: String] = [:],
        storedFamilyIDs: [String: String] = [:],
        storedExecutionPaths: [String: String] = [:],
        liveRootRepositoryPaths: [String: String] = [:]
    ) -> WorkspaceGitSelectionResolver {
        WorkspaceGitSelectionResolver(
            normalizePath: { normalizeGitTestPath($0) },
            rootProjectForPath: { rootProjectByPath[$0] },
            activeProjectPath: { activeProjectPath },
            openWorkspaceSessions: { openSessions },
            currentBranchByProjectPath: { currentBranches },
            storedFamilyID: { storedFamilyIDs[$0] },
            storedExecutionPath: { storedExecutionPaths[$0] },
            resolveDisplayProject: { _, _ in nil },
            liveRootRepositoryPath: { liveRootRepositoryPaths[$0] }
        )
    }

    private func makeProject(
        name: String,
        path: String,
        isGitRepository: Bool,
        worktrees: [ProjectWorktree] = []
    ) -> Project {
        let now = Date().timeIntervalSinceReferenceDate
        return Project(
            id: UUID().uuidString,
            name: name,
            path: path,
            tags: [],
            runConfigurations: [],
            worktrees: worktrees,
            mtime: now,
            size: 0,
            checksum: UUID().uuidString,
            isGitRepository: isGitRepository,
            gitCommits: 0,
            gitLastCommit: 0,
            created: now,
            checked: now
        )
    }
}

private func normalizeGitTestPath(_ path: String) -> String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return ""
    }
    var normalized = canonicalGitTestPath(trimmed).replacingOccurrences(of: "\\", with: "/")
    while normalized.count > 1 && normalized.hasSuffix("/") {
        normalized.removeLast()
    }
    return normalized
}

private func canonicalGitTestPath(_ path: String) -> String {
    let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
    let fileManager = FileManager.default
    var ancestorPath = standardizedPath
    var trailingComponents = [String]()

    while ancestorPath != "/", !fileManager.fileExists(atPath: ancestorPath) {
        let lastComponent = (ancestorPath as NSString).lastPathComponent
        guard !lastComponent.isEmpty else {
            break
        }
        trailingComponents.insert(lastComponent, at: 0)
        ancestorPath = (ancestorPath as NSString).deletingLastPathComponent
        if ancestorPath.isEmpty {
            ancestorPath = "/"
            break
        }
    }

    let canonicalAncestorPath = realpathGitTestPath(ancestorPath) ?? ancestorPath
    guard !trailingComponents.isEmpty else {
        return canonicalAncestorPath
    }

    return trailingComponents.reduce(canonicalAncestorPath as NSString) { partial, component in
        partial.appendingPathComponent(component) as NSString
    } as String
}

private func realpathGitTestPath(_ path: String) -> String? {
    guard !path.isEmpty else {
        return nil
    }
    return path.withCString { pointer in
        guard let resolvedPointer = realpath(pointer, nil) else {
            return nil
        }
        defer { free(resolvedPointer) }
        return String(cString: resolvedPointer)
    }
}
