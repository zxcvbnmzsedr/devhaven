import XCTest
@testable import DevHavenApp
@testable import DevHavenCore

@MainActor
final class WorkspaceSurfaceRegistryTests: XCTestCase {
    func testRegistryReusesModelForSamePaneAcrossRepeatedLookups() {
        let registry = WorkspaceSurfaceRegistry()
        let pane = makePane(id: "pane:1")

        let first = registry.model(
            for: pane
        )
        let second = registry.model(
            for: pane
        )

        XCTAssertIdentical(first, second)
        XCTAssertEqual(registry.modelCount, 1)
    }

    func testRegistryReleasesModelsForRemovedPanesDuringSync() {
        let registry = WorkspaceSurfaceRegistry()
        let firstPane = makePane(id: "pane:1")
        let secondPane = makePane(id: "pane:2")

        let firstModel = registry.model(
            for: firstPane
        )
        _ = registry.model(
            for: secondPane
        )

        registry.syncRetainedPaneIDs([secondPane.id])

        XCTAssertEqual(registry.modelCount, 1)
        let recreated = registry.model(
            for: firstPane
        )
        XCTAssertFalse(firstModel === recreated)
    }

    private func makePane(id: String) -> WorkspacePaneState {
        WorkspacePaneState(
            request: WorkspaceTerminalLaunchRequest(
                projectPath: "/tmp/devhaven",
                workspaceId: "workspace:test",
                tabId: "tab:test",
                paneId: id,
                surfaceId: "surface:\(id)",
                terminalSessionId: "session:\(id)"
            )
        )
    }
}
