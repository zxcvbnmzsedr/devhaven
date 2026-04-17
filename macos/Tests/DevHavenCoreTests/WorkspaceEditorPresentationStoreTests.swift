import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceEditorPresentationStoreTests: XCTestCase {
    func testDefaultPresentationPutsAllTabsIntoSingleGroup() {
        let harness = EditorPresentationStoreHarness()
        let firstTab = harness.makeTab(id: "editor-1", filePath: "/tmp/devhaven/First.swift")
        let secondTab = harness.makeTab(id: "editor-2", filePath: "/tmp/devhaven/Second.swift")

        let presentation = harness.store.defaultPresentation(tabs: [firstTab, secondTab])

        XCTAssertEqual(presentation.groups.count, 1)
        XCTAssertEqual(presentation.groups.first?.tabIDs, [firstTab.id, secondTab.id])
        XCTAssertEqual(presentation.groups.first?.selectedTabID, secondTab.id)
        XCTAssertEqual(presentation.activeGroupID, presentation.groups.first?.id)
    }

    func testNormalizedPresentationTrimsDuplicatesAndMergesExtraGroups() throws {
        let harness = EditorPresentationStoreHarness()
        let firstTab = harness.makeTab(id: "editor-1", filePath: "/tmp/devhaven/First.swift")
        let secondTab = harness.makeTab(id: "editor-2", filePath: "/tmp/devhaven/Second.swift")
        let thirdTab = harness.makeTab(id: "editor-3", filePath: "/tmp/devhaven/Third.swift")

        let presentation = try XCTUnwrap(
            harness.store.normalizedPresentation(
                WorkspaceEditorPresentationState(
                    groups: [
                        WorkspaceEditorGroupState(id: "group-1", tabIDs: [firstTab.id, secondTab.id], selectedTabID: secondTab.id),
                        WorkspaceEditorGroupState(id: "group-2", tabIDs: [secondTab.id], selectedTabID: secondTab.id),
                        WorkspaceEditorGroupState(id: "group-3", tabIDs: [thirdTab.id], selectedTabID: thirdTab.id),
                    ],
                    activeGroupID: "group-3",
                    splitAxis: .vertical
                ),
                availableTabs: [firstTab, secondTab, thirdTab]
            )
        )

        XCTAssertEqual(presentation.groups.count, 2)
        XCTAssertEqual(presentation.groups[0].tabIDs, [firstTab.id, secondTab.id])
        XCTAssertEqual(presentation.groups[1].tabIDs, [thirdTab.id])
        XCTAssertEqual(presentation.activeGroupID, presentation.groups[0].id)
        XCTAssertEqual(presentation.splitAxis, .vertical)
    }

    func testResolvedPresentationUsesCurrentStateAndTabsForProject() throws {
        let harness = EditorPresentationStoreHarness()
        let firstTab = harness.makeTab(id: "editor-1", filePath: "/tmp/devhaven/First.swift")
        let secondTab = harness.makeTab(id: "editor-2", filePath: "/tmp/devhaven/Second.swift")
        harness.tabsByProjectPath[harness.projectPath] = [firstTab, secondTab]
        harness.state.editorPresentationByProjectPath[harness.projectPath] = WorkspaceEditorPresentationState(
            groups: [
                WorkspaceEditorGroupState(id: "group-1", tabIDs: [firstTab.id], selectedTabID: firstTab.id),
                WorkspaceEditorGroupState(id: "group-2", tabIDs: [secondTab.id], selectedTabID: secondTab.id),
            ],
            activeGroupID: "group-2",
            splitAxis: .horizontal
        )

        let presentation = try XCTUnwrap(harness.store.resolvedPresentation(for: harness.projectPath))

        XCTAssertEqual(presentation.groups.count, 2)
        XCTAssertEqual(presentation.activeGroupID, "group-2")
        XCTAssertEqual(presentation.groups[1].selectedTabID, secondTab.id)
    }

    func testRestorePresentationDropsPreviewTabs() throws {
        let harness = EditorPresentationStoreHarness()
        let regularTab = harness.makeTab(id: "editor-1", filePath: "/tmp/devhaven/Regular.swift", isPreview: false)
        let previewTab = harness.makeTab(id: "editor-2", filePath: "/tmp/devhaven/Preview.swift", isPreview: true)
        harness.tabsByProjectPath[harness.projectPath] = [regularTab, previewTab]
        harness.state.editorPresentationByProjectPath[harness.projectPath] = WorkspaceEditorPresentationState(
            groups: [
                WorkspaceEditorGroupState(
                    id: "group-1",
                    tabIDs: [regularTab.id, previewTab.id],
                    selectedTabID: previewTab.id
                ),
            ],
            activeGroupID: "group-1"
        )

        let presentation = try XCTUnwrap(harness.store.restorePresentation(for: harness.projectPath))

        XCTAssertEqual(presentation.groups.count, 1)
        XCTAssertEqual(presentation.groups[0].tabIDs, [regularTab.id])
        XCTAssertEqual(presentation.groups[0].selectedTabID, regularTab.id)
    }
}

@MainActor
private final class EditorPresentationStoreHarness {
    let projectPath = "/tmp/devhaven-project"
    let state = WorkspacePresentationState()
    var tabsByProjectPath: [String: [WorkspaceEditorTabState]] = [:]

    lazy var store = WorkspaceEditorPresentationStore(
        presentationState: state,
        editorTabsForProject: { [unowned self] in self.tabsByProjectPath[$0] ?? [] }
    )

    func makeTab(id: String, filePath: String, isPreview: Bool = false) -> WorkspaceEditorTabState {
        WorkspaceEditorTabState(
            id: id,
            identity: filePath,
            projectPath: projectPath,
            filePath: filePath,
            title: URL(fileURLWithPath: filePath).lastPathComponent,
            isPreview: isPreview,
            kind: .text,
            text: "",
            isEditable: true
        )
    }
}
