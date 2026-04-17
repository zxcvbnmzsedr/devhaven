import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspacePresentedTabCoordinatorTests: XCTestCase {
    func testCloseSelectedDiffTabRestoresTerminalBrowserOriginContext() throws {
        let harness = PresentedTabCoordinatorHarness()
        let terminalTabID = harness.controller.createTab().id
        harness.controller.selectTab(terminalTabID)
        let paneID = try XCTUnwrap(
            harness.controller.selectedPane?.id ?? harness.controller.selectedTab?.leaves.first?.id
        )
        let browserItemID = try XCTUnwrap(
            harness.controller.createBrowserItem(inPane: paneID, urlString: "https://example.com")?.id
        )
        let diffTab = makeDiffTab(
            id: "diff-1",
            title: "A.swift",
            originContext: WorkspaceDiffOriginContext(
                presentedTabSelection: .terminal(terminalTabID),
                focusedArea: .browserPaneItem(browserItemID)
            )
        )

        harness.state.diffTabsByProjectPath[harness.projectPath] = [diffTab]
        harness.state.selectedPresentedTabsByProjectPath[harness.projectPath] = .diff(diffTab.id)
        harness.state.focusedArea = .diffTab(diffTab.id)

        XCTAssertTrue(harness.coordinator.closeDiffTab(diffTab.id, in: harness.projectPath))
        XCTAssertEqual(harness.state.selectedPresentedTabsByProjectPath[harness.projectPath], .terminal(terminalTabID))
        XCTAssertEqual(harness.state.focusedArea, .browserPaneItem(browserItemID))
        XCTAssertEqual(harness.removedDiffViewModelIDs, [diffTab.id])
    }

    func testCloseSelectedDiffTabFallsBackToDefaultFocusedEditorWhenOriginAreaIsInvalid() {
        let harness = PresentedTabCoordinatorHarness()
        let editorTab = makeEditorTab(
            id: "editor-1",
            projectPath: harness.projectPath,
            filePath: "/tmp/devhaven/README.md"
        )
        let diffTab = makeDiffTab(
            id: "diff-2",
            title: "README.md",
            originContext: WorkspaceDiffOriginContext(
                presentedTabSelection: .editor(editorTab.id),
                focusedArea: .diffTab("missing-diff")
            )
        )
        harness.editorTabsByProjectPath[harness.projectPath] = [editorTab]
        XCTAssertTrue(harness.coordinator.select(.editor(editorTab.id), in: harness.projectPath))
        XCTAssertEqual(harness.state.selectedPresentedTabsByProjectPath[harness.projectPath], .editor(editorTab.id))
        harness.state.diffTabsByProjectPath[harness.projectPath] = [diffTab]
        harness.state.selectedPresentedTabsByProjectPath[harness.projectPath] = .diff(diffTab.id)
        harness.state.focusedArea = .diffTab(diffTab.id)

        XCTAssertTrue(harness.coordinator.closeDiffTab(diffTab.id, in: harness.projectPath))
        XCTAssertEqual(harness.activatedEditorTabs.count, 2)
        XCTAssertEqual(harness.activatedEditorTabs.last?.0, editorTab.id)
        XCTAssertEqual(harness.activatedEditorTabs.last?.1, harness.projectPath)
        XCTAssertEqual(harness.state.selectedPresentedTabsByProjectPath[harness.projectPath], .editor(editorTab.id))
        XCTAssertEqual(harness.state.focusedArea, .editorTab(editorTab.id))
        XCTAssertEqual(harness.selectedProjectTreePaths.last?.0, editorTab.filePath)
        XCTAssertEqual(harness.selectedProjectTreePaths.last?.1, harness.projectPath)
    }

    func testCloseSelectedDiffTabFallsBackToAdjacentDiffWhenOriginSelectionIsInvalid() {
        let harness = PresentedTabCoordinatorHarness()
        let closingTab = makeDiffTab(
            id: "diff-3",
            title: "First.swift",
            originContext: WorkspaceDiffOriginContext(
                presentedTabSelection: .editor("missing-editor"),
                focusedArea: .editorTab("missing-editor")
            )
        )
        let remainingTab = makeDiffTab(id: "diff-4", title: "Second.swift")
        harness.state.diffTabsByProjectPath[harness.projectPath] = [closingTab, remainingTab]
        harness.state.selectedPresentedTabsByProjectPath[harness.projectPath] = .diff(closingTab.id)
        harness.state.focusedArea = .diffTab(closingTab.id)

        XCTAssertTrue(harness.coordinator.closeDiffTab(closingTab.id, in: harness.projectPath))
        XCTAssertEqual(harness.state.selectedPresentedTabsByProjectPath[harness.projectPath], .diff(remainingTab.id))
        XCTAssertEqual(harness.state.focusedArea, .diffTab(remainingTab.id))
        XCTAssertEqual(harness.removedDiffViewModelIDs, [closingTab.id])
    }

    private func makeEditorTab(id: String, projectPath: String, filePath: String) -> WorkspaceEditorTabState {
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

    private func makeDiffTab(
        id: String,
        title: String,
        originContext: WorkspaceDiffOriginContext? = nil
    ) -> WorkspaceDiffTabState {
        let source = WorkspaceDiffSource.gitLogCommitFile(
            repositoryPath: "/tmp/repo",
            commitHash: "abc123",
            filePath: title
        )
        return WorkspaceDiffTabState(
            id: id,
            identity: source.identity,
            title: title,
            source: source,
            viewerMode: .sideBySide,
            originContext: originContext
        )
    }
}

@MainActor
private final class PresentedTabCoordinatorHarness {
    let projectPath = "/tmp/devhaven-project"
    let state = WorkspacePresentationState()
    let controller: GhosttyWorkspaceController
    var editorTabsByProjectPath: [String: [WorkspaceEditorTabState]] = [:]
    var activatedEditorTabs: [(String, String)] = []
    var selectedProjectTreePaths: [(String?, String)] = []
    var shownSideKinds: [WorkspaceToolWindowKind] = []
    var shownBottomKinds: [WorkspaceToolWindowKind] = []
    var removedDiffViewModelIDs: [String] = []

    lazy var coordinator = WorkspacePresentedTabCoordinator(
        presentationState: state,
        controllerForProject: { [unowned self] path in
            path == self.projectPath ? self.controller : nil
        },
        editorTabsForProject: { [unowned self] in self.editorTabsByProjectPath[$0] ?? [] },
        activateEditorTab: { [unowned self] tabID, projectPath in
            self.activatedEditorTabs.append((tabID, projectPath))
            self.state.selectedPresentedTabsByProjectPath[projectPath] = .editor(tabID)
            self.state.focusedArea = .editorTab(tabID)
        },
        selectProjectTreeNode: { [unowned self] filePath, projectPath in
            self.selectedProjectTreePaths.append((filePath, projectPath))
        },
        showSideToolWindow: { [unowned self] kind in
            self.shownSideKinds.append(kind)
            self.state.sideToolWindowState.activeKind = kind
            self.state.sideToolWindowState.isVisible = true
            self.state.focusedArea = .sideToolWindow(kind)
        },
        showBottomToolWindow: { [unowned self] kind in
            self.shownBottomKinds.append(kind)
            self.state.bottomToolWindowState.activeKind = kind
            self.state.bottomToolWindowState.isVisible = true
            self.state.focusedArea = .bottomToolWindow(kind)
        },
        isBrowserPaneItem: { [unowned self] itemID, lookupProjectPath in
            guard lookupProjectPath == self.projectPath else {
                return false
            }
            return self.controller.tabs
                .flatMap(\.leaves)
                .flatMap(\.items)
                .contains(where: { $0.id == itemID && $0.isBrowser })
        },
        removeDiffViewModel: { [unowned self] in self.removedDiffViewModelIDs.append($0) }
    )

    init() {
        self.controller = GhosttyWorkspaceController(projectPath: projectPath)
        if self.controller.selectedTabId == nil {
            _ = self.controller.createTab()
        }
    }
}
