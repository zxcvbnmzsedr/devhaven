import XCTest
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelWorkspaceTerminalTabTests: XCTestCase {
    func testCreateWorkspaceTerminalTabCreatesAndSelectsNewTerminalTab() throws {
        let projectPath = "/tmp/workspace-terminal-tabs"
        let controller = GhosttyWorkspaceController(projectPath: projectPath)
        let initialTabID = try XCTUnwrap(controller.selectedTabId)

        let viewModel = NativeAppViewModel()
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: projectPath,
                controller: controller
            )
        ]
        viewModel.activeWorkspaceProjectPath = projectPath

        let createdTab = try XCTUnwrap(viewModel.createWorkspaceTerminalTab())

        XCTAssertNotEqual(createdTab.id, initialTabID)
        XCTAssertEqual(controller.selectedTabId, createdTab.id)
        XCTAssertEqual(
            viewModel.workspacePresentedTabSnapshot(for: projectPath).selection,
            .terminal(createdTab.id)
        )
        XCTAssertEqual(viewModel.workspaceFocusedArea, .terminal)
    }

    func testCreateWorkspaceTerminalTabWithoutActiveWorkspaceReturnsNil() {
        let viewModel = NativeAppViewModel()

        XCTAssertNil(viewModel.createWorkspaceTerminalTab())
    }

    func testActiveWorkspaceLaunchRequestChangesSurfaceWithinSamePane() throws {
        let projectPath = "/tmp/workspace-terminal-pane-items"
        let controller = GhosttyWorkspaceController(projectPath: projectPath)
        let initialRequest = try XCTUnwrap(controller.selectedPane?.request)

        let viewModel = NativeAppViewModel()
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: projectPath,
                controller: controller
            )
        ]
        viewModel.activeWorkspaceProjectPath = projectPath

        let createdItem = try XCTUnwrap(controller.createTerminalItem(inPane: initialRequest.paneId))
        let updatedRequest = try XCTUnwrap(viewModel.activeWorkspaceLaunchRequest)

        XCTAssertEqual(updatedRequest.paneId, initialRequest.paneId)
        XCTAssertEqual(updatedRequest.surfaceId, createdItem.id)
        XCTAssertNotEqual(updatedRequest.surfaceId, initialRequest.surfaceId)
    }

    func testEnterOrResumeWorkspacePrefersHiddenMountedSessionOverChangedSelection() throws {
        let fixture = try WorkspaceResumeFixture.make()
        defer { fixture.cleanup() }

        let viewModel = fixture.makeViewModel()
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: fixture.repositoryURL.path,
                controller: GhosttyWorkspaceController(projectPath: fixture.repositoryURL.path)
            ),
            OpenWorkspaceSessionState(
                projectPath: fixture.worktreeURL.path,
                rootProjectPath: fixture.repositoryURL.path,
                controller: GhosttyWorkspaceController(projectPath: fixture.worktreeURL.path)
            )
        ]
        viewModel.selectedProjectPath = fixture.worktreeURL.path
        viewModel.activeWorkspaceProjectPath = fixture.worktreeURL.path

        viewModel.exitWorkspace()
        viewModel.selectedProjectPath = fixture.repositoryURL.path
        viewModel.enterOrResumeWorkspace()

        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, fixture.worktreeURL.path)
    }

    func testEnterWorkspaceOpensExplicitRootSessionInsteadOfHiddenMountedWorktree() throws {
        let fixture = try WorkspaceResumeFixture.make()
        defer { fixture.cleanup() }

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(projects: [fixture.makeProject(name: "Repo")])
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: fixture.repositoryURL.path,
                controller: GhosttyWorkspaceController(projectPath: fixture.repositoryURL.path)
            ),
            OpenWorkspaceSessionState(
                projectPath: fixture.worktreeURL.path,
                rootProjectPath: fixture.repositoryURL.path,
                controller: GhosttyWorkspaceController(projectPath: fixture.worktreeURL.path)
            )
        ]
        viewModel.activeWorkspaceProjectPath = fixture.worktreeURL.path

        viewModel.exitWorkspace()
        viewModel.enterWorkspace(fixture.repositoryURL.path)

        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, fixture.repositoryURL.path)
        XCTAssertEqual(
            canonicalPath(try XCTUnwrap(viewModel.selectedProjectPath)),
            canonicalPath(fixture.repositoryURL.path)
        )
    }

    func testMountedWorkspaceProjectPathKeepsLastExitedSessionWhileHidden() throws {
        let fixture = try WorkspaceResumeFixture.make()
        defer { fixture.cleanup() }

        let viewModel = fixture.makeViewModel()
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: fixture.repositoryURL.path,
                controller: GhosttyWorkspaceController(projectPath: fixture.repositoryURL.path)
            ),
            OpenWorkspaceSessionState(
                projectPath: fixture.worktreeURL.path,
                rootProjectPath: fixture.repositoryURL.path,
                controller: GhosttyWorkspaceController(projectPath: fixture.worktreeURL.path)
            )
        ]
        viewModel.activeWorkspaceProjectPath = fixture.worktreeURL.path

        viewModel.exitWorkspace()

        XCTAssertNil(viewModel.activeWorkspaceProjectPath)
        XCTAssertEqual(viewModel.mountedWorkspaceProjectPath, fixture.worktreeURL.path)
    }
}

private func canonicalPath(_ path: String) -> String {
    NSString(string: path).resolvingSymlinksInPath
}

private struct WorkspaceResumeFixture {
    let rootURL: URL
    let homeURL: URL
    let repositoryURL: URL
    let worktreeURL: URL

    static func make() throws -> WorkspaceResumeFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devhaven-workspace-resume-\(UUID().uuidString)", isDirectory: true)
        let homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
        let repositoryURL = rootURL.appendingPathComponent("repo", isDirectory: true)
        let worktreeURL = rootURL.appendingPathComponent("repo-feature", isDirectory: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreeURL, withIntermediateDirectories: true)
        return WorkspaceResumeFixture(
            rootURL: rootURL,
            homeURL: homeURL,
            repositoryURL: repositoryURL,
            worktreeURL: worktreeURL
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    @MainActor
    func makeViewModel() -> NativeAppViewModel {
        NativeAppViewModel(
            store: LegacyCompatStore(homeDirectoryURL: homeURL),
            worktreeService: NativeGitWorktreeService(homeDirectoryURL: homeURL)
        )
    }

    func makeProject(name: String) -> Project {
        let now = Date().timeIntervalSinceReferenceDate
        return Project(
            id: UUID().uuidString,
            name: name,
            path: repositoryURL.path,
            tags: [],
            runConfigurations: [],
            worktrees: [
                ProjectWorktree(
                    id: UUID().uuidString,
                    name: "feature",
                    path: worktreeURL.path,
                    branch: "feature",
                    inheritConfig: true,
                    created: now
                )
            ],
            mtime: now,
            size: 0,
            checksum: UUID().uuidString,
            isGitRepository: false,
            gitCommits: 0,
            gitLastCommit: now,
            created: now,
            checked: now
        )
    }
}
