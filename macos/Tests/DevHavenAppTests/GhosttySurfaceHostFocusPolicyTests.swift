import XCTest
@testable import DevHavenApp

@MainActor
final class GhosttySurfaceHostFocusPolicyTests: XCTestCase {
    func testResolvedAttachedSurfaceFocusRequiresWindowResponderOwnership() {
        XCTAssertFalse(
            GhosttySurfaceHostModel.resolvedAttachedSurfaceFocus(
                desiredFocus: true,
                ownsWindowFirstResponder: false
            ),
            "attach 阶段即使逻辑上想聚焦，只要 NS responder 还未真正切到该 surface，就不应提前把 focused=true 写给 Ghostty。"
        )
    }

    func testResolvedAttachedSurfaceFocusAllowsFocusedOwnedSurface() {
        XCTAssertTrue(
            GhosttySurfaceHostModel.resolvedAttachedSurfaceFocus(
                desiredFocus: true,
                ownsWindowFirstResponder: true
            ),
            "当 surface 已经真实持有窗口 responder 时，应继续把 focused 状态同步给 Ghostty。"
        )
    }

    func testResolvedAttachedSurfaceFocusKeepsBlurredSurfaceUnfocused() {
        XCTAssertFalse(
            GhosttySurfaceHostModel.resolvedAttachedSurfaceFocus(
                desiredFocus: false,
                ownsWindowFirstResponder: true
            ),
            "逻辑焦点已移开时，即使 responder 还在当前 view，也不应继续把 Ghostty 维持在 focused。"
        )
    }
}
