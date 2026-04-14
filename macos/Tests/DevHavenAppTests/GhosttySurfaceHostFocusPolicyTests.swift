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

    func testFocusRequestPolicyReassertsPreferredPaneWhenSurfaceStillNotFocused() {
        XCTAssertTrue(
            GhosttySurfaceFocusRequestPolicy.shouldRequestFocus(
                preferredFocus: true,
                wasPreferredFocus: true,
                isSurfaceFocused: false,
                currentEventType: nil
            ),
            "返回工作台后，只要 pane 仍是 preferredFocus 但 surface 还没真正 focused，就必须继续请求焦点；不能因为它之前也曾是 preferredFocus 就跳过。"
        )
    }

    func testFocusRequestPolicySkipsAlreadyFocusedPane() {
        XCTAssertFalse(
            GhosttySurfaceFocusRequestPolicy.shouldRequestFocus(
                preferredFocus: true,
                wasPreferredFocus: true,
                isSurfaceFocused: true,
                currentEventType: nil
            ),
            "surface 已经真正 focused 时，不应继续重复发起焦点请求。"
        )
    }

    func testResponderRestorePolicyDefersUntilSurfaceAttachmentCompletes() {
        XCTAssertFalse(
            GhosttySurfaceResponderRestorePolicy.shouldAttemptRestore(
                hasLiveSurface: true,
                hasCompletedSurfaceAttachment: false,
                desiredFocus: true
            ),
            "在 scroll view 的 attach/layout 真正完成前，不应提前排队 responder restore；否则 attach 阶段会被旧 pending 任务抢跑。"
        )
    }

    func testResponderRestorePolicyAllowsFocusedSurfaceAfterAttachment() {
        XCTAssertTrue(
            GhosttySurfaceResponderRestorePolicy.shouldAttemptRestore(
                hasLiveSurface: true,
                hasCompletedSurfaceAttachment: true,
                desiredFocus: true
            ),
            "surface 完成 attach 后，如果 pane 仍应保持 focused，就应允许发起 responder restore。"
        )
    }

    func testResponderRestorePolicyBlocksUninitializedSurfaceBeforeAttachmentRecovery() {
        XCTAssertEqual(
            GhosttySurfaceResponderRestorePolicy.blockedReason(
                hasLiveSurface: false,
                hasCompletedSurfaceAttachment: true,
                desiredFocus: true
            ),
            "surface-uninitialized",
            "底层 surface 尚未真正创建时，不应继续参与 responder restore；否则会把焦点抢到一个空壳 view。"
        )
    }

    func testWindowResponderRestoreRetryPolicyRetriesTransientWindowLoss() {
        XCTAssertTrue(
            GhosttySurfaceWindowResponderRestoreRetryPolicy.shouldRetry(
                attempt: 1,
                desiredFocus: true
            ),
            "如果 focused pane 在恢复链路里短暂丢失 window，应该允许短时间内继续补偿重试，而不是第一次 window-missing 就直接放弃。"
        )
    }

    func testWindowResponderRestoreRetryPolicyStopsWhenPaneNoLongerNeedsFocus() {
        XCTAssertFalse(
            GhosttySurfaceWindowResponderRestoreRetryPolicy.shouldRetry(
                attempt: 1,
                desiredFocus: false
            ),
            "一旦 pane 已不再是目标焦点，就不应继续为旧 surface 保持 responder restore 重试。"
        )
    }

    func testWindowResponderRestoreRetryPolicyStopsAfterRetryBudget() {
        XCTAssertFalse(
            GhosttySurfaceWindowResponderRestoreRetryPolicy.shouldRetry(
                attempt: 9,
                desiredFocus: true
            ),
            "transient window detach 需要补偿，但重试预算必须有限，避免在真正失活后无限循环。"
        )
    }
}
