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

    func testAttachmentStateResetForContainerReuseClearsVisibilityFocusAndResizeCaches() {
        var state = GhosttySurfaceAttachmentState(
            lastOcclusion: true,
            lastSurfaceFocus: true,
            lastBackingSize: NSSize(width: 320, height: 180)
        )

        state.prepareForContainerReuse()

        XCTAssertNil(state.lastOcclusion)
        XCTAssertNil(state.lastSurfaceFocus)
        XCTAssertEqual(state.lastBackingSize, NSSize.zero)
    }

    func testSurfaceAttachmentHandlerRunsAfterFirstLayoutOnlyOnce() {
        let surfaceView = NSView(frame: .zero)
        var attachCount = 0
        let scrollView = GhosttySurfaceScrollView(
            surfaceView: surfaceView,
            onSurfaceAttached: {
                attachCount += 1
            }
        )
        scrollView.frame = NSRect(x: 0, y: 0, width: 320, height: 180)

        XCTAssertEqual(attachCount, 0)

        scrollView.layoutSubtreeIfNeeded()
        XCTAssertEqual(attachCount, 1)

        scrollView.layoutSubtreeIfNeeded()
        XCTAssertEqual(attachCount, 1)
    }

    func testSurfaceAttachmentHandlerRunsAgainAfterSurfaceSwap() {
        let firstSurfaceView = NSView(frame: .zero)
        var attachCount = 0
        let scrollView = GhosttySurfaceScrollView(
            surfaceView: firstSurfaceView,
            onSurfaceAttached: {
                attachCount += 1
            }
        )
        scrollView.frame = NSRect(x: 0, y: 0, width: 320, height: 180)
        scrollView.layoutSubtreeIfNeeded()

        let secondSurfaceView = NSView(frame: .zero)
        scrollView.setSurfaceAttachmentHandler {
            attachCount += 1
        }
        scrollView.setSurfaceView(secondSurfaceView)

        XCTAssertEqual(attachCount, 2)
        XCTAssertTrue(secondSurfaceView.isDescendant(of: scrollView))
    }
}
