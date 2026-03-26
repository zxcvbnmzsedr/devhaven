import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceDiffTabViewModelTests: XCTestCase {
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
        recorder.workingTreeDiff = """
        diff --git a/Package.swift b/Package.swift
        --- a/Package.swift
        +++ b/Package.swift
        @@ -1 +1,2 @@
         import PackageDescription
        +// demo
        """
        let viewModel = makeViewModel(
            tab: WorkspaceDiffTabState(
                id: "diff-2",
                identity: "working-tree|/tmp/root|Package.swift",
                title: "Changes: Package.swift",
                source: .workingTreeChange(repositoryPath: "/tmp/root", executionPath: "/tmp/root", filePath: "Package.swift"),
                viewerMode: .sideBySide
            ),
            recorder: recorder
        )

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(recorder.workingTreeRequests.count, 1)
        XCTAssertEqual(recorder.workingTreeRequests.first?.executionPath, "/tmp/root")
        XCTAssertEqual(recorder.workingTreeRequests.first?.filePath, "Package.swift")
        XCTAssertEqual(viewModel.documentState.loadedDocument?.newPath, "Package.swift")
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
        let loadedBefore = viewModel.documentState.loadedDocument

        viewModel.updateViewerMode(.unified)

        XCTAssertEqual(viewModel.documentState.viewerMode, .unified)
        XCTAssertEqual(viewModel.documentState.loadedDocument, loadedBefore)
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
        XCTAssertNil(viewModel.documentState.loadedDocument)
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
}

private final class WorkspaceDiffTabClientRecorder: @unchecked Sendable {
    var gitLogDiff = ""
    var workingTreeDiff = ""
    var loadError: Error?
    var gitLogRequests = [GitLogRequest]()
    var workingTreeRequests = [WorkingTreeRequest]()

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
            loadWorkingTreeDiff: { [weak self] executionPath, filePath in
                self?.workingTreeRequests.append(
                    WorkingTreeRequest(
                        executionPath: executionPath,
                        filePath: filePath
                    )
                )
                if let error = self?.loadError {
                    throw error
                }
                return self?.workingTreeDiff ?? ""
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

private enum WorkspaceDiffTabViewModelTestError: LocalizedError {
    case fixture

    var errorDescription: String? {
        switch self {
        case .fixture:
            return "diff load failed"
        }
    }
}
