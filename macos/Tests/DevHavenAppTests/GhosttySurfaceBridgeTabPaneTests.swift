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


    func testHandleActionRoutesDesktopNotificationToClosure() {
        let bridge = GhosttySurfaceBridge()
        var received: (String, String)?
        bridge.onDesktopNotification = { title, body in
            received = (title, body)
        }

        var action = makeAction(GHOSTTY_ACTION_DESKTOP_NOTIFICATION)
        "任务完成".withCString { titlePointer in
            "构建已通过".withCString { bodyPointer in
                action.action.desktop_notification = ghostty_action_desktop_notification_s(
                    title: titlePointer,
                    body: bodyPointer
                )
                XCTAssertTrue(bridge.handleAction(target: ghostty_target_s(), action: action))
            }
        }

        XCTAssertEqual(received?.0, "任务完成")
        XCTAssertEqual(received?.1, "构建已通过")
    }

    func testHandleActionUpdatesTaskStatusAndBellState() {
        let bridge = GhosttySurfaceBridge()
        var statuses: [GhosttySurfaceTaskStatus] = []
        bridge.onTaskStatusChange = { status in
            statuses.append(status)
        }

        var progress = makeAction(GHOSTTY_ACTION_PROGRESS_REPORT)
        progress.action.progress_report = ghostty_action_progress_report_s(
            state: GHOSTTY_PROGRESS_STATE_SET,
            progress: 42
        )
        XCTAssertTrue(bridge.handleAction(target: ghostty_target_s(), action: progress))
        XCTAssertEqual(bridge.state.taskStatus, .running)

        let bell = makeAction(GHOSTTY_ACTION_RING_BELL)
        XCTAssertTrue(bridge.handleAction(target: ghostty_target_s(), action: bell))
        XCTAssertEqual(bridge.state.bellCount, 1)

        progress.action.progress_report = ghostty_action_progress_report_s(
            state: GHOSTTY_PROGRESS_STATE_REMOVE,
            progress: -1
        )
        XCTAssertTrue(bridge.handleAction(target: ghostty_target_s(), action: progress))
        XCTAssertEqual(bridge.state.taskStatus, .idle)
        XCTAssertEqual(statuses, [.running, .idle])
    }

    func testHandleActionUpdatesSearchStateFromGhosttySearchCallbacks() {
        let bridge = GhosttySurfaceBridge()

        var startSearch = makeAction(GHOSTTY_ACTION_START_SEARCH)
        "hello".withCString { needlePointer in
            startSearch.action.start_search = ghostty_action_start_search_s(needle: needlePointer)
            XCTAssertTrue(bridge.handleAction(target: ghostty_target_s(), action: startSearch))
        }

        XCTAssertEqual(bridge.state.searchNeedle, "hello")
        XCTAssertEqual(bridge.state.searchFocusCount, 1)
        XCTAssertNil(bridge.state.searchTotal)
        XCTAssertNil(bridge.state.searchSelected)

        var total = makeAction(GHOSTTY_ACTION_SEARCH_TOTAL)
        total.action.search_total = ghostty_action_search_total_s(total: 7)
        XCTAssertTrue(bridge.handleAction(target: ghostty_target_s(), action: total))
        XCTAssertEqual(bridge.state.searchTotal, 7)

        var selected = makeAction(GHOSTTY_ACTION_SEARCH_SELECTED)
        selected.action.search_selected = ghostty_action_search_selected_s(selected: 2)
        XCTAssertTrue(bridge.handleAction(target: ghostty_target_s(), action: selected))
        XCTAssertEqual(bridge.state.searchSelected, 2)

        let end = makeAction(GHOSTTY_ACTION_END_SEARCH)
        XCTAssertTrue(bridge.handleAction(target: ghostty_target_s(), action: end))
        XCTAssertNil(bridge.state.searchNeedle)
        XCTAssertNil(bridge.state.searchTotal)
        XCTAssertNil(bridge.state.searchSelected)
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
