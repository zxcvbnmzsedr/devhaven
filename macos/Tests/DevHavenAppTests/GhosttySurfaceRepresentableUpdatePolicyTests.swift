import XCTest
@testable import DevHavenApp
@testable import DevHavenCore

@MainActor
final class GhosttySurfaceRepresentableUpdatePolicyTests: XCTestCase {
    func testRepresentableUpdateDoesNotApplyHostSyncByDefault() {
        XCTAssertFalse(GhosttySurfaceRepresentableUpdatePolicy.shouldApplyLatestModelStateOnUpdate)
    }

    func testResolvedSurfaceViewCreatesFreshModelsSurfaceWhenCurrentSurfaceIsMissing() {
        let model = GhosttySurfaceHostModel(request: makeRequest(paneID: "pane:fresh"))
        defer { model.releaseSurface() }

        XCTAssertNil(model.currentSurfaceView)

        let resolved = GhosttySurfaceRepresentableUpdatePolicy.resolvedSurfaceView(
            for: model,
            preferredFocus: false
        )

        XCTAssertTrue(model.currentSurfaceView === resolved)
    }

    func testResolvedSurfaceViewReusesExistingSurfaceWhenModelAlreadyOwnsOne() {
        let model = GhosttySurfaceHostModel(request: makeRequest(paneID: "pane:existing"))
        defer { model.releaseSurface() }
        let existing = model.acquireSurfaceView(preferredFocus: false)

        let resolved = GhosttySurfaceRepresentableUpdatePolicy.resolvedSurfaceView(
            for: model,
            preferredFocus: true
        )

        XCTAssertTrue(existing === resolved)
    }

    private func makeRequest(paneID: String) -> WorkspaceTerminalLaunchRequest {
        WorkspaceTerminalLaunchRequest(
            projectPath: "/tmp/devhaven",
            workspaceId: "workspace:test",
            tabId: "tab:test",
            paneId: paneID,
            surfaceId: "surface:\(paneID)",
            terminalSessionId: "session:\(paneID)"
        )
    }
}
