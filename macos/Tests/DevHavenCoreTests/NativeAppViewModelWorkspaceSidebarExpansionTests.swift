import XCTest
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelWorkspaceSidebarExpansionTests: XCTestCase {
    func testWorkspaceSidebarProjectExpansionPersistsAcrossReload() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devhaven-workspace-sidebar-expansion-\(UUID().uuidString)", isDirectory: true)
        let homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = LegacyCompatStore(homeDirectoryURL: homeURL)
        let project = makeProject(
            id: "project-a",
            name: "Project A",
            path: "/tmp/project-a",
            worktrees: [
                makeWorktree(id: "worktree-a", name: "Feature A", path: "/tmp/project-a-feature-a", branch: "feature/a"),
                makeWorktree(id: "worktree-b", name: "Feature B", path: "/tmp/project-a-feature-b", branch: "feature/b")
            ]
        )

        let viewModel = NativeAppViewModel(store: store)
        seed(viewModel, with: project)

        XCTAssertEqual(viewModel.workspaceSidebarGroups.first?.isWorktreeListExpanded, true)

        viewModel.setWorkspaceSidebarProjectExpanded(false, for: project.path)

        XCTAssertEqual(viewModel.workspaceSidebarGroups.first?.isWorktreeListExpanded, false)
        let collapsedPaths = viewModel.snapshot.appState.settings.collapsedWorkspaceSidebarProjectPaths
        XCTAssertEqual(collapsedPaths.count, 1)
        XCTAssertTrue(collapsedPaths[0].hasSuffix("/project-a"))

        let reloadedAppState = try store.loadSnapshot().appState
        let reloadedViewModel = NativeAppViewModel(store: store)
        reloadedViewModel.snapshot = NativeAppSnapshot(appState: reloadedAppState, projects: [project])
        reloadedViewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: project.path,
                controller: GhosttyWorkspaceController(projectPath: project.path)
            )
        ]

        XCTAssertEqual(reloadedViewModel.workspaceSidebarGroups.first?.isWorktreeListExpanded, false)
        XCTAssertEqual(
            reloadedViewModel.snapshot.appState.settings.collapsedWorkspaceSidebarProjectPaths,
            collapsedPaths
        )

        reloadedViewModel.setWorkspaceSidebarProjectExpanded(true, for: project.path)

        XCTAssertEqual(reloadedViewModel.workspaceSidebarGroups.first?.isWorktreeListExpanded, true)
        XCTAssertTrue(reloadedViewModel.snapshot.appState.settings.collapsedWorkspaceSidebarProjectPaths.isEmpty)
    }

    private func seed(_ viewModel: NativeAppViewModel, with project: Project) {
        viewModel.snapshot = NativeAppSnapshot(projects: [project])
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: project.path,
                controller: GhosttyWorkspaceController(projectPath: project.path)
            )
        ]
    }

    private func makeProject(
        id: String,
        name: String,
        path: String,
        worktrees: [ProjectWorktree]
    ) -> Project {
        Project(
            id: id,
            name: name,
            path: path,
            tags: [],
            runConfigurations: [],
            worktrees: worktrees,
            mtime: 0,
            size: 0,
            checksum: "",
            isGitRepository: true,
            gitCommits: 0,
            gitLastCommit: 0,
            gitLastCommitMessage: nil,
            gitDaily: nil,
            notesSummary: nil,
            created: 0,
            checked: 0
        )
    }

    private func makeWorktree(
        id: String,
        name: String,
        path: String,
        branch: String
    ) -> ProjectWorktree {
        ProjectWorktree(
            id: id,
            name: name,
            path: path,
            branch: branch,
            inheritConfig: true,
            created: 0
        )
    }
}
