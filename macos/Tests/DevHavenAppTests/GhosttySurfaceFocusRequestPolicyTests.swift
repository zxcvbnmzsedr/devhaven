import XCTest
import AppKit
@testable import DevHavenApp

final class GhosttySurfaceFocusRequestPolicyTests: XCTestCase {
    func testSkipsFocusRequestWhileDividerDragIsInFlight() {
        XCTAssertFalse(
            GhosttySurfaceFocusRequestPolicy.shouldRequestFocus(
                preferredFocus: true,
                wasPreferredFocus: false,
                isSurfaceFocused: false,
                currentEventType: .leftMouseDragged
            )
        )
    }

    func testSkipsFocusRequestWhenSurfaceIsAlreadyFocused() {
        XCTAssertFalse(
            GhosttySurfaceFocusRequestPolicy.shouldRequestFocus(
                preferredFocus: true,
                wasPreferredFocus: true,
                isSurfaceFocused: true,
                currentEventType: nil
            )
        )
    }

    func testAllowsFocusRequestWhenPaneShouldBecomeFocusedOutsideDrag() {
        XCTAssertTrue(
            GhosttySurfaceFocusRequestPolicy.shouldRequestFocus(
                preferredFocus: true,
                wasPreferredFocus: false,
                isSurfaceFocused: false,
                currentEventType: nil
            )
        )
    }

    func testSkipsFocusRequestWhenPreferredFocusHasNotChanged() {
        XCTAssertFalse(
            GhosttySurfaceFocusRequestPolicy.shouldRequestFocus(
                preferredFocus: true,
                wasPreferredFocus: true,
                isSurfaceFocused: false,
                currentEventType: .leftMouseDown
            )
        )
    }

    func testSkipsFocusRequestWhenPaneIsNotPreferredFocusTarget() {
        XCTAssertFalse(
            GhosttySurfaceFocusRequestPolicy.shouldRequestFocus(
                preferredFocus: false,
                wasPreferredFocus: false,
                isSurfaceFocused: false,
                currentEventType: nil
            )
        )
    }

    func testAllowsFocusRequestWhenPreferredFocusTransitionsToTrue() {
        XCTAssertTrue(
            GhosttySurfaceFocusRequestPolicy.shouldRequestFocus(
                preferredFocus: true,
                wasPreferredFocus: false,
                isSurfaceFocused: false,
                currentEventType: nil
            )
        )
    }
}
