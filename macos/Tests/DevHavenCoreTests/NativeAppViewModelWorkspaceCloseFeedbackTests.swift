import XCTest
@testable import DevHavenCore

    @MainActor
    final class NativeAppViewModelWorkspaceCloseFeedbackTests: XCTestCase {
    func testClosingQuickTerminalWithFeedbackShowsToast() {
        let quickTerminalPath = FileManager.default.homeDirectoryForCurrentUser.path
        let viewModel = NativeAppViewModel()
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: quickTerminalPath,
                controller: GhosttyWorkspaceController(projectPath: quickTerminalPath),
                isQuickTerminal: true
            )
        ]
        viewModel.activeWorkspaceProjectPath = quickTerminalPath

        viewModel.closeWorkspaceProjectWithFeedback(quickTerminalPath)

        XCTAssertTrue(viewModel.openWorkspaceSessions.isEmpty)
        XCTAssertNil(viewModel.activeWorkspaceProjectPath)
        XCTAssertEqual(viewModel.workspaceToastMessage, "已结束快速终端")
        viewModel.dismissWorkspaceToast()
    }

    func testClosingWorkspaceRootWithFeedbackShowsWorkspaceToast() {
        let workspaceRootPath = "/tmp/workspace-root"
        let viewModel = NativeAppViewModel()
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: workspaceRootPath,
                controller: GhosttyWorkspaceController(projectPath: workspaceRootPath),
                isQuickTerminal: true,
                workspaceRootContext: WorkspaceRootSessionContext(
                    workspaceID: "workspace-1",
                    workspaceName: "支付链路"
                )
            )
        ]
        viewModel.activeWorkspaceProjectPath = workspaceRootPath

        viewModel.closeWorkspaceProjectWithFeedback(workspaceRootPath)

        XCTAssertTrue(viewModel.openWorkspaceSessions.isEmpty)
        XCTAssertNil(viewModel.activeWorkspaceProjectPath)
        XCTAssertEqual(viewModel.workspaceToastMessage, "已关闭工作区「支付链路」")
        viewModel.dismissWorkspaceToast()
    }

    func testClosingRegularWorkspaceWithFeedbackDoesNotShowToast() {
        let projectPath = "/tmp/regular-project"
        let viewModel = NativeAppViewModel()
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: projectPath,
                controller: GhosttyWorkspaceController(projectPath: projectPath)
            )
        ]
        viewModel.activeWorkspaceProjectPath = projectPath

        viewModel.closeWorkspaceProjectWithFeedback(projectPath)

        XCTAssertTrue(viewModel.openWorkspaceSessions.isEmpty)
        XCTAssertNil(viewModel.workspaceToastMessage)
    }

    func testClosingRegularWorkspaceSessionWithFeedbackShowsProjectToast() {
        let rootProjectPath = "/tmp/project"
        let companionPath = "/tmp/project-worktree"
        let viewModel = NativeAppViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            projects: [
                Project(
                    id: rootProjectPath,
                    name: "DevHaven",
                    path: rootProjectPath,
                    tags: [],
                    runConfigurations: [],
                    worktrees: [
                        ProjectWorktree(
                            id: "worktree-1",
                            name: "feature/tab-close",
                            path: companionPath,
                            branch: "feature/tab-close",
                            inheritConfig: true,
                            created: 0
                        )
                    ],
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
            ]
        )
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: rootProjectPath,
                controller: GhosttyWorkspaceController(projectPath: rootProjectPath)
            ),
            OpenWorkspaceSessionState(
                projectPath: companionPath,
                rootProjectPath: rootProjectPath,
                controller: GhosttyWorkspaceController(projectPath: companionPath)
            )
        ]
        viewModel.activeWorkspaceProjectPath = rootProjectPath

        viewModel.closeWorkspaceSessionWithFeedback(rootProjectPath)

        XCTAssertEqual(viewModel.openWorkspaceSessions.map(\.projectPath), [companionPath])
        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, companionPath)
        XCTAssertEqual(viewModel.workspaceToastMessage, "已关闭项目「DevHaven」")
        viewModel.dismissWorkspaceToast()
    }
}
