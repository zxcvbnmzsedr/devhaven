import XCTest
@testable import DevHavenApp

final class AppRootContentVisibilityPolicyTests: XCTestCase {
    func testBrowsingModeKeepsWorkspaceMountedButHiddenAndNonInteractive() {
        let policy = AppRootContentVisibilityPolicy.resolve(isWorkspacePresented: false)

        XCTAssertTrue(policy.keepsMainContentMounted)
        XCTAssertTrue(policy.keepsWorkspaceMounted)
        XCTAssertEqual(policy.mainContentOpacity, 1)
        XCTAssertTrue(policy.mainContentAllowsHitTesting)
        XCTAssertEqual(policy.workspaceContentOpacity, 0)
        XCTAssertFalse(policy.workspaceContentAllowsHitTesting)
    }

    func testWorkspaceModeKeepsMainMountedButHiddenAndNonInteractive() {
        let policy = AppRootContentVisibilityPolicy.resolve(isWorkspacePresented: true)

        XCTAssertTrue(policy.keepsMainContentMounted)
        XCTAssertTrue(policy.keepsWorkspaceMounted)
        XCTAssertEqual(policy.mainContentOpacity, 0)
        XCTAssertFalse(policy.mainContentAllowsHitTesting)
        XCTAssertEqual(policy.workspaceContentOpacity, 1)
        XCTAssertTrue(policy.workspaceContentAllowsHitTesting)
    }
}
