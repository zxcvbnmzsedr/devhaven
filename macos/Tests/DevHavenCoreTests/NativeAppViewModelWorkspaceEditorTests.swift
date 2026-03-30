import XCTest
@testable import DevHavenCore

final class NativeAppViewModelWorkspaceEditorTests: XCTestCase {
    private var rootURL: URL!
    private var homeURL: URL!
    private var projectURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devhaven-workspace-editor-\(UUID().uuidString)", isDirectory: true)
        homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
        projectURL = rootURL.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        projectURL = nil
        homeURL = nil
        rootURL = nil
        try super.tearDownWithError()
    }

    @MainActor
    func testClosingDirtyEditorCreatesConfirmationRequest() throws {
        let fileURL = projectURL.appendingPathComponent("README.md")
        try "first".write(to: fileURL, atomically: true, encoding: .utf8)

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: homeURL))
        viewModel.snapshot = NativeAppSnapshot(projects: [makeProject()])
        viewModel.enterWorkspace(projectURL.path)
        viewModel.openWorkspaceEditorTab(for: fileURL.path, in: projectURL.path)

        let tab = try XCTUnwrap(viewModel.activeWorkspaceEditorTabs.first)
        viewModel.updateWorkspaceEditorText("changed", tabID: tab.id, in: projectURL.path)
        viewModel.closeWorkspaceEditorTab(tab.id, in: projectURL.path)

        XCTAssertEqual(viewModel.activeWorkspaceEditorTabs.map(\.id), [tab.id])
        let request = try XCTUnwrap(viewModel.workspacePendingEditorCloseRequest)
        XCTAssertEqual(request.projectPath, projectURL.path)
        XCTAssertEqual(request.tabID, tab.id)

        viewModel.confirmWorkspaceEditorCloseRequest()

        XCTAssertTrue(viewModel.activeWorkspaceEditorTabs.isEmpty)
        XCTAssertNil(viewModel.workspacePendingEditorCloseRequest)
    }

    @MainActor
    func testCloseOtherEditorTabsPromptsForDirtyTabsSequentially() throws {
        let firstFileURL = projectURL.appendingPathComponent("First.swift")
        let secondFileURL = projectURL.appendingPathComponent("Second.swift")
        let thirdFileURL = projectURL.appendingPathComponent("Third.swift")
        try "struct First {}".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try "struct Second {}".write(to: secondFileURL, atomically: true, encoding: .utf8)
        try "struct Third {}".write(to: thirdFileURL, atomically: true, encoding: .utf8)

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: homeURL))
        viewModel.snapshot = NativeAppSnapshot(projects: [makeProject()])
        viewModel.enterWorkspace(projectURL.path)
        viewModel.openWorkspaceEditorTab(for: firstFileURL.path, in: projectURL.path, openingPolicy: .regular)
        viewModel.openWorkspaceEditorTab(for: secondFileURL.path, in: projectURL.path, openingPolicy: .regular)
        viewModel.openWorkspaceEditorTab(for: thirdFileURL.path, in: projectURL.path, openingPolicy: .regular)

        let secondTab = try XCTUnwrap(
            viewModel.activeWorkspaceEditorTabs.first(where: { canonicalPath($0.filePath) == canonicalPath(secondFileURL.path) })
        )
        let thirdTab = try XCTUnwrap(
            viewModel.activeWorkspaceEditorTabs.first(where: { canonicalPath($0.filePath) == canonicalPath(thirdFileURL.path) })
        )
        viewModel.updateWorkspaceEditorText("struct Second { let dirty = true }", tabID: secondTab.id, in: projectURL.path)

        viewModel.closeOtherWorkspaceEditorTabs(keeping: thirdTab.id, in: projectURL.path)

        XCTAssertEqual(
            Set(viewModel.activeWorkspaceEditorTabs.map { canonicalPath($0.filePath) }),
            Set([canonicalPath(secondFileURL.path), canonicalPath(thirdFileURL.path)])
        )
        XCTAssertEqual(viewModel.workspacePendingEditorCloseRequest?.tabID, secondTab.id)

        viewModel.confirmWorkspaceEditorCloseRequest()

        XCTAssertEqual(viewModel.activeWorkspaceEditorTabs.map(\.id), [thirdTab.id])
        XCTAssertNil(viewModel.workspacePendingEditorCloseRequest)
    }

    @MainActor
    func testPreviewTabIsReusedAndRegularOpenPromotesPreview() throws {
        let firstFileURL = projectURL.appendingPathComponent("First.swift")
        let secondFileURL = projectURL.appendingPathComponent("Second.swift")
        try "struct First {}".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try "struct Second {}".write(to: secondFileURL, atomically: true, encoding: .utf8)

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: homeURL))
        viewModel.snapshot = NativeAppSnapshot(projects: [makeProject()])
        viewModel.enterWorkspace(projectURL.path)

        viewModel.openWorkspaceEditorTab(for: firstFileURL.path, in: projectURL.path, openingPolicy: .preview)
        let initialPreviewTab = try XCTUnwrap(viewModel.activeWorkspaceEditorTabs.first)
        XCTAssertTrue(initialPreviewTab.isPreview)
        XCTAssertFalse(initialPreviewTab.isPinned)

        viewModel.openWorkspaceEditorTab(for: secondFileURL.path, in: projectURL.path, openingPolicy: .preview)

        let reusedPreviewTab = try XCTUnwrap(viewModel.activeWorkspaceEditorTabs.first)
        XCTAssertEqual(viewModel.activeWorkspaceEditorTabs.count, 1)
        XCTAssertEqual(reusedPreviewTab.id, initialPreviewTab.id)
        XCTAssertEqual(canonicalPath(reusedPreviewTab.filePath), canonicalPath(secondFileURL.path))
        XCTAssertTrue(reusedPreviewTab.isPreview)
        XCTAssertEqual(viewModel.activeWorkspaceSelectedEditorTabID, reusedPreviewTab.id)

        viewModel.openWorkspaceEditorTab(for: secondFileURL.path, in: projectURL.path, openingPolicy: .regular)

        let promotedTab = try XCTUnwrap(viewModel.activeWorkspaceEditorTabs.first)
        XCTAssertEqual(promotedTab.id, initialPreviewTab.id)
        XCTAssertFalse(promotedTab.isPreview)
        XCTAssertFalse(promotedTab.isPinned)
    }

    @MainActor
    func testPinnedTabIsNotReusedByPreviewAndPinnedOpeningPromotesExistingPreview() throws {
        let firstFileURL = projectURL.appendingPathComponent("First.swift")
        let secondFileURL = projectURL.appendingPathComponent("Second.swift")
        let thirdFileURL = projectURL.appendingPathComponent("Third.swift")
        try "struct First {}".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try "struct Second {}".write(to: secondFileURL, atomically: true, encoding: .utf8)
        try "struct Third {}".write(to: thirdFileURL, atomically: true, encoding: .utf8)

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: homeURL))
        viewModel.snapshot = NativeAppSnapshot(projects: [makeProject()])
        viewModel.enterWorkspace(projectURL.path)

        viewModel.openWorkspaceEditorTab(for: firstFileURL.path, in: projectURL.path, openingPolicy: .preview)
        let previewTabID = try XCTUnwrap(viewModel.activeWorkspaceEditorTabs.first?.id)

        viewModel.openWorkspaceEditorTab(for: firstFileURL.path, in: projectURL.path, openingPolicy: .pinned)

        let pinnedTab = try XCTUnwrap(viewModel.activeWorkspaceEditorTabs.first)
        XCTAssertEqual(pinnedTab.id, previewTabID)
        XCTAssertTrue(pinnedTab.isPinned)
        XCTAssertFalse(pinnedTab.isPreview)

        viewModel.openWorkspaceEditorTab(for: secondFileURL.path, in: projectURL.path, openingPolicy: .preview)
        let secondPreviewTab = try XCTUnwrap(viewModel.activeWorkspaceEditorTabs.first(where: { $0.isPreview }))

        viewModel.openWorkspaceEditorTab(for: thirdFileURL.path, in: projectURL.path, openingPolicy: .preview)

        XCTAssertEqual(viewModel.activeWorkspaceEditorTabs.count, 2)
        let currentPinnedTab = try XCTUnwrap(viewModel.activeWorkspaceEditorTabs.first(where: { $0.isPinned }))
        let reusedPreviewTab = try XCTUnwrap(viewModel.activeWorkspaceEditorTabs.first(where: { $0.isPreview }))
        XCTAssertEqual(currentPinnedTab.id, pinnedTab.id)
        XCTAssertEqual(canonicalPath(currentPinnedTab.filePath), canonicalPath(firstFileURL.path))
        XCTAssertEqual(reusedPreviewTab.id, secondPreviewTab.id)
        XCTAssertEqual(canonicalPath(reusedPreviewTab.filePath), canonicalPath(thirdFileURL.path))
    }

    @MainActor
    func testPromotePreviewToRegularAndTogglePinnedStateFromTabActions() throws {
        let regularFileURL = projectURL.appendingPathComponent("Regular.swift")
        let previewFileURL = projectURL.appendingPathComponent("Preview.swift")
        try "struct Regular {}".write(to: regularFileURL, atomically: true, encoding: .utf8)
        try "struct Preview {}".write(to: previewFileURL, atomically: true, encoding: .utf8)

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: homeURL))
        viewModel.snapshot = NativeAppSnapshot(projects: [makeProject()])
        viewModel.enterWorkspace(projectURL.path)

        viewModel.openWorkspaceEditorTab(for: regularFileURL.path, in: projectURL.path, openingPolicy: .regular)
        viewModel.openWorkspaceEditorTab(for: previewFileURL.path, in: projectURL.path, openingPolicy: .preview)

        let previewTab = try XCTUnwrap(
            viewModel.activeWorkspaceEditorTabs.first(where: {
                canonicalPath($0.filePath) == canonicalPath(previewFileURL.path)
            })
        )
        XCTAssertTrue(previewTab.isPreview)
        XCTAssertFalse(previewTab.isPinned)

        viewModel.promoteWorkspaceEditorTabToRegular(previewTab.id, in: projectURL.path)

        let regularizedPreviewTab = try XCTUnwrap(
            viewModel.activeWorkspaceEditorTabs.first(where: { $0.id == previewTab.id })
        )
        XCTAssertFalse(regularizedPreviewTab.isPreview)
        XCTAssertFalse(regularizedPreviewTab.isPinned)

        viewModel.setWorkspaceEditorTabPinned(true, tabID: previewTab.id, in: projectURL.path)

        let pinnedTab = try XCTUnwrap(viewModel.activeWorkspaceEditorTabs.first(where: { $0.id == previewTab.id }))
        XCTAssertTrue(pinnedTab.isPinned)
        XCTAssertFalse(pinnedTab.isPreview)

        viewModel.setWorkspaceEditorTabPinned(false, tabID: previewTab.id, in: projectURL.path)

        let unpinnedTab = try XCTUnwrap(viewModel.activeWorkspaceEditorTabs.first(where: { $0.id == previewTab.id }))
        XCTAssertFalse(unpinnedTab.isPinned)
        XCTAssertFalse(unpinnedTab.isPreview)
    }

    @MainActor
    func testWorkspaceRestoreRecoversRegularAndPinnedEditorTabsButSkipsPreview() throws {
        let regularFileURL = projectURL.appendingPathComponent("Regular.swift")
        let pinnedFileURL = projectURL.appendingPathComponent("Pinned.swift")
        let previewFileURL = projectURL.appendingPathComponent("Preview.swift")
        try "struct Regular {}".write(to: regularFileURL, atomically: true, encoding: .utf8)
        try "struct Pinned {}".write(to: pinnedFileURL, atomically: true, encoding: .utf8)
        try "struct Preview {}".write(to: previewFileURL, atomically: true, encoding: .utf8)

        let store = LegacyCompatStore(homeDirectoryURL: homeURL)
        let project = makeProject()
        try store.updateProjects([project])

        let viewModel = NativeAppViewModel(store: store)
        viewModel.snapshot = NativeAppSnapshot(projects: [project])
        viewModel.enterWorkspace(projectURL.path)
        viewModel.openWorkspaceEditorTab(for: regularFileURL.path, in: projectURL.path, openingPolicy: .regular)
        viewModel.openWorkspaceEditorTab(for: pinnedFileURL.path, in: projectURL.path, openingPolicy: .pinned)
        viewModel.openWorkspaceEditorTab(for: previewFileURL.path, in: projectURL.path, openingPolicy: .preview)

        let pinnedTabID = try XCTUnwrap(
            viewModel.activeWorkspaceEditorTabs.first(where: {
                canonicalPath($0.filePath) == canonicalPath(pinnedFileURL.path)
            })?.id
        )
        viewModel.openWorkspaceEditorTab(for: pinnedFileURL.path, in: projectURL.path, openingPolicy: .pinned)
        viewModel.flushWorkspaceRestoreSnapshotNow()

        let restoredViewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: homeURL))
        restoredViewModel.load()

        XCTAssertEqual(restoredViewModel.activeWorkspaceProjectPath, projectURL.path)
        let restoredTabs = restoredViewModel.activeWorkspaceEditorTabs
        XCTAssertEqual(restoredTabs.count, 2)
        XCTAssertEqual(
            Set(restoredTabs.map { canonicalPath($0.filePath) }),
            Set([canonicalPath(regularFileURL.path), canonicalPath(pinnedFileURL.path)])
        )
        XCTAssertFalse(restoredTabs.contains(where: { canonicalPath($0.filePath) == canonicalPath(previewFileURL.path) }))
        XCTAssertTrue(restoredTabs.contains(where: {
            canonicalPath($0.filePath) == canonicalPath(pinnedFileURL.path) && $0.isPinned
        }))
        XCTAssertEqual(restoredViewModel.activeWorkspaceSelectedEditorTabID, pinnedTabID)
    }

    @MainActor
    func testSplittingWorkspaceEditorCreatesSecondaryGroupAndAssignsNewTabIntoActiveGroup() throws {
        let firstFileURL = projectURL.appendingPathComponent("First.swift")
        let secondFileURL = projectURL.appendingPathComponent("Second.swift")
        try "struct First {}".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try "struct Second {}".write(to: secondFileURL, atomically: true, encoding: .utf8)

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: homeURL))
        viewModel.snapshot = NativeAppSnapshot(projects: [makeProject()])
        viewModel.enterWorkspace(projectURL.path)

        viewModel.openWorkspaceEditorTab(for: firstFileURL.path, in: projectURL.path, openingPolicy: .regular)
        let firstTabID = try XCTUnwrap(viewModel.activeWorkspaceEditorTabs.first?.id)

        viewModel.splitWorkspaceEditorActiveGroup(axis: .horizontal, in: projectURL.path)

        var presentation = try XCTUnwrap(viewModel.workspaceEditorPresentationState(for: projectURL.path))
        XCTAssertEqual(presentation.groups.count, 2)
        XCTAssertEqual(presentation.splitAxis, .horizontal)
        XCTAssertEqual(presentation.groups.first?.tabIDs, [firstTabID])
        XCTAssertTrue(presentation.groups.last?.tabIDs.isEmpty == true)
        let secondGroupID = try XCTUnwrap(presentation.groups.last?.id)
        XCTAssertEqual(presentation.activeGroupID, secondGroupID)

        viewModel.openWorkspaceEditorTab(for: secondFileURL.path, in: projectURL.path, openingPolicy: .regular)

        let secondTabID = try XCTUnwrap(
            viewModel.activeWorkspaceEditorTabs.first(where: {
                canonicalPath($0.filePath) == canonicalPath(secondFileURL.path)
            })?.id
        )
        presentation = try XCTUnwrap(viewModel.workspaceEditorPresentationState(for: projectURL.path))
        XCTAssertEqual(Set(presentation.groups.flatMap(\.tabIDs)), Set([firstTabID, secondTabID]))
        XCTAssertTrue(presentation.groups[0].tabIDs.contains(firstTabID))
        XCTAssertTrue(presentation.groups[1].tabIDs.contains(secondTabID))
        XCTAssertEqual(presentation.groups[1].selectedTabID, secondTabID)
        XCTAssertEqual(presentation.activeGroupID, secondGroupID)
        XCTAssertEqual(viewModel.activeWorkspaceSelectedEditorTabID, secondTabID)
    }

    @MainActor
    func testWorkspaceRestoreRecoversEditorSplitPresentation() throws {
        let firstFileURL = projectURL.appendingPathComponent("First.swift")
        let secondFileURL = projectURL.appendingPathComponent("Second.swift")
        try "struct First {}".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try "struct Second {}".write(to: secondFileURL, atomically: true, encoding: .utf8)

        let store = LegacyCompatStore(homeDirectoryURL: homeURL)
        let project = makeProject()
        try store.updateProjects([project])

        let viewModel = NativeAppViewModel(store: store)
        viewModel.snapshot = NativeAppSnapshot(projects: [project])
        viewModel.enterWorkspace(projectURL.path)
        viewModel.openWorkspaceEditorTab(for: firstFileURL.path, in: projectURL.path, openingPolicy: .regular)
        let firstTabID = try XCTUnwrap(
            viewModel.activeWorkspaceEditorTabs.first(where: {
                canonicalPath($0.filePath) == canonicalPath(firstFileURL.path)
            })?.id
        )

        viewModel.splitWorkspaceEditorActiveGroup(axis: .vertical, in: projectURL.path)
        let splitGroupID = try XCTUnwrap(viewModel.workspaceEditorPresentationState(for: projectURL.path)?.groups.last?.id)

        viewModel.openWorkspaceEditorTab(for: secondFileURL.path, in: projectURL.path, openingPolicy: .regular)
        let secondTabID = try XCTUnwrap(
            viewModel.activeWorkspaceEditorTabs.first(where: {
                canonicalPath($0.filePath) == canonicalPath(secondFileURL.path)
            })?.id
        )

        viewModel.flushWorkspaceRestoreSnapshotNow()

        let restoredViewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: homeURL))
        restoredViewModel.load()

        let restoredPresentation = try XCTUnwrap(restoredViewModel.workspaceEditorPresentationState(for: projectURL.path))
        XCTAssertEqual(restoredPresentation.groups.count, 2)
        XCTAssertEqual(restoredPresentation.splitAxis, .vertical)
        XCTAssertEqual(restoredPresentation.activeGroupID, splitGroupID)
        XCTAssertEqual(restoredViewModel.activeWorkspaceSelectedEditorTabID, secondTabID)

        let restoredFirstGroupPaths = restoredPresentation.groups[0].tabIDs.compactMap {
            restoredViewModel.workspaceEditorTabState(for: projectURL.path, tabID: $0)?.filePath
        }
        let restoredSecondGroupPaths = restoredPresentation.groups[1].tabIDs.compactMap {
            restoredViewModel.workspaceEditorTabState(for: projectURL.path, tabID: $0)?.filePath
        }
        XCTAssertEqual(Set(restoredFirstGroupPaths.map(canonicalPath)), Set([canonicalPath(firstFileURL.path)]))
        XCTAssertEqual(Set(restoredSecondGroupPaths.map(canonicalPath)), Set([canonicalPath(secondFileURL.path)]))
        XCTAssertTrue(restoredPresentation.groups[0].tabIDs.contains(firstTabID))
        XCTAssertTrue(restoredPresentation.groups[1].tabIDs.contains(secondTabID))
    }

    @MainActor
    func testSelectingWorkspaceEditorGroupActivatesThatGroupsSelectedTab() throws {
        let firstFileURL = projectURL.appendingPathComponent("First.swift")
        let secondFileURL = projectURL.appendingPathComponent("Second.swift")
        try "struct First {}".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try "struct Second {}".write(to: secondFileURL, atomically: true, encoding: .utf8)

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: homeURL))
        viewModel.snapshot = NativeAppSnapshot(projects: [makeProject()])
        viewModel.enterWorkspace(projectURL.path)

        viewModel.openWorkspaceEditorTab(for: firstFileURL.path, in: projectURL.path, openingPolicy: .regular)
        let firstTabID = try XCTUnwrap(
            viewModel.activeWorkspaceEditorTabs.first(where: {
                canonicalPath($0.filePath) == canonicalPath(firstFileURL.path)
            })?.id
        )

        viewModel.splitWorkspaceEditorActiveGroup(axis: .horizontal, in: projectURL.path)
        let initialPresentation = try XCTUnwrap(viewModel.workspaceEditorPresentationState(for: projectURL.path))
        let firstGroupID = try XCTUnwrap(initialPresentation.groups.first?.id)
        let secondGroupID = try XCTUnwrap(initialPresentation.groups.last?.id)

        viewModel.openWorkspaceEditorTab(for: secondFileURL.path, in: projectURL.path, openingPolicy: .regular)
        let secondTabID = try XCTUnwrap(
            viewModel.activeWorkspaceEditorTabs.first(where: {
                canonicalPath($0.filePath) == canonicalPath(secondFileURL.path)
            })?.id
        )

        viewModel.selectWorkspaceEditorGroup(firstGroupID, in: projectURL.path)
        XCTAssertEqual(viewModel.activeWorkspaceSelectedEditorTabID, firstTabID)
        XCTAssertEqual(viewModel.workspaceFocusedArea, .editorTab(firstTabID))

        viewModel.selectWorkspaceEditorGroup(secondGroupID, in: projectURL.path)
        XCTAssertEqual(viewModel.activeWorkspaceSelectedEditorTabID, secondTabID)
        XCTAssertEqual(viewModel.workspaceFocusedArea, .editorTab(secondTabID))
    }

    @MainActor
    func testMoveWorkspaceEditorTabToOtherGroupReassignsOwnership() throws {
        let firstFileURL = projectURL.appendingPathComponent("First.swift")
        let secondFileURL = projectURL.appendingPathComponent("Second.swift")
        try "struct First {}".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try "struct Second {}".write(to: secondFileURL, atomically: true, encoding: .utf8)

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: homeURL))
        viewModel.snapshot = NativeAppSnapshot(projects: [makeProject()])
        viewModel.enterWorkspace(projectURL.path)
        viewModel.openWorkspaceEditorTab(for: firstFileURL.path, in: projectURL.path, openingPolicy: .regular)
        let firstTabID = try XCTUnwrap(viewModel.activeWorkspaceEditorTabs.first?.id)

        viewModel.splitWorkspaceEditorActiveGroup(axis: .horizontal, in: projectURL.path)
        let secondGroupID = try XCTUnwrap(viewModel.workspaceEditorPresentationState(for: projectURL.path)?.groups.last?.id)
        viewModel.openWorkspaceEditorTab(for: secondFileURL.path, in: projectURL.path, openingPolicy: .regular)

        viewModel.moveWorkspaceEditorTab(firstTabID, toGroup: secondGroupID, in: projectURL.path)

        let presentation = try XCTUnwrap(viewModel.workspaceEditorPresentationState(for: projectURL.path))
        XCTAssertFalse(presentation.groups[0].tabIDs.contains(firstTabID))
        XCTAssertTrue(presentation.groups[1].tabIDs.contains(firstTabID))
        XCTAssertEqual(presentation.activeGroupID, secondGroupID)
    }

    @MainActor
    func testCloseWorkspaceEditorGroupMergesTabsBackIntoRemainingGroup() throws {
        let firstFileURL = projectURL.appendingPathComponent("First.swift")
        let secondFileURL = projectURL.appendingPathComponent("Second.swift")
        try "struct First {}".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try "struct Second {}".write(to: secondFileURL, atomically: true, encoding: .utf8)

        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: homeURL))
        viewModel.snapshot = NativeAppSnapshot(projects: [makeProject()])
        viewModel.enterWorkspace(projectURL.path)
        viewModel.openWorkspaceEditorTab(for: firstFileURL.path, in: projectURL.path, openingPolicy: .regular)
        let firstTabID = try XCTUnwrap(viewModel.activeWorkspaceEditorTabs.first?.id)

        viewModel.splitWorkspaceEditorActiveGroup(axis: .vertical, in: projectURL.path)
        let secondGroupID = try XCTUnwrap(viewModel.workspaceEditorPresentationState(for: projectURL.path)?.groups.last?.id)
        viewModel.openWorkspaceEditorTab(for: secondFileURL.path, in: projectURL.path, openingPolicy: .regular)
        let secondTabID = try XCTUnwrap(
            viewModel.activeWorkspaceEditorTabs.first(where: {
                canonicalPath($0.filePath) == canonicalPath(secondFileURL.path)
            })?.id
        )

        viewModel.closeWorkspaceEditorGroup(secondGroupID, in: projectURL.path)

        let presentation = try XCTUnwrap(viewModel.workspaceEditorPresentationState(for: projectURL.path))
        XCTAssertEqual(presentation.groups.count, 1)
        XCTAssertNil(presentation.splitAxis)
        XCTAssertEqual(Set(presentation.groups[0].tabIDs), Set([firstTabID, secondTabID]))
        XCTAssertTrue(presentation.activeGroupID == presentation.groups[0].id)
    }

    @MainActor
    func testUpdateWorkspaceEditorDisplayOptionsPersistsIntoSettingsSnapshot() {
        let viewModel = NativeAppViewModel(store: LegacyCompatStore(homeDirectoryURL: homeURL))
        let nextOptions = WorkspaceEditorDisplayOptions(
            showsLineNumbers: false,
            highlightsCurrentLine: false,
            usesSoftWraps: true,
            showsWhitespaceCharacters: true,
            showsRightMargin: true,
            rightMarginColumn: 96
        )

        viewModel.updateWorkspaceEditorDisplayOptions(nextOptions)

        XCTAssertEqual(viewModel.workspaceEditorDisplayOptions, nextOptions)
        XCTAssertEqual(viewModel.snapshot.appState.settings.workspaceEditorDisplayOptions, nextOptions)
    }

    private func makeProject() -> Project {
        let now = Date().timeIntervalSinceReferenceDate
        return Project(
            id: UUID().uuidString,
            name: projectURL.lastPathComponent,
            path: projectURL.path,
            tags: [],
            runConfigurations: [],
            worktrees: [],
            mtime: now,
            size: 0,
            checksum: UUID().uuidString,
            isGitRepository: false,
            gitCommits: 0,
            gitLastCommit: now,
            created: now,
            checked: now
        )
    }
}

private func canonicalPath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
}
