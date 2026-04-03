import XCTest
@testable import DevHavenCore

final class WorkspaceRestoreStoreTests: XCTestCase {
    func testSaveSnapshotReturnsPersistedSnapshotWithoutRequiringReloadRoundTrip() throws {
        let homeDirectoryURL = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectoryURL) }

        let store = WorkspaceRestoreStore(homeDirectoryURL: homeDirectoryURL)
        let snapshot = WorkspaceRestoreSnapshot(
            activeProjectPath: "/tmp/project",
            selectedProjectPath: "/tmp/project",
            sessions: [
                ProjectWorkspaceRestoreSnapshot(
                    projectPath: "/tmp/project",
                    rootProjectPath: "/tmp/project",
                    isQuickTerminal: false,
                    workspaceId: "workspace-1",
                    selectedTabId: "tab-1",
                    nextTabNumber: 2,
                    nextPaneNumber: 2,
                    tabs: [
                        WorkspaceTabRestoreSnapshot(
                            id: "tab-1",
                            title: "Tab 1",
                            focusedPaneId: "pane-1",
                            tree: WorkspacePaneTreeRestoreSnapshot(
                                root: .leaf(
                                    WorkspacePaneRestoreSnapshot(
                                        paneId: "pane-1",
                                        selectedItemId: "surface-1",
                                        items: [
                                            WorkspacePaneItemRestoreSnapshot(
                                                surfaceId: "surface-1",
                                                terminalSessionId: "session-1",
                                                restoredWorkingDirectory: "/tmp/project",
                                                restoredTitle: "Shell",
                                                agentSummary: "Agent",
                                                snapshotTextRef: nil,
                                                snapshotText: "echo hello"
                                            )
                                        ]
                                    )
                                ),
                                zoomedPaneId: nil
                            )
                        )
                    ]
                )
            ]
        )

        let persisted = try store.saveSnapshot(snapshot)
        let pane = try XCTUnwrap(persisted.sessions.first?.tabs.first?.tree.leaves.first)
        XCTAssertNotNil(pane.snapshotTextRef)
        XCTAssertEqual(pane.snapshotText, "echo hello")

        let loaded = try XCTUnwrap(store.loadSnapshot())
        let loadedPane = try XCTUnwrap(loaded.sessions.first?.tabs.first?.tree.leaves.first)
        XCTAssertNotNil(loadedPane.snapshotTextRef)
        XCTAssertEqual(store.loadPaneText(for: loadedPane.snapshotTextRef), "echo hello")
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
