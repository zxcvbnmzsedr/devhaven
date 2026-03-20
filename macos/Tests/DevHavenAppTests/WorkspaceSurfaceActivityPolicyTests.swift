import XCTest
@testable import DevHavenApp

final class WorkspaceSurfaceActivityPolicyTests: XCTestCase {
    func testFocusedPaneInVisibleSelectedTabIsVisibleAndFocused() {
        let activity = WorkspaceSurfaceActivityPolicy.activity(
            isWorkspaceVisible: true,
            isSelectedTab: true,
            windowIsVisible: true,
            windowIsKey: true,
            focusedPaneID: "pane-1",
            paneID: "pane-1"
        )

        XCTAssertTrue(activity.isVisible)
        XCTAssertTrue(activity.isFocused)
    }

    func testPaneInHiddenTabIsNotVisibleOrFocused() {
        let activity = WorkspaceSurfaceActivityPolicy.activity(
            isWorkspaceVisible: true,
            isSelectedTab: false,
            windowIsVisible: true,
            windowIsKey: true,
            focusedPaneID: "pane-1",
            paneID: "pane-2"
        )

        XCTAssertFalse(activity.isVisible)
        XCTAssertFalse(activity.isFocused)
    }

    func testVisiblePaneStopsBeingFocusedWhenWindowResignsKey() {
        let activity = WorkspaceSurfaceActivityPolicy.activity(
            isWorkspaceVisible: true,
            isSelectedTab: true,
            windowIsVisible: true,
            windowIsKey: false,
            focusedPaneID: "pane-1",
            paneID: "pane-1"
        )

        XCTAssertTrue(activity.isVisible)
        XCTAssertFalse(activity.isFocused)
    }

    func testPaneStopsBeingVisibleWhenWorkspaceIsHidden() {
        let activity = WorkspaceSurfaceActivityPolicy.activity(
            isWorkspaceVisible: false,
            isSelectedTab: true,
            windowIsVisible: true,
            windowIsKey: true,
            focusedPaneID: "pane-1",
            paneID: "pane-1"
        )

        XCTAssertFalse(activity.isVisible)
        XCTAssertFalse(activity.isFocused)
    }
}
