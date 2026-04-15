import Foundation
import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceCommitViewModelTests: XCTestCase {
    func testRefreshChangesSnapshotLoadsOffMainActor() async throws {
        let repositoryPath = "/tmp/devhaven-commit-refresh"
        let started = expectation(description: "background refresh started")
        let gate = DispatchSemaphore(value: 0)
        let expectedSnapshot = Self.makeSnapshot(
            branchName: "main",
            changes: [
                WorkspaceCommitChange(
                    path: "Sources/App.swift",
                    status: .modified,
                    group: .staged,
                    isIncludedByDefault: true
                )
            ]
        )

        let viewModel = WorkspaceCommitViewModel(
            repositoryContext: Self.makeRepositoryContext(path: repositoryPath),
            client: .init(
                loadChangesSnapshot: { path in
                    XCTAssertEqual(path, repositoryPath)
                    started.fulfill()
                    gate.wait()
                    return expectedSnapshot
                },
                loadDiffPreview: { _, _ in "" },
                executeCommit: { _, _ in }
            )
        )

        let startedAt = Date()
        viewModel.refreshChangesSnapshot()
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertLessThan(elapsed, 0.05)
        await fulfillment(of: [started], timeout: 1)
        XCTAssertNil(viewModel.changesSnapshot)

        gate.signal()

        let loaded = await waitUntil(timeout: 1) {
            viewModel.changesSnapshot == expectedSnapshot
        }

        XCTAssertTrue(loaded)
        XCTAssertEqual(viewModel.includedPaths, Set(["Sources/App.swift"]))
        XCTAssertNil(viewModel.errorMessage)
    }

    func testExecuteCommitRunsOffMainActorAndRefreshesSnapshotAfterSuccess() async throws {
        let repositoryPath = "/tmp/devhaven-commit-execute"
        let executionStarted = expectation(description: "background commit started")
        let executionGate = DispatchSemaphore(value: 0)
        let snapshotBox = LockedBox(
            Self.makeSnapshot(
                branchName: "main",
                changes: [
                    WorkspaceCommitChange(
                        path: "Sources/App.swift",
                        status: .modified,
                        group: .staged,
                        isIncludedByDefault: true
                    )
                ]
            )
        )

        let viewModel = WorkspaceCommitViewModel(
            repositoryContext: Self.makeRepositoryContext(path: repositoryPath),
            client: .init(
                loadChangesSnapshot: { path in
                    XCTAssertEqual(path, repositoryPath)
                    return snapshotBox.value
                },
                loadDiffPreview: { _, _ in "" },
                executeCommit: { path, request in
                    XCTAssertEqual(path, repositoryPath)
                    XCTAssertEqual(request.action, .commit)
                    XCTAssertEqual(request.message, "Ship async refresh")
                    XCTAssertEqual(request.includedPaths, ["Sources/App.swift"])
                    executionStarted.fulfill()
                    executionGate.wait()
                }
            )
        )

        viewModel.changesSnapshot = snapshotBox.value
        viewModel.includedPaths = Set(["Sources/App.swift"])
        viewModel.includedPathsByRepositoryGroupID = [repositoryPath: Set(["Sources/App.swift"])]
        viewModel.commitMessage = "Ship async refresh"

        let startedAt = Date()
        viewModel.executeCommit(action: .commit)
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertLessThan(elapsed, 0.05)
        XCTAssertEqual(viewModel.executionState, .running(.commit))
        await fulfillment(of: [executionStarted], timeout: 1)

        snapshotBox.value = Self.makeSnapshot(branchName: "main", changes: [])
        executionGate.signal()

        let finished = await waitUntil(timeout: 1.5) {
            viewModel.executionState == .succeeded(.commit) &&
                viewModel.changesSnapshot?.changes.isEmpty == true
        }

        XCTAssertTrue(finished)
        XCTAssertEqual(viewModel.includedPaths, [])
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRevertChangesRunsOffMainActorAndRefreshesSnapshotAfterSuccess() async throws {
        let repositoryPath = "/tmp/devhaven-commit-revert"
        let revertStarted = expectation(description: "background revert started")
        let revertGate = DispatchSemaphore(value: 0)
        let snapshotBox = LockedBox(
            Self.makeSnapshot(
                branchName: "main",
                changes: [
                    WorkspaceCommitChange(
                        path: "Sources/App.swift",
                        status: .modified,
                        group: .unstaged,
                        isIncludedByDefault: false
                    )
                ]
            )
        )

        let viewModel = WorkspaceCommitViewModel(
            repositoryContext: Self.makeRepositoryContext(path: repositoryPath),
            client: .init(
                loadChangesSnapshot: { path in
                    XCTAssertEqual(path, repositoryPath)
                    return snapshotBox.value
                },
                loadDiffPreview: { _, _ in "" },
                executeCommit: { _, _ in },
                revertChanges: { path, paths, deleteLocallyAddedFiles in
                    XCTAssertEqual(path, repositoryPath)
                    XCTAssertEqual(paths, ["Sources/App.swift"])
                    XCTAssertFalse(deleteLocallyAddedFiles)
                    revertStarted.fulfill()
                    revertGate.wait()
                }
            )
        )

        viewModel.changesSnapshot = snapshotBox.value
        viewModel.selectChange("Sources/App.swift")

        let startedAt = Date()
        viewModel.revertChanges(paths: ["Sources/App.swift"], deleteLocallyAddedFiles: false)
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertLessThan(elapsed, 0.05)
        XCTAssertTrue(viewModel.isRevertingChanges)
        await fulfillment(of: [revertStarted], timeout: 1)

        snapshotBox.value = Self.makeSnapshot(branchName: "main", changes: [])
        revertGate.signal()

        let finished = await waitUntil(timeout: 1.5) {
            viewModel.isRevertingChanges == false &&
                viewModel.changesSnapshot?.changes.isEmpty == true &&
                viewModel.selectedChangePath == nil
        }

        XCTAssertTrue(finished)
        XCTAssertEqual(viewModel.includedPaths, [])
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRefreshBuildsRepositoryGroupSummariesAndSelectionCanSwitchFamily() async throws {
        let repoAPath = "/tmp/devhaven-commit-repo-a"
        let repoBPath = "/tmp/devhaven-commit-repo-b"
        let repoAFamily = WorkspaceGitRepositoryFamilyContext(
            id: "family-a",
            displayName: "repo-a",
            repositoryPath: repoAPath,
            preferredExecutionPath: repoAPath,
            members: [
                WorkspaceGitWorktreeContext(
                    path: repoAPath,
                    displayName: "repo-a",
                    branchName: "main",
                    isRootProject: true
                )
            ]
        )
        let repoBFamily = WorkspaceGitRepositoryFamilyContext(
            id: "family-b",
            displayName: "repo-b",
            repositoryPath: repoBPath,
            preferredExecutionPath: repoBPath,
            members: [
                WorkspaceGitWorktreeContext(
                    path: repoBPath,
                    displayName: "repo-b",
                    branchName: "feature/demo",
                    isRootProject: true
                )
            ]
        )
        let callback = expectation(description: "repository selection callback fired")
        var callbackContext: WorkspaceCommitRepositoryContext?

        let viewModel = WorkspaceCommitViewModel(
            repositoryContext: WorkspaceCommitRepositoryContext(
                rootProjectPath: "/tmp/workspace",
                repositoryPath: repoAPath,
                executionPath: repoAPath,
                repositoryFamilies: [repoAFamily, repoBFamily],
                selectedRepositoryFamilyID: repoAFamily.id
            ),
            client: .init(
                loadChangesSnapshot: { path in
                    switch path {
                    case repoAPath:
                        return Self.makeSnapshot(
                            branchName: "main",
                            changes: [
                                WorkspaceCommitChange(
                                    path: "README.md",
                                    status: .modified,
                                    group: .staged,
                                    isIncludedByDefault: true
                                )
                            ]
                        )
                    case repoBPath:
                        return Self.makeSnapshot(
                            branchName: "feature/demo",
                            changes: [
                                WorkspaceCommitChange(
                                    path: "Sources/App.swift",
                                    status: .modified,
                                    group: .unstaged,
                                    isIncludedByDefault: false
                                ),
                                WorkspaceCommitChange(
                                    path: "Sources/View.swift",
                                    status: .modified,
                                    group: .unstaged,
                                    isIncludedByDefault: false
                                )
                            ]
                        )
                    default:
                        XCTFail("unexpected path \(path)")
                        return Self.makeSnapshot(branchName: nil, changes: [])
                    }
                },
                loadDiffPreview: { _, _ in "" },
                executeCommit: { _, _ in }
            )
        )
        viewModel.onRepositorySelectionChange = { context in
            callbackContext = context
            callback.fulfill()
        }

        viewModel.refreshChangesSnapshot()

        let loaded = await waitUntil(timeout: 1.5) {
            viewModel.repositoryGroupSummaries.count == 2 &&
                viewModel.repositoryGroupSummaries.first(where: { $0.id == repoAFamily.id })?.changeCount == 1 &&
                viewModel.repositoryGroupSummaries.first(where: { $0.id == repoBFamily.id })?.changeCount == 2
        }
        XCTAssertTrue(loaded)
        XCTAssertEqual(viewModel.selectedRepositoryFamilyDisplayName, "repo-a")
        XCTAssertEqual(viewModel.changesSnapshot(forRepositoryGroupID: repoAFamily.id)?.changes.count, 1)
        XCTAssertEqual(viewModel.changesSnapshot(forRepositoryGroupID: repoBFamily.id)?.changes.count, 2)

        viewModel.selectRepositoryFamily(repoBFamily.id)
        await fulfillment(of: [callback], timeout: 1)

        XCTAssertEqual(callbackContext?.repositoryPath, repoBPath)
        XCTAssertEqual(callbackContext?.executionPath, repoBPath)
        XCTAssertEqual(viewModel.repositoryContext.selectedRepositoryFamilyID, repoBFamily.id)
        XCTAssertEqual(viewModel.selectedRepositoryFamilyDisplayName, "repo-b")
    }

    func testCrossRepositoryInclusionPersistsAcrossFamilySwitchAndCanExecuteFromAnotherGroup() async throws {
        let repoAPath = "/tmp/devhaven-commit-cross-a"
        let repoBPath = "/tmp/devhaven-commit-cross-b"
        let repoAFamily = Self.makeRepositoryFamily(
            id: "family-a",
            displayName: "repo-a",
            path: repoAPath,
            branchName: "main"
        )
        let repoBFamily = Self.makeRepositoryFamily(
            id: "family-b",
            displayName: "repo-b",
            path: repoBPath,
            branchName: "feature/demo"
        )

        let viewModel = WorkspaceCommitViewModel(
            repositoryContext: WorkspaceCommitRepositoryContext(
                rootProjectPath: "/tmp/workspace",
                repositoryPath: repoAPath,
                executionPath: repoAPath,
                repositoryFamilies: [repoAFamily, repoBFamily],
                selectedRepositoryFamilyID: repoAFamily.id
            ),
            client: .init(
                loadChangesSnapshot: { path in
                    switch path {
                    case repoAPath:
                        return Self.makeSnapshot(
                            branchName: "main",
                            changes: [
                                WorkspaceCommitChange(
                                    path: "README.md",
                                    status: .modified,
                                    group: .unstaged,
                                    isIncludedByDefault: false
                                )
                            ]
                        )
                    case repoBPath:
                        return Self.makeSnapshot(
                            branchName: "feature/demo",
                            changes: [
                                WorkspaceCommitChange(
                                    path: "Sources/App.swift",
                                    status: .modified,
                                    group: .unstaged,
                                    isIncludedByDefault: false
                                )
                            ]
                        )
                    default:
                        XCTFail("unexpected path \(path)")
                        return Self.makeSnapshot(branchName: nil, changes: [])
                    }
                },
                loadDiffPreview: { _, _ in "" },
                executeCommit: { _, _ in }
            )
        )

        viewModel.refreshChangesSnapshot()

        let loaded = await waitUntil(timeout: 1.5) {
            viewModel.changesSnapshot(forRepositoryGroupID: repoAFamily.id)?.changes.count == 1 &&
                viewModel.changesSnapshot(forRepositoryGroupID: repoBFamily.id)?.changes.count == 1
        }
        XCTAssertTrue(loaded)

        viewModel.toggleInclusion(for: "Sources/App.swift", repositoryGroupID: repoBFamily.id)
        viewModel.commitMessage = "Cross repo selection"

        XCTAssertEqual(viewModel.includedPaths, [])
        XCTAssertEqual(viewModel.includedPathsByRepositoryGroupID[repoBFamily.id], Set(["Sources/App.swift"]))
        XCTAssertEqual(viewModel.totalIncludedPathCount, 1)
        XCTAssertTrue(viewModel.canExecuteCommit(action: .commit))

        viewModel.selectRepositoryFamily(repoBFamily.id)

        XCTAssertEqual(viewModel.repositoryContext.selectedRepositoryFamilyID, repoBFamily.id)
        XCTAssertEqual(viewModel.includedPaths, Set(["Sources/App.swift"]))

        viewModel.selectRepositoryFamily(repoAFamily.id)

        XCTAssertEqual(viewModel.repositoryContext.selectedRepositoryFamilyID, repoAFamily.id)
        XCTAssertEqual(viewModel.includedPaths, [])
        XCTAssertEqual(viewModel.includedPathsByRepositoryGroupID[repoBFamily.id], Set(["Sources/App.swift"]))
    }

    func testExecuteCommitRunsForEachIncludedRepositoryGroup() async throws {
        let repoAPath = "/tmp/devhaven-commit-multi-a"
        let repoBPath = "/tmp/devhaven-commit-multi-b"
        let repoAFamily = Self.makeRepositoryFamily(
            id: "family-a",
            displayName: "repo-a",
            path: repoAPath,
            branchName: "main"
        )
        let repoBFamily = Self.makeRepositoryFamily(
            id: "family-b",
            displayName: "repo-b",
            path: repoBPath,
            branchName: "feature/demo"
        )
        let snapshotBox = LockedBox(
            [
                repoAPath: Self.makeSnapshot(
                    branchName: "main",
                    changes: [
                        WorkspaceCommitChange(
                            path: "README.md",
                            status: .modified,
                            group: .unstaged,
                            isIncludedByDefault: false
                        )
                    ]
                ),
                repoBPath: Self.makeSnapshot(
                    branchName: "feature/demo",
                    changes: [
                        WorkspaceCommitChange(
                            path: "Sources/App.swift",
                            status: .modified,
                            group: .unstaged,
                            isIncludedByDefault: false
                        )
                    ]
                )
            ]
        )
        let executedRequestsBox = LockedBox<[(String, WorkspaceCommitExecutionRequest)]>([])

        let viewModel = WorkspaceCommitViewModel(
            repositoryContext: WorkspaceCommitRepositoryContext(
                rootProjectPath: "/tmp/workspace",
                repositoryPath: repoAPath,
                executionPath: repoAPath,
                repositoryFamilies: [repoAFamily, repoBFamily],
                selectedRepositoryFamilyID: repoAFamily.id
            ),
            client: .init(
                loadChangesSnapshot: { path in
                    snapshotBox.value[path] ?? Self.makeSnapshot(branchName: nil, changes: [])
                },
                loadDiffPreview: { _, _ in "" },
                executeCommit: { path, request in
                    var executedRequests = executedRequestsBox.value
                    executedRequests.append((path, request))
                    executedRequestsBox.value = executedRequests

                    var snapshots = snapshotBox.value
                    snapshots[path] = Self.makeSnapshot(branchName: snapshots[path]?.branchName, changes: [])
                    snapshotBox.value = snapshots
                }
            )
        )

        viewModel.refreshChangesSnapshot()

        let loaded = await waitUntil(timeout: 1.5) {
            viewModel.changesSnapshot(forRepositoryGroupID: repoAFamily.id)?.changes.count == 1 &&
                viewModel.changesSnapshot(forRepositoryGroupID: repoBFamily.id)?.changes.count == 1
        }
        XCTAssertTrue(loaded)

        viewModel.toggleInclusion(for: "README.md", repositoryGroupID: repoAFamily.id)
        viewModel.toggleInclusion(for: "Sources/App.swift", repositoryGroupID: repoBFamily.id)
        viewModel.commitMessage = "Ship multi repo commit"

        viewModel.executeCommit(action: .commit)

        let finished = await waitUntil(timeout: 1.5) {
            viewModel.executionState == .succeeded(.commit) &&
                viewModel.changesSnapshot(forRepositoryGroupID: repoAFamily.id)?.changes.isEmpty == true &&
                viewModel.changesSnapshot(forRepositoryGroupID: repoBFamily.id)?.changes.isEmpty == true &&
                viewModel.totalIncludedPathCount == 0
        }
        XCTAssertTrue(finished)

        let recordedRequests = executedRequestsBox.value

        XCTAssertEqual(recordedRequests.map(\.0), [repoAPath, repoBPath])
        XCTAssertEqual(recordedRequests.map(\.1.includedPaths), [["README.md"], ["Sources/App.swift"]])
        XCTAssertTrue(recordedRequests.allSatisfy { $0.1.message == "Ship multi repo commit" })
        XCTAssertNil(viewModel.errorMessage)
    }

    func testVisibleRepositoryGroupSummariesExcludeGroupsWithoutChanges() async throws {
        let repoAPath = "/tmp/devhaven-commit-visible-a"
        let repoBPath = "/tmp/devhaven-commit-visible-b"
        let repoAFamily = Self.makeRepositoryFamily(
            id: "family-a",
            displayName: "repo-a",
            path: repoAPath,
            branchName: "main"
        )
        let repoBFamily = Self.makeRepositoryFamily(
            id: "family-b",
            displayName: "repo-b",
            path: repoBPath,
            branchName: "feature/demo"
        )

        let viewModel = WorkspaceCommitViewModel(
            repositoryContext: WorkspaceCommitRepositoryContext(
                rootProjectPath: "/tmp/workspace",
                repositoryPath: repoAPath,
                executionPath: repoAPath,
                repositoryFamilies: [repoAFamily, repoBFamily],
                selectedRepositoryFamilyID: repoAFamily.id
            ),
            client: .init(
                loadChangesSnapshot: { path in
                    switch path {
                    case repoAPath:
                        return Self.makeSnapshot(branchName: "main", changes: [])
                    case repoBPath:
                        return Self.makeSnapshot(
                            branchName: "feature/demo",
                            changes: [
                                WorkspaceCommitChange(
                                    path: "Sources/App.swift",
                                    status: .modified,
                                    group: .unstaged,
                                    isIncludedByDefault: false
                                )
                            ]
                        )
                    default:
                        XCTFail("unexpected path \(path)")
                        return Self.makeSnapshot(branchName: nil, changes: [])
                    }
                },
                loadDiffPreview: { _, _ in "" },
                executeCommit: { _, _ in }
            )
        )

        viewModel.refreshChangesSnapshot()

        let loaded = await waitUntil(timeout: 1.5) {
            viewModel.repositoryGroupSummaries.count == 2 &&
                viewModel.visibleRepositoryGroupSummaries.count == 1
        }
        XCTAssertTrue(loaded)
        XCTAssertEqual(viewModel.visibleRepositoryGroupSummaries.map(\.id), [repoBFamily.id])
        XCTAssertEqual(viewModel.visibleRepositoryGroupSummaries.first?.changeCount, 1)
    }

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

    private nonisolated static func makeRepositoryContext(path: String) -> WorkspaceCommitRepositoryContext {
        WorkspaceCommitRepositoryContext(
            rootProjectPath: path,
            repositoryPath: path,
            executionPath: path
        )
    }

    private nonisolated static func makeRepositoryFamily(
        id: String,
        displayName: String,
        path: String,
        branchName: String?
    ) -> WorkspaceGitRepositoryFamilyContext {
        WorkspaceGitRepositoryFamilyContext(
            id: id,
            displayName: displayName,
            repositoryPath: path,
            preferredExecutionPath: path,
            members: [
                WorkspaceGitWorktreeContext(
                    path: path,
                    displayName: displayName,
                    branchName: branchName,
                    isRootProject: true
                )
            ]
        )
    }

    private nonisolated static func makeSnapshot(
        branchName: String?,
        changes: [WorkspaceCommitChange]
    ) -> WorkspaceCommitChangesSnapshot {
        WorkspaceCommitChangesSnapshot(branchName: branchName, changes: changes)
    }
}

private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: T

    init(_ storage: T) {
        self.storage = storage
    }

    var value: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}
