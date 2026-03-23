import XCTest
@testable import DevHavenCore

@MainActor
final class GhosttyWorkspaceRestoreSnapshotTests: XCTestCase {
    func testControllerCanExportAndRestoreNestedWorkspaceTopologySnapshot() throws {
        let controller = GhosttyWorkspaceController(projectPath: "/tmp/devhaven", workspaceId: "workspace:test")
        let firstTabID = try XCTUnwrap(controller.selectedTab?.id)
        let firstPaneID = try XCTUnwrap(controller.selectedPane?.id)
        let secondPaneID = try XCTUnwrap(controller.splitFocusedPane(direction: .right)?.id)
        controller.setSelectedTabSplitRatio(at: WorkspacePaneTree.Path(components: []), ratio: 0.72)
        controller.toggleZoomOnFocusedPane()

        let secondTabID = controller.createTab().id
        let thirdPaneID = try XCTUnwrap(controller.selectedPane?.id)
        let fourthPaneID = try XCTUnwrap(controller.splitFocusedPane(direction: .down)?.id)
        controller.selectTab(firstTabID)
        controller.focusPane(secondPaneID)

        let snapshot = controller.makeRestoreSnapshot(rootProjectPath: "/tmp/devhaven", isQuickTerminal: false)
        let restored = GhosttyWorkspaceController(projectPath: "/tmp/devhaven", workspaceId: "workspace:other")

        restored.restore(from: snapshot)

        XCTAssertEqual(restored.workspaceId, "workspace:test")
        XCTAssertEqual(restored.selectedTabId, firstTabID)
        XCTAssertEqual(restored.tabs.map(\.id), [firstTabID, secondTabID])
        XCTAssertEqual(restored.tabs.first?.focusedPaneId, secondPaneID)
        XCTAssertEqual(restored.tabs.first?.tree.zoomedPaneId, secondPaneID)
        XCTAssertEqual(restored.tabs.first?.rootSplit?.ratio ?? 0, 0.72, accuracy: 0.0001)
        XCTAssertEqual(restored.tabs.first?.leaves.map(\.id), [firstPaneID, secondPaneID])
        XCTAssertEqual(restored.tabs.last?.leaves.map(\.id), [thirdPaneID, fourthPaneID])
    }

    func testRestoredControllerContinuesStableTabAndPaneNumbering() throws {
        let controller = GhosttyWorkspaceController(projectPath: "/tmp/devhaven", workspaceId: "workspace:test")
        _ = controller.splitFocusedPane(direction: .right)
        _ = controller.createTab()
        _ = controller.splitFocusedPane(direction: .down)

        let snapshot = controller.makeRestoreSnapshot(rootProjectPath: "/tmp/devhaven", isQuickTerminal: false)
        let restored = GhosttyWorkspaceController(projectPath: "/tmp/devhaven")
        restored.restore(from: snapshot)

        let newTab = restored.createTab()
        XCTAssertEqual(newTab.id, "workspace:test/tab:3")
        XCTAssertEqual(newTab.focusedPaneId, "workspace:test/pane:5")

        let newPane = try XCTUnwrap(restored.splitFocusedPane(direction: .right))
        XCTAssertEqual(newPane.id, "workspace:test/pane:6")
        XCTAssertEqual(newPane.request.terminalSessionId, "workspace:test/session:6")
    }
}
