import XCTest
@testable import DevHavenApp

final class WorkspaceTerminalStartupPresentationPolicyTests: XCTestCase {
    func testDoesNotShowOverlayWhenInitializationFailed() {
        XCTAssertFalse(
            WorkspaceTerminalStartupPresentationPolicy.shouldShowOverlay(
                hasInitializationError: true,
                processState: .failed,
                hasSurfaceView: false
            )
        )
    }

    func testDoesNotShowOverlayWhenProcessExited() {
        XCTAssertFalse(
            WorkspaceTerminalStartupPresentationPolicy.shouldShowOverlay(
                hasInitializationError: false,
                processState: .exited,
                hasSurfaceView: false
            )
        )
    }

    func testShowsOverlayWhenSurfaceIsNotPreparedYet() {
        XCTAssertTrue(
            WorkspaceTerminalStartupPresentationPolicy.shouldShowOverlay(
                hasInitializationError: false,
                processState: .running,
                hasSurfaceView: false
            )
        )
    }

    func testHidesOverlayAfterSurfaceIsPrepared() {
        XCTAssertFalse(
            WorkspaceTerminalStartupPresentationPolicy.shouldShowOverlay(
                hasInitializationError: false,
                processState: .running,
                hasSurfaceView: true
            )
        )
    }
}
