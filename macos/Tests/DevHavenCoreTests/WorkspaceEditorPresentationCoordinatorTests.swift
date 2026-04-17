import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceEditorPresentationCoordinatorTests: XCTestCase {
    func testActivateTabUpdatesSelectionFocusAndProjectTree() throws {
        let harness = EditorPresentationCoordinatorHarness()
        let firstTab = harness.makeTab(id: "editor-1", filePath: "/tmp/devhaven/First.swift")
        let secondTab = harness.makeTab(id: "editor-2", filePath: "/tmp/devhaven/Second.swift")
        harness.tabsByProjectPath[harness.projectPath] = [firstTab, secondTab]

        XCTAssertTrue(harness.coordinator.activateTab(secondTab.id, in: harness.projectPath))

        let presentation = try XCTUnwrap(harness.state.editorPresentationByProjectPath[harness.projectPath])
        XCTAssertEqual(presentation.activeGroupID, presentation.groups.first?.id)
        XCTAssertEqual(presentation.groups.first?.selectedTabID, secondTab.id)
        XCTAssertEqual(harness.state.selectedPresentedTabsByProjectPath[harness.projectPath], .editor(secondTab.id))
        XCTAssertEqual(harness.state.focusedArea, .editorTab(secondTab.id))
        XCTAssertEqual(harness.selectedProjectTreePaths.last?.0, secondTab.filePath)
    }

    func testSplitAndAssignTabToActiveGroupCreatesSecondEditorGroup() throws {
        let harness = EditorPresentationCoordinatorHarness()
        let firstTab = harness.makeTab(id: "editor-1", filePath: "/tmp/devhaven/First.swift")
        let secondTab = harness.makeTab(id: "editor-2", filePath: "/tmp/devhaven/Second.swift")
        harness.tabsByProjectPath[harness.projectPath] = [firstTab]
        XCTAssertTrue(harness.coordinator.activateTab(firstTab.id, in: harness.projectPath))

        let splitResult = harness.coordinator.splitActiveGroup(axis: .horizontal, in: harness.projectPath)
        XCTAssertTrue(splitResult.didMutate)
        XCTAssertNil(splitResult.selectedTabID)

        harness.tabsByProjectPath[harness.projectPath] = [firstTab, secondTab]
        harness.coordinator.assignTabToActiveGroup(secondTab.id, in: harness.projectPath)
        XCTAssertTrue(harness.coordinator.activateTab(secondTab.id, in: harness.projectPath))

        let presentation = try XCTUnwrap(harness.state.editorPresentationByProjectPath[harness.projectPath])
        XCTAssertEqual(presentation.groups.count, 2)
        XCTAssertEqual(presentation.splitAxis, .horizontal)
        XCTAssertEqual(presentation.groups[0].tabIDs, [firstTab.id])
        XCTAssertEqual(presentation.groups[1].tabIDs, [secondTab.id])
        XCTAssertEqual(presentation.activeGroupID, presentation.groups[1].id)
    }

    func testCloseGroupPrefersStillSelectedEditorTab() throws {
        let harness = EditorPresentationCoordinatorHarness()
        let firstTab = harness.makeTab(id: "editor-1", filePath: "/tmp/devhaven/First.swift")
        let secondTab = harness.makeTab(id: "editor-2", filePath: "/tmp/devhaven/Second.swift")
        harness.tabsByProjectPath[harness.projectPath] = [firstTab, secondTab]
        harness.state.editorPresentationByProjectPath[harness.projectPath] = WorkspaceEditorPresentationState(
            groups: [
                WorkspaceEditorGroupState(id: "group-1", tabIDs: [firstTab.id], selectedTabID: firstTab.id),
                WorkspaceEditorGroupState(id: "group-2", tabIDs: [secondTab.id], selectedTabID: secondTab.id),
            ],
            activeGroupID: "group-2",
            splitAxis: .vertical
        )
        harness.state.selectedPresentedTabsByProjectPath[harness.projectPath] = .editor(firstTab.id)

        let result = harness.coordinator.closeGroup("group-2", in: harness.projectPath)

        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(result.selectedTabID, firstTab.id)
        let presentation = try XCTUnwrap(harness.state.editorPresentationByProjectPath[harness.projectPath])
        XCTAssertEqual(presentation.groups.count, 1)
        XCTAssertNil(presentation.splitAxis)
        XCTAssertEqual(Set(presentation.groups[0].tabIDs), Set([firstTab.id, secondTab.id]))
    }

    func testRemoveTabAndPreferredTabAfterClosingUseRemainingActiveGroupState() throws {
        let harness = EditorPresentationCoordinatorHarness()
        let firstTab = harness.makeTab(id: "editor-1", filePath: "/tmp/devhaven/First.swift")
        let secondTab = harness.makeTab(id: "editor-2", filePath: "/tmp/devhaven/Second.swift")
        harness.tabsByProjectPath[harness.projectPath] = [firstTab, secondTab]
        harness.state.editorPresentationByProjectPath[harness.projectPath] = WorkspaceEditorPresentationState(
            groups: [
                WorkspaceEditorGroupState(id: "group-1", tabIDs: [firstTab.id, secondTab.id], selectedTabID: secondTab.id),
            ],
            activeGroupID: "group-1"
        )

        harness.tabsByProjectPath[harness.projectPath] = [firstTab]
        let removed = harness.coordinator.removeTab(
            secondTab.id,
            from: harness.state.editorPresentationByProjectPath[harness.projectPath],
            in: harness.projectPath
        )
        harness.state.editorPresentationByProjectPath[harness.projectPath] = removed

        let preferred = harness.coordinator.preferredTabAfterClosing(
            removedIndex: 1,
            in: harness.projectPath,
            remainingTabs: [firstTab]
        )

        XCTAssertEqual(removed?.groups.first?.tabIDs, [firstTab.id])
        XCTAssertEqual(removed?.groups.first?.selectedTabID, firstTab.id)
        XCTAssertEqual(preferred, firstTab.id)
    }
}

@MainActor
private final class EditorPresentationCoordinatorHarness {
    let projectPath = "/tmp/devhaven-project"
    let state = WorkspacePresentationState()
    var tabsByProjectPath: [String: [WorkspaceEditorTabState]] = [:]
    var selectedProjectTreePaths: [(String?, String)] = []

    lazy var coordinator = WorkspaceEditorPresentationCoordinator(
        presentationState: state,
        editorTabsForProject: { [unowned self] in self.tabsByProjectPath[$0] ?? [] },
        presentationStore: store,
        selectProjectTreeNode: { [unowned self] filePath, projectPath in
            self.selectedProjectTreePaths.append((filePath, projectPath))
        }
    )

    lazy var store = WorkspaceEditorPresentationStore(
        presentationState: state,
        editorTabsForProject: { [unowned self] in self.tabsByProjectPath[$0] ?? [] }
    )

    func makeTab(id: String, filePath: String) -> WorkspaceEditorTabState {
        WorkspaceEditorTabState(
            id: id,
            identity: filePath,
            projectPath: projectPath,
            filePath: filePath,
            title: URL(fileURLWithPath: filePath).lastPathComponent,
            kind: .text,
            text: "",
            isEditable: true
        )
    }
}
