import XCTest
@testable import DevHavenApp

final class WorkspaceSplitLayoutPolicyTests: XCTestCase {
    func testClampedLeadingSizeRespectsMinimumLeadingPaneSize() {
        let resolved = WorkspaceSplitLayoutPolicy.clampedLeadingSize(
            proposedSize: 80,
            axisLength: 900,
            minLeadingSize: 220,
            minTrailingSize: 320
        )

        XCTAssertEqual(resolved, 220, accuracy: 0.001)
    }

    func testClampedLeadingSizeRespectsMinimumTrailingPaneSize() {
        let resolved = WorkspaceSplitLayoutPolicy.clampedLeadingSize(
            proposedSize: 760,
            axisLength: 900,
            minLeadingSize: 220,
            minTrailingSize: 320
        )

        XCTAssertEqual(resolved, 580, accuracy: 0.001)
    }

    func testClampedLeadingSizeFallsBackWhenContainerIsSmallerThanCombinedMinimums() {
        let resolved = WorkspaceSplitLayoutPolicy.clampedLeadingSize(
            proposedSize: 200,
            axisLength: 300,
            minLeadingSize: 220,
            minTrailingSize: 160
        )

        XCTAssertEqual(resolved, 140, accuracy: 0.001)
    }
}
