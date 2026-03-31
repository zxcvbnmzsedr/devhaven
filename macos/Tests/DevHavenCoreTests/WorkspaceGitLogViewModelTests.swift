import Foundation
import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceGitLogViewModelTests: XCTestCase {
    func testRefreshLoadsCommitSummaryWithoutAutoLoadingFileDiff() async throws {
        let counter = CallCounter()
        let repositoryPath = "/tmp/repo"
        let commit = Self.makeCommitSummary(hash: "abc123")
        let detail = Self.makeCommitDetail(
            hash: commit.hash,
            files: [
                WorkspaceGitCommitFileChange(
                    path: "Sources/App.swift",
                    status: .modified
                )
            ],
            diff: ""
        )
        let expectedFileDiff = """
        diff --git a/Sources/App.swift b/Sources/App.swift
        @@ -1 +1 @@
        -old
        +new
        """

        let viewModel = makeViewModel(
            repositoryPath: repositoryPath,
            client: .init(
                loadLogSnapshot: { path, _ in
                    counter.increment("log")
                    XCTAssertEqual(path, repositoryPath)
                    return WorkspaceGitLogSnapshot(
                        refs: WorkspaceGitRefsSnapshot(
                            localBranches: [
                                WorkspaceGitBranchSnapshot(
                                    name: "main",
                                    fullName: "refs/heads/main",
                                    hash: commit.hash,
                                    kind: .local,
                                    isCurrent: true
                                )
                            ],
                            remoteBranches: [],
                            tags: []
                        ),
                        commits: [commit]
                    )
                },
                loadCommitSummary: { path, hash in
                    counter.increment("summary")
                    XCTAssertEqual(path, repositoryPath)
                    XCTAssertEqual(hash, commit.hash)
                    return detail
                },
                loadFileDiffForCommit: { path, hash, filePath in
                    counter.increment("fileDiff")
                    XCTAssertEqual(path, repositoryPath)
                    XCTAssertEqual(hash, commit.hash)
                    XCTAssertEqual(filePath, "Sources/App.swift")
                    return expectedFileDiff
                },
                loadAuthorSuggestions: { path, limit in
                    counter.increment("authors")
                    XCTAssertEqual(path, repositoryPath)
                    XCTAssertEqual(limit, 200)
                    return []
                }
            )
        )

        viewModel.refresh()

        let loaded = await waitUntil(timeout: 1) {
            !viewModel.isLoading &&
            !viewModel.isLoadingSelectedCommitDetail &&
            !viewModel.isLoadingSelectedFileDiff &&
            viewModel.selectedCommitHash == commit.hash &&
            viewModel.selectedCommitDetail?.hash == commit.hash &&
            viewModel.selectedFilePath == "Sources/App.swift"
        }

        XCTAssertTrue(loaded)
        XCTAssertEqual(counter.value(for: "log"), 1)
        XCTAssertEqual(counter.value(for: "summary"), 1)
        XCTAssertEqual(counter.value(for: "fileDiff"), 0)
        XCTAssertEqual(counter.value(for: "authors"), 1)
        XCTAssertEqual(viewModel.selectedCommitDetail?.diff, "")
        XCTAssertEqual(viewModel.selectedCommitDetail?.files.map(\.path), ["Sources/App.swift"])
        XCTAssertNil(viewModel.selectedFileDiffNotice)
        XCTAssertFalse(viewModel.isSelectedFileDiffTruncated)
        XCTAssertEqual(viewModel.selectedFileDiff, "")
        XCTAssertEqual(viewModel.tableRows.first?.decorationBadges, ["HEAD -> main"])
        XCTAssertEqual(
            viewModel.tableRows.first?.formattedDateText,
            Self.expectedFormattedDateText(for: commit.authorTimestamp)
        )
        XCTAssertEqual(viewModel.tableRows.first?.isHighlightedOnCurrentBranch, true)

        viewModel.selectCommitFile("Sources/App.swift")

        let diffLoaded = await waitUntil(timeout: 1) {
            !viewModel.isLoadingSelectedFileDiff &&
            viewModel.selectedFileDiff == expectedFileDiff
        }

        XCTAssertTrue(diffLoaded)
        XCTAssertEqual(counter.value(for: "fileDiff"), 1)
    }

    func testRefreshReusesCachedAuthorSuggestionsWithinSameRepository() async throws {
        let counter = CallCounter()
        let repositoryPath = "/tmp/repo"
        let expectedAuthors = ["Alice", "Bob"]
        let viewModel = makeViewModel(
            repositoryPath: repositoryPath,
            client: .init(
                loadLogSnapshot: { path, _ in
                    counter.increment("log")
                    XCTAssertEqual(path, repositoryPath)
                    return Self.makeSnapshot(commits: [])
                },
                loadCommitSummary: { _, _ in
                    counter.increment("summary")
                    return Self.makeCommitDetail(hash: "unused", files: [])
                },
                loadFileDiffForCommit: { _, _, _ in
                    counter.increment("fileDiff")
                    return ""
                },
                loadAuthorSuggestions: { path, limit in
                    counter.increment("authors")
                    XCTAssertEqual(path, repositoryPath)
                    XCTAssertEqual(limit, 200)
                    return expectedAuthors
                }
            )
        )

        viewModel.refresh()
        let firstLoaded = await waitUntil(timeout: 1) {
            !viewModel.isLoading &&
            viewModel.availableAuthors == expectedAuthors
        }
        XCTAssertTrue(firstLoaded)

        viewModel.refresh()
        let secondLoaded = await waitUntil(timeout: 1) {
            !viewModel.isLoading &&
            counter.value(for: "log") == 2
        }
        XCTAssertTrue(secondLoaded)

        XCTAssertEqual(counter.value(for: "authors"), 1)
        XCTAssertEqual(counter.value(for: "summary"), 0)
        XCTAssertEqual(counter.value(for: "fileDiff"), 0)
        XCTAssertEqual(viewModel.availableAuthors, expectedAuthors)
    }

    func testRepositoryChangeLoadsAuthorSuggestionsForNewRepository() async throws {
        let counter = CallCounter()
        let firstRepositoryPath = "/tmp/repo-a"
        let secondRepositoryPath = "/tmp/repo-b"
        let firstAuthors = ["Alice"]
        let secondAuthors = ["Bob"]
        let viewModel = makeViewModel(
            repositoryPath: firstRepositoryPath,
            client: .init(
                loadLogSnapshot: { path, _ in
                    counter.increment("log:\(path)")
                    return Self.makeSnapshot(commits: [])
                },
                loadCommitSummary: { _, _ in
                    counter.increment("summary")
                    return Self.makeCommitDetail(hash: "unused", files: [])
                },
                loadFileDiffForCommit: { _, _, _ in
                    counter.increment("fileDiff")
                    return ""
                },
                loadAuthorSuggestions: { path, _ in
                    counter.increment("authors:\(path)")
                    switch path {
                    case firstRepositoryPath:
                        return firstAuthors
                    case secondRepositoryPath:
                        return secondAuthors
                    default:
                        XCTFail("unexpected repository path: \(path)")
                        return []
                    }
                }
            )
        )

        viewModel.refresh()
        let firstLoaded = await waitUntil(timeout: 1) {
            !viewModel.isLoading &&
            viewModel.availableAuthors == firstAuthors
        }
        XCTAssertTrue(firstLoaded)

        viewModel.updateRepositoryContext(
            WorkspaceGitRepositoryContext(
                rootProjectPath: secondRepositoryPath,
                repositoryPath: secondRepositoryPath
            )
        )

        let switched = await waitUntil(timeout: 1) {
            !viewModel.isLoading &&
            viewModel.availableAuthors == secondAuthors
        }
        XCTAssertTrue(switched)

        XCTAssertEqual(counter.value(for: "authors:\(firstRepositoryPath)"), 1)
        XCTAssertEqual(counter.value(for: "authors:\(secondRepositoryPath)"), 1)
        XCTAssertEqual(counter.value(for: "summary"), 0)
        XCTAssertEqual(counter.value(for: "fileDiff"), 0)
    }

    func testRefreshIfNeededOnlyTriggersInitialReadOnce() async throws {
        let counter = CallCounter()
        let repositoryPath = "/tmp/repo"
        let viewModel = makeViewModel(
            repositoryPath: repositoryPath,
            client: .init(
                loadLogSnapshot: { path, _ in
                    XCTAssertEqual(path, repositoryPath)
                    counter.increment("log")
                    return Self.makeSnapshot(commits: [])
                },
                loadCommitSummary: { _, _ in
                    counter.increment("summary")
                    return Self.makeCommitDetail(hash: "unused", files: [])
                },
                loadFileDiffForCommit: { _, _, _ in
                    counter.increment("fileDiff")
                    return ""
                },
                loadAuthorSuggestions: { _, _ in
                    counter.increment("authors")
                    return []
                }
            )
        )

        viewModel.refreshIfNeeded()
        viewModel.refreshIfNeeded()

        let loaded = await waitUntil(timeout: 1) {
            !viewModel.isLoading && counter.value(for: "log") == 1
        }
        XCTAssertTrue(loaded)
        XCTAssertEqual(counter.value(for: "log"), 1)
        XCTAssertEqual(counter.value(for: "authors"), 1)
    }

    func testRefreshBuildsGraphProjectionOffMainActor() async throws {
        let repositoryPath = "/tmp/repo"
        let commit = Self.makeCommitSummary(hash: "graph-1")
        let threadRecorder = BooleanRecorder()
        let viewModel = makeViewModel(
            repositoryPath: repositoryPath,
            client: .init(
                loadLogSnapshot: { path, _ in
                    XCTAssertEqual(path, repositoryPath)
                    return Self.makeSnapshot(commits: [commit])
                },
                loadCommitSummary: { _, hash in
                    Self.makeCommitDetail(hash: hash, files: [])
                },
                loadFileDiffForCommit: { _, _, _ in "" },
                loadAuthorSuggestions: { _, _ in [] }
            ),
            graphVisibleModelBuilder: { commits in
                if !commits.isEmpty {
                    threadRecorder.record(Thread.isMainThread)
                }
                return WorkspaceGitCommitGraphBuilder.buildVisibleModel(commits: commits)
            }
        )

        viewModel.refresh()

        let loaded = await waitUntil(timeout: 1) {
            !viewModel.isLoading &&
            viewModel.tableRows.count == 1 &&
            viewModel.graphVisibleModel.rows.count == 1
        }

        XCTAssertTrue(loaded)
        XCTAssertEqual(threadRecorder.values, [false], "graph projection 应在后台线程构建，避免卡住主线程刷新")
    }

    private func makeViewModel(
        repositoryPath: String,
        client: WorkspaceGitLogViewModel.Client,
        graphVisibleModelBuilder: @escaping @Sendable ([WorkspaceGitCommitSummary]) -> WorkspaceGitCommitGraphVisibleModel = WorkspaceGitCommitGraphBuilder.buildVisibleModel
    ) -> WorkspaceGitLogViewModel {
        WorkspaceGitLogViewModel(
            repositoryContext: WorkspaceGitRepositoryContext(
                rootProjectPath: repositoryPath,
                repositoryPath: repositoryPath
            ),
            client: client,
            graphVisibleModelBuilder: graphVisibleModelBuilder
        )
    }

    private nonisolated static func makeSnapshot(
        commits: [WorkspaceGitCommitSummary]
    ) -> WorkspaceGitLogSnapshot {
        WorkspaceGitLogSnapshot(
            refs: WorkspaceGitRefsSnapshot(
                localBranches: [],
                remoteBranches: [],
                tags: []
            ),
            commits: commits
        )
    }

    private nonisolated static func makeCommitSummary(hash: String) -> WorkspaceGitCommitSummary {
        WorkspaceGitCommitSummary(
            hash: hash,
            shortHash: String(hash.prefix(7)),
            graphPrefix: "*",
            parentHashes: ["parent-\(hash)"],
            authorName: "Alice",
            authorEmail: "alice@example.com",
            authorTimestamp: 1_710_000_000,
            subject: "Refine git log performance",
            decorations: "HEAD -> main"
        )
    }

    private nonisolated static func makeCommitDetail(
        hash: String,
        files: [WorkspaceGitCommitFileChange],
        diff: String = ""
    ) -> WorkspaceGitCommitDetail {
        WorkspaceGitCommitDetail(
            hash: hash,
            shortHash: String(hash.prefix(7)),
            parentHashes: ["parent-\(hash)"],
            authorName: "Alice",
            authorEmail: "alice@example.com",
            authorTimestamp: 1_710_000_000,
            subject: "Refine git log performance",
            body: "summary only",
            decorations: "HEAD -> main",
            changedFiles: files,
            diff: diff
        )
    }

    private nonisolated static func expectedFormattedDateText(for authorTimestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: authorTimestamp)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天"
        }
        if calendar.isDateInYesterday(date) {
            return "昨天"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
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

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Int] = [:]

    func increment(_ key: String) {
        lock.lock()
        values[key, default: 0] += 1
        lock.unlock()
    }

    func value(for key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return values[key, default: 0]
    }
}

private final class BooleanRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Bool] = []

    func record(_ value: Bool) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
