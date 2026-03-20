import XCTest
import AppKit
@testable import DevHavenApp

@MainActor
final class GhosttySurfaceContainerViewTests: XCTestCase {
    func testContainerKeepsWrappedSurfaceMountedAndSizedToBounds() {
        let surfaceView = NSView(frame: .zero)
        let container = GhosttySurfaceContainerView(surfaceView: surfaceView)
        container.frame = NSRect(x: 0, y: 0, width: 320, height: 180)

        container.layoutSubtreeIfNeeded()

        XCTAssertTrue(surfaceView.isDescendant(of: container))
        XCTAssertEqual(surfaceView.frame.size.width, 320, accuracy: 0.001)
        XCTAssertEqual(surfaceView.frame.size.height, 180, accuracy: 0.001)
    }
}
