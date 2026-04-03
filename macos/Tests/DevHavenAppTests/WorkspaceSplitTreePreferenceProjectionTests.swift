import XCTest
@testable import DevHavenApp

final class WorkspaceSplitTreePreferenceProjectionTests: XCTestCase {
    func testItemFramesAreRoundedToStablePointAlignedRects() {
        let frames = WorkspaceSplitTreePreferenceProjection.itemFrames(
            from: [
                WorkspacePaneItemFramePreference(
                    paneID: "pane-1",
                    itemID: "item-1",
                    frame: CGRect(x: 10.49, y: 20.51, width: 100.49, height: 30.51)
                )
            ]
        )

        XCTAssertEqual(
            frames["item-1"],
            CGRect(x: 10, y: 21, width: 100, height: 31)
        )
    }

    func testTabStripFramesCollapseSubPointJitterIntoSameProjection() {
        let first = WorkspaceSplitTreePreferenceProjection.tabStripFrames(
            from: [
                WorkspacePaneTabStripFramePreference(
                    paneID: "pane-1",
                    frame: CGRect(x: 5.12, y: 7.21, width: 220.18, height: 28.18)
                )
            ]
        )
        let second = WorkspaceSplitTreePreferenceProjection.tabStripFrames(
            from: [
                WorkspacePaneTabStripFramePreference(
                    paneID: "pane-1",
                    frame: CGRect(x: 5.39, y: 7.43, width: 220.41, height: 28.42)
                )
            ]
        )

        XCTAssertEqual(
            first["pane-1"],
            CGRect(x: 5, y: 7, width: 220, height: 28)
        )
        XCTAssertEqual(second["pane-1"], first["pane-1"])
    }

    func testNormalizePreservesAlreadyStableRects() {
        let rect = CGRect(x: 12, y: 18, width: 240, height: 32)
        XCTAssertEqual(
            WorkspaceSplitTreePreferenceProjection.normalize(rect),
            rect
        )
    }
}
