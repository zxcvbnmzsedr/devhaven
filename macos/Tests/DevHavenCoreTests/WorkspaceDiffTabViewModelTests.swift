import XCTest
import Observation
@testable import DevHavenCore

@MainActor
final class WorkspaceDiffTabViewModelTests: XCTestCase {
    private final class ObservationCounter: @unchecked Sendable {
        var count = 0
    }

    func testRefreshLoadsGitLogCommitFileDiff() async throws {
        let recorder = WorkspaceDiffTabClientRecorder()
        recorder.gitLogDiff = """
        diff --git a/README.md b/README.md
        --- a/README.md
        +++ b/README.md
        @@ -1 +1 @@
        -before
        +after
        """
        let viewModel = makeViewModel(
            tab: WorkspaceDiffTabState(
                id: "diff-1",
                identity: "git-log|/tmp/root|abc1234|README.md",
                title: "Commit: README.md",
                source: .gitLogCommitFile(repositoryPath: "/tmp/root", commitHash: "abc1234", filePath: "README.md"),
                viewerMode: .sideBySide
            ),
            recorder: recorder
        )

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(recorder.gitLogRequests.count, 1)
        XCTAssertEqual(recorder.gitLogRequests.first?.repositoryPath, "/tmp/root")
        XCTAssertEqual(recorder.gitLogRequests.first?.commitHash, "abc1234")
        XCTAssertEqual(recorder.gitLogRequests.first?.filePath, "README.md")
        XCTAssertEqual(viewModel.documentState.viewerMode, .sideBySide)
        XCTAssertEqual(viewModel.documentState.loadedDocument?.kind, .text)
    }

    func testRefreshLoadsWorkingTreeDiffForCommitBrowserSource() async throws {
        let recorder = WorkspaceDiffTabClientRecorder()
        recorder.workingTreeDocument = .compare(
            WorkspaceDiffCompareDocument(
                mode: .unstaged,
                leftPane: WorkspaceDiffEditorPane(
                    title: "Staged",
                    path: "Package.swift",
                    text: "import PackageDescription\n",
                    isEditable: false
                ),
                rightPane: WorkspaceDiffEditorPane(
                    title: "Local",
                    path: "Package.swift",
                    text: "import PackageDescription\n// demo\n",
                    isEditable: true
                )
            )
        )
        let viewModel = makeViewModel(
            tab: WorkspaceDiffTabState(
                id: "diff-2",
                identity: "working-tree|/tmp/root|Package.swift",
                title: "Changes: Package.swift",
                source: .workingTreeChange(
                    repositoryPath: "/tmp/root",
                    executionPath: "/tmp/root",
                    filePath: "Package.swift",
                    group: .unstaged,
                    status: .modified,
                    oldPath: nil
                ),
                viewerMode: .sideBySide
            ),
            recorder: recorder
        )

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(recorder.workingTreeRequests.count, 1)
        XCTAssertEqual(recorder.workingTreeRequests.first?.executionPath, "/tmp/root")
        XCTAssertEqual(recorder.workingTreeRequests.first?.filePath, "Package.swift")
        XCTAssertEqual(viewModel.documentState.loadedCompareDocument?.rightPane.path, "Package.swift")
        XCTAssertTrue(viewModel.documentState.loadedCompareDocument?.rightPane.isEditable == true)
    }

    func testRefreshBuildsCompareBlocksAndHighlightsForUnstagedDocument() async throws {
        let recorder = WorkspaceDiffTabClientRecorder()
        recorder.workingTreeDocument = .compare(
            WorkspaceDiffCompareDocument(
                mode: .unstaged,
                leftPane: WorkspaceDiffEditorPane(title: "Staged", path: "README.md", text: "hello\nbefore\nkeep\n", isEditable: false),
                rightPane: WorkspaceDiffEditorPane(title: "Local", path: "README.md", text: "hello\nafter\nkeep\n", isEditable: true)
            )
        )
        let viewModel = makeViewModel(
            tab: WorkspaceDiffTabState(
                id: "compare-blocks-1",
                identity: "commit-preview|/tmp/root",
                title: "Changes: README.md",
                source: .workingTreeChange(
                    repositoryPath: "/tmp/root",
                    executionPath: "/tmp/root",
                    filePath: "README.md",
                    group: .unstaged,
                    status: .modified,
                    oldPath: nil
                ),
                viewerMode: .sideBySide
            ),
            recorder: recorder
        )

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(viewModel.documentState.loadedCompareDocument?.blocks.count, 1)
        XCTAssertEqual(viewModel.documentState.loadedCompareDocument?.leftPane.highlights.count, 1)
        XCTAssertEqual(viewModel.documentState.loadedCompareDocument?.rightPane.highlights.count, 1)
    }

    func testRefreshBuildsInlineHighlightsForSingleLineReplacement() async throws {
        let recorder = WorkspaceDiffTabClientRecorder()
        recorder.workingTreeDocument = .compare(
            WorkspaceDiffCompareDocument(
                mode: .unstaged,
                leftPane: WorkspaceDiffEditorPane(title: "Staged", path: "README.md", text: "prefix-before-suffix\n", isEditable: false),
                rightPane: WorkspaceDiffEditorPane(title: "Local", path: "README.md", text: "prefix-after-suffix\n", isEditable: true)
            )
        )
        let viewModel = makeViewModel(
            tab: WorkspaceDiffTabState(
                id: "compare-inline-1",
                identity: "commit-preview|/tmp/root",
                title: "Changes: README.md",
                source: .workingTreeChange(
                    repositoryPath: "/tmp/root",
                    executionPath: "/tmp/root",
                    filePath: "README.md",
                    group: .unstaged,
                    status: .modified,
                    oldPath: nil
                ),
                viewerMode: .sideBySide
            ),
            recorder: recorder
        )

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(viewModel.documentState.loadedCompareDocument?.leftPane.inlineHighlights.count, 1)
        XCTAssertEqual(viewModel.documentState.loadedCompareDocument?.rightPane.inlineHighlights.count, 1)
    }

    func testCompareSessionSelectsFirstDifferenceOnLoad() async throws {
        let recorder = WorkspaceDiffTabClientRecorder()
        recorder.workingTreeDocumentByFilePath["README.md"] = .compare(
            WorkspaceDiffCompareDocument(
                mode: .unstaged,
                leftPane: WorkspaceDiffEditorPane(
                    title: "Staged",
                    path: "README.md",
                    text: "same\nbefore\nsame\nafter\n",
                    isEditable: false
                ),
                rightPane: WorkspaceDiffEditorPane(
                    title: "Local",
                    path: "README.md",
                    text: "same\nBEFORE\nsame\nAFTER\n",
                    isEditable: true
                )
            )
        )
        let viewModel = makeViewModel(
            tab: WorkspaceDiffTabState(
                id: "session-compare-1",
                identity: "commit-preview|/tmp/root",
                title: "Changes: README.md",
                source: .workingTreeChange(
                    repositoryPath: "/tmp/root",
                    executionPath: "/tmp/root",
                    filePath: "README.md",
                    group: .unstaged,
                    status: .modified,
                    oldPath: nil
                ),
                viewerMode: .sideBySide
            ),
            recorder: recorder
        )

        viewModel.openSession(
            WorkspaceDiffRequestChain(
                items: [
                    makeRequestItem(id: "readme", filePath: "README.md")
                ]
            )
        )
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(viewModel.selectedDifferenceAnchor, .compareBlock("compare-block-0"))
        XCTAssertEqual(viewModel.sessionState.requestChain.activeIndex, 0)
        XCTAssertEqual(viewModel.sessionState.navigatorState.currentDifferenceIndex, 1)
        XCTAssertEqual(viewModel.sessionState.navigatorState.totalDifferences, 2)
    }

    func testUpdateViewerModeDoesNotDropLoadedDocument() async throws {
        let recorder = WorkspaceDiffTabClientRecorder()
        recorder.gitLogDiff = """
        diff --git a/README.md b/README.md
        --- a/README.md
        +++ b/README.md
        @@ -1 +1 @@
        -before
        +after
        """
        let viewModel = makeViewModel(
            tab: WorkspaceDiffTabState(
                id: "diff-3",
                identity: "git-log|/tmp/root|abc1234|README.md",
                title: "Commit: README.md",
                source: .gitLogCommitFile(repositoryPath: "/tmp/root", commitHash: "abc1234", filePath: "README.md"),
                viewerMode: .sideBySide
            ),
            recorder: recorder
        )

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(80))
        let loadedBefore = viewModel.documentState.loadedPatchDocument

        viewModel.updateViewerMode(.unified)

        XCTAssertEqual(viewModel.documentState.viewerMode, .unified)
        XCTAssertEqual(viewModel.documentState.loadedPatchDocument, loadedBefore)
    }

    func testRefreshSurfacesStableChineseErrorStateWhenLoadFails() async throws {
        let recorder = WorkspaceDiffTabClientRecorder()
        recorder.loadError = WorkspaceDiffTabViewModelTestError.fixture
        let viewModel = makeViewModel(
            tab: WorkspaceDiffTabState(
                id: "diff-4",
                identity: "git-log|/tmp/root|abc1234|README.md",
                title: "Commit: README.md",
                source: .gitLogCommitFile(repositoryPath: "/tmp/root", commitHash: "abc1234", filePath: "README.md"),
                viewerMode: .sideBySide
            ),
            recorder: recorder
        )

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(viewModel.documentState.errorMessage, "diff load failed")
        XCTAssertNil(viewModel.documentState.loadedPatchDocument)
    }

    func testUpdateTabReloadsDiffForNewWorkingTreeSourceInSamePreviewInstance() async throws {
        let recorder = WorkspaceDiffTabClientRecorder()
        recorder.workingTreeDocumentByFilePath["README.md"] = .compare(
            WorkspaceDiffCompareDocument(
                mode: .unstaged,
                leftPane: WorkspaceDiffEditorPane(title: "Staged", path: "README.md", text: "before\n", isEditable: false),
                rightPane: WorkspaceDiffEditorPane(title: "Local", path: "README.md", text: "after\n", isEditable: true)
            )
        )
        recorder.workingTreeDocumentByFilePath["Package.swift"] = .compare(
            WorkspaceDiffCompareDocument(
                mode: .unstaged,
                leftPane: WorkspaceDiffEditorPane(title: "Staged", path: "Package.swift", text: "import PackageDescription\n", isEditable: false),
                rightPane: WorkspaceDiffEditorPane(title: "Local", path: "Package.swift", text: "import PackageDescription\n// preview switched\n", isEditable: true)
            )
        )
        let viewModel = makeViewModel(
            tab: WorkspaceDiffTabState(
                id: "commit-preview-1",
                identity: "commit-preview|/tmp/root",
                title: "Changes: README.md",
                source: .workingTreeChange(
                    repositoryPath: "/tmp/root",
                    executionPath: "/tmp/root",
                    filePath: "README.md",
                    group: .unstaged,
                    status: .modified,
                    oldPath: nil
                ),
                viewerMode: .sideBySide
            ),
            recorder: recorder
        )

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(80))

        viewModel.updateTab(
            WorkspaceDiffTabState(
                id: "commit-preview-1",
                identity: "commit-preview|/tmp/root",
                title: "Changes: Package.swift",
                source: .workingTreeChange(
                    repositoryPath: "/tmp/root",
                    executionPath: "/tmp/root",
                    filePath: "Package.swift",
                    group: .unstaged,
                    status: .modified,
                    oldPath: nil
                ),
                viewerMode: .sideBySide
            )
        )
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(recorder.workingTreeRequests.map(\.filePath), ["README.md", "Package.swift"])
        XCTAssertEqual(viewModel.documentState.title, "Changes: Package.swift")
        XCTAssertEqual(viewModel.documentState.loadedCompareDocument?.rightPane.path, "Package.swift")
    }

    func testUpdateTabWithIdenticalTabDoesNotInvalidateObservedState() async throws {
        let recorder = WorkspaceDiffTabClientRecorder()
        recorder.gitLogDiff = """
        diff --git a/README.md b/README.md
        --- a/README.md
        +++ b/README.md
        @@ -1 +1 @@
        -before
        +after
        """
        let viewModel = makeViewModel(
            tab: WorkspaceDiffTabState(
                id: "diff-identical-1",
                identity: "git-log|/tmp/root|abc1234|README.md",
                title: "Commit: README.md",
                source: .gitLogCommitFile(repositoryPath: "/tmp/root", commitHash: "abc1234", filePath: "README.md"),
                viewerMode: .sideBySide
            ),
            recorder: recorder
        )

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(80))
        let loadedBefore = viewModel.documentState.loadedPatchDocument
        let sameTab = viewModel.tab
        let counter = ObservationCounter()

        withObservationTracking {
            _ = viewModel.tab
            _ = viewModel.documentState.title
            _ = viewModel.documentState.viewerMode
            _ = viewModel.documentState.loadState
        } onChange: {
            counter.count += 1
        }

        viewModel.updateTab(sameTab)

        XCTAssertEqual(counter.count, 0, "相同 tab 不应触发新的观察失效")
        XCTAssertEqual(recorder.gitLogRequests.count, 1, "相同 tab 不应重新触发加载")
        XCTAssertEqual(viewModel.documentState.loadedPatchDocument, loadedBefore, "相同 tab 不应破坏已加载文档")
    }

    func testRefreshLoadsConflictedWorkingTreeAsMergeDocument() async throws {
        let recorder = WorkspaceDiffTabClientRecorder()
        recorder.workingTreeDocument = .merge(
            WorkspaceDiffMergeDocument(
                oursPane: WorkspaceDiffEditorPane(title: "Ours", path: "README.md", text: "main\n", isEditable: false),
                basePane: WorkspaceDiffEditorPane(title: "Base", path: "README.md", text: "hello\n", isEditable: false),
                theirsPane: WorkspaceDiffEditorPane(title: "Theirs", path: "README.md", text: "feature\n", isEditable: false),
                resultPane: WorkspaceDiffEditorPane(title: "Result", path: "README.md", text: "<<<<<<< ours\nmain\n=======\nfeature\n>>>>>>> theirs\n", isEditable: true)
            )
        )
        let viewModel = makeViewModel(
            tab: WorkspaceDiffTabState(
                id: "merge-1",
                identity: "commit-preview|/tmp/root",
                title: "Changes: README.md",
                source: .workingTreeChange(
                    repositoryPath: "/tmp/root",
                    executionPath: "/tmp/root",
                    filePath: "README.md",
                    group: .conflicted,
                    status: .unmerged,
                    oldPath: nil
                ),
                viewerMode: .sideBySide
            ),
            recorder: recorder
        )

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(viewModel.documentState.loadedMergeDocument?.oursPane.title, "Ours")
        XCTAssertTrue(viewModel.documentState.loadedMergeDocument?.resultPane.isEditable == true)
    }

    func testMergeSessionFallsBackToZeroOfZeroWhenNoConflictsRemain() async throws {
        let recorder = WorkspaceDiffTabClientRecorder()
        recorder.workingTreeDocumentByFilePath["README.md"] = .merge(
            WorkspaceDiffMergeDocument(
                oursPane: WorkspaceDiffEditorPane(title: "Ours", path: "README.md", text: "main\n", isEditable: false),
                basePane: WorkspaceDiffEditorPane(title: "Base", path: "README.md", text: "hello\n", isEditable: false),
                theirsPane: WorkspaceDiffEditorPane(title: "Theirs", path: "README.md", text: "feature\n", isEditable: false),
                resultPane: WorkspaceDiffEditorPane(title: "Result", path: "README.md", text: "resolved\n", isEditable: true)
            )
        )
        let viewModel = makeViewModel(
            tab: WorkspaceDiffTabState(
                id: "session-merge-1",
                identity: "commit-preview|/tmp/root",
                title: "Changes: README.md",
                source: .workingTreeChange(
                    repositoryPath: "/tmp/root",
                    executionPath: "/tmp/root",
                    filePath: "README.md",
                    group: .conflicted,
                    status: .modified,
                    oldPath: nil
                ),
                viewerMode: .sideBySide
            ),
            recorder: recorder
        )

        viewModel.openSession(
            WorkspaceDiffRequestChain(
                items: [
                    makeRequestItem(id: "conflict", filePath: "README.md", group: .conflicted)
                ]
            )
        )
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertNil(viewModel.selectedDifferenceAnchor)
        XCTAssertEqual(viewModel.sessionState.navigatorState.currentDifferenceIndex, 0)
        XCTAssertEqual(viewModel.sessionState.navigatorState.totalDifferences, 0)
        XCTAssertFalse(viewModel.sessionState.navigatorState.canGoNext)
        XCTAssertFalse(viewModel.sessionState.navigatorState.canGoPrevious)
    }

    func testRefreshBuildsInlineHighlightsForMergeConflictOursAndTheirs() async throws {
        let recorder = WorkspaceDiffTabClientRecorder()
        recorder.workingTreeDocument = .merge(
            WorkspaceDiffMergeDocument(
                oursPane: WorkspaceDiffEditorPane(title: "Ours", path: "README.md", text: "prefix-ours-suffix\n", isEditable: false),
                basePane: WorkspaceDiffEditorPane(title: "Base", path: "README.md", text: "prefix-base-suffix\n", isEditable: false),
                theirsPane: WorkspaceDiffEditorPane(title: "Theirs", path: "README.md", text: "prefix-theirs-suffix\n", isEditable: false),
                resultPane: WorkspaceDiffEditorPane(
                    title: "Result",
                    path: "README.md",
                    text: """
                    <<<<<<< ours
                    prefix-ours-suffix
                    =======
                    prefix-theirs-suffix
                    >>>>>>> theirs
                    """,
                    isEditable: true
                )
            )
        )
        let viewModel = makeViewModel(
            tab: WorkspaceDiffTabState(
                id: "merge-inline-1",
                identity: "commit-preview|/tmp/root",
                title: "Changes: README.md",
                source: .workingTreeChange(
                    repositoryPath: "/tmp/root",
                    executionPath: "/tmp/root",
                    filePath: "README.md",
                    group: .conflicted,
                    status: .unmerged,
                    oldPath: nil
                ),
                viewerMode: .sideBySide
            ),
            recorder: recorder
        )

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(viewModel.documentState.loadedMergeDocument?.oursPane.inlineHighlights.count, 1)
        XCTAssertEqual(viewModel.documentState.loadedMergeDocument?.theirsPane.inlineHighlights.count, 1)
    }

    func testRefreshBuildsInlineHighlightsForMergeResultPaneConflictBody() async throws {
        let recorder = WorkspaceDiffTabClientRecorder()
        recorder.workingTreeDocument = .merge(
            WorkspaceDiffMergeDocument(
                oursPane: WorkspaceDiffEditorPane(title: "Ours", path: "README.md", text: "prefix-ours-suffix\n", isEditable: false),
                basePane: WorkspaceDiffEditorPane(title: "Base", path: "README.md", text: "prefix-base-suffix\n", isEditable: false),
                theirsPane: WorkspaceDiffEditorPane(title: "Theirs", path: "README.md", text: "prefix-theirs-suffix\n", isEditable: false),
                resultPane: WorkspaceDiffEditorPane(
                    title: "Result",
                    path: "README.md",
                    text: """
                    <<<<<<< ours
                    prefix-ours-suffix
                    =======
                    prefix-theirs-suffix
                    >>>>>>> theirs
                    """,
                    isEditable: true
                )
            )
        )
        let viewModel = makeViewModel(
            tab: WorkspaceDiffTabState(
                id: "merge-inline-result-1",
                identity: "commit-preview|/tmp/root",
                title: "Changes: README.md",
                source: .workingTreeChange(
                    repositoryPath: "/tmp/root",
                    executionPath: "/tmp/root",
                    filePath: "README.md",
                    group: .conflicted,
                    status: .unmerged,
                    oldPath: nil
                ),
                viewerMode: .sideBySide
            ),
            recorder: recorder
        )

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(viewModel.documentState.loadedMergeDocument?.resultPane.inlineHighlights.count, 2)
    }

    func testSaveEditableContentPersistsUpdatedLocalPaneAndRefreshesDocument() async throws {
        let recorder = WorkspaceDiffTabClientRecorder()
        recorder.workingTreeDocument = .compare(
            WorkspaceDiffCompareDocument(
                mode: .unstaged,
                leftPane: WorkspaceDiffEditorPane(title: "Staged", path: "README.md", text: "before\n", isEditable: false),
                rightPane: WorkspaceDiffEditorPane(title: "Local", path: "README.md", text: "after\n", isEditable: true)
            )
        )
        recorder.workingTreeDocumentAfterSave = .compare(
            WorkspaceDiffCompareDocument(
                mode: .unstaged,
                leftPane: WorkspaceDiffEditorPane(title: "Staged", path: "README.md", text: "before\n", isEditable: false),
                rightPane: WorkspaceDiffEditorPane(title: "Local", path: "README.md", text: "edited\n", isEditable: true)
            )
        )
        let viewModel = makeViewModel(
            tab: WorkspaceDiffTabState(
                id: "compare-save-1",
                identity: "commit-preview|/tmp/root",
                title: "Changes: README.md",
                source: .workingTreeChange(
                    repositoryPath: "/tmp/root",
                    executionPath: "/tmp/root",
                    filePath: "README.md",
                    group: .unstaged,
                    status: .modified,
                    oldPath: nil
                ),
                viewerMode: .sideBySide
            ),
            recorder: recorder
        )

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(80))
        viewModel.updateEditableContent("edited\n")
        try viewModel.saveEditableContent()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(recorder.savedWorkingTreeWrites.first?.filePath, "README.md")
        XCTAssertEqual(recorder.savedWorkingTreeWrites.first?.content, "edited\n")
        XCTAssertEqual(viewModel.documentState.loadedCompareDocument?.rightPane.text, "edited\n")
    }

    func testUpdateEditableContentRebuildsCompareBlocksAfterManualEdit() async throws {
        let recorder = WorkspaceDiffTabClientRecorder()
        recorder.workingTreeDocument = .compare(
            WorkspaceDiffCompareDocument(
                mode: .unstaged,
                leftPane: WorkspaceDiffEditorPane(title: "Staged", path: "README.md", text: "hello\nsame\n", isEditable: false),
                rightPane: WorkspaceDiffEditorPane(title: "Local", path: "README.md", text: "hello\nchanged\n", isEditable: true)
            )
        )
        let viewModel = makeViewModel(
            tab: WorkspaceDiffTabState(
                id: "compare-rebuild-1",
                identity: "commit-preview|/tmp/root",
                title: "Changes: README.md",
                source: .workingTreeChange(
                    repositoryPath: "/tmp/root",
                    executionPath: "/tmp/root",
                    filePath: "README.md",
                    group: .unstaged,
                    status: .modified,
                    oldPath: nil
                ),
                viewerMode: .sideBySide
            ),
            recorder: recorder
        )

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(viewModel.documentState.loadedCompareDocument?.blocks.count, 1)

        viewModel.updateEditableContent("hello\nsame\n")

        XCTAssertEqual(viewModel.documentState.loadedCompareDocument?.blocks.count, 0)
        XCTAssertEqual(viewModel.documentState.loadedCompareDocument?.rightPane.highlights.count, 0)
    }

    func testApplyMergeActionCanReplaceEditableResultPane() async throws {
        let recorder = WorkspaceDiffTabClientRecorder()
        recorder.workingTreeDocument = .merge(
            WorkspaceDiffMergeDocument(
                oursPane: WorkspaceDiffEditorPane(title: "Ours", path: "README.md", text: "main\n", isEditable: false),
                basePane: WorkspaceDiffEditorPane(title: "Base", path: "README.md", text: "hello\n", isEditable: false),
                theirsPane: WorkspaceDiffEditorPane(title: "Theirs", path: "README.md", text: "feature\n", isEditable: false),
                resultPane: WorkspaceDiffEditorPane(title: "Result", path: "README.md", text: "", isEditable: true)
            )
        )
        let viewModel = makeViewModel(
            tab: WorkspaceDiffTabState(
                id: "merge-action-1",
                identity: "commit-preview|/tmp/root",
                title: "Changes: README.md",
                source: .workingTreeChange(
                    repositoryPath: "/tmp/root",
                    executionPath: "/tmp/root",
                    filePath: "README.md",
                    group: .conflicted,
                    status: .unmerged,
                    oldPath: nil
                ),
                viewerMode: .sideBySide
            ),
            recorder: recorder
        )

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(80))
        viewModel.applyMergeAction(.acceptBoth)

        XCTAssertEqual(viewModel.documentState.loadedMergeDocument?.resultPane.text, "main\nfeature\n")
    }

    func testApplyMergeActionCanReplaceSingleConflictBlockOnly() async throws {
        let recorder = WorkspaceDiffTabClientRecorder()
        recorder.workingTreeDocument = .merge(
            WorkspaceDiffMergeDocument(
                oursPane: WorkspaceDiffEditorPane(title: "Ours", path: "README.md", text: "alpha\nours-one\nmiddle\nours-two\nomega\n", isEditable: false),
                basePane: WorkspaceDiffEditorPane(title: "Base", path: "README.md", text: "alpha\nbase-one\nmiddle\nbase-two\nomega\n", isEditable: false),
                theirsPane: WorkspaceDiffEditorPane(title: "Theirs", path: "README.md", text: "alpha\ntheirs-one\nmiddle\ntheirs-two\nomega\n", isEditable: false),
                resultPane: WorkspaceDiffEditorPane(
                    title: "Result",
                    path: "README.md",
                    text: """
                    alpha
                    <<<<<<< ours
                    ours-one
                    =======
                    theirs-one
                    >>>>>>> theirs
                    middle
                    <<<<<<< ours
                    ours-two
                    =======
                    theirs-two
                    >>>>>>> theirs
                    omega
                    """,
                    isEditable: true
                )
            )
        )
        let viewModel = makeViewModel(
            tab: WorkspaceDiffTabState(
                id: "merge-block-1",
                identity: "commit-preview|/tmp/root",
                title: "Changes: README.md",
                source: .workingTreeChange(
                    repositoryPath: "/tmp/root",
                    executionPath: "/tmp/root",
                    filePath: "README.md",
                    group: .conflicted,
                    status: .unmerged,
                    oldPath: nil
                ),
                viewerMode: .sideBySide
            ),
            recorder: recorder
        )

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(80))
        let firstBlockID = try XCTUnwrap(viewModel.documentState.loadedMergeDocument?.conflictBlocks.first?.id)

        viewModel.applyMergeAction(.acceptOurs, blockID: firstBlockID)

        XCTAssertEqual(viewModel.documentState.loadedMergeDocument?.conflictBlocks.count, 1)
        XCTAssertEqual(
            viewModel.documentState.loadedMergeDocument?.resultPane.text,
            """
            alpha
            ours-one
            middle
            <<<<<<< ours
            ours-two
            =======
            theirs-two
            >>>>>>> theirs
            omega
            """
        )
    }

    func testApplyCompareBlockStageActionSendsSinglePatchToClient() async throws {
        let recorder = WorkspaceDiffTabClientRecorder()
        recorder.workingTreeDocument = .compare(
            WorkspaceDiffCompareDocument(
                mode: .unstaged,
                leftPane: WorkspaceDiffEditorPane(title: "Staged", path: "README.md", text: "hello\nbefore\nkeep\n", isEditable: false),
                rightPane: WorkspaceDiffEditorPane(title: "Local", path: "README.md", text: "hello\nafter\nkeep\n", isEditable: true)
            )
        )
        let viewModel = makeViewModel(
            tab: WorkspaceDiffTabState(
                id: "stage-block-1",
                identity: "commit-preview|/tmp/root",
                title: "Changes: README.md",
                source: .workingTreeChange(
                    repositoryPath: "/tmp/root",
                    executionPath: "/tmp/root",
                    filePath: "README.md",
                    group: .unstaged,
                    status: .modified,
                    oldPath: nil
                ),
                viewerMode: .sideBySide
            ),
            recorder: recorder
        )

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(80))
        let blockID = try XCTUnwrap(viewModel.documentState.loadedCompareDocument?.blocks.first?.id)

        try viewModel.applyCompareBlockAction(.stage, blockID: blockID)

        XCTAssertEqual(recorder.stagedPatches.count, 1)
        XCTAssertTrue(recorder.stagedPatches[0].patch.contains("diff --git a/README.md b/README.md"))
        XCTAssertTrue(recorder.stagedPatches[0].patch.contains("-before"))
        XCTAssertTrue(recorder.stagedPatches[0].patch.contains("+after"))
    }

    func testApplyCompareBlockStageActionSupportsUntrackedNewFilePatchHeader() async throws {
        let recorder = WorkspaceDiffTabClientRecorder()
        recorder.workingTreeDocument = .compare(
            WorkspaceDiffCompareDocument(
                mode: .untracked,
                leftPane: WorkspaceDiffEditorPane(title: "Empty", path: nil, text: "", isEditable: false),
                rightPane: WorkspaceDiffEditorPane(title: "Local", path: "NEW.md", text: "first line\nsecond line\n", isEditable: true)
            )
        )
        let viewModel = makeViewModel(
            tab: WorkspaceDiffTabState(
                id: "stage-untracked-block-1",
                identity: "commit-preview|/tmp/root",
                title: "Changes: NEW.md",
                source: .workingTreeChange(
                    repositoryPath: "/tmp/root",
                    executionPath: "/tmp/root",
                    filePath: "NEW.md",
                    group: .untracked,
                    status: .added,
                    oldPath: nil
                ),
                viewerMode: .sideBySide
            ),
            recorder: recorder
        )

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(80))
        let blockID = try XCTUnwrap(viewModel.documentState.loadedCompareDocument?.blocks.first?.id)

        try viewModel.applyCompareBlockAction(.stage, blockID: blockID)

        XCTAssertEqual(recorder.stagedPatches.count, 1)
        XCTAssertTrue(recorder.stagedPatches[0].patch.contains("new file mode 100644"))
        XCTAssertTrue(recorder.stagedPatches[0].patch.contains("--- /dev/null"))
        XCTAssertTrue(recorder.stagedPatches[0].patch.contains("+++ b/NEW.md"))
    }

    func testApplyCompareBlockUnstageActionSendsReversePatchToClient() async throws {
        let recorder = WorkspaceDiffTabClientRecorder()
        recorder.workingTreeDocument = .compare(
            WorkspaceDiffCompareDocument(
                mode: .staged,
                leftPane: WorkspaceDiffEditorPane(title: "HEAD", path: "README.md", text: "hello\nbefore\nkeep\n", isEditable: false),
                rightPane: WorkspaceDiffEditorPane(title: "Staged", path: "README.md", text: "hello\nafter\nkeep\n", isEditable: false)
            )
        )
        let viewModel = makeViewModel(
            tab: WorkspaceDiffTabState(
                id: "unstage-block-1",
                identity: "commit-preview|/tmp/root",
                title: "Changes: README.md",
                source: .workingTreeChange(
                    repositoryPath: "/tmp/root",
                    executionPath: "/tmp/root",
                    filePath: "README.md",
                    group: .staged,
                    status: .modified,
                    oldPath: nil
                ),
                viewerMode: .sideBySide
            ),
            recorder: recorder
        )

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(80))
        let blockID = try XCTUnwrap(viewModel.documentState.loadedCompareDocument?.blocks.first?.id)

        try viewModel.applyCompareBlockAction(.unstage, blockID: blockID)

        XCTAssertEqual(recorder.unstagedPatches.count, 1)
        XCTAssertTrue(recorder.unstagedPatches[0].patch.contains("diff --git a/README.md b/README.md"))
        XCTAssertTrue(recorder.unstagedPatches[0].patch.contains("+after"))
    }

    func testApplyCompareBlockRevertActionOnlyRevertsSelectedRange() async throws {
        let recorder = WorkspaceDiffTabClientRecorder()
        recorder.workingTreeDocument = .compare(
            WorkspaceDiffCompareDocument(
                mode: .unstaged,
                leftPane: WorkspaceDiffEditorPane(title: "Staged", path: "README.md", text: "hello\nbase-one\nmid\nbase-two\n", isEditable: false),
                rightPane: WorkspaceDiffEditorPane(title: "Local", path: "README.md", text: "hello\nlocal-one\nmid\nlocal-two\n", isEditable: true)
            )
        )
        let viewModel = makeViewModel(
            tab: WorkspaceDiffTabState(
                id: "revert-block-1",
                identity: "commit-preview|/tmp/root",
                title: "Changes: README.md",
                source: .workingTreeChange(
                    repositoryPath: "/tmp/root",
                    executionPath: "/tmp/root",
                    filePath: "README.md",
                    group: .unstaged,
                    status: .modified,
                    oldPath: nil
                ),
                viewerMode: .sideBySide
            ),
            recorder: recorder
        )

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(80))
        let blocks = try XCTUnwrap(viewModel.documentState.loadedCompareDocument?.blocks)
        XCTAssertEqual(blocks.count, 2)

        try viewModel.applyCompareBlockAction(.revert, blockID: blocks[0].id)

        XCTAssertEqual(viewModel.documentState.loadedCompareDocument?.rightPane.text, "hello\nbase-one\nmid\nlocal-two\n")
        XCTAssertEqual(viewModel.documentState.loadedCompareDocument?.blocks.count, 1)
    }

    private func makeViewModel(
        tab: WorkspaceDiffTabState,
        recorder: WorkspaceDiffTabClientRecorder
    ) -> WorkspaceDiffTabViewModel {
        WorkspaceDiffTabViewModel(
            tab: tab,
            client: recorder.client
        )
    }

    private func makeRequestItem(
        id: String,
        filePath: String,
        group: WorkspaceCommitChangeGroup = .unstaged
    ) -> WorkspaceDiffRequestItem {
        WorkspaceDiffRequestItem(
            id: id,
            title: filePath,
            source: .workingTreeChange(
                repositoryPath: "/tmp/root",
                executionPath: "/tmp/root",
                filePath: filePath,
                group: group,
                status: .modified,
                oldPath: nil
            ),
            preferredViewerMode: .sideBySide
        )
    }
}

private final class WorkspaceDiffTabClientRecorder: @unchecked Sendable {
    var gitLogDiff = ""
    var workingTreeDocument: WorkspaceDiffLoadedDocument?
    var workingTreeDocumentAfterSave: WorkspaceDiffLoadedDocument?
    var workingTreeDocumentByFilePath = [String: WorkspaceDiffLoadedDocument]()
    var loadError: Error?
    var gitLogRequests = [GitLogRequest]()
    var workingTreeRequests = [WorkingTreeRequest]()
    var savedWorkingTreeWrites = [WorkingTreeWrite]()
    var stagedPatches = [PatchMutation]()
    var unstagedPatches = [PatchMutation]()

    var client: WorkspaceDiffTabViewModel.Client {
        WorkspaceDiffTabViewModel.Client(
            loadGitLogCommitFileDiff: { [weak self] repositoryPath, commitHash, filePath in
                self?.gitLogRequests.append(
                    GitLogRequest(
                        repositoryPath: repositoryPath,
                        commitHash: commitHash,
                        filePath: filePath
                    )
                )
                if let error = self?.loadError {
                    throw error
                }
                return self?.gitLogDiff ?? ""
            },
            loadWorkingTreeDocument: { [weak self] source in
                guard case let .workingTreeChange(_, executionPath, filePath, _, _, _) = source else {
                    fatalError("测试只应在 workingTree source 上调用")
                }
                self?.workingTreeRequests.append(
                    WorkingTreeRequest(
                        executionPath: executionPath,
                        filePath: filePath
                    )
                )
                if let error = self?.loadError {
                    throw error
                }
                if let writes = self?.savedWorkingTreeWrites, !writes.isEmpty,
                   let afterSave = self?.workingTreeDocumentAfterSave {
                    return afterSave
                }
                if let specific = self?.workingTreeDocumentByFilePath[filePath] {
                    return specific
                }
                return self?.workingTreeDocument ?? .patch(.init(
                    kind: .empty,
                    oldPath: nil,
                    newPath: nil,
                    headerLines: [],
                    hunks: [],
                    message: "暂无 Diff"
                ))
            },
            saveWorkingTreeFile: { [weak self] executionPath, filePath, content in
                self?.savedWorkingTreeWrites.append(
                    WorkingTreeWrite(
                        executionPath: executionPath,
                        filePath: filePath,
                        content: content
                    )
                )
            },
            stageWorkingTreePatch: { [weak self] executionPath, patch in
                self?.stagedPatches.append(PatchMutation(executionPath: executionPath, patch: patch))
            },
            unstageWorkingTreePatch: { [weak self] executionPath, patch in
                self?.unstagedPatches.append(PatchMutation(executionPath: executionPath, patch: patch))
            }
        )
    }
}

private struct GitLogRequest: Equatable {
    let repositoryPath: String
    let commitHash: String
    let filePath: String
}

private struct WorkingTreeRequest: Equatable {
    let executionPath: String
    let filePath: String
}

private struct WorkingTreeWrite: Equatable {
    let executionPath: String
    let filePath: String
    let content: String
}

private struct PatchMutation: Equatable {
    let executionPath: String
    let patch: String
}

private enum WorkspaceDiffTabViewModelTestError: LocalizedError {
    case fixture

    var errorDescription: String? {
        switch self {
        case .fixture:
            return "diff load failed"
        }
    }
}
