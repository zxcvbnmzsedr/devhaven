import XCTest
import GhosttyKit
@testable import DevHavenApp

@MainActor
final class GhosttySurfaceBridgeTabPaneTests: XCTestCase {
    func testHandleActionRoutesTabRequestsToClosures() {
        let bridge = GhosttySurfaceBridge()
        var newTabCount = 0
        var closeModes: [ghostty_action_close_tab_mode_e] = []
        var gotoTargets: [ghostty_action_goto_tab_e] = []
        var moveAmounts: [Int] = []

        bridge.onNewTab = {
            newTabCount += 1
            return true
        }
        bridge.onCloseTab = { mode in
            closeModes.append(mode)
            return true
        }
        bridge.onGotoTab = { target in
            gotoTargets.append(target)
            return true
        }
        bridge.onMoveTab = { move in
            moveAmounts.append(Int(move.amount))
            return true
        }

        XCTAssertTrue(bridge.handleAction(target: ghostty_target_s(), action: makeAction(GHOSTTY_ACTION_NEW_TAB)))
        XCTAssertTrue(bridge.handleAction(target: ghostty_target_s(), action: makeCloseTabAction(mode: GHOSTTY_ACTION_CLOSE_TAB_MODE_RIGHT)))
        XCTAssertTrue(bridge.handleAction(target: ghostty_target_s(), action: makeGotoTabAction(target: ghostty_action_goto_tab_e(rawValue: 2))))
        XCTAssertTrue(bridge.handleAction(target: ghostty_target_s(), action: makeMoveTabAction(amount: 1)))

        XCTAssertEqual(newTabCount, 1)
        XCTAssertEqual(closeModes, [GHOSTTY_ACTION_CLOSE_TAB_MODE_RIGHT])
        XCTAssertEqual(gotoTargets.map(\.rawValue), [2])
        XCTAssertEqual(moveAmounts, [1])
    }

    func testHandleActionRoutesSplitRequestsToUnifiedClosure() {
        let bridge = GhosttySurfaceBridge()
        var actions: [GhosttySplitAction] = []
        bridge.onSplitAction = { action in
            actions.append(action)
            return true
        }

        XCTAssertTrue(bridge.handleAction(target: ghostty_target_s(), action: makeNewSplitAction(direction: GHOSTTY_SPLIT_DIRECTION_RIGHT)))
        XCTAssertTrue(bridge.handleAction(target: ghostty_target_s(), action: makeGotoSplitAction(direction: GHOSTTY_GOTO_SPLIT_LEFT)))
        XCTAssertTrue(bridge.handleAction(target: ghostty_target_s(), action: makeResizeSplitAction(direction: GHOSTTY_RESIZE_SPLIT_RIGHT, amount: 12)))
        XCTAssertTrue(bridge.handleAction(target: ghostty_target_s(), action: makeAction(GHOSTTY_ACTION_EQUALIZE_SPLITS)))
        XCTAssertTrue(bridge.handleAction(target: ghostty_target_s(), action: makeAction(GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM)))

        XCTAssertEqual(actions.count, 5)
        XCTAssertEqual(actions[0], .newSplit(direction: .right))
        XCTAssertEqual(actions[1], .gotoSplit(direction: .left))
        XCTAssertEqual(actions[2], .resizeSplit(direction: .right, amount: 12))
        XCTAssertEqual(actions[3], .equalizeSplits)
        XCTAssertEqual(actions[4], .toggleSplitZoom)
    }

    private func makeAction(_ tag: ghostty_action_tag_e) -> ghostty_action_s {
        var action = ghostty_action_s()
        action.tag = tag
        return action
    }

    private func makeCloseTabAction(mode: ghostty_action_close_tab_mode_e) -> ghostty_action_s {
        var action = makeAction(GHOSTTY_ACTION_CLOSE_TAB)
        action.action.close_tab_mode = mode
        return action
    }

    private func makeGotoTabAction(target: ghostty_action_goto_tab_e) -> ghostty_action_s {
        var action = makeAction(GHOSTTY_ACTION_GOTO_TAB)
        action.action.goto_tab = target
        return action
    }

    private func makeMoveTabAction(amount: Int) -> ghostty_action_s {
        var action = makeAction(GHOSTTY_ACTION_MOVE_TAB)
        action.action.move_tab = ghostty_action_move_tab_s(amount: amount)
        return action
    }

    private func makeNewSplitAction(direction: ghostty_action_split_direction_e) -> ghostty_action_s {
        var action = makeAction(GHOSTTY_ACTION_NEW_SPLIT)
        action.action.new_split = direction
        return action
    }

    private func makeGotoSplitAction(direction: ghostty_action_goto_split_e) -> ghostty_action_s {
        var action = makeAction(GHOSTTY_ACTION_GOTO_SPLIT)
        action.action.goto_split = direction
        return action
    }

    private func makeResizeSplitAction(direction: ghostty_action_resize_split_direction_e, amount: UInt16) -> ghostty_action_s {
        var action = makeAction(GHOSTTY_ACTION_RESIZE_SPLIT)
        action.action.resize_split = ghostty_action_resize_split_s(amount: amount, direction: direction)
        return action
    }
}
