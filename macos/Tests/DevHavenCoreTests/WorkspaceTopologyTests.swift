import XCTest
import CoreGraphics
@testable import DevHavenCore

final class WorkspaceTopologyTests: XCTestCase {
    func testInitialWorkspaceStartsWithSingleSelectedTabAndPane() {
        let session = WorkspaceSessionState(projectPath: "/tmp/devhaven", workspaceId: "workspace:test")

        XCTAssertEqual(session.tabs.count, 1)
        XCTAssertEqual(session.selectedTab?.id, session.selectedTabId)
        XCTAssertEqual(session.selectedTab?.title, "终端1")
        XCTAssertEqual(session.selectedTab?.leaves.count, 1)
        XCTAssertEqual(session.selectedPane?.request.projectPath, "/tmp/devhaven")
        XCTAssertEqual(session.selectedPane?.request.workspaceId, "workspace:test")
    }

    func testCreateTabAppendsAfterSelectionAndSelectsNewTab() {
        var session = WorkspaceSessionState(projectPath: "/tmp/devhaven", workspaceId: "workspace:test")
        let firstTabID = session.selectedTabId

        let secondTab = session.createTab()

        XCTAssertEqual(session.tabs.count, 2)
        XCTAssertEqual(session.tabs[0].id, firstTabID)
        XCTAssertEqual(session.tabs[1].id, secondTab.id)
        XCTAssertEqual(session.selectedTabId, secondTab.id)
        XCTAssertEqual(session.selectedTab?.title, "终端2")
    }

    func testSplitFocusedPaneCreatesNewLeafAndFocusesIt() {
        var session = WorkspaceSessionState(projectPath: "/tmp/devhaven", workspaceId: "workspace:test")
        let originalPaneID = session.selectedPane?.id

        let newPane = session.splitFocusedPane(direction: .right)

        XCTAssertEqual(session.selectedTab?.leaves.count, 2)
        XCTAssertEqual(session.selectedTab?.focusedPaneId, newPane?.id)
        XCTAssertEqual(session.selectedTab?.leaves.map(\.id), [originalPaneID, newPane?.id].compactMap { $0 })
    }

    func testCloseFocusedPaneFallsBackToNeighborInSameTab() {
        var session = WorkspaceSessionState(projectPath: "/tmp/devhaven", workspaceId: "workspace:test")
        let firstPaneID = session.selectedPane?.id
        let secondPaneID = session.splitFocusedPane(direction: .right)?.id
        XCTAssertEqual(session.selectedTab?.focusedPaneId, secondPaneID)

        session.closePane(secondPaneID)

        XCTAssertEqual(session.selectedTab?.leaves.count, 1)
        XCTAssertEqual(session.selectedTab?.focusedPaneId, firstPaneID)
    }

    func testClosingLastPaneOfLastTabCreatesReplacementTab() {
        var session = WorkspaceSessionState(projectPath: "/tmp/devhaven", workspaceId: "workspace:test")
        let originalTabID = session.selectedTabId
        let originalPaneID = session.selectedPane?.id

        session.closePane(originalPaneID)

        XCTAssertEqual(session.tabs.count, 1)
        XCTAssertNotEqual(session.selectedTabId, originalTabID)
        XCTAssertEqual(session.selectedTab?.leaves.count, 1)
    }

    func testGotoAndMoveTabRequestsUpdateSelectionAndOrder() {
        var session = WorkspaceSessionState(projectPath: "/tmp/devhaven", workspaceId: "workspace:test")
        let first = session.selectedTab!.id
        let second = session.createTab().id
        let third = session.createTab().id

        session.gotoPreviousTab()
        XCTAssertEqual(session.selectedTabId, second)

        session.gotoTab(at: 1)
        XCTAssertEqual(session.selectedTabId, first)

        session.selectTab(second)
        session.moveSelectedTab(by: 1)
        XCTAssertEqual(session.tabs.map(\.id), [first, third, second])
        XCTAssertEqual(session.selectedTabId, second)
    }

    func testResizeEqualizeAndZoomUpdateSelectedTabTree() {
        var session = WorkspaceSessionState(projectPath: "/tmp/devhaven", workspaceId: "workspace:test")
        _ = session.splitFocusedPane(direction: .right)

        let initialRatio = session.selectedTab?.rootSplit?.ratio
        session.resizeFocusedPane(direction: .right, amount: 10)
        let resizedRatio = session.selectedTab?.rootSplit?.ratio
        XCTAssertNotEqual(initialRatio, resizedRatio)

        session.equalizeSelectedTabSplits()
        XCTAssertEqual(session.selectedTab?.rootSplit?.ratio ?? 0, 0.5, accuracy: 0.0001)

        let focusedPaneID = session.selectedTab?.focusedPaneId
        session.toggleZoomOnFocusedPane()
        XCTAssertEqual(session.selectedTab?.tree.zoomedPaneId, focusedPaneID)
        session.toggleZoomOnFocusedPane()
        XCTAssertNil(session.selectedTab?.tree.zoomedPaneId)
    }

    func testFocusSplitDirectionMovesToNeighborPane() {
        var session = WorkspaceSessionState(projectPath: "/tmp/devhaven", workspaceId: "workspace:test")
        let leftPaneID = session.selectedPane?.id
        let rightPaneID = session.splitFocusedPane(direction: .right)?.id
        XCTAssertEqual(session.selectedTab?.focusedPaneId, rightPaneID)

        session.focusPane(direction: .left)
        XCTAssertEqual(session.selectedTab?.focusedPaneId, leftPaneID)

        session.focusPane(direction: .right)
        XCTAssertEqual(session.selectedTab?.focusedPaneId, rightPaneID)
    }

    func testSplitTreeStructuralIdentityIgnoresRatioChanges() {
        var session = WorkspaceSessionState(projectPath: "/tmp/devhaven", workspaceId: "workspace:test")
        _ = session.splitFocusedPane(direction: .right)

        let identityBefore = session.selectedTab?.tree.structuralIdentity
        XCTAssertNotNil(identityBefore)

        session.setSelectedTabSplitRatio(at: WorkspacePaneTree.Path(components: []), ratio: 0.72)

        let identityAfter = session.selectedTab?.tree.structuralIdentity
        XCTAssertEqual(identityBefore, identityAfter)
    }

    func testSplitHandlesExposeRootSplitPathAndDirection() throws {
        var session = WorkspaceSessionState(projectPath: "/tmp/devhaven", workspaceId: "workspace:test")
        _ = session.splitFocusedPane(direction: .right)

        let root = try XCTUnwrap(session.selectedTab?.tree.root)
        let handles = root.splitHandles(
            in: CGRect(x: 0, y: 0, width: 100, height: 60),
            path: WorkspacePaneTree.Path(components: [])
        )

        XCTAssertEqual(handles.count, 1)
        XCTAssertEqual(handles.first?.path, WorkspacePaneTree.Path(components: []))
        XCTAssertEqual(handles.first?.direction, .horizontal)
        XCTAssertEqual(handles.first?.splitBounds, CGRect(x: 0, y: 0, width: 100, height: 60))
    }

    func testNestedSplitHandlesPreserveChildPath() throws {
        var session = WorkspaceSessionState(projectPath: "/tmp/devhaven", workspaceId: "workspace:test")
        let originalPaneID = try XCTUnwrap(session.selectedPane?.id)
        _ = session.splitFocusedPane(direction: .right)
        session.focusPane(originalPaneID)
        _ = session.splitFocusedPane(direction: .down)

        let root = try XCTUnwrap(session.selectedTab?.tree.root)
        let handles = root.splitHandles(
            in: CGRect(x: 0, y: 0, width: 120, height: 80),
            path: WorkspacePaneTree.Path(components: [])
        )

        XCTAssertEqual(handles.count, 2)
        XCTAssertEqual(handles.map(\.path), [
            WorkspacePaneTree.Path(components: []),
            WorkspacePaneTree.Path(components: [.left]),
        ])
        XCTAssertEqual(handles.map(\.direction), [.horizontal, .vertical])
    }
}
