import XCTest
import AppKit
@testable import DevHavenApp

@MainActor
final class GhosttySurfaceScrollViewTests: XCTestCase {
    func testScrollViewKeepsWrappedSurfaceMountedAndSizedToBounds() {
        let surfaceView = NSView(frame: .zero)
        let scrollView = GhosttySurfaceScrollView(surfaceView: surfaceView)
        scrollView.frame = NSRect(x: 0, y: 0, width: 320, height: 180)

        scrollView.layoutSubtreeIfNeeded()

        XCTAssertTrue(surfaceView.isDescendant(of: scrollView))
        XCTAssertEqual(surfaceView.frame.size.width, 320, accuracy: 0.001)
        XCTAssertEqual(surfaceView.frame.size.height, 180, accuracy: 0.001)
    }
}
