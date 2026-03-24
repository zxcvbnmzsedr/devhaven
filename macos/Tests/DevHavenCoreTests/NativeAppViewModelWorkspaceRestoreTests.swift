import XCTest
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelWorkspaceRestoreTests: XCTestCase {
    func testLoadRestoresWorkspaceSessionsTopologyAndPaneRestoreContext() throws {
        let fixture = try NativeAppWorkspaceRestoreFixture()
        let controller = GhosttyWorkspaceController(projectPath: fixture.rootProject.path, workspaceId: "workspace:root")
        let firstPaneID = try XCTUnwrap(controller.selectedPane?.id)
        let secondPaneID = try XCTUnwrap(controller.splitFocusedPane(direction: .right)?.id)
        let workspaceSnapshot = WorkspaceRestoreSnapshot(
            activeProjectPath: fixture.worktree.path,
            selectedProjectPath: fixture.rootProject.path,
            sessions: [
                fixture.makeSessionSnapshot(
                    from: controller,
                    projectPath: fixture.rootProject.path,
                    rootProjectPath: fixture.rootProject.path,
                    paneContexts: [
                        firstPaneID: WorkspaceTerminalRestoreContext(
                            workingDirectory: fixture.rootProject.path,
                            title: "主 Pane",
                            snapshotText: "git status",
                            agentSummary: "Claude 运行中"
                        ),
                        secondPaneID: WorkspaceTerminalRestoreContext(
                            workingDirectory: fixture.rootProject.path + "/Sources",
                            title: "右侧 Pane",
                            snapshotText: "swift test",
                            agentSummary: "Codex 等待输入"
                        ),
                    ]
                ),
                fixture.makeManualSessionSnapshot(
                    projectPath: fixture.worktree.path,
                    rootProjectPath: fixture.rootProject.path,
                    workspaceId: "workspace:worktree",
                    paneID: "workspace:worktree/pane:1",
                    workingDirectory: fixture.worktree.path,
                    title: "worktree pane",
                    snapshotText: "git checkout feature/restore",
                    agentSummary: nil
                ),
            ]
        )
        try fixture.restoreStore.saveSnapshot(workspaceSnapshot)

        let viewModel = fixture.makeViewModel()
        viewModel.load()

        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [fixture.rootProject.path, fixture.worktree.path])
        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, fixture.worktree.path)
        XCTAssertEqual(viewModel.selectedProjectPath, fixture.rootProject.path)

        let rootSession = try XCTUnwrap(viewModel.openWorkspaceSessions.first(where: { $0.projectPath == fixture.rootProject.path }))
        XCTAssertEqual(rootSession.controller.tabs.count, 1)
        XCTAssertEqual(rootSession.controller.selectedTab?.leaves.count, 2)
        let restoredPane = try XCTUnwrap(rootSession.controller.tabs.first?.leaves.first(where: { $0.id == firstPaneID }))
        XCTAssertEqual(restoredPane.request.workingDirectory, fixture.rootProject.path)
        XCTAssertEqual(restoredPane.request.restoreContext?.title, "主 Pane")
        XCTAssertEqual(restoredPane.request.restoreContext?.snapshotText, "git status")

        let worktreeSession = try XCTUnwrap(viewModel.openWorkspaceSessions.first(where: { $0.projectPath == fixture.worktree.path }))
        XCTAssertEqual(worktreeSession.rootProjectPath, fixture.rootProject.path)
        XCTAssertEqual(worktreeSession.controller.selectedPane?.request.restoreContext?.title, "worktree pane")
    }

    func testLoadSkipsMissingProjectSessionsAndKeepsRemainingWorkspace() throws {
        let fixture = try NativeAppWorkspaceRestoreFixture()
        let controller = GhosttyWorkspaceController(projectPath: fixture.rootProject.path, workspaceId: "workspace:root")
        let snapshot = WorkspaceRestoreSnapshot(
            activeProjectPath: "/tmp/missing-project",
            selectedProjectPath: fixture.rootProject.path,
            sessions: [
                fixture.makeSessionSnapshot(
                    from: controller,
                    projectPath: fixture.rootProject.path,
                    rootProjectPath: fixture.rootProject.path,
                    paneContexts: [:]
                ),
                fixture.makeManualSessionSnapshot(
                    projectPath: "/tmp/missing-project",
                    rootProjectPath: "/tmp/missing-project",
                    workspaceId: "workspace:missing",
                    paneID: "workspace:missing/pane:1",
                    workingDirectory: "/tmp/missing-project",
                    title: "missing",
                    snapshotText: "pwd",
                    agentSummary: nil
                ),
            ]
        )
        try fixture.restoreStore.saveSnapshot(snapshot)

        let viewModel = fixture.makeViewModel()
        viewModel.load()

        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [fixture.rootProject.path])
        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, fixture.rootProject.path)
        XCTAssertEqual(viewModel.selectedProjectPath, fixture.rootProject.path)
    }

    func testWorkspaceMutationsAutosaveAndClosingLastSessionClearsSnapshot() async throws {
        let fixture = try NativeAppWorkspaceRestoreFixture()
        let viewModel = fixture.makeViewModel(autosaveDelayNanoseconds: 0)
        viewModel.load()

        viewModel.enterWorkspace(fixture.rootProject.path)
        await fixture.waitForAutosave()

        var persisted = try XCTUnwrap(fixture.restoreStore.loadSnapshot())
        XCTAssertEqual(persisted.sessions.map(\.projectPath), [fixture.rootProject.path])
        XCTAssertEqual(persisted.activeProjectPath, fixture.rootProject.path)

        viewModel.createWorkspaceTab(in: fixture.rootProject.path)
        await fixture.waitForAutosave()

        persisted = try XCTUnwrap(fixture.restoreStore.loadSnapshot())
        XCTAssertEqual(persisted.sessions.first?.tabs.count, 2)

        viewModel.closeWorkspaceProject(fixture.rootProject.path)
        await fixture.waitForAutosave()

        XCTAssertNil(fixture.restoreStore.loadSnapshot())
    }
}

private struct NativeAppWorkspaceRestoreFixture {
    let homeURL: URL
    let store: LegacyCompatStore
    let restoreStore: WorkspaceRestoreStore
    let rootProject: Project
    let worktree: ProjectWorktree

    init() throws {
        homeURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        store = LegacyCompatStore(homeDirectoryURL: homeURL)
        restoreStore = WorkspaceRestoreStore(homeDirectoryURL: homeURL)
        worktree = ProjectWorktree(
            id: "worktree:/tmp/devhaven-feature",
            name: "devhaven-feature",
            path: "/tmp/devhaven-feature",
            branch: "feature/restore",
            baseBranch: "main",
            inheritConfig: true,
            created: 1,
            status: nil,
            initStep: nil,
            initMessage: nil,
            initError: nil,
            initJobId: nil,
            updatedAt: 1
        )
        rootProject = Project(
            id: "project-1",
            name: "DevHaven",
            path: "/tmp/devhaven",
            tags: [],
            runConfigurations: [],
            worktrees: [worktree],
            mtime: 1,
            size: 0,
            checksum: "checksum",
            gitCommits: 1,
            gitLastCommit: 1,
            gitLastCommitMessage: "feat: restore",
            gitDaily: nil,
            created: 1,
            checked: 1
        )
        try store.updateProjects([rootProject])
    }

    @MainActor
    func makeViewModel(autosaveDelayNanoseconds: UInt64 = 0) -> NativeAppViewModel {
        NativeAppViewModel(
            store: store,
            projectDocumentLoader: { _ in ProjectDocumentSnapshot(notes: nil, todoItems: [], readmeFallback: nil) },
            gitDailyCollector: { _, _ in [] },
            gitDailyCollectorAsync: { _, _, _ in [] },
            workspaceRestoreStore: restoreStore,
            workspaceRestoreAutosaveDelayNanoseconds: autosaveDelayNanoseconds
        )
    }

    @MainActor
    func waitForAutosave() async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    @MainActor
    func makeSessionSnapshot(
        from controller: GhosttyWorkspaceController,
        projectPath: String,
        rootProjectPath: String,
        paneContexts: [String: WorkspaceTerminalRestoreContext]
    ) -> ProjectWorkspaceRestoreSnapshot {
        var snapshot = controller.makeRestoreSnapshot(rootProjectPath: rootProjectPath, isQuickTerminal: false)
        snapshot.projectPath = projectPath
        snapshot.tabs = snapshot.tabs.map { tab in
            var tab = tab
            tab.tree = WorkspacePaneTreeRestoreSnapshot(
                root: hydrate(node: tab.tree.root, paneContexts: paneContexts),
                zoomedPaneId: tab.tree.zoomedPaneId
            )
            return tab
        }
        return snapshot
    }

    func makeManualSessionSnapshot(
        projectPath: String,
        rootProjectPath: String,
        workspaceId: String,
        paneID: String,
        workingDirectory: String?,
        title: String?,
        snapshotText: String?,
        agentSummary: String?
    ) -> ProjectWorkspaceRestoreSnapshot {
        let pane = WorkspacePaneRestoreSnapshot(
            paneId: paneID,
            surfaceId: paneID.replacingOccurrences(of: "/pane:", with: "/surface:"),
            terminalSessionId: paneID.replacingOccurrences(of: "/pane:", with: "/session:"),
            restoredWorkingDirectory: workingDirectory,
            restoredTitle: title,
            agentSummary: agentSummary,
            snapshotTextRef: WorkspacePaneSnapshotTextRef.forPaneID(paneID),
            snapshotText: snapshotText
        )
        let tab = WorkspaceTabRestoreSnapshot(
            id: "\(workspaceId)/tab:1",
            title: "终端 1",
            focusedPaneId: paneID,
            tree: WorkspacePaneTreeRestoreSnapshot(root: .leaf(pane), zoomedPaneId: nil)
        )
        return ProjectWorkspaceRestoreSnapshot(
            projectPath: projectPath,
            rootProjectPath: rootProjectPath,
            isQuickTerminal: false,
            workspaceId: workspaceId,
            selectedTabId: tab.id,
            nextTabNumber: 2,
            nextPaneNumber: 2,
            tabs: [tab]
        )
    }

    private func hydrate(
        node: WorkspacePaneTreeRestoreSnapshot.Node,
        paneContexts: [String: WorkspaceTerminalRestoreContext]
    ) -> WorkspacePaneTreeRestoreSnapshot.Node {
        switch node {
        case let .leaf(pane):
            let context = paneContexts[pane.paneId]
            return .leaf(
                WorkspacePaneRestoreSnapshot(
                    paneId: pane.paneId,
                    surfaceId: pane.surfaceId,
                    terminalSessionId: pane.terminalSessionId,
                    restoredWorkingDirectory: context?.workingDirectory,
                    restoredTitle: context?.title,
                    agentSummary: context?.agentSummary,
                    snapshotTextRef: context?.snapshotText == nil ? nil : WorkspacePaneSnapshotTextRef.forPaneID(pane.paneId),
                    snapshotText: context?.snapshotText
                )
            )
        case let .split(split):
            return .split(
                WorkspaceSplitRestoreSnapshot(
                    direction: split.direction,
                    ratio: split.ratio,
                    left: hydrate(node: split.left, paneContexts: paneContexts),
                    right: hydrate(node: split.right, paneContexts: paneContexts)
                )
            )
        }
    }
}
