import XCTest
@testable import DevHavenApp

final class WorkspaceChromePolicyTests: XCTestCase {
    func testWorkspacePresentationUsesMinimalChrome() {
        let policy = WorkspaceChromePolicy.resolve(isWorkspacePresented: true)

        XCTAssertFalse(policy.showsGlobalSidebar)
        XCTAssertFalse(policy.showsWorkspaceHeader)
        XCTAssertFalse(policy.showsPaneHeader)
        XCTAssertFalse(policy.showsSurfaceStatusBar)
    }

    func testBrowsingPresentationKeepsStandardChrome() {
        let policy = WorkspaceChromePolicy.resolve(isWorkspacePresented: false)

        XCTAssertTrue(policy.showsGlobalSidebar)
        XCTAssertTrue(policy.showsWorkspaceHeader)
        XCTAssertTrue(policy.showsPaneHeader)
        XCTAssertTrue(policy.showsSurfaceStatusBar)
    }
}
