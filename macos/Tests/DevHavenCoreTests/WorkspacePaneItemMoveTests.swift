import XCTest
@testable import DevHavenCore

final class WorkspacePaneItemMoveTests: XCTestCase {
    func testMovePaneItemReordersItemsWithinPaneAndKeepsSelection() throws {
        var session = WorkspaceSessionState(projectPath: "/tmp/project", workspaceId: "workspace:test")
        let paneID = try XCTUnwrap(session.selectedPane?.id)
        let firstItemID = try XCTUnwrap(session.selectedPane?.selectedItem?.id)
        let secondItemID = try XCTUnwrap(session.createTerminalItem(inPane: paneID)?.id)
        let thirdItemID = try XCTUnwrap(session.createTerminalItem(inPane: paneID)?.id)

        session.movePaneItem(inPane: paneID, itemID: thirdItemID, by: -2)

        let items = try XCTUnwrap(session.selectedPane?.items)
        XCTAssertEqual(items.map(\.id), [thirdItemID, firstItemID, secondItemID])
        XCTAssertEqual(session.selectedPane?.selectedItemId, thirdItemID)
    }

    func testMovePaneItemAcrossPanesKeepsIdentityAndTargetsSelectedPane() throws {
        var session = WorkspaceSessionState(projectPath: "/tmp/project", workspaceId: "workspace:test")
        let sourcePaneID = try XCTUnwrap(session.selectedPane?.id)
        let originalItemID = try XCTUnwrap(session.selectedPane?.selectedItem?.id)
        let movedItem = try XCTUnwrap(session.createTerminalItem(inPane: sourcePaneID))
        let targetPane = try XCTUnwrap(session.splitFocusedPane(direction: .right))

        let result = try XCTUnwrap(
            session.movePaneItem(
                movedItem.id,
                from: sourcePaneID,
                to: targetPane.id,
                at: 1
            )
        )

        let updatedSourcePane = try XCTUnwrap(session.selectedTab?.tree.find(paneID: sourcePaneID))
        let updatedTargetPane = try XCTUnwrap(session.selectedTab?.tree.find(paneID: targetPane.id))

        XCTAssertEqual(result.id, movedItem.id)
        XCTAssertEqual(result.request.terminalSessionId, movedItem.request.terminalSessionId)
        XCTAssertEqual(result.request.paneId, targetPane.id)
        XCTAssertEqual(updatedSourcePane.items.map(\.id), [originalItemID])
        XCTAssertEqual(updatedTargetPane.items.map(\.id), [targetPane.items[0].id, movedItem.id])
        XCTAssertEqual(updatedTargetPane.selectedItemId, movedItem.id)
        XCTAssertEqual(session.selectedTab?.focusedPaneId, targetPane.id)
    }

    func testSplitPaneItemCreatesSiblingPaneAndKeepsMovedIdentity() throws {
        var session = WorkspaceSessionState(projectPath: "/tmp/project", workspaceId: "workspace:test")
        let sourcePaneID = try XCTUnwrap(session.selectedPane?.id)
        _ = try XCTUnwrap(session.selectedPane?.selectedItem?.id)
        let movedItem = try XCTUnwrap(session.createTerminalItem(inPane: sourcePaneID))

        let createdPane = try XCTUnwrap(
            session.splitPaneItem(
                movedItem.id,
                from: sourcePaneID,
                beside: sourcePaneID,
                direction: .right
            )
        )

        let updatedSourcePane = try XCTUnwrap(session.selectedTab?.tree.find(paneID: sourcePaneID))
        let updatedCreatedPane = try XCTUnwrap(session.selectedTab?.tree.find(paneID: createdPane.id))

        XCTAssertEqual(updatedSourcePane.items.count, 1)
        XCTAssertEqual(updatedCreatedPane.items.count, 1)
        XCTAssertEqual(updatedCreatedPane.selectedItemId, movedItem.id)
        XCTAssertEqual(updatedCreatedPane.selectedItem?.id, movedItem.id)
        XCTAssertEqual(updatedCreatedPane.selectedItem?.request.terminalSessionId, movedItem.request.terminalSessionId)
        XCTAssertEqual(updatedCreatedPane.selectedItem?.request.paneId, createdPane.id)
        XCTAssertEqual(session.selectedTab?.focusedPaneId, createdPane.id)
    }
}
