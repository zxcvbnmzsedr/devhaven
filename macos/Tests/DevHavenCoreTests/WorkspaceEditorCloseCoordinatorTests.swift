import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceEditorCloseCoordinatorTests: XCTestCase {
    func testBeginClosingStopsAtFirstDirtyTabAndQueuesRemainingBatch() {
        let coordinator = WorkspaceEditorCloseCoordinator()
        let cleanTab = makeTab(id: "editor-clean", filePath: "/tmp/devhaven/Clean.swift", isDirty: false)
        let dirtyTab = makeTab(id: "editor-dirty", filePath: "/tmp/devhaven/Dirty.swift", isDirty: true)
        let tailTab = makeTab(id: "editor-tail", filePath: "/tmp/devhaven/Tail.swift", isDirty: false)

        let result = coordinator.beginClosing(
            [cleanTab.id, dirtyTab.id, tailTab.id],
            in: "/tmp/devhaven-project",
            displayProjectPath: "/tmp/devhaven-project",
            tabs: [cleanTab, dirtyTab, tailTab]
        )

        XCTAssertEqual(result.forceCloseTabIDs, [cleanTab.id])
        XCTAssertEqual(result.request?.tabID, dirtyTab.id)
        XCTAssertEqual(result.request?.title, dirtyTab.title)

        let confirmed = coordinator.confirmCloseRequest(try! XCTUnwrap(result.request))
        XCTAssertEqual(confirmed.projectPath, "/tmp/devhaven-project")
        XCTAssertEqual(confirmed.tabID, dirtyTab.id)
        XCTAssertEqual(confirmed.remainingTabIDs, [tailTab.id])
    }

    func testDismissCloseRequestClearsPendingBatch() {
        let coordinator = WorkspaceEditorCloseCoordinator()
        let dirtyTab = makeTab(id: "editor-dirty", filePath: "/tmp/devhaven/Dirty.swift", isDirty: true)

        let result = coordinator.beginClosing(
            [dirtyTab.id],
            in: "/tmp/devhaven-project",
            displayProjectPath: "/display/project",
            tabs: [dirtyTab]
        )
        coordinator.dismissCloseRequest()

        let confirmed = coordinator.confirmCloseRequest(try! XCTUnwrap(result.request))
        XCTAssertEqual(confirmed.projectPath, "/display/project")
        XCTAssertEqual(confirmed.remainingTabIDs, [])
    }

    func testPostCloseSelectionPrefersEditorThenDiffThenTerminal() {
        let coordinator = WorkspaceEditorCloseCoordinator()
        let diffTab = makeDiffTab(id: "diff-1")

        XCTAssertEqual(
            coordinator.postCloseSelection(
                preferredEditorTabID: "editor-1",
                diffTabs: [diffTab],
                terminalTabID: "terminal-1"
            ),
            .editor("editor-1")
        )
        XCTAssertEqual(
            coordinator.postCloseSelection(
                preferredEditorTabID: nil,
                diffTabs: [diffTab],
                terminalTabID: "terminal-1"
            ),
            .diff(diffTab.id)
        )
        XCTAssertEqual(
            coordinator.postCloseSelection(
                preferredEditorTabID: nil,
                diffTabs: [],
                terminalTabID: "terminal-1"
            ),
            .terminal("terminal-1")
        )
        XCTAssertEqual(
            coordinator.postCloseSelection(
                preferredEditorTabID: nil,
                diffTabs: [],
                terminalTabID: nil
            ),
            .none
        )
    }

    private func makeTab(id: String, filePath: String, isDirty: Bool) -> WorkspaceEditorTabState {
        WorkspaceEditorTabState(
            id: id,
            identity: filePath,
            projectPath: "/tmp/devhaven-project",
            filePath: filePath,
            title: URL(fileURLWithPath: filePath).lastPathComponent,
            kind: .text,
            text: "",
            isEditable: true,
            isDirty: isDirty
        )
    }

    private func makeDiffTab(id: String) -> WorkspaceDiffTabState {
        WorkspaceDiffTabState(
            id: id,
            identity: id,
            title: "Diff",
            source: .gitLogCommitFile(
                repositoryPath: "/tmp/repo",
                commitHash: "abc123",
                filePath: "Diff.swift"
            ),
            viewerMode: .sideBySide
        )
    }
}
