import XCTest
@testable import DevHavenCore

final class WorkspaceRunLogStoreTests: XCTestCase {
    func testCreateLogFilePlacesFileUnderRunLogsDirectory() throws {
        let homeURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = WorkspaceRunLogStore(baseDirectoryURL: homeURL)

        let fileURL = try store.createLogFile(scriptName: "npm run dev", sessionID: "session-1")

        XCTAssertTrue(fileURL.path.contains(".devhaven/run-logs"))
        XCTAssertEqual(fileURL.pathExtension, "log")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "创建 session 时应同步预建日志文件")
    }

    func testAppendPersistsChunksInOrder() throws {
        let homeURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = WorkspaceRunLogStore(baseDirectoryURL: homeURL)
        let fileURL = try store.createLogFile(scriptName: "worker", sessionID: "session-2")

        try store.append("hello\n", to: fileURL)
        try store.append("world\n", to: fileURL)

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(content, "hello\nworld\n")
    }

    func testConsoleStateFallsBackToLatestSessionWhenSelectionMissing() {
        let first = WorkspaceRunSession(
            id: "session-1",
            configurationID: "project::/tmp/devhaven::dev",
            configurationName: "Dev",
            configurationSource: .projectScript,
            projectPath: "/tmp/devhaven",
            rootProjectPath: "/tmp/devhaven",
            command: "npm run dev",
            workingDirectory: "/tmp/devhaven",
            state: .running,
            processID: 101,
            logFilePath: "/tmp/session-1.log",
            startedAt: Date(timeIntervalSince1970: 10),
            endedAt: nil,
            displayBuffer: "first"
        )
        let second = WorkspaceRunSession(
            id: "session-2",
            configurationID: "project::/tmp/devhaven::worker",
            configurationName: "Worker",
            configurationSource: .projectScript,
            projectPath: "/tmp/devhaven",
            rootProjectPath: "/tmp/devhaven",
            command: "python worker.py",
            workingDirectory: "/tmp/devhaven",
            state: .completed(exitCode: 0),
            processID: 102,
            logFilePath: "/tmp/session-2.log",
            startedAt: Date(timeIntervalSince1970: 20),
            endedAt: Date(timeIntervalSince1970: 30),
            displayBuffer: "second"
        )

        let state = WorkspaceRunConsoleState(
            sessions: [first, second],
            selectedSessionID: "missing",
            selectedConfigurationID: "project::/tmp/devhaven::worker",
            isVisible: true
        )

        XCTAssertEqual(state.selectedSession?.id, second.id, "当前选中 session 丢失时，应回退到最近创建的 session，避免底部日志面板直接空白")
        XCTAssertEqual(state.runningSessionCount, 1)
    }
}
