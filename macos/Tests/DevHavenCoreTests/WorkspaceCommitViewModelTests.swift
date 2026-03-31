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
