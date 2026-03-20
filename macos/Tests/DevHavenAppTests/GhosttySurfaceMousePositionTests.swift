import XCTest
import AppKit
@testable import DevHavenApp

@MainActor
final class GhosttySurfaceMousePositionTests: XCTestCase {
    func testGhosttyMousePositionFlipsLocalYToTerminalCoordinates() {
        let point = NSPoint(x: 24, y: 36)
        let mapped = GhosttySurfaceMousePosition.map(localPoint: point, boundsHeight: 200)

        XCTAssertEqual(mapped.x, 24, accuracy: 0.001)
        XCTAssertEqual(mapped.y, 164, accuracy: 0.001)
    }
}
