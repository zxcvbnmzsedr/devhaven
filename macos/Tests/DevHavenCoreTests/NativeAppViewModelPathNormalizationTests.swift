import XCTest
import Darwin
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelPathNormalizationTests: XCTestCase {
    func testActivateWorkspaceProjectCanonicalizesEquivalentSessionPath() throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(projects: [fixture.makeProject(name: "Repo")])

        viewModel.enterWorkspace(fixture.repositoryURL.path)
        viewModel.activateWorkspaceProject(fixture.repositoryURL.path + "/")

        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, fixture.canonicalPath(fixture.repositoryURL.path))
        XCTAssertEqual(viewModel.selectedProjectPath, fixture.canonicalPath(fixture.repositoryURL.path))
        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [fixture.canonicalPath(fixture.repositoryURL.path)])
    }

    func testWorkspaceAlignmentProjectionResolvesProjectByNormalizedMemberPath() throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }

        let project = fixture.makeProject(name: "Repo")
        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(
                workspaceAlignmentGroups: [
                    WorkspaceAlignmentGroupDefinition(
                        name: "联调",
                        targetBranch: "main",
                        projectPaths: [fixture.repositoryURL.path + "/"]
                    )
                ]
            ),
            projects: [project]
        )

        let member = try XCTUnwrap(viewModel.workspaceAlignmentGroups.first?.members.first)
        XCTAssertEqual(member.projectPath, fixture.canonicalPath(fixture.repositoryURL.path))
        XCTAssertEqual(member.projectName, "Repo")
        XCTAssertEqual(member.alias, "Repo")
    }

    func testEnterDirectoryWorkspaceCreatesTransientDisplayProject() throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }

        let directoryURL = fixture.rootURL.appendingPathComponent("workspace-root", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let viewModel = fixture.makeViewModel()
        viewModel.enterDirectoryWorkspace(directoryURL.path)

        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, fixture.canonicalPath(directoryURL.path))
        XCTAssertEqual(viewModel.selectedProjectPath, fixture.canonicalPath(directoryURL.path))
        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [fixture.canonicalPath(directoryURL.path)])
        XCTAssertEqual(viewModel.activeWorkspaceProject?.path, fixture.canonicalPath(directoryURL.path))
        XCTAssertEqual(viewModel.activeWorkspaceProject?.name, "workspace-root")
        XCTAssertEqual(viewModel.activeWorkspaceProject?.isDirectoryWorkspace, true)
        XCTAssertEqual(viewModel.openWorkspaceProjects.map(\.path), [fixture.canonicalPath(directoryURL.path)])
        XCTAssertEqual(viewModel.workspaceSidebarGroups.first?.rootProject.path, fixture.canonicalPath(directoryURL.path))
        XCTAssertEqual(viewModel.workspaceSidebarGroups.first?.rootProject.isDirectoryWorkspace, true)
    }

    func testDirectoryWorkspaceSurvivesFilterSelectionReconciliation() throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }

        let directoryURL = fixture.rootURL.appendingPathComponent("workspace-root", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(projects: [fixture.makeProject(name: "Repo")])
        viewModel.enterDirectoryWorkspace(directoryURL.path)

        viewModel.selectDirectory(.all)
        viewModel.updateGitFilter(.all)

        XCTAssertTrue(viewModel.isWorkspacePresented)
        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [fixture.canonicalPath(directoryURL.path)])
        XCTAssertEqual(viewModel.activeWorkspaceProject?.isDirectoryWorkspace, true)
    }

    func testEnterWorkspacePromotesDirectoryWorkspaceBackToRegularProject() throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }

        let project = fixture.makeProject(name: "Repo")
        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(projects: [project])

        viewModel.enterDirectoryWorkspace(fixture.repositoryURL.path)
        XCTAssertEqual(viewModel.openWorkspaceSessions.first?.transientDisplayProject?.isDirectoryWorkspace, true)
        XCTAssertEqual(viewModel.workspaceSidebarGroups.first?.rootProject.isDirectoryWorkspace, true)

        viewModel.enterWorkspace(fixture.repositoryURL.path)

        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [fixture.canonicalPath(fixture.repositoryURL.path)])
        XCTAssertEqual(viewModel.activeWorkspaceProject?.name, "Repo")
        XCTAssertEqual(viewModel.activeWorkspaceProject?.isDirectoryWorkspace, false)
        XCTAssertNil(viewModel.openWorkspaceSessions.first?.transientDisplayProject)
        XCTAssertEqual(viewModel.workspaceSidebarGroups.first?.rootProject.name, "Repo")
        XCTAssertEqual(viewModel.workspaceSidebarGroups.first?.rootProject.isDirectoryWorkspace, false)
    }

    func testActivateWorkspaceSidebarProjectPromotesDirectoryWorkspaceBackToRegularProject() throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }

        let project = fixture.makeProject(name: "Repo")
        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(projects: [project])

        viewModel.enterDirectoryWorkspace(fixture.repositoryURL.path)
        XCTAssertEqual(viewModel.openWorkspaceSessions.first?.transientDisplayProject?.isDirectoryWorkspace, true)
        XCTAssertEqual(viewModel.workspaceSidebarGroups.first?.rootProject.isDirectoryWorkspace, true)

        viewModel.activateWorkspaceSidebarProject(fixture.repositoryURL.path)

        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [fixture.canonicalPath(fixture.repositoryURL.path)])
        XCTAssertEqual(viewModel.activeWorkspaceProject?.name, "Repo")
        XCTAssertEqual(viewModel.activeWorkspaceProject?.isDirectoryWorkspace, false)
        XCTAssertNil(viewModel.openWorkspaceSessions.first?.transientDisplayProject)
        XCTAssertEqual(viewModel.workspaceSidebarGroups.first?.rootProject.isDirectoryWorkspace, false)
    }

    func testDirectoryWorkspaceGitContextsFallbackToLiveRepositoryDetection() throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }
        try fixture.markRepositoryAsGitRepository()

        let viewModel = fixture.makeViewModel()
        viewModel.enterDirectoryWorkspace(fixture.repositoryURL.path)

        XCTAssertEqual(viewModel.activeWorkspaceProject?.isDirectoryWorkspace, true)
        XCTAssertTrue(viewModel.activeWorkspaceSupportsGitToolWindows)
        XCTAssertEqual(viewModel.activeWorkspaceGitRepositoryContext?.repositoryPath, fixture.canonicalPath(fixture.repositoryURL.path))
        XCTAssertEqual(viewModel.activeWorkspaceCommitRepositoryContext?.repositoryPath, fixture.canonicalPath(fixture.repositoryURL.path))

        viewModel.prepareActiveWorkspaceGitViewModel()
        viewModel.prepareActiveWorkspaceCommitViewModel()

        XCTAssertNotNil(viewModel.activeWorkspaceGitViewModel)
        XCTAssertNotNil(viewModel.activeWorkspaceCommitViewModel)
    }

    func testWorkspaceGitContextsFallbackWhenCatalogGitFlagIsStale() throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }
        try fixture.markRepositoryAsGitRepository()

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(projects: [fixture.makeProject(name: "Repo", isGitRepository: false)])

        viewModel.enterWorkspace(fixture.repositoryURL.path)

        XCTAssertEqual(viewModel.activeWorkspaceGitRepositoryContext?.repositoryPath, fixture.canonicalPath(fixture.repositoryURL.path))
        XCTAssertEqual(viewModel.activeWorkspaceCommitRepositoryContext?.repositoryPath, fixture.canonicalPath(fixture.repositoryURL.path))

        viewModel.prepareActiveWorkspaceGitViewModel()
        viewModel.prepareActiveWorkspaceCommitViewModel()
        viewModel.prepareActiveWorkspaceGitHubViewModel()

        XCTAssertNotNil(viewModel.activeWorkspaceGitViewModel)
        XCTAssertNotNil(viewModel.activeWorkspaceCommitViewModel)
        XCTAssertNotNil(viewModel.activeWorkspaceGitHubViewModel)
    }

    func testDirectoryWorkspaceAggregatesSymlinkedRepositoryRootAndWorktreeIntoOneFamily() throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }

        try fixture.makeGitRepository(at: fixture.repositoryURL)
        let worktreeURL = fixture.rootURL.appendingPathComponent("repo-worktree", isDirectory: true)
        try fixture.createGitWorktree(
            sourceRepositoryURL: fixture.repositoryURL,
            worktreeURL: worktreeURL,
            branch: "feature/worktree"
        )

        let workspaceRootURL = fixture.rootURL.appendingPathComponent("workspace-root", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRootURL, withIntermediateDirectories: true)
        try fixture.createSymlink(
            at: workspaceRootURL.appendingPathComponent("repo", isDirectory: true),
            destinationURL: fixture.repositoryURL
        )
        try fixture.createSymlink(
            at: workspaceRootURL.appendingPathComponent("repo-worktree", isDirectory: true),
            destinationURL: worktreeURL
        )

        let viewModel = fixture.makeViewModel()
        viewModel.enterDirectoryWorkspace(workspaceRootURL.path)

        let gitContext = try XCTUnwrap(viewModel.activeWorkspaceGitRepositoryContext)
        let commitContext = try XCTUnwrap(viewModel.activeWorkspaceCommitRepositoryContext)
        let family = try XCTUnwrap(gitContext.selectedRepositoryFamily)

        XCTAssertEqual(gitContext.rootProjectPath, fixture.canonicalPath(workspaceRootURL.path))
        XCTAssertEqual(gitContext.repositoryFamilies.count, 1)
        XCTAssertEqual(family.repositoryPath, fixture.canonicalPath(fixture.repositoryURL.path))
        XCTAssertEqual(
            Set(family.members.map(\.path)),
            Set([
                fixture.canonicalPath(fixture.repositoryURL.path),
                fixture.canonicalPath(worktreeURL.path),
            ])
        )
        XCTAssertEqual(
            family.members.filter(\.isRootProject).map(\.path),
            [fixture.canonicalPath(fixture.repositoryURL.path)]
        )
        XCTAssertEqual(commitContext.executionPath, fixture.canonicalPath(fixture.repositoryURL.path))
    }

    func testDirectoryWorkspaceRepositoryFamilySelectionPropagatesToCommitAndGitHubViewModels() throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }

        try fixture.makeGitRepository(at: fixture.repositoryURL)
        let secondRepositoryURL = fixture.rootURL.appendingPathComponent("repo-b", isDirectory: true)
        try fixture.makeGitRepository(at: secondRepositoryURL)

        let workspaceRootURL = fixture.rootURL.appendingPathComponent("workspace-root", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRootURL, withIntermediateDirectories: true)
        try fixture.createSymlink(
            at: workspaceRootURL.appendingPathComponent("repo-a", isDirectory: true),
            destinationURL: fixture.repositoryURL
        )
        try fixture.createSymlink(
            at: workspaceRootURL.appendingPathComponent("repo-b", isDirectory: true),
            destinationURL: secondRepositoryURL
        )

        let viewModel = fixture.makeViewModel()
        viewModel.enterDirectoryWorkspace(workspaceRootURL.path)
        viewModel.prepareActiveWorkspaceGitViewModel()
        viewModel.prepareActiveWorkspaceCommitViewModel()
        viewModel.prepareActiveWorkspaceGitHubViewModel()

        let gitViewModel = try XCTUnwrap(viewModel.activeWorkspaceGitViewModel)
        let targetFamily = try XCTUnwrap(gitViewModel.repositoryFamilies.first(where: {
            $0.repositoryPath == fixture.canonicalPath(secondRepositoryURL.path)
        }))

        gitViewModel.selectRepositoryFamily(targetFamily.id)

        XCTAssertEqual(viewModel.activeWorkspaceGitRepositoryContext?.repositoryPath, fixture.canonicalPath(secondRepositoryURL.path))
        XCTAssertEqual(viewModel.activeWorkspaceCommitRepositoryContext?.repositoryPath, fixture.canonicalPath(secondRepositoryURL.path))
        XCTAssertEqual(viewModel.activeWorkspaceCommitViewModel?.repositoryContext.repositoryPath, fixture.canonicalPath(secondRepositoryURL.path))
        XCTAssertEqual(viewModel.activeWorkspaceGitHubViewModel?.repositoryContext.repositoryPath, fixture.canonicalPath(secondRepositoryURL.path))
    }

    func testProjectTreeSelectionDrivesDirectoryWorkspaceGitFamilySelection() async throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }

        try fixture.makeGitRepository(at: fixture.repositoryURL)
        let secondRepositoryURL = fixture.rootURL.appendingPathComponent("repo-b", isDirectory: true)
        try fixture.makeGitRepository(at: secondRepositoryURL)

        let workspaceRootURL = fixture.rootURL.appendingPathComponent("workspace-root", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRootURL, withIntermediateDirectories: true)
        let firstLinkURL = workspaceRootURL.appendingPathComponent("repo-a", isDirectory: true)
        let secondLinkURL = workspaceRootURL.appendingPathComponent("repo-b", isDirectory: true)
        try fixture.createSymlink(at: firstLinkURL, destinationURL: fixture.repositoryURL)
        try fixture.createSymlink(at: secondLinkURL, destinationURL: secondRepositoryURL)

        let viewModel = fixture.makeViewModel()
        viewModel.enterDirectoryWorkspace(workspaceRootURL.path)
        viewModel.refreshWorkspaceProjectTree()

        let treeLoaded = await waitUntilPathNormalization(timeout: 2) {
            (viewModel.activeWorkspaceProjectTreeState?.rootNodes.count ?? 0) >= 2
        }
        XCTAssertTrue(treeLoaded)

        viewModel.selectWorkspaceProjectTreeNode(secondLinkURL.path)

        XCTAssertEqual(
            viewModel.activeWorkspaceGitRepositoryContext?.repositoryPath,
            fixture.canonicalPath(secondRepositoryURL.path)
        )
        XCTAssertEqual(
            viewModel.activeWorkspaceCommitRepositoryContext?.repositoryPath,
            fixture.canonicalPath(secondRepositoryURL.path)
        )
        XCTAssertEqual(
            viewModel.activeWorkspaceCommitRepositoryContext?.executionPath,
            fixture.canonicalPath(secondRepositoryURL.path)
        )
    }

    func testWorkspaceRootSessionIsNotTreatedAsStandaloneQuickTerminal() throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }

        let workspaceRootURL = fixture.rootURL.appendingPathComponent("workspace-root", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRootURL, withIntermediateDirectories: true)

        let viewModel = fixture.makeViewModel()
        let projectPath = fixture.canonicalPath(workspaceRootURL.path)
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: projectPath,
                rootProjectPath: projectPath,
                controller: GhosttyWorkspaceController(projectPath: projectPath),
                isQuickTerminal: true,
                workspaceRootContext: WorkspaceRootSessionContext(
                    workspaceID: "workspace-root",
                    workspaceName: "联调工作区"
                )
            )
        ]
        viewModel.activeWorkspaceProjectPath = projectPath

        XCTAssertFalse(viewModel.activeWorkspaceIsStandaloneQuickTerminal)
    }

    func testStandaloneQuickTerminalStillMarkedAsStandaloneQuickTerminal() throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }

        let quickTerminalPath = fixture.canonicalPath(fixture.homeURL.path)
        let viewModel = fixture.makeViewModel()
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: quickTerminalPath,
                rootProjectPath: quickTerminalPath,
                controller: GhosttyWorkspaceController(projectPath: quickTerminalPath),
                isQuickTerminal: true
            )
        ]
        viewModel.activeWorkspaceProjectPath = quickTerminalPath

        XCTAssertTrue(viewModel.activeWorkspaceIsStandaloneQuickTerminal)
    }

    func testNonGitProjectDoesNotSupportGitToolWindows() throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }

        let nonGitURL = fixture.rootURL.appendingPathComponent("non-git", isDirectory: true)
        try FileManager.default.createDirectory(at: nonGitURL, withIntermediateDirectories: true)

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            projects: [
                fixture.makeProject(name: "NonGit", path: nonGitURL.path, isGitRepository: false)
            ]
        )

        viewModel.enterWorkspace(nonGitURL.path)
        viewModel.toggleWorkspaceToolWindow(.commit)
        viewModel.toggleWorkspaceToolWindow(.git)

        XCTAssertFalse(viewModel.activeWorkspaceSupportsGitToolWindows)
        XCTAssertFalse(viewModel.workspaceToolWindowKindIsSupported(.commit))
        XCTAssertFalse(viewModel.workspaceToolWindowKindIsSupported(.git))
        XCTAssertFalse(viewModel.workspaceSideToolWindowState.isVisible)
        XCTAssertFalse(viewModel.workspaceBottomToolWindowState.isVisible)
    }

    func testDirectoryWorkspaceWithoutGitRepositoriesDoesNotSupportGitToolWindows() throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }

        let workspaceRootURL = fixture.rootURL.appendingPathComponent("workspace-root", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRootURL, withIntermediateDirectories: true)

        let viewModel = fixture.makeViewModel()
        viewModel.enterDirectoryWorkspace(workspaceRootURL.path)

        XCTAssertFalse(viewModel.activeWorkspaceSupportsGitToolWindows)
        XCTAssertFalse(viewModel.workspaceToolWindowKindIsSupported(.commit))
        XCTAssertFalse(viewModel.workspaceToolWindowKindIsSupported(.git))
    }

    func testDirectoryWorkspaceWithGitRepositorySupportsGitToolWindows() throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }

        let workspaceRootURL = fixture.rootURL.appendingPathComponent("workspace-root", isDirectory: true)
        let childRepositoryURL = workspaceRootURL.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRootURL, withIntermediateDirectories: true)
        try fixture.makeGitRepository(at: childRepositoryURL)

        let viewModel = fixture.makeViewModel()
        viewModel.enterDirectoryWorkspace(workspaceRootURL.path)

        XCTAssertTrue(viewModel.activeWorkspaceSupportsGitToolWindows)
        XCTAssertTrue(viewModel.workspaceToolWindowKindIsSupported(.commit))
        XCTAssertTrue(viewModel.workspaceToolWindowKindIsSupported(.git))
    }

    func testDirectoryWorkspaceGitDiscoveryDoesNotResolveBranchesSynchronously() throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }

        let workspaceRootURL = fixture.rootURL.appendingPathComponent("workspace-root", isDirectory: true)
        let childRepositoryURL = workspaceRootURL.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRootURL, withIntermediateDirectories: true)
        try fixture.makeGitRepository(at: childRepositoryURL)

        let worktreeService = CountingWorktreeService()
        let viewModel = fixture.makeViewModel(worktreeService: worktreeService)
        viewModel.enterDirectoryWorkspace(workspaceRootURL.path)

        XCTAssertEqual(worktreeService.currentBranchCallCount, 0)
        XCTAssertEqual(
            viewModel.activeWorkspaceGitRepositoryContext?.repositoryPath,
            fixture.canonicalPath(childRepositoryURL.path)
        )
        XCTAssertEqual(worktreeService.currentBranchCallCount, 0)

        viewModel.prepareActiveWorkspaceCommitViewModel()

        XCTAssertNotNil(viewModel.activeWorkspaceCommitViewModel)
        XCTAssertEqual(worktreeService.currentBranchCallCount, 0)
    }

    func testSyncActiveWorkspaceToolWindowContextHidesGitToolWindowsAfterSwitchingToNonGitProject() throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }

        let nonGitURL = fixture.rootURL.appendingPathComponent("non-git", isDirectory: true)
        try FileManager.default.createDirectory(at: nonGitURL, withIntermediateDirectories: true)

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            projects: [
                fixture.makeProject(name: "Repo", path: fixture.repositoryURL.path, isGitRepository: true),
                fixture.makeProject(name: "NonGit", path: nonGitURL.path, isGitRepository: false)
            ]
        )

        viewModel.enterWorkspace(fixture.repositoryURL.path)
        viewModel.showWorkspaceSideToolWindow(.commit)
        viewModel.showWorkspaceBottomToolWindow(.git)

        XCTAssertTrue(viewModel.workspaceSideToolWindowState.isVisible)
        XCTAssertTrue(viewModel.workspaceBottomToolWindowState.isVisible)

        viewModel.enterWorkspace(nonGitURL.path)
        viewModel.syncActiveWorkspaceToolWindowContext()

        XCTAssertFalse(viewModel.activeWorkspaceSupportsGitToolWindows)
        XCTAssertFalse(viewModel.workspaceSideToolWindowState.isVisible)
        XCTAssertFalse(viewModel.workspaceBottomToolWindowState.isVisible)
    }

    @MainActor
    private func waitUntilPathNormalization(
        timeout: TimeInterval,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }
}

private struct PathNormalizationFixture {
    let rootURL: URL
    let homeURL: URL
    let repositoryURL: URL

    static func make() throws -> PathNormalizationFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devhaven-path-normalization-\(UUID().uuidString)", isDirectory: true)
        let homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
        let repositoryURL = rootURL.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        return PathNormalizationFixture(rootURL: rootURL, homeURL: homeURL, repositoryURL: repositoryURL)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func markRepositoryAsGitRepository() throws {
        try FileManager.default.createDirectory(
            at: repositoryURL.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    func makeGitRepository(at repositoryURL: URL) throws {
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try runGit(["init"], at: repositoryURL)
        try runGit(["config", "user.name", "DevHaven Tests"], at: repositoryURL)
        try runGit(["config", "user.email", "tests@example.com"], at: repositoryURL)
        let readmeURL = repositoryURL.appendingPathComponent("README.md")
        try "fixture\n".write(to: readmeURL, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], at: repositoryURL)
        try runGit(["commit", "-m", "Initial commit"], at: repositoryURL)
        try runGit(["branch", "-M", "main"], at: repositoryURL)
    }

    func createGitWorktree(sourceRepositoryURL: URL, worktreeURL: URL, branch: String) throws {
        try runGit(
            ["worktree", "add", "-b", branch, worktreeURL.path],
            at: sourceRepositoryURL
        )
    }

    func createSymlink(at linkURL: URL, destinationURL: URL) throws {
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: destinationURL)
    }

    func canonicalPath(_ path: String) -> String {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return standardizedPath.withCString { pointer in
            guard let resolvedPointer = realpath(pointer, nil) else {
                return standardizedPath
            }
            defer { free(resolvedPointer) }
            return String(cString: resolvedPointer)
        }
    }

    @MainActor
    func makeViewModel(worktreeService: (any NativeWorktreeServicing)? = nil) -> NativeAppViewModel {
        NativeAppViewModel(
            store: LegacyCompatStore(homeDirectoryURL: homeURL),
            worktreeService: worktreeService ?? NativeGitWorktreeService(homeDirectoryURL: homeURL)
        )
    }

    func makeProject(name: String, path: String? = nil, isGitRepository: Bool = true) -> Project {
        let now = Date().timeIntervalSinceReferenceDate
        return Project(
            id: UUID().uuidString,
            name: name,
            path: path ?? repositoryURL.path,
            tags: [],
            runConfigurations: [],
            worktrees: [],
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

    private func runGit(_ arguments: [String], at repositoryURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryURL

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "git failed"
            throw NSError(domain: "PathNormalizationFixture", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
    }
}

private final class CountingWorktreeService: NativeWorktreeServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var storageCurrentBranchCallCount = 0

    var currentBranchCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storageCurrentBranchCallCount
    }

    func managedWorktreePath(for sourceProjectPath: String, branch: String) throws -> String {
        sourceProjectPath
    }

    func preflightCreateWorktree(_ request: NativeWorktreeCreateRequest) throws -> String {
        request.targetPath ?? request.sourceProjectPath
    }

    func currentBranch(at projectPath: String) throws -> String {
        lock.lock()
        storageCurrentBranchCallCount += 1
        lock.unlock()
        throw NativeWorktreeError.commandFailed("currentBranch should not be called during workspace Git discovery")
    }

    func listBranches(at projectPath: String) throws -> [NativeGitBranch] {
        []
    }

    func listWorktrees(at projectPath: String) throws -> [NativeGitWorktree] {
        []
    }

    func createWorktree(
        _ request: NativeWorktreeCreateRequest,
        progress: @escaping @Sendable (NativeWorktreeProgress) -> Void
    ) throws -> NativeWorktreeCreateResult {
        throw NativeWorktreeError.commandFailed("unused")
    }

    func removeWorktree(_ request: NativeWorktreeRemoveRequest) throws -> NativeWorktreeRemoveResult {
        throw NativeWorktreeError.commandFailed("unused")
    }

    func cleanupFailedWorktreeCreate(_ request: NativeWorktreeCleanupRequest) throws -> NativeWorktreeCleanupResult {
        throw NativeWorktreeError.commandFailed("unused")
    }
}
