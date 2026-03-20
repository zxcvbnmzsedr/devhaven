import XCTest
@testable import DevHavenApp
@testable import DevHavenCore

@MainActor
final class WorkspaceTerminalSessionStoreTests: XCTestCase {
    func testStoreReusesModelForSamePaneAcrossRepeatedLookups() {
        let store = WorkspaceTerminalSessionStore()
        let pane = makePane(id: "pane:1")

        let first = store.model(for: pane)
        let second = store.model(for: pane)

        XCTAssertIdentical(first, second)
        XCTAssertEqual(store.modelCount, 1)
    }

    func testStoreReleasesModelsForRemovedPanesDuringSync() {
        let store = WorkspaceTerminalSessionStore()
        let firstPane = makePane(id: "pane:1")
        let secondPane = makePane(id: "pane:2")

        let firstModel = store.model(for: firstPane)
        _ = store.model(for: secondPane)

        store.syncRetainedPaneIDs([secondPane.id])

        XCTAssertEqual(store.modelCount, 1)
        let recreated = store.model(for: firstPane)
        XCTAssertFalse(firstModel === recreated)
    }

    func testWarmSelectedPaneOnlyPreparesControllersSelectedPane() throws {
        let store = WorkspaceTerminalSessionStore()
        let controller = GhosttyWorkspaceController(projectPath: "/tmp/devhaven")
        _ = controller.splitFocusedPane(direction: .right)
        let selectedPane = try XCTUnwrap(controller.selectedPane)
        let unselectedPane = try XCTUnwrap(
            controller.selectedTab?.leaves.first(where: { $0.id != selectedPane.id })
        )

        store.warmSelectedPane(in: controller)

        XCTAssertEqual(store.modelCount, 1)
        let warmed = store.model(for: selectedPane)
        let createdLater = store.model(for: unselectedPane)
        XCTAssertEqual(store.modelCount, 2)
        XCTAssertFalse(warmed === createdLater)
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
