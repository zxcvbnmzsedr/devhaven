import XCTest
import Darwin
@testable import DevHavenCore

final class WorkspaceSessionDisplayMapperTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devhaven-session-display-mapper-\(UUID().uuidString)", isDirectory: true)
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
    func testDisplayProjectPathFallsBackWhenResolverMisses() {
        let mapper = makeMapper()

        XCTAssertEqual(
            mapper.displayProjectPath(for: "/tmp/missing", rootProjectPath: "/tmp/missing", fallbackPath: "/tmp/missing"),
            "/tmp/missing"
        )
    }

    @MainActor
    func testNormalizedRestoreSnapshotCanonicalizesPathsAndDirectoryWorkspaceProject() throws {
        let workspaceURL = rootURL.appendingPathComponent("workspace-root", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let aliasURL = rootURL.appendingPathComponent("workspace-alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: aliasURL, withDestinationURL: workspaceURL)

        let mapper = makeMapper()
        let snapshot = ProjectWorkspaceRestoreSnapshot(
            projectPath: aliasURL.path + "/",
            rootProjectPath: aliasURL.path + "/",
            isQuickTerminal: false,
            transientDisplayProject: Project.directoryWorkspace(at: aliasURL.path + "/"),
            workspaceId: "workspace-1",
            selectedTabId: nil,
            nextTabNumber: 1,
            nextPaneNumber: 1,
            tabs: []
        )

        let normalized = mapper.normalizedRestoreSnapshot(snapshot)

        XCTAssertEqual(normalized.projectPath, normalizeSessionDisplayTestPath(workspaceURL.path))
        XCTAssertEqual(normalized.rootProjectPath, normalizeSessionDisplayTestPath(workspaceURL.path))
        XCTAssertEqual(normalized.transientDisplayProject?.path, normalizeSessionDisplayTestPath(workspaceURL.path))
        XCTAssertTrue(normalized.transientDisplayProject?.isDirectoryWorkspace == true)
    }

    @MainActor
    func testRestoredSessionStateUsesResolvedDisplayPaths() throws {
        let repositoryURL = rootURL.appendingPathComponent("repo", isDirectory: true)
        let worktreeURL = rootURL.appendingPathComponent("repo-feature", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreeURL, withIntermediateDirectories: true)

        let normalizedRepositoryPath = normalizeSessionDisplayTestPath(repositoryURL.path)
        let normalizedWorktreePath = normalizeSessionDisplayTestPath(worktreeURL.path)
        let rootProject = makeProject(name: "Repo", path: normalizedRepositoryPath)
        let worktreeProject = makeProject(name: "feature", path: normalizedWorktreePath)
        let mapper = makeMapper(
            resolvedProjects: [
                SessionDisplayLookupKey(path: normalizedRepositoryPath, rootProjectPath: normalizedRepositoryPath): rootProject,
                SessionDisplayLookupKey(path: normalizedWorktreePath, rootProjectPath: normalizedRepositoryPath): worktreeProject,
            ]
        )
        let controller = GhosttyWorkspaceController(projectPath: normalizedWorktreePath)
        let workspaceRootContext = WorkspaceRootSessionContext(workspaceID: "workspace-1", workspaceName: "联调")
        let snapshot = ProjectWorkspaceRestoreSnapshot(
            projectPath: normalizedWorktreePath,
            rootProjectPath: normalizedRepositoryPath,
            isQuickTerminal: false,
            workspaceId: "workspace-1",
            selectedTabId: nil,
            nextTabNumber: 1,
            nextPaneNumber: 1,
            tabs: []
        )

        let session = mapper.restoredSessionState(
            from: snapshot,
            controller: controller,
            workspaceRootContext: workspaceRootContext
        )

        XCTAssertEqual(session.projectPath, normalizedWorktreePath)
        XCTAssertEqual(session.rootProjectPath, normalizedRepositoryPath)
        XCTAssertEqual(session.workspaceRootContext, workspaceRootContext)
        XCTAssertFalse(session.isQuickTerminal)
    }

    @MainActor
    func testRestoredSessionStateNormalizesDirectoryWorkspaceTransientProjectWithSnapshotPath() throws {
        let workspaceURL = rootURL.appendingPathComponent("workspace-root", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let normalizedWorkspacePath = normalizeSessionDisplayTestPath(workspaceURL.path)
        let mapper = makeMapper()
        let snapshot = ProjectWorkspaceRestoreSnapshot(
            projectPath: normalizedWorkspacePath,
            rootProjectPath: normalizedWorkspacePath,
            isQuickTerminal: false,
            transientDisplayProject: Project.directoryWorkspace(at: normalizedWorkspacePath + "/"),
            workspaceId: "workspace-1",
            selectedTabId: nil,
            nextTabNumber: 1,
            nextPaneNumber: 1,
            tabs: []
        )

        let session = mapper.restoredSessionState(
            from: snapshot,
            controller: GhosttyWorkspaceController(projectPath: normalizedWorkspacePath),
            workspaceRootContext: nil
        )

        XCTAssertEqual(session.transientDisplayProject?.path, normalizedWorkspacePath)
        XCTAssertTrue(session.transientDisplayProject?.isDirectoryWorkspace == true)
    }

    @MainActor
    private func makeMapper(
        resolvedProjects: [SessionDisplayLookupKey: Project] = [:]
    ) -> WorkspaceSessionDisplayMapper {
        WorkspaceSessionDisplayMapper(
            normalizePath: { normalizeSessionDisplayTestPath($0) },
            resolveDisplayProject: { path, rootProjectPath in
                resolvedProjects[SessionDisplayLookupKey(
                    path: normalizeSessionDisplayTestPath(path),
                    rootProjectPath: rootProjectPath.map(normalizeSessionDisplayTestPath)
                )]
            }
        )
    }

    private func makeProject(name: String, path: String) -> Project {
        let now = Date().timeIntervalSinceReferenceDate
        return Project(
            id: UUID().uuidString,
            name: name,
            path: path,
            tags: [],
            runConfigurations: [],
            worktrees: [],
            mtime: now,
            size: 0,
            checksum: UUID().uuidString,
            isGitRepository: true,
            gitCommits: 1,
            gitLastCommit: now,
            created: now,
            checked: now
        )
    }
}

private struct SessionDisplayLookupKey: Hashable {
    let path: String
    let rootProjectPath: String?
}

private func normalizeSessionDisplayTestPath(_ path: String) -> String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return ""
    }
    var normalized = canonicalSessionDisplayTestPath(trimmed).replacingOccurrences(of: "\\", with: "/")
    while normalized.count > 1 && normalized.hasSuffix("/") {
        normalized.removeLast()
    }
    return normalized
}

private func canonicalSessionDisplayTestPath(_ path: String) -> String {
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

    let canonicalAncestorPath = realpathSessionDisplayTestPath(ancestorPath) ?? ancestorPath
    guard !trailingComponents.isEmpty else {
        return canonicalAncestorPath
    }

    return trailingComponents.reduce(canonicalAncestorPath as NSString) { partial, component in
        partial.appendingPathComponent(component) as NSString
    } as String
}

private func realpathSessionDisplayTestPath(_ path: String) -> String? {
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
