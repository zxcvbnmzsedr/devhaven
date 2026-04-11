import XCTest
@testable import DevHavenApp

final class WindowFocusObserverViewTests: XCTestCase {
    func testResolvedVisibilityTreatsKeyVisibleWindowAsVisibleBeforeOcclusionRefresh() {
        XCTAssertTrue(
            WindowActivityState.resolvedVisibility(
                isKeyWindow: true,
                isWindowVisible: true,
                isOccludedVisible: false
            ),
            "新窗口首帧即使 occlusion 还没刷新，只要已经可见且为 key window，也应判定为 visible。"
        )
    }

    func testResolvedVisibilityRequiresActualWindowVisibility() {
        XCTAssertFalse(
            WindowActivityState.resolvedVisibility(
                isKeyWindow: true,
                isWindowVisible: false,
                isOccludedVisible: true
            ),
            "窗口本身不可见时，不应仅凭 occlusion 标记把它判成 visible。"
        )
    }

    func testResolvedVisibilityKeepsBackgroundOccludedWindowHidden() {
        XCTAssertFalse(
            WindowActivityState.resolvedVisibility(
                isKeyWindow: false,
                isWindowVisible: true,
                isOccludedVisible: false
            ),
            "后台且未曝光的窗口仍应保持 invisible，避免后台持续驱动 surface。"
        )
    }
}
