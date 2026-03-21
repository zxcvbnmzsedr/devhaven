import XCTest
@testable import DevHavenApp

final class WorkspaceSidebarLayoutPolicyTests: XCTestCase {
    func testSidebarWidthFromRatioClampsToMinimumWidth() {
        let width = WorkspaceSidebarLayoutPolicy.sidebarWidth(for: 0.05, totalWidth: 1280)

        XCTAssertEqual(width, 220, accuracy: 0.001)
    }

    func testSidebarWidthFromRatioKeepsDefaultWidthAroundInitialRatio() {
        let width = WorkspaceSidebarLayoutPolicy.sidebarWidth(
            for: 280.0 / 1280.0,
            totalWidth: 1280
        )

        XCTAssertEqual(width, WorkspaceSidebarLayoutPolicy.defaultSidebarWidth, accuracy: 0.001)
    }

    func testSidebarWidthFromRatioLeavesMinimumRoomForWorkspaceContent() {
        let width = WorkspaceSidebarLayoutPolicy.sidebarWidth(for: 0.8, totalWidth: 680)

        XCTAssertEqual(width, 220, accuracy: 0.001)
    }

    func testSidebarRatioUsesClampedWidthInsteadOfOverflowingContent() {
        let ratio = WorkspaceSidebarLayoutPolicy.sidebarRatio(for: 600, totalWidth: 1000)

        XCTAssertEqual(ratio, 0.42, accuracy: 0.0001)
    }
}
