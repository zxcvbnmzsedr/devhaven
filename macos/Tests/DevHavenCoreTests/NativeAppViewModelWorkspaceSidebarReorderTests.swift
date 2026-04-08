import XCTest
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelWorkspaceSidebarReorderTests: XCTestCase {
    func testWorkspaceSidebarGroupsFollowSessionOrderAcrossProjectsAndWorkspaceRoots() {
        let projectA = makeProject(id: "project-a", name: "Project A", path: "/tmp/project-a")
        let projectB = makeProject(id: "project-b", name: "Project B", path: "/tmp/project-b")
        let workspaceRootPath = "/tmp/workspace-root"
        let workspaceRootID = Project.workspaceRoot(name: "支付链路", path: workspaceRootPath).id

        let viewModel = NativeAppViewModel()
        viewModel.snapshot = NativeAppSnapshot(projects: [projectA, projectB])
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: projectB.path,
                controller: GhosttyWorkspaceController(projectPath: projectB.path)
            ),
            OpenWorkspaceSessionState(
                projectPath: workspaceRootPath,
                controller: GhosttyWorkspaceController(projectPath: workspaceRootPath),
                isQuickTerminal: true,
                workspaceRootContext: WorkspaceRootSessionContext(
                    workspaceID: "workspace-1",
                    workspaceName: "支付链路"
                )
            ),
            OpenWorkspaceSessionState(
                projectPath: projectA.path,
                controller: GhosttyWorkspaceController(projectPath: projectA.path)
            ),
        ]

        XCTAssertEqual(
            viewModel.workspaceSidebarGroups.map(\.rootProject.id),
            [projectB.id, workspaceRootID, projectA.id]
        )
    }

    func testMovingWorkspaceSidebarGroupMovesAllOwnedSessionsTogether() {
        let projectA = makeProject(id: "project-a", name: "Project A", path: "/tmp/project-a")
        let projectB = makeProject(id: "project-b", name: "Project B", path: "/tmp/project-b")
        let projectAWorktreePath = "/tmp/project-a-worktree"
        let workspaceRootPath = "/tmp/workspace-root"
        let workspaceRootID = Project.workspaceRoot(name: "支付链路", path: workspaceRootPath).id

        let viewModel = NativeAppViewModel()
        viewModel.snapshot = NativeAppSnapshot(projects: [projectA, projectB])
        viewModel.openWorkspaceSessions = [
            OpenWorkspaceSessionState(
                projectPath: projectA.path,
                controller: GhosttyWorkspaceController(projectPath: projectA.path)
            ),
            OpenWorkspaceSessionState(
                projectPath: projectB.path,
                controller: GhosttyWorkspaceController(projectPath: projectB.path)
            ),
            OpenWorkspaceSessionState(
                projectPath: projectAWorktreePath,
                rootProjectPath: projectA.path,
                controller: GhosttyWorkspaceController(projectPath: projectAWorktreePath)
            ),
            OpenWorkspaceSessionState(
                projectPath: workspaceRootPath,
                controller: GhosttyWorkspaceController(projectPath: workspaceRootPath),
                isQuickTerminal: true,
                workspaceRootContext: WorkspaceRootSessionContext(
                    workspaceID: "workspace-1",
                    workspaceName: "支付链路"
                )
            ),
        ]

        viewModel.moveWorkspaceSidebarGroup(
            projectA.id,
            relativeTo: workspaceRootID,
            insertAfter: true
        )

        XCTAssertEqual(
            viewModel.openWorkspaceSessions.map(\.projectPath),
            [projectB.path, workspaceRootPath, projectA.path, projectAWorktreePath]
        )
        XCTAssertEqual(
            viewModel.workspaceSidebarGroups.map(\.rootProject.id),
            [projectB.id, workspaceRootID, projectA.id]
        )
    }

    func testMovingWorkspaceAlignmentGroupPersistsOrder() throws {
        let homeURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "devhaven-sidebar-reorder-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: homeURL) }

        let store = LegacyCompatStore(homeDirectoryURL: homeURL)
        let viewModel = NativeAppViewModel(store: store)
        let groupA = WorkspaceAlignmentGroupDefinition(id: "ws-a", name: "A", targetBranch: "main")
        let groupB = WorkspaceAlignmentGroupDefinition(id: "ws-b", name: "B", targetBranch: "main")
        let groupC = WorkspaceAlignmentGroupDefinition(id: "ws-c", name: "C", targetBranch: "main")
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [groupA, groupB, groupC]),
            projects: []
        )

        try viewModel.moveWorkspaceAlignmentGroup(
            groupC.id,
            relativeTo: groupA.id,
            insertAfter: false
        )

        XCTAssertEqual(
            viewModel.snapshot.appState.workspaceAlignmentGroups.map(\.id),
            [groupC.id, groupA.id, groupB.id]
        )

        let reloadedSnapshot = try store.loadSnapshot()
        XCTAssertEqual(
            reloadedSnapshot.appState.workspaceAlignmentGroups.map(\.id),
            [groupC.id, groupA.id, groupB.id]
        )
    }

    private func makeProject(id: String, name: String, path: String) -> Project {
        Project(
            id: id,
            name: name,
            path: path,
            tags: [],
            runConfigurations: [],
            worktrees: [],
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
}
