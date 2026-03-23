import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceRestoreCoordinatorTests: XCTestCase {
    func testLoadSnapshotHydratesPaneTextFromReferencedFiles() throws {
        let fixture = try WorkspaceRestoreFixture()
        let store = WorkspaceRestoreStore(homeDirectoryURL: fixture.homeURL)
        let coordinator = WorkspaceRestoreCoordinator(store: store, autosaveDelayNanoseconds: 0)
        let snapshot = fixture.makeSnapshot(
            projectPath: "/tmp/devhaven",
            rootProjectPath: "/tmp/devhaven",
            workingDirectory: "/tmp/devhaven",
            title: "DevHaven",
            agentSummary: "Codex 等待输入",
            snapshotText: "git status"
        )

        try store.saveSnapshot(snapshot)
        let loaded = try XCTUnwrap(coordinator.loadSnapshot())
        let pane = try XCTUnwrap(loaded.sessions.first?.tabs.first?.tree.rootLeaf)

        XCTAssertEqual(pane.snapshotText, "git status")
        XCTAssertEqual(pane.restoredTitle, "DevHaven")
    }

    func testFlushNowCapturesSessionSelectionAndPaneContext() throws {
        let fixture = try WorkspaceRestoreFixture()
        let store = WorkspaceRestoreStore(homeDirectoryURL: fixture.homeURL)
        let coordinator = WorkspaceRestoreCoordinator(store: store, autosaveDelayNanoseconds: 0)
        let controller = GhosttyWorkspaceController(projectPath: "/tmp/devhaven", workspaceId: "workspace:test")
        let firstPaneID = try XCTUnwrap(controller.selectedPane?.id)
        let secondPaneID = try XCTUnwrap(controller.splitFocusedPane(direction: .right)?.id)
        controller.createTab()
        let secondTabID = try XCTUnwrap(controller.selectedTab?.id)

        try coordinator.flushNow(
            activeProjectPath: "/tmp/devhaven",
            selectedProjectPath: "/tmp/devhaven",
            sessions: [
                OpenWorkspaceSessionState(
                    projectPath: "/tmp/devhaven",
                    rootProjectPath: "/tmp/devhaven",
                    controller: controller,
                    isQuickTerminal: false
                )
            ],
            paneSnapshotProvider: { projectPath, paneID in
                XCTAssertEqual(projectPath, "/tmp/devhaven")
                switch paneID {
                case firstPaneID:
                    return WorkspaceTerminalRestoreContext(
                        workingDirectory: "/tmp/devhaven",
                        title: "主 Pane",
                        snapshotText: "pwd\n/tmp/devhaven",
                        agentSummary: "Claude 运行中"
                    )
                case secondPaneID:
                    return WorkspaceTerminalRestoreContext(
                        workingDirectory: "/tmp/devhaven/packages/app",
                        title: "右侧 Pane",
                        snapshotText: "npm test",
                        agentSummary: "Codex 等待输入"
                    )
                default:
                    return nil
                }
            }
        )

        let persisted = try XCTUnwrap(coordinator.loadSnapshot())
        XCTAssertEqual(persisted.activeProjectPath, "/tmp/devhaven")
        XCTAssertEqual(persisted.selectedProjectPath, "/tmp/devhaven")
        XCTAssertEqual(persisted.sessions.count, 1)
        XCTAssertEqual(persisted.sessions.first?.tabs.count, 2)
        XCTAssertEqual(persisted.sessions.first?.selectedTabId, secondTabID)

        let panes = persisted.sessions.first?.tabs.flatMap(\.tree.leaves) ?? []
        let firstPane = try XCTUnwrap(panes.first(where: { $0.paneId == firstPaneID }))
        let secondPane = try XCTUnwrap(panes.first(where: { $0.paneId == secondPaneID }))
        XCTAssertEqual(firstPane.restoredTitle, "主 Pane")
        XCTAssertEqual(firstPane.snapshotText, "pwd\n/tmp/devhaven")
        XCTAssertEqual(secondPane.restoredWorkingDirectory, "/tmp/devhaven/packages/app")
        XCTAssertEqual(secondPane.agentSummary, "Codex 等待输入")
    }

    func testFlushNowKeepsPreviousPaneContextWhenProviderReturnsNil() throws {
        let fixture = try WorkspaceRestoreFixture()
        let store = WorkspaceRestoreStore(homeDirectoryURL: fixture.homeURL)
        let coordinator = WorkspaceRestoreCoordinator(store: store, autosaveDelayNanoseconds: 0)
        let controller = GhosttyWorkspaceController(projectPath: "/tmp/devhaven", workspaceId: "workspace:test")
        let paneID = try XCTUnwrap(controller.selectedPane?.id)
        let snapshot = fixture.makeSnapshot(
            projectPath: "/tmp/devhaven",
            rootProjectPath: "/tmp/devhaven",
            paneID: paneID,
            workspaceId: "workspace:test",
            workingDirectory: "/tmp/devhaven/old",
            title: "旧标题",
            agentSummary: "旧摘要",
            snapshotText: "旧输出"
        )
        try store.saveSnapshot(snapshot)
        _ = coordinator.loadSnapshot()

        try coordinator.flushNow(
            activeProjectPath: "/tmp/devhaven",
            selectedProjectPath: "/tmp/devhaven",
            sessions: [
                OpenWorkspaceSessionState(
                    projectPath: "/tmp/devhaven",
                    rootProjectPath: "/tmp/devhaven",
                    controller: controller,
                    isQuickTerminal: false
                )
            ],
            paneSnapshotProvider: { _, _ in nil as WorkspaceTerminalRestoreContext? }
        )

        let persisted = try XCTUnwrap(coordinator.loadSnapshot())
        let pane = try XCTUnwrap(persisted.sessions.first?.tabs.first?.tree.rootLeaf)
        XCTAssertEqual(pane.restoredWorkingDirectory, "/tmp/devhaven/old")
        XCTAssertEqual(pane.restoredTitle, "旧标题")
        XCTAssertEqual(pane.agentSummary, "旧摘要")
        XCTAssertEqual(pane.snapshotText, "旧输出")
    }

    func testFlushNowRemovesSnapshotWhenWorkspaceIsEmpty() throws {
        let fixture = try WorkspaceRestoreFixture()
        let store = WorkspaceRestoreStore(homeDirectoryURL: fixture.homeURL)
        let coordinator = WorkspaceRestoreCoordinator(store: store, autosaveDelayNanoseconds: 0)
        try store.saveSnapshot(
            fixture.makeSnapshot(
                projectPath: "/tmp/devhaven",
                rootProjectPath: "/tmp/devhaven",
                workingDirectory: "/tmp/devhaven",
                title: "终端",
                agentSummary: nil,
                snapshotText: "pwd"
            )
        )

        try coordinator.flushNow(
            activeProjectPath: nil as String?,
            selectedProjectPath: nil as String?,
            sessions: [],
            paneSnapshotProvider: { _, _ in nil as WorkspaceTerminalRestoreContext? }
        )

        XCTAssertNil(store.loadSnapshot())
    }
}

private struct WorkspaceRestoreFixture {
    let homeURL: URL

    init() throws {
        homeURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    }

    func makeSnapshot(
        projectPath: String,
        rootProjectPath: String,
        paneID: String = "workspace:test/pane:1",
        workspaceId: String = "workspace:test",
        workingDirectory: String?,
        title: String?,
        agentSummary: String?,
        snapshotText: String?
    ) -> WorkspaceRestoreSnapshot {
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
        let session = ProjectWorkspaceRestoreSnapshot(
            projectPath: projectPath,
            rootProjectPath: rootProjectPath,
            isQuickTerminal: false,
            workspaceId: workspaceId,
            selectedTabId: tab.id,
            nextTabNumber: 2,
            nextPaneNumber: 2,
            tabs: [tab]
        )
        return WorkspaceRestoreSnapshot(
            activeProjectPath: projectPath,
            selectedProjectPath: projectPath,
            sessions: [session]
        )
    }
}

private extension WorkspacePaneTreeRestoreSnapshot {
    var rootLeaf: WorkspacePaneRestoreSnapshot? {
        guard case let .leaf(pane) = root else {
            return nil
        }
        return pane
    }
}
