import XCTest
@testable import DevHavenCore

final class WorkspaceSessionStateTabClosureTests: XCTestCase {
    func testCloseLastTabAllowingEmptyDoesNotRecreatePlaceholderTab() {
        var session = WorkspaceSessionState(projectPath: "/tmp/project", workspaceId: "workspace:test")
        let onlyTabID = try! XCTUnwrap(session.selectedTabId)

        session.closeTabAllowingEmpty(onlyTabID)

        XCTAssertTrue(session.tabs.isEmpty)
        XCTAssertNil(session.selectedTabId)
        XCTAssertNil(session.selectedTab)
        XCTAssertNil(session.selectedPane)
    }

    func testCloseLastTabStillRecreatesPlaceholderByDefault() {
        var session = WorkspaceSessionState(projectPath: "/tmp/project", workspaceId: "workspace:test")
        let onlyTabID = try! XCTUnwrap(session.selectedTabId)

        session.closeTab(onlyTabID)

        XCTAssertEqual(session.tabs.count, 1)
        XCTAssertNotNil(session.selectedTabId)
        XCTAssertNotNil(session.selectedPane)
    }
}
