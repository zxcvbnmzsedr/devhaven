import XCTest
@testable import DevHavenApp

final class AppRootContentVisibilityPolicyTests: XCTestCase {
    func testHomeModeUnmountsWorkspaceContent() {
        let policy = AppRootContentVisibilityPolicy.resolve(isWorkspacePresented: false)

        XCTAssertTrue(
            policy.keepsMainContentMounted,
            "主页态应保留主页内容挂载。"
        )
        XCTAssertFalse(
            policy.keepsWorkspaceMounted,
            "主页态不应继续把 Workspace 视图留在层级里；否则隐藏 workspace 仍会持续参与 Ghostty attach/focus 链路。"
        )
        XCTAssertEqual(policy.mainContentOpacity, 1)
        XCTAssertEqual(policy.workspaceContentOpacity, 0)
    }

    func testWorkspaceModeUnmountsHomeContent() {
        let policy = AppRootContentVisibilityPolicy.resolve(isWorkspacePresented: true)

        XCTAssertFalse(
            policy.keepsMainContentMounted,
            "进入 Workspace 后，不应继续把主页内容留在同一个 ZStack 里。"
        )
        XCTAssertTrue(
            policy.keepsWorkspaceMounted,
            "Workspace 态应保留 Workspace 视图挂载。"
        )
        XCTAssertEqual(policy.mainContentOpacity, 0)
        XCTAssertEqual(policy.workspaceContentOpacity, 1)
    }
}
