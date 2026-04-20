import XCTest
import Darwin
@testable import DevHavenCore

final class WorkspaceDisplayProjectResolverTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devhaven-display-project-resolver-\(UUID().uuidString)", isDirectory: true)
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
    func testResolveProjectReturnsCatalogProjectForEquivalentPath() throws {
        let repositoryURL = rootURL.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        let aliasURL = rootURL.appendingPathComponent("repo-alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: aliasURL, withDestinationURL: repositoryURL)

        let normalizedRepositoryPath = normalizeDisplayProjectTestPath(repositoryURL.path)
        let project = makeProject(name: "Repo", path: normalizedRepositoryPath)
        let resolver = makeResolver(
            projects: [project],
            projectsByPath: [normalizedRepositoryPath: project]
        )

        let resolved = try XCTUnwrap(resolver.resolveProject(for: aliasURL.path + "/"))

        XCTAssertEqual(resolved.path, normalizedRepositoryPath)
        XCTAssertEqual(resolved.name, "Repo")
        XCTAssertFalse(resolved.isDirectoryWorkspace)
    }

    @MainActor
    func testResolveProjectBuildsVirtualProjectForPersistedWorktree() throws {
        let repositoryURL = rootURL.appendingPathComponent("repo", isDirectory: true)
        let worktreeURL = rootURL.appendingPathComponent("repo-feature-a", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreeURL, withIntermediateDirectories: true)

        let normalizedRepositoryPath = normalizeDisplayProjectTestPath(repositoryURL.path)
        let normalizedWorktreePath = normalizeDisplayProjectTestPath(worktreeURL.path)
        let rootProject = makeProject(
            name: "Repo",
            path: normalizedRepositoryPath,
            worktrees: [
                ProjectWorktree(
                    id: "worktree-feature-a",
                    name: "feature-a",
                    path: normalizedWorktreePath,
                    branch: "feature/a",
                    inheritConfig: true,
                    created: 10,
                    updatedAt: 10
                )
            ],
            runConfigurations: [
                ProjectRunConfiguration(id: "run-1", name: "Dev", command: "npm run dev")
            ]
        )
        let resolver = makeResolver(
            projects: [rootProject],
            projectsByPath: [normalizedRepositoryPath: rootProject]
        )

        let resolved = try XCTUnwrap(resolver.resolveProject(for: normalizedWorktreePath))

        XCTAssertEqual(resolved.id, "worktree:\(normalizedWorktreePath)")
        XCTAssertEqual(resolved.path, normalizedWorktreePath)
        XCTAssertEqual(resolved.name, "feature-a")
        XCTAssertEqual(resolved.runConfigurations.map(\.name), ["Dev"])
        XCTAssertTrue(resolved.worktrees.isEmpty)
        XCTAssertTrue(resolved.isGitRepository)
    }

    @MainActor
    func testResolveProjectFallsBackToTransientSessionProject() throws {
        let directoryURL = rootURL.appendingPathComponent("workspace-root", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let normalizedDirectoryPath = normalizeDisplayProjectTestPath(directoryURL.path)
        let transientProject = Project.directoryWorkspace(at: normalizedDirectoryPath)
        let session = OpenWorkspaceSessionState(
            projectPath: normalizedDirectoryPath,
            controller: GhosttyWorkspaceController(projectPath: normalizedDirectoryPath),
            transientDisplayProject: transientProject
        )
        let resolver = makeResolver(sessions: [session])

        let resolved = try XCTUnwrap(resolver.resolveProject(for: directoryURL.path))

        XCTAssertEqual(resolved.path, normalizedDirectoryPath)
        XCTAssertEqual(resolved.name, "workspace-root")
        XCTAssertTrue(resolved.isDirectoryWorkspace)
    }

    @MainActor
    func testClearCacheMakesUpdatedCatalogProjectVisible() throws {
        let repositoryURL = rootURL.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)

        let normalizedRepositoryPath = normalizeDisplayProjectTestPath(repositoryURL.path)
        let source = MutableProjectCatalogSource(
            projects: [makeProject(name: "Repo", path: normalizedRepositoryPath)],
            projectsByPath: [:]
        )
        source.projectsByPath = [normalizedRepositoryPath: source.projects[0]]

        let resolver = WorkspaceDisplayProjectResolver(
            normalizePath: { normalizeDisplayProjectTestPath($0) },
            normalizeOptionalPath: { $0.map(normalizeDisplayProjectTestPath) },
            projects: { source.projects },
            projectsByNormalizedPath: { source.projectsByPath },
            workspaceSessionWithoutNormalizing: { _ in nil },
            workspaceSession: { _ in nil },
            buildWorktreeVirtualProject: { sourceProject, worktree in
                buildDisplayProjectVirtualProject(sourceProject: sourceProject, worktree: worktree)
            }
        )

        XCTAssertEqual(resolver.resolveProject(for: normalizedRepositoryPath)?.name, "Repo")

        let updatedProject = makeProject(name: "Repo v2", path: normalizedRepositoryPath)
        source.projects = [updatedProject]
        source.projectsByPath = [normalizedRepositoryPath: updatedProject]

        XCTAssertEqual(resolver.resolveProject(for: normalizedRepositoryPath)?.name, "Repo")

        resolver.clearCache()

        XCTAssertEqual(resolver.resolveProject(for: normalizedRepositoryPath)?.name, "Repo v2")
    }

    @MainActor
    private func makeResolver(
        projects: [Project] = [],
        projectsByPath: [String: Project] = [:],
        sessions: [OpenWorkspaceSessionState] = []
    ) -> WorkspaceDisplayProjectResolver {
        WorkspaceDisplayProjectResolver(
            normalizePath: { normalizeDisplayProjectTestPath($0) },
            normalizeOptionalPath: { $0.map(normalizeDisplayProjectTestPath) },
            projects: { projects },
            projectsByNormalizedPath: { projectsByPath },
            workspaceSessionWithoutNormalizing: { path in
                sessions.first(where: { $0.projectPath == path })
            },
            workspaceSession: { path in
                guard let normalizedPath = path.map(normalizeDisplayProjectTestPath) else {
                    return nil
                }
                return sessions.first(where: {
                    normalizeDisplayProjectTestPath($0.projectPath) == normalizedPath ||
                        normalizeDisplayProjectTestPath($0.rootProjectPath) == normalizedPath
                })
            },
            buildWorktreeVirtualProject: { sourceProject, worktree in
                buildDisplayProjectVirtualProject(sourceProject: sourceProject, worktree: worktree)
            }
        )
    }

    private func makeProject(
        name: String,
        path: String,
        worktrees: [ProjectWorktree] = [],
        runConfigurations: [ProjectRunConfiguration] = [],
        isGitRepository: Bool = true
    ) -> Project {
        let now = Date().timeIntervalSinceReferenceDate
        return Project(
            id: UUID().uuidString,
            name: name,
            path: path,
            tags: [],
            runConfigurations: runConfigurations,
            worktrees: worktrees,
            mtime: now,
            size: 0,
            checksum: UUID().uuidString,
            isGitRepository: isGitRepository,
            gitCommits: 1,
            gitLastCommit: now,
            created: now,
            checked: now
        )
    }
}

private final class MutableProjectCatalogSource: @unchecked Sendable {
    var projects: [Project]
    var projectsByPath: [String: Project]

    init(projects: [Project], projectsByPath: [String: Project]) {
        self.projects = projects
        self.projectsByPath = projectsByPath
    }
}

private func buildDisplayProjectVirtualProject(sourceProject: Project, worktree: ProjectWorktree) -> Project {
    let now = Date().timeIntervalSinceReferenceDate
    return Project(
        id: "worktree:\(worktree.path)",
        name: worktree.name,
        path: worktree.path,
        tags: sourceProject.tags,
        runConfigurations: sourceProject.runConfigurations,
        worktrees: [],
        mtime: sourceProject.mtime,
        size: sourceProject.size,
        checksum: "worktree:\(worktree.path)",
        isGitRepository: sourceProject.isGitRepository,
        gitCommits: sourceProject.gitCommits,
        gitLastCommit: sourceProject.gitLastCommit,
        gitLastCommitMessage: sourceProject.gitLastCommitMessage,
        gitDaily: sourceProject.gitDaily,
        notesSummary: sourceProject.notesSummary,
        created: worktree.created,
        checked: now,
        hasPersistedNotesSummary: sourceProject.hasPersistedNotesSummary
    )
}

private func normalizeDisplayProjectTestPath(_ path: String) -> String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return ""
    }
    var normalized = canonicalDisplayProjectTestPath(trimmed).replacingOccurrences(of: "\\", with: "/")
    while normalized.count > 1 && normalized.hasSuffix("/") {
        normalized.removeLast()
    }
    return normalized
}

private func canonicalDisplayProjectTestPath(_ path: String) -> String {
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

    let canonicalAncestorPath = realpathDisplayProjectTestPath(ancestorPath) ?? ancestorPath
    guard !trailingComponents.isEmpty else {
        return canonicalAncestorPath
    }

    return trailingComponents.reduce(canonicalAncestorPath as NSString) { partial, component in
        partial.appendingPathComponent(component) as NSString
    } as String
}

private func realpathDisplayProjectTestPath(_ path: String) -> String? {
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
