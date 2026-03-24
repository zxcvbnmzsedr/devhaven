import XCTest
@testable import DevHavenApp

final class AppQuitGuardStateMachineTests: XCTestCase {
    func testFirstQuitRequestWithVisibleWindowShowsToastAndArmsGuard() {
        var state = AppQuitGuardState()
        let machine = AppQuitGuardStateMachine()
        let now = Date(timeIntervalSince1970: 1_000)

        let action = machine.handleQuitRequest(
            state: &state,
            now: now,
            hasVisibleWindow: true
        )

        XCTAssertEqual(
            action,
            .showToast(AppQuitGuardCopy.default.message)
        )
        XCTAssertEqual(state.pendingConfirmationDeadline, now.addingTimeInterval(machine.confirmationInterval))
        XCTAssertEqual(state.toastMessage, AppQuitGuardCopy.default.message)
    }

    func testSecondQuitRequestWithinConfirmationWindowTerminatesApp() {
        let machine = AppQuitGuardStateMachine()
        let now = Date(timeIntervalSince1970: 1_000)
        var state = AppQuitGuardState(
            pendingConfirmationDeadline: now.addingTimeInterval(machine.confirmationInterval),
            toastMessage: AppQuitGuardCopy.default.message
        )

        let action = machine.handleQuitRequest(
            state: &state,
            now: now.addingTimeInterval(0.8),
            hasVisibleWindow: true
        )

        XCTAssertEqual(action, .terminate)
        XCTAssertNil(state.pendingConfirmationDeadline)
        XCTAssertNil(state.toastMessage)
    }

    func testQuitRequestAfterConfirmationWindowShowsToastAgain() {
        let machine = AppQuitGuardStateMachine()
        let now = Date(timeIntervalSince1970: 1_000)
        var state = AppQuitGuardState(
            pendingConfirmationDeadline: now.addingTimeInterval(machine.confirmationInterval),
            toastMessage: AppQuitGuardCopy.default.message
        )

        let action = machine.handleQuitRequest(
            state: &state,
            now: now.addingTimeInterval(2.0),
            hasVisibleWindow: true
        )

        XCTAssertEqual(action, .showToast(AppQuitGuardCopy.default.message))
        XCTAssertEqual(state.toastMessage, AppQuitGuardCopy.default.message)
    }

    func testQuitRequestWithoutVisibleWindowTerminatesImmediately() {
        var state = AppQuitGuardState()
        let machine = AppQuitGuardStateMachine()

        let action = machine.handleQuitRequest(
            state: &state,
            now: Date(timeIntervalSince1970: 1_000),
            hasVisibleWindow: false
        )

        XCTAssertEqual(action, .terminate)
        XCTAssertNil(state.pendingConfirmationDeadline)
        XCTAssertNil(state.toastMessage)
    }

    func testExpireConfirmationClearsToastAfterDeadline() {
        let machine = AppQuitGuardStateMachine()
        let now = Date(timeIntervalSince1970: 1_000)
        var state = AppQuitGuardState(
            pendingConfirmationDeadline: now.addingTimeInterval(machine.confirmationInterval),
            toastMessage: AppQuitGuardCopy.default.message
        )

        machine.expireIfNeeded(state: &state, now: now.addingTimeInterval(1.6))

        XCTAssertNil(state.pendingConfirmationDeadline)
        XCTAssertNil(state.toastMessage)
    }
}

final class AppQuitGuardCopyTests: XCTestCase {
    func testDefaultCopyUsesExpectedPrompt() {
        XCTAssertEqual(AppQuitGuardCopy.default.message, "再按一次 ⌘Q 退出 DevHaven")
    }
}
