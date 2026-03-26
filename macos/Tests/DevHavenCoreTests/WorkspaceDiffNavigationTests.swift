import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceDiffNavigationTests: XCTestCase {
    func testNextDifferenceMovesAcrossBlocksThenAdvancesToNextRequestItem() async throws {
        let recorder = WorkspaceDiffNavigationRecorder()
        let viewModel = makeViewModel(recorder: recorder, filePath: "README.md")

        viewModel.openSession(
            WorkspaceDiffRequestChain(
                items: [
                    makeRequestItem(id: "readme", filePath: "README.md"),
                    makeRequestItem(id: "package", filePath: "Package.swift"),
                ]
            )
        )
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(viewModel.selectedDifferenceAnchor, .compareBlock("compare-block-0"))
        XCTAssertEqual(viewModel.sessionState.navigatorState.currentDifferenceIndex, 1)
        XCTAssertEqual(viewModel.sessionState.requestChain.activeIndex, 0)

        viewModel.goToNextDifference()

        XCTAssertEqual(viewModel.selectedDifferenceAnchor, .compareBlock("compare-block-1"))
        XCTAssertEqual(viewModel.sessionState.navigatorState.currentDifferenceIndex, 2)
        XCTAssertEqual(viewModel.sessionState.requestChain.activeIndex, 0)

        viewModel.goToNextDifference()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(viewModel.selectedDifferenceAnchor, .compareBlock("compare-block-0"))
        XCTAssertEqual(viewModel.sessionState.navigatorState.currentDifferenceIndex, 1)
        XCTAssertEqual(viewModel.sessionState.requestChain.activeIndex, 1)
        XCTAssertEqual(viewModel.tab.title, "Package.swift")
        XCTAssertEqual(viewModel.documentState.loadedCompareDocument?.rightPane.path, "Package.swift")
    }

    func testPreviousDifferenceMovesToPreviousItemLastDifference() async throws {
        let recorder = WorkspaceDiffNavigationRecorder()
        let viewModel = makeViewModel(recorder: recorder, filePath: "Package.swift")

        viewModel.openSession(
            WorkspaceDiffRequestChain(
                items: [
                    makeRequestItem(id: "readme", filePath: "README.md"),
                    makeRequestItem(id: "package", filePath: "Package.swift"),
                ],
                activeIndex: 1
            )
        )
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(viewModel.selectedDifferenceAnchor, .compareBlock("compare-block-0"))
        XCTAssertEqual(viewModel.sessionState.navigatorState.currentDifferenceIndex, 1)
        XCTAssertEqual(viewModel.sessionState.requestChain.activeIndex, 1)

        viewModel.goToPreviousDifference()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(viewModel.selectedDifferenceAnchor, .compareBlock("compare-block-1"))
        XCTAssertEqual(viewModel.sessionState.navigatorState.currentDifferenceIndex, 2)
        XCTAssertEqual(viewModel.sessionState.requestChain.activeIndex, 0)
        XCTAssertEqual(viewModel.tab.title, "README.md")
        XCTAssertEqual(viewModel.documentState.loadedCompareDocument?.rightPane.path, "README.md")
    }

    private func makeViewModel(
        recorder: WorkspaceDiffNavigationRecorder,
        filePath: String
    ) -> WorkspaceDiffTabViewModel {
        WorkspaceDiffTabViewModel(
            tab: WorkspaceDiffTabState(
                id: "diff-navigation",
                identity: "commit-preview|/tmp/root",
                title: filePath,
                source: .workingTreeChange(
                    repositoryPath: "/tmp/root",
                    executionPath: "/tmp/root",
                    filePath: filePath,
                    group: .unstaged,
                    status: .modified,
                    oldPath: nil
                ),
                viewerMode: .sideBySide
            ),
            client: recorder.client
        )
    }

    private func makeRequestItem(id: String, filePath: String) -> WorkspaceDiffRequestItem {
        WorkspaceDiffRequestItem(
            id: id,
            title: filePath,
            source: .workingTreeChange(
                repositoryPath: "/tmp/root",
                executionPath: "/tmp/root",
                filePath: filePath,
                group: .unstaged,
                status: .modified,
                oldPath: nil
            ),
            preferredViewerMode: .sideBySide
        )
    }
}

private final class WorkspaceDiffNavigationRecorder: @unchecked Sendable {
    var client: WorkspaceDiffTabViewModel.Client {
        WorkspaceDiffTabViewModel.Client(
            loadGitLogCommitFileDiff: { _, _, _ in
                XCTFail("导航测试不应加载 git log patch")
                return ""
            },
            loadWorkingTreeDocument: { source in
                guard case let .workingTreeChange(_, _, filePath, _, _, _) = source else {
                    fatalError("导航测试只应请求 working tree source")
                }
                return .compare(
                    WorkspaceDiffCompareDocument(
                        mode: .unstaged,
                        leftPane: WorkspaceDiffEditorPane(
                            title: "Staged",
                            path: filePath,
                            text: filePath == "README.md"
                                ? "same\nbefore\nsame\nafter\n"
                                : "import PackageDescription\n",
                            isEditable: false
                        ),
                        rightPane: WorkspaceDiffEditorPane(
                            title: "Local",
                            path: filePath,
                            text: filePath == "README.md"
                                ? "same\nBEFORE\nsame\nAFTER\n"
                                : "import PackageDescription\n// diff\n",
                            isEditable: true
                        )
                    )
                )
            },
            saveWorkingTreeFile: { _, _, _ in }
        )
    }
}
