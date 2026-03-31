import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceDiffTabViewModelTests: XCTestCase {
    func testUpdateEditableCompareContentDefersDiffRebuildUntilDebounce() async throws {
        let viewModel = makeViewModel(rebuildDelayNanoseconds: 40_000_000)
        viewModel.documentState.loadState = .loaded(
            .compare(
                WorkspaceDiffCompareDocument(
                    mode: .unstaged,
                    leftPane: WorkspaceDiffEditorPane(
                        title: "Staged",
                        path: "Sources/App.swift",
                        text: "line 1\nline 2\n",
                        isEditable: false
                    ),
                    rightPane: WorkspaceDiffEditorPane(
                        title: "Local",
                        path: "Sources/App.swift",
                        text: "line 1\nline 2\n",
                        isEditable: true
                    ),
                    blocks: []
                )
            )
        )

        viewModel.updateEditableContent("line 1\nline x\n")

        let immediateDocument = try XCTUnwrap(viewModel.documentState.loadedCompareDocument)
        XCTAssertEqual(immediateDocument.rightPane.text, "line 1\nline x\n")
        XCTAssertTrue(immediateDocument.blocks.isEmpty, "输入后应先保留轻量文本更新，不立即主线程重算 diff")

        let rebuilt = await waitUntil(timeout: 1) {
            !(viewModel.documentState.loadedCompareDocument?.blocks.isEmpty ?? true)
        }
        XCTAssertTrue(rebuilt)

        let rebuiltDocument = try XCTUnwrap(viewModel.documentState.loadedCompareDocument)
        XCTAssertEqual(rebuiltDocument.rightPane.text, "line 1\nline x\n")
        XCTAssertEqual(rebuiltDocument.blocks.count, 1)
        XCTAssertEqual(rebuiltDocument.blocks.first?.rightLines, ["line x"])
    }

    func testLatestCompareEditWinsWhenPreviousRebuildIsCancelled() async throws {
        let viewModel = makeViewModel(rebuildDelayNanoseconds: 60_000_000)
        viewModel.documentState.loadState = .loaded(
            .compare(
                WorkspaceDiffCompareDocument(
                    mode: .unstaged,
                    leftPane: WorkspaceDiffEditorPane(
                        title: "Staged",
                        path: "Sources/App.swift",
                        text: "line 1\nline 2\n",
                        isEditable: false
                    ),
                    rightPane: WorkspaceDiffEditorPane(
                        title: "Local",
                        path: "Sources/App.swift",
                        text: "line 1\nline 2\n",
                        isEditable: true
                    ),
                    blocks: []
                )
            )
        )

        viewModel.updateEditableContent("line 1\nfirst\n")
        try await Task.sleep(nanoseconds: 10_000_000)
        viewModel.updateEditableContent("line 1\nsecond\n")

        let rebuilt = await waitUntil(timeout: 1) {
            viewModel.documentState.loadedCompareDocument?.blocks.first?.rightLines == ["second"]
        }
        XCTAssertTrue(rebuilt)

        let rebuiltDocument = try XCTUnwrap(viewModel.documentState.loadedCompareDocument)
        XCTAssertEqual(rebuiltDocument.rightPane.text, "line 1\nsecond\n")
        XCTAssertEqual(rebuiltDocument.blocks.first?.rightLines, ["second"])
    }

    func testUpdateEditableMergeContentDefersConflictRebuildUntilDebounce() async throws {
        let viewModel = makeViewModel(rebuildDelayNanoseconds: 40_000_000)
        viewModel.documentState.loadState = .loaded(
            .merge(
                WorkspaceDiffMergeDocument(
                    oursPane: WorkspaceDiffEditorPane(
                        title: "Ours",
                        path: "Sources/App.swift",
                        text: "A\n",
                        isEditable: false
                    ),
                    basePane: WorkspaceDiffEditorPane(
                        title: "Base",
                        path: "Sources/App.swift",
                        text: "",
                        isEditable: false
                    ),
                    theirsPane: WorkspaceDiffEditorPane(
                        title: "Theirs",
                        path: "Sources/App.swift",
                        text: "B\n",
                        isEditable: false
                    ),
                    resultPane: WorkspaceDiffEditorPane(
                        title: "Result",
                        path: "Sources/App.swift",
                        text: "",
                        isEditable: true
                    ),
                    conflictBlocks: []
                )
            )
        )

        viewModel.updateEditableContent("<<<<<<< ours\nA\n=======\nB\n>>>>>>> theirs\n")

        let immediateDocument = try XCTUnwrap(viewModel.documentState.loadedMergeDocument)
        XCTAssertEqual(immediateDocument.resultPane.text, "<<<<<<< ours\nA\n=======\nB\n>>>>>>> theirs\n")
        XCTAssertTrue(immediateDocument.conflictBlocks.isEmpty)

        let rebuilt = await waitUntil(timeout: 1) {
            !(viewModel.documentState.loadedMergeDocument?.conflictBlocks.isEmpty ?? true)
        }
        XCTAssertTrue(rebuilt)

        let rebuiltDocument = try XCTUnwrap(viewModel.documentState.loadedMergeDocument)
        XCTAssertEqual(rebuiltDocument.conflictBlocks.count, 1)
        XCTAssertEqual(rebuiltDocument.resultPane.text, "<<<<<<< ours\nA\n=======\nB\n>>>>>>> theirs\n")
    }

    private func makeViewModel(rebuildDelayNanoseconds: UInt64) -> WorkspaceDiffTabViewModel {
        WorkspaceDiffTabViewModel(
            tab: WorkspaceDiffTabState(
                id: "diff-tab",
                identity: "diff-tab",
                title: "Sources/App.swift",
                source: .workingTreeChange(
                    repositoryPath: "/tmp/repo",
                    executionPath: "/tmp/repo",
                    filePath: "Sources/App.swift",
                    group: .unstaged,
                    status: .modified,
                    oldPath: nil
                ),
                viewerMode: .sideBySide
            ),
            client: .init(
                loadGitLogCommitFileDiff: { _, _, _ in "" },
                loadWorkingTreeDocument: { _ in
                    WorkspaceDiffLoadedDocument.compare(
                        WorkspaceDiffCompareDocument(
                            mode: .unstaged,
                            leftPane: WorkspaceDiffEditorPane(title: "Staged", path: nil, text: "", isEditable: false),
                            rightPane: WorkspaceDiffEditorPane(title: "Local", path: nil, text: "", isEditable: true)
                        )
                    )
                },
                saveWorkingTreeFile: { _, _, _ in }
            ),
            editableContentRebuildDelayNanoseconds: rebuildDelayNanoseconds
        )
    }

    @discardableResult
    private func waitUntil(
        timeout: TimeInterval,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }
}
