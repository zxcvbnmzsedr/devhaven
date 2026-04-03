import XCTest
import DevHavenCore
@testable import DevHavenApp

@MainActor
final class WorkspaceTerminalSessionStoreTests: XCTestCase {
    func testModelCreatedAfterTrackingSyncImmediatelyStartsCodexTracking() {
        let store = WorkspaceTerminalSessionStore()
        store.syncCodexDisplayTracking(["pane-1"])

        let pane = makePaneState(projectPath: "/tmp/project", paneID: "pane-1")
        let model = store.model(for: pane.selectedItem ?? pane.items[0], in: pane)
        model.updateCodexDisplaySnapshot(withVisibleText: "Codex output", now: Date(timeIntervalSinceReferenceDate: 100))

        XCTAssertEqual(model.codexDisplaySnapshot()?.recentTextWindow, "Codex output")
    }

    func testRegistryNotifiesLateMaterializedModelCreation() {
        let registry = WorkspaceTerminalStoreRegistry()
        var observedProjectPath: String?
        var observedPaneID: String?

        registry.setCodexDisplayModelCreatedObserver { projectPath, paneID, _ in
            observedProjectPath = projectPath
            observedPaneID = paneID
        }

        let projectPath = "/tmp/project"
        let paneID = "pane-1"
        let store = registry.store(for: projectPath)
        let pane = makePaneState(projectPath: projectPath, paneID: paneID)
        _ = store.model(for: pane.selectedItem ?? pane.items[0], in: pane)

        XCTAssertEqual(observedProjectPath, projectPath)
        XCTAssertEqual(observedPaneID, paneID)
    }

    private func makePaneState(projectPath: String, paneID: String) -> WorkspacePaneState {
        let item = WorkspacePaneItemState(
            request: WorkspaceTerminalLaunchRequest(
                projectPath: projectPath,
                workspaceId: "workspace",
                tabId: "tab",
                paneId: paneID,
                surfaceId: "surface-\(paneID)",
                terminalSessionId: "session-\(paneID)"
            ),
            title: "终端"
        )
        return WorkspacePaneState(
            paneId: paneID,
            items: [item],
            selectedItemId: item.id
        )
    }
}
