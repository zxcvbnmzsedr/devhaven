import XCTest
@testable import DevHavenCore

final class WorkspaceAgentSignalStoreTests: XCTestCase {
    func testStoreLoadsSignalsFromSessionDirectory() throws {
        let rootURL = try makeHomeDirectory()
        let sessionsDirectoryURL = rootURL
            .appending(path: ".devhaven", directoryHint: .isDirectory)
            .appending(path: "agent-status", directoryHint: .isDirectory)
            .appending(path: "sessions", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionsDirectoryURL, withIntermediateDirectories: true)

        let signal = makeSignal(
            terminalSessionId: "session:1",
            state: .running,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try writeSignal(signal, to: sessionsDirectoryURL)

        let store = WorkspaceAgentSignalStore(baseDirectoryURL: sessionsDirectoryURL)
        let snapshots = try store.reloadForTesting()

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots["session:1"]?.state, .running)
        XCTAssertEqual(snapshots["session:1"]?.summary, "running summary")
    }

    func testStorePrunesStaleRunningSignalsWhenProcessIsGone() throws {
        let rootURL = try makeHomeDirectory()
        let sessionsDirectoryURL = rootURL
            .appending(path: ".devhaven", directoryHint: .isDirectory)
            .appending(path: "agent-status", directoryHint: .isDirectory)
            .appending(path: "sessions", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionsDirectoryURL, withIntermediateDirectories: true)

        let stale = makeSignal(
            terminalSessionId: "session:stale",
            state: .running,
            pid: 99999,
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let signalFileName = WorkspaceAgentSignalStore.signalFileName(for: stale.terminalSessionId)
        try writeSignal(stale, to: sessionsDirectoryURL)

        let store = WorkspaceAgentSignalStore(baseDirectoryURL: sessionsDirectoryURL)
        _ = try store.reloadForTesting()
        try store.sweepStaleSignals(
            now: Date(timeIntervalSince1970: 100),
            processAlive: { _ in false }
        )

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: sessionsDirectoryURL.appending(path: signalFileName).path
            )
        )
        XCTAssertTrue(store.snapshotsByTerminalSessionID.isEmpty)
    }

    func testStorePrunesStaleRunningSignalsWhenTerminalSessionIdContainsSlash() throws {
        let rootURL = try makeHomeDirectory()
        let sessionsDirectoryURL = rootURL
            .appending(path: ".devhaven", directoryHint: .isDirectory)
            .appending(path: "agent-status", directoryHint: .isDirectory)
            .appending(path: "sessions", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionsDirectoryURL, withIntermediateDirectories: true)

        let stale = makeSignal(
            terminalSessionId: "workspace:slash/session:1",
            state: .running,
            pid: 99999,
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let signalFileName = WorkspaceAgentSignalStore.signalFileName(for: stale.terminalSessionId)
        try writeSignal(stale, to: sessionsDirectoryURL, fileName: signalFileName)

        let store = WorkspaceAgentSignalStore(baseDirectoryURL: sessionsDirectoryURL)
        _ = try store.reloadForTesting()
        try store.sweepStaleSignals(
            now: Date(timeIntervalSince1970: 100),
            processAlive: { _ in false }
        )

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: sessionsDirectoryURL.appending(path: signalFileName).path
            )
        )
        XCTAssertTrue(store.snapshotsByTerminalSessionID.isEmpty)
    }

    func testSweepStaleSignalsCanBeCalledFromStoreQueueWithoutReentrantSyncCrash() throws {
        let rootURL = try makeHomeDirectory()
        let sessionsDirectoryURL = rootURL
            .appending(path: ".devhaven", directoryHint: .isDirectory)
            .appending(path: "agent-status", directoryHint: .isDirectory)
            .appending(path: "sessions", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionsDirectoryURL, withIntermediateDirectories: true)

        let stale = makeSignal(
            terminalSessionId: "session:reentrant-sweep",
            state: .running,
            pid: 99999,
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        try writeSignal(stale, to: sessionsDirectoryURL)

        let store = WorkspaceAgentSignalStore(baseDirectoryURL: sessionsDirectoryURL)
        _ = try store.reloadForTesting()

        let snapshots = try store.performOnStoreQueueForTesting {
            try store.sweepStaleSignals(
                now: Date(timeIntervalSince1970: 100),
                processAlive: { _ in false }
            )
        }

        XCTAssertTrue(snapshots.isEmpty)
        XCTAssertTrue(store.currentSnapshots.isEmpty)
    }

    func testReloadForTestingCanBeCalledFromStoreQueueWithoutReentrantSyncCrash() throws {
        let rootURL = try makeHomeDirectory()
        let sessionsDirectoryURL = rootURL
            .appending(path: ".devhaven", directoryHint: .isDirectory)
            .appending(path: "agent-status", directoryHint: .isDirectory)
            .appending(path: "sessions", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionsDirectoryURL, withIntermediateDirectories: true)

        let signal = makeSignal(
            terminalSessionId: "session:reentrant-reload",
            state: .waiting,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try writeSignal(signal, to: sessionsDirectoryURL)

        let store = WorkspaceAgentSignalStore(baseDirectoryURL: sessionsDirectoryURL)

        let snapshots = try store.performOnStoreQueueForTesting {
            try store.reloadForTesting()
        }

        XCTAssertEqual(snapshots["session:reentrant-reload"]?.state, .waiting)
        XCTAssertEqual(store.currentSnapshots["session:reentrant-reload"]?.state, .waiting)
    }

    func testCompletedSignalFallsBackToIdleAfterRetentionDuringSweep() throws {
        let rootURL = try makeHomeDirectory()
        let sessionsDirectoryURL = rootURL
            .appending(path: ".devhaven", directoryHint: .isDirectory)
            .appending(path: "agent-status", directoryHint: .isDirectory)
            .appending(path: "sessions", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionsDirectoryURL, withIntermediateDirectories: true)

        let createdAt = Date()
        let signal = makeSignal(
            terminalSessionId: "session:completed-retention",
            state: .completed,
            updatedAt: createdAt
        )
        try writeSignal(signal, to: sessionsDirectoryURL)

        let store = WorkspaceAgentSignalStore(baseDirectoryURL: sessionsDirectoryURL)
        let initialSnapshots = try store.reloadForTesting()
        XCTAssertEqual(initialSnapshots["session:completed-retention"]?.state, .completed)

        let snapshots = try store.sweepStaleSignals(
            now: createdAt.addingTimeInterval(100),
            processAlive: { _ in false }
        )

        XCTAssertEqual(snapshots["session:completed-retention"]?.state, .idle)
        XCTAssertNil(snapshots["session:completed-retention"]?.summary)
        XCTAssertNil(snapshots["session:completed-retention"]?.detail)
        XCTAssertNil(snapshots["session:completed-retention"]?.pid)
    }

    func testReloadSkipsMalformedSignalFilesAndKeepsValidSnapshots() throws {
        let rootURL = try makeHomeDirectory()
        let sessionsDirectoryURL = rootURL
            .appending(path: ".devhaven", directoryHint: .isDirectory)
            .appending(path: "agent-status", directoryHint: .isDirectory)
            .appending(path: "sessions", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionsDirectoryURL, withIntermediateDirectories: true)

        let validSignal = makeSignal(
            terminalSessionId: "session:valid",
            state: .running,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try writeSignal(validSignal, to: sessionsDirectoryURL)
        try "{ invalid json".write(
            to: sessionsDirectoryURL.appending(path: "broken.json"),
            atomically: true,
            encoding: .utf8
        )

        let store = WorkspaceAgentSignalStore(baseDirectoryURL: sessionsDirectoryURL)
        let snapshots = try store.reloadForTesting()

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots["session:valid"]?.state, .running)
    }

    private func makeSignal(
        terminalSessionId: String,
        state: WorkspaceAgentState,
        pid: Int32? = 42,
        updatedAt: Date
    ) -> WorkspaceAgentSessionSignal {
        WorkspaceAgentSessionSignal(
            projectPath: "/tmp/devhaven",
            workspaceId: "workspace:test",
            tabId: "tab:test",
            paneId: "pane:test",
            surfaceId: "surface:test",
            terminalSessionId: terminalSessionId,
            agentKind: .claude,
            sessionId: "agent-session-\(terminalSessionId)",
            pid: pid,
            state: state,
            summary: "\(state.rawValue) summary",
            detail: nil,
            updatedAt: updatedAt
        )
    }

    private func writeSignal(
        _ signal: WorkspaceAgentSessionSignal,
        to directoryURL: URL,
        fileName: String? = nil
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(signal)
        try data.write(
            to: directoryURL.appending(
                path: fileName ?? WorkspaceAgentSignalStore.signalFileName(for: signal.terminalSessionId)
            ),
            options: .atomic
        )
    }

    private func makeHomeDirectory() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        return rootURL
    }
}
