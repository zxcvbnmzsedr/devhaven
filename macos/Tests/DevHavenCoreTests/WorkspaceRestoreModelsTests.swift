import XCTest
@testable import DevHavenCore

final class WorkspaceRestoreModelsTests: XCTestCase {
    func testProjectWorkspaceRestoreSnapshotDecodesLegacyManifestWithoutEditorFields() throws {
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
                    selectedPresentedTab: .editor("editor-1"),
                    nextTabNumber: 2,
                    nextPaneNumber: 2,
                    editorTabs: [
                        WorkspaceEditorTabRestoreSnapshot(
                            id: "editor-1",
                            filePath: "/tmp/project/README.md",
                            title: "README.md",
                            isPinned: true
                        )
                    ],
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
                                                agentSummary: nil,
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

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(snapshot)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var sessions = try XCTUnwrap(object["sessions"] as? [[String: Any]])
        sessions[0].removeValue(forKey: "selectedPresentedTab")
        sessions[0].removeValue(forKey: "editorTabs")
        object["sessions"] = sessions

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try decoder.decode(WorkspaceRestoreSnapshot.self, from: legacyData)
        let restoredSession = try XCTUnwrap(decoded.sessions.first)

        XCTAssertNil(restoredSession.selectedPresentedTab)
        XCTAssertEqual(restoredSession.editorTabs, [])
        XCTAssertEqual(restoredSession.tabs.count, 1)
    }
}
