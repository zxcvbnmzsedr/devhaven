import XCTest
import CoreGraphics
@testable import DevHavenApp

final class GhosttySurfaceResizePolicyTests: XCTestCase {
    func testResizeDecisionSkipsUnchangedBackingSize() {
        let decision = GhosttySurfaceResizePolicy.resizeDecision(
            lastBackingSize: CGSize(width: 800, height: 600),
            newBackingSize: CGSize(width: 800, height: 600),
            cellSizeInPixels: CGSize(width: 0, height: 0)
        )

        XCTAssertNil(decision)
    }

    func testResizeDecisionAllowsChangedBackingSizeWhenCellSizeUnknown() {
        let decision = GhosttySurfaceResizePolicy.resizeDecision(
            lastBackingSize: CGSize(width: 800, height: 600),
            newBackingSize: CGSize(width: 801.8, height: 601.4),
            cellSizeInPixels: .zero
        )

        XCTAssertEqual(decision, GhosttySurfaceResizeDecision(width: 801, height: 601))
    }

    func testResizeDecisionSkipsUndersizedGrid() {
        let decision = GhosttySurfaceResizePolicy.resizeDecision(
            lastBackingSize: CGSize(width: 800, height: 600),
            newBackingSize: CGSize(width: 39, height: 21),
            cellSizeInPixels: CGSize(width: 10, height: 10)
        )

        XCTAssertNil(decision)
    }

    func testResizeDecisionAllowsSufficientGrid() {
        let decision = GhosttySurfaceResizePolicy.resizeDecision(
            lastBackingSize: CGSize(width: 800, height: 600),
            newBackingSize: CGSize(width: 55, height: 25),
            cellSizeInPixels: CGSize(width: 10, height: 10)
        )

        XCTAssertEqual(decision, GhosttySurfaceResizeDecision(width: 55, height: 25))
    }
}
