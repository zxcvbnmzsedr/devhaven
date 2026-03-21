import XCTest
import AppKit
import GhosttyKit
@testable import DevHavenApp

@MainActor
final class GhosttySurfaceScrollInputTests: XCTestCase {
    func testPreciseScrollingDoublesDeltaAndPreservesChangedMomentum() {
        let input = GhosttySurfaceScrollInput.make(
            deltaX: 1.5,
            deltaY: -2.0,
            hasPreciseScrollingDeltas: true,
            momentumPhase: .changed
        )

        XCTAssertEqual(input.deltaX, 3.0, accuracy: 0.001)
        XCTAssertEqual(input.deltaY, -4.0, accuracy: 0.001)
        XCTAssertEqual(input.mods, ghostty_input_scroll_mods_t(0b0000_0111))
    }

    func testDiscreteScrollingKeepsDeltaAndEncodesEndedMomentumWithoutPrecisionBit() {
        let input = GhosttySurfaceScrollInput.make(
            deltaX: 0.5,
            deltaY: -1.0,
            hasPreciseScrollingDeltas: false,
            momentumPhase: .ended
        )

        XCTAssertEqual(input.deltaX, 0.5, accuracy: 0.001)
        XCTAssertEqual(input.deltaY, -1.0, accuracy: 0.001)
        XCTAssertEqual(input.mods, ghostty_input_scroll_mods_t(0b0000_1000))
    }
}
