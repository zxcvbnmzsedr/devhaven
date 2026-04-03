import XCTest
@testable import DevHavenCore

final class WorkspacePaneMoveTests: XCTestCase {
    func testMovePaneToRightOfSiblingSwapsLeafOrderAndFocus() throws {
        var session = WorkspaceSessionState(projectPath: "/tmp/project", workspaceId: "workspace:test")
        let originalPaneID = try XCTUnwrap(session.selectedPane?.id)

        let createdPane = try XCTUnwrap(session.splitFocusedPane(direction: .right))
        let siblingPaneID = createdPane.id

        session.movePane(originalPaneID, beside: siblingPaneID, direction: .right)

        let leaves = try XCTUnwrap(session.selectedTab?.leaves)
        XCTAssertEqual(leaves.map(\.id), [siblingPaneID, originalPaneID])
        XCTAssertEqual(session.selectedTab?.focusedPaneId, originalPaneID)
    }

    func testMovePaneToTopOfSiblingCreatesVerticalOrder() throws {
        var session = WorkspaceSessionState(projectPath: "/tmp/project", workspaceId: "workspace:test")
        let originalPaneID = try XCTUnwrap(session.selectedPane?.id)

        let createdPane = try XCTUnwrap(session.splitFocusedPane(direction: .right))
        let siblingPaneID = createdPane.id

        session.movePane(originalPaneID, beside: siblingPaneID, direction: .top)

        let leaves = try XCTUnwrap(session.selectedTab?.leaves)
        XCTAssertEqual(leaves.map(\.id), [originalPaneID, siblingPaneID])
        XCTAssertEqual(session.selectedTab?.rootSplit?.direction, .vertical)
        XCTAssertEqual(session.selectedTab?.focusedPaneId, originalPaneID)
    }

    func testMovePaneToSelfDoesNothing() throws {
        var session = WorkspaceSessionState(projectPath: "/tmp/project", workspaceId: "workspace:test")
        let originalPaneID = try XCTUnwrap(session.selectedPane?.id)

        let createdPane = try XCTUnwrap(session.splitFocusedPane(direction: .right))
        let siblingPaneID = createdPane.id
        let before = session.selectedTab

        session.movePane(siblingPaneID, beside: siblingPaneID, direction: .left)

        XCTAssertEqual(session.selectedTab, before)
        XCTAssertEqual(session.selectedTab?.focusedPaneId, siblingPaneID)
        XCTAssertNotEqual(originalPaneID, siblingPaneID)
    }
}
