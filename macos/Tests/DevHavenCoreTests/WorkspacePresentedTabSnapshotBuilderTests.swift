import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspacePresentedTabSnapshotBuilderTests: XCTestCase {
    func testSnapshotBuildsTerminalEditorAndDiffItemsInDisplayOrder() {
        let controller = GhosttyWorkspaceController(projectPath: "/repo/project")
        let terminalTab = controller.createTab()
        let terminalTabIDs = controller.tabs.map(\.id)
        let terminalTabTitles = controller.tabs.map(\.title)
        let editorTab = WorkspaceEditorTabState(
            id: "editor-1",
            identity: "file:/repo/project/main.swift",
            projectPath: "/repo/project",
            filePath: "/repo/project/main.swift",
            title: "main.swift",
            isPinned: true,
            isPreview: true,
            kind: .text,
            isDirty: true
        )
        let diffTab = WorkspaceDiffTabState(
            id: "diff-1",
            identity: "diff:/repo/project/main.swift",
            title: "main.swift diff",
            source: .gitLogCommitFile(
                repositoryPath: "/repo/project",
                commitHash: "abc123",
                filePath: "main.swift"
            ),
            viewerMode: .sideBySide
        )

        let snapshot: NativeAppViewModel.WorkspacePresentedTabSnapshot = WorkspacePresentedTabSnapshotBuilder().snapshot(
            controller: controller,
            editorTabs: [editorTab],
            diffTabs: [diffTab],
            selection: .editor("editor-1")
        )

        XCTAssertEqual(snapshot.selection, WorkspacePresentedTabSelection.editor("editor-1"))
        XCTAssertEqual(snapshot.items.map { $0.id }, terminalTabIDs + ["editor-1", "diff-1"])
        XCTAssertEqual(
            snapshot.items.map { $0.selection },
            terminalTabIDs.map(WorkspacePresentedTabSelection.terminal) + [
                .editor("editor-1"),
                .diff("diff-1"),
            ]
        )
        XCTAssertEqual(snapshot.items.map { $0.title }, terminalTabTitles + ["● main.swift", "main.swift diff"])
        XCTAssertEqual(snapshot.items.map { $0.isSelected }, Array(repeating: false, count: terminalTabIDs.count) + [true, false])
        XCTAssertEqual(snapshot.items.map { $0.isPinned }, Array(repeating: false, count: terminalTabIDs.count) + [true, false])
        XCTAssertEqual(snapshot.items.map { $0.isPreview }, Array(repeating: false, count: terminalTabIDs.count) + [true, false])
        XCTAssertEqual(terminalTabIDs.last, terminalTab.id)
    }

    func testSnapshotHandlesMissingControllerAndNoSelection() {
        let snapshot = WorkspacePresentedTabSnapshotBuilder().snapshot(
            controller: nil,
            editorTabs: [],
            diffTabs: [],
            selection: nil
        )

        XCTAssertTrue(snapshot.items.isEmpty)
        XCTAssertNil(snapshot.selection)
    }
}
