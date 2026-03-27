import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceGitLogViewModelTests: XCTestCase {
    func testRefreshLoadsCommitsAndAvailableAuthors() async throws {
        let recorder = WorkspaceGitLogClientRecorder()
        let viewModel = makeViewModel(recorder: recorder)

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(140))

        XCTAssertEqual(viewModel.logSnapshot.commits.count, 1)
        XCTAssertEqual(viewModel.availableAuthors, ["Alice", "Bob"])
    }

    func testSelectingCommitLoadsDetailsAndAutoLoadsFirstFileDiff() async throws {
        let recorder = WorkspaceGitLogClientRecorder()
        recorder.commitChangedFiles = [
            WorkspaceGitCommitFileChange(path: "Sources/App/Main.swift", status: .modified),
            WorkspaceGitCommitFileChange(path: "Tests/AppTests/MainTests.swift", status: .added),
        ]
        recorder.fileDiffs = [
            "hash-log|Sources/App/Main.swift": "diff --git a/Sources/App/Main.swift b/Sources/App/Main.swift\n+main\n",
        ]
        let viewModel = makeViewModel(recorder: recorder)

        viewModel.selectCommit("hash-log")
        try await Task.sleep(for: .milliseconds(180))

        XCTAssertEqual(viewModel.selectedCommitDetail?.hash, "hash-log")
        XCTAssertEqual(viewModel.selectedFilePath, "Sources/App/Main.swift")
        XCTAssertTrue(viewModel.selectedFileDiff.contains("Sources/App/Main.swift"))
        XCTAssertEqual(recorder.loadedFileDiffRequests.last?.filePath, "Sources/App/Main.swift")
    }

    func testPathFilterDebounceOnlyAppliesLatestValue() async throws {
        let recorder = WorkspaceGitLogClientRecorder()
        let viewModel = makeViewModel(recorder: recorder)

        viewModel.updatePathFilterQuery("Source")
        try await Task.sleep(for: .milliseconds(120))
        viewModel.updatePathFilterQuery("Sources/App")

        try await Task.sleep(for: .milliseconds(220))
        XCTAssertTrue(recorder.logPaths.isEmpty)

        try await Task.sleep(for: .milliseconds(140))
        XCTAssertEqual(viewModel.debouncedPathFilterQuery, "Sources/App")
        XCTAssertEqual(recorder.logPaths.last, "Sources/App")
    }

    func testGraphVisibleModelIsNotRebuiltForRepeatedTableReads() async throws {
        let recorder = WorkspaceGitLogClientRecorder()
        let buildCounter = GraphVisibleModelBuildCounter()
        let viewModel = makeViewModel(
            recorder: recorder,
            graphVisibleModelBuilder: { commits in
                buildCounter.increment()
                return WorkspaceGitCommitGraphBuilder.buildVisibleModel(commits: commits)
            }
        )

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(140))

        let buildCountAfterRefresh = buildCounter.value
        XCTAssertGreaterThan(buildCountAfterRefresh, 0, "刷新后应至少构建一次 graph visible model")

        _ = viewModel.tableRows
        _ = viewModel.preferredGraphWidth
        _ = viewModel.graphVisibleModel
        _ = viewModel.tableRows

        XCTAssertEqual(
            buildCounter.value,
            buildCountAfterRefresh,
            "tableRows / preferredGraphWidth / graphVisibleModel 的重复读取不应再次重建整份 graph visible model"
        )
    }

    private func makeViewModel(
        recorder: WorkspaceGitLogClientRecorder,
        graphVisibleModelBuilder: @escaping @Sendable ([WorkspaceGitCommitSummary]) -> WorkspaceGitCommitGraphVisibleModel = WorkspaceGitCommitGraphBuilder.buildVisibleModel
    ) -> WorkspaceGitLogViewModel {
        WorkspaceGitLogViewModel(
            repositoryContext: WorkspaceGitRepositoryContext(
                rootProjectPath: "/tmp/root",
                repositoryPath: "/tmp/root"
            ),
            client: recorder.client,
            graphVisibleModelBuilder: graphVisibleModelBuilder
        )
    }
}

private final class GraphVisibleModelBuildCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var rawValue = 0

    var value: Int {
        lock.withLock { rawValue }
    }

    func increment() {
        lock.withLock {
            rawValue += 1
        }
    }
}

private final class WorkspaceGitLogClientRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var rawLoadedFileDiffRequests: [(commitHash: String, filePath: String)] = []
    private var rawLogPaths: [String?] = []
    var commitChangedFiles: [WorkspaceGitCommitFileChange] = []
    var fileDiffs: [String: String] = [:]

    var loadedFileDiffRequests: [(commitHash: String, filePath: String)] {
        lock.withLock { rawLoadedFileDiffRequests }
    }

    var logPaths: [String?] {
        lock.withLock { rawLogPaths }
    }

    var client: WorkspaceGitLogViewModel.Client {
        WorkspaceGitLogViewModel.Client(
            loadLogSnapshot: { [weak self] _, query in
                self?.lock.withLock {
                    self?.rawLogPaths.append(query.path)
                }
                return WorkspaceGitLogSnapshot(
                    refs: WorkspaceGitRefsSnapshot(localBranches: [], remoteBranches: [], tags: []),
                    commits: [
                        WorkspaceGitCommitSummary(
                            hash: "hash-log",
                            shortHash: "hash",
                            graphPrefix: "*",
                            parentHashes: [],
                            authorName: "DevHaven",
                            authorEmail: "devhaven@example.com",
                            authorTimestamp: 1,
                            subject: "feat: log row",
                            decorations: "HEAD -> main"
                        ),
                    ]
                )
            },
            loadCommitDetail: { [weak self] _, commitHash in
                WorkspaceGitCommitDetail(
                    hash: commitHash,
                    shortHash: "hash",
                    parentHashes: [],
                    authorName: "DevHaven",
                    authorEmail: "devhaven@example.com",
                    authorTimestamp: 1,
                    subject: "feat: log row",
                    body: "body",
                    decorations: "HEAD -> main",
                    changedFiles: self?.commitChangedFiles ?? [],
                    diff: "diff --git a/README.md b/README.md\n+demo\n"
                )
            },
            loadFileDiffForCommit: { [weak self] _, commitHash, filePath in
                self?.lock.withLock {
                    self?.rawLoadedFileDiffRequests.append((commitHash: commitHash, filePath: filePath))
                }
                return self?.fileDiffs["\(commitHash)|\(filePath)"] ?? ""
            },
            loadAuthorSuggestions: { _, _ in
                ["Alice", "Bob"]
            }
        )
    }
}
