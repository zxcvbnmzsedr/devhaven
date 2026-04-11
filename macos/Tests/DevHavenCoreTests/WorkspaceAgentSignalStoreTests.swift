import Foundation
import XCTest
@testable import DevHavenCore

final class WorkspaceAgentSignalStoreTests: XCTestCase {
    func testReloadForTestingReusesCachedSignalsForUnchangedFiles() throws {
        let tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectoryURL) }

        let signalA = makeSignal(
            terminalSessionId: "terminal-a",
            state: .running,
            summary: "first"
        )
        let signalB = makeSignal(
            terminalSessionId: "terminal-b",
            state: .waiting,
            summary: "second"
        )
        try writeSignal(signalA, baseDirectoryURL: tempDirectoryURL)
        try writeSignal(signalB, baseDirectoryURL: tempDirectoryURL)

        let loadCounter = LoadCounter()
        let store = WorkspaceAgentSignalStore(
            baseDirectoryURL: tempDirectoryURL,
            signalLoader: { url in
                loadCounter.increment()
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode(WorkspaceAgentSessionSignal.self, from: data)
            }
        )

        let firstReload = try store.reloadForTesting()
        XCTAssertEqual(firstReload.count, 2)
        XCTAssertEqual(loadCounter.value, 2)

        let secondReload = try store.reloadForTesting()
        XCTAssertEqual(secondReload.count, 2)
        XCTAssertEqual(loadCounter.value, 2, "未变化的 signal 文件应直接命中缓存，不重复 decode")

        var updatedSignalA = signalA
        updatedSignalA.summary = "first-updated-with-longer-content"
        updatedSignalA.updatedAt = signalA.updatedAt.addingTimeInterval(1)
        try writeSignal(updatedSignalA, baseDirectoryURL: tempDirectoryURL)

        let thirdReload = try store.reloadForTesting()
        XCTAssertEqual(thirdReload["terminal-a"]?.summary, updatedSignalA.summary)
        XCTAssertEqual(loadCounter.value, 3, "只有变更过的 signal 文件需要重新 decode")

        let signalBURL = tempDirectoryURL.appendingPathComponent(
            WorkspaceAgentSignalStore.signalFileName(for: signalB.terminalSessionId)
        )
        try FileManager.default.removeItem(at: signalBURL)

        let fourthReload = try store.reloadForTesting()
        XCTAssertEqual(fourthReload.count, 1)
        XCTAssertNil(fourthReload["terminal-b"])
        XCTAssertEqual(loadCounter.value, 3, "删除文件不应导致未变化的剩余 signal 重新 decode")
    }

    func testStartCoalescesBurstDirectoryEventsIntoSingleReload() throws {
        let tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectoryURL) }

        let notificationCounter = LoadCounter()
        let expectedSummary = "third"
        let store = WorkspaceAgentSignalStore(
            baseDirectoryURL: tempDirectoryURL,
            reloadDebounceNanoseconds: 40_000_000
        )
        defer { store.stop() }

        let firstSignalExpectation = expectation(description: "signal change published")
        firstSignalExpectation.assertForOverFulfill = false
        store.onSignalsChange = { snapshots in
            notificationCounter.increment()
            if snapshots["terminal-a"]?.summary == expectedSummary {
                firstSignalExpectation.fulfill()
            }
        }

        try store.start()

        try writeSignal(
            makeSignal(
                terminalSessionId: "terminal-a",
                state: .running,
                summary: "first"
            ),
            baseDirectoryURL: tempDirectoryURL
        )
        Thread.sleep(forTimeInterval: 0.005)
        try writeSignal(
            makeSignal(
                terminalSessionId: "terminal-a",
                state: .running,
                summary: "second"
            ),
            baseDirectoryURL: tempDirectoryURL
        )
        Thread.sleep(forTimeInterval: 0.005)
        try writeSignal(
            makeSignal(
                terminalSessionId: "terminal-a",
                state: .running,
                summary: expectedSummary
            ),
            baseDirectoryURL: tempDirectoryURL
        )

        wait(for: [firstSignalExpectation], timeout: 2)
        Thread.sleep(forTimeInterval: 0.2)

        XCTAssertEqual(notificationCounter.value, 1, "突发目录事件应在 debounce 窗口内合并成一次 reload/通知")
        XCTAssertEqual(store.currentSnapshots["terminal-a"]?.summary, expectedSummary)
    }

    func testCompletedSignalsNormalizeBackToIdleAndClearRicherMetadataAfterRetention() throws {
        let tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectoryURL) }

        let store = WorkspaceAgentSignalStore(
            baseDirectoryURL: tempDirectoryURL,
            completedSignalRetentionInterval: 0
        )

        var signal = makeSignal(
            terminalSessionId: "terminal-finished",
            state: .completed,
            summary: "done"
        )
        signal.phase = .completed
        signal.attention = .error
        signal.toolName = "Bash"
        signal.updatedAt = Date(timeIntervalSince1970: 1)
        try writeSignal(signal, baseDirectoryURL: tempDirectoryURL)

        let snapshots = try store.reloadForTesting()
        XCTAssertEqual(snapshots["terminal-finished"]?.state, .idle)
        XCTAssertEqual(snapshots["terminal-finished"]?.phase, .idle)
        XCTAssertEqual(snapshots["terminal-finished"]?.attention, WorkspaceAgentAttentionRequirement.none)
        XCTAssertNil(snapshots["terminal-finished"]?.toolName)
        XCTAssertNil(snapshots["terminal-finished"]?.summary)
        XCTAssertNil(snapshots["terminal-finished"]?.detail)
    }

    private func writeSignal(
        _ signal: WorkspaceAgentSessionSignal,
        baseDirectoryURL: URL
    ) throws {
        let url = baseDirectoryURL.appendingPathComponent(
            WorkspaceAgentSignalStore.signalFileName(for: signal.terminalSessionId)
        )
        let data = try JSONEncoder().encode(signal)
        try data.write(to: url, options: .atomic)
    }

    private func makeSignal(
        terminalSessionId: String,
        state: WorkspaceAgentState,
        summary: String
    ) -> WorkspaceAgentSessionSignal {
        WorkspaceAgentSessionSignal(
            projectPath: "/tmp/project",
            workspaceId: "workspace",
            tabId: "tab",
            paneId: "pane",
            surfaceId: "surface",
            terminalSessionId: terminalSessionId,
            agentKind: .codex,
            sessionId: "session-\(terminalSessionId)",
            pid: 123,
            state: state,
            summary: summary,
            detail: "detail-\(summary)",
            updatedAt: Date(timeIntervalSince1970: 1_710_000_000)
        )
    }
}

private final class LoadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
