import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceRunManagerTests: XCTestCase {
    func testStartStreamsOutputAndCompletesSuccessfully() throws {
        let logStore = WorkspaceRunLogStore(baseDirectoryURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
        let manager = WorkspaceRunManager(logStore: logStore)
        defer { manager.onEvent = nil }
        let finished = expectation(description: "run finished")
        let sawOutput = expectation(description: "run output")
        let capture = RunEventCapture()
        var didSeeOutput = false

        manager.onEvent = { event in
            switch event {
            case let .output(_, _, chunk):
                capture.appendOutput(chunk)
                if !didSeeOutput, capture.output.contains("world") {
                    didSeeOutput = true
                    sawOutput.fulfill()
                }
            case let .stateChanged(_, _, state):
                if case .completed = state {
                    capture.setFinalState(state)
                    finished.fulfill()
                }
            }
        }

        let session = try manager.start(
            WorkspaceRunStartRequest(
                sessionID: "session-1",
                configurationID: "project::/tmp/devhaven::dev",
                configurationName: "Dev",
                configurationSource: .projectRunConfiguration,
                projectPath: "/tmp/devhaven",
                rootProjectPath: "/tmp/devhaven",
                executable: .shell(command: "printf 'hello\\nworld\\n'; sleep 0.2"),
                displayCommand: "printf 'hello\\nworld\\n'; sleep 0.2",
                workingDirectory: "/tmp"
            )
        )

        XCTAssertEqual(session.state, .running)
        wait(for: [sawOutput, finished], timeout: 5)

        XCTAssertEqual(capture.finalState, .completed(exitCode: 0))
        XCTAssertTrue(capture.output.contains("[DevHaven] 执行命令："))
        XCTAssertTrue(capture.output.hasSuffix("hello\nworld\n"))
        XCTAssertNotNil(session.logFilePath)
        let logContent = try String(contentsOfFile: try XCTUnwrap(session.logFilePath), encoding: .utf8)
        XCTAssertTrue(logContent.contains("[DevHaven] 执行目录：/tmp"))
        XCTAssertTrue(logContent.hasSuffix("hello\nworld\n"))
    }

    func testStopMarksSessionAsStopped() throws {
        let logStore = WorkspaceRunLogStore(baseDirectoryURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
        let manager = WorkspaceRunManager(logStore: logStore)
        defer { manager.onEvent = nil }
        let stopped = expectation(description: "run stopped")
        let capture = RunEventCapture()
        var didStop = false

        manager.onEvent = { event in
            if case let .stateChanged(_, _, state) = event {
                capture.appendState(state)
                if !didStop, state == .stopped {
                    didStop = true
                    stopped.fulfill()
                }
            }
        }

        let session = try manager.start(
            WorkspaceRunStartRequest(
                sessionID: "session-2",
                configurationID: "project::/tmp/devhaven::watch",
                configurationName: "Watch",
                configurationSource: .projectRunConfiguration,
                projectPath: "/tmp/devhaven",
                rootProjectPath: "/tmp/devhaven",
                executable: .shell(command: "trap 'exit 0' INT TERM; while true; do sleep 0.1; done"),
                displayCommand: "trap 'exit 0' INT TERM; while true; do sleep 0.1; done",
                workingDirectory: "/tmp"
            )
        )

        manager.stop(sessionID: session.id)
        wait(for: [stopped], timeout: 5)

        XCTAssertTrue(capture.states.contains(.stopping))
        XCTAssertEqual(capture.states.last, .stopped)
    }

    func testStartSupportsMultilineCommandsWithAssignmentsBeforeInnerExec() throws {
        let logStore = WorkspaceRunLogStore(baseDirectoryURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
        let manager = WorkspaceRunManager(logStore: logStore)
        defer { manager.onEvent = nil }
        let finished = expectation(description: "run finished")
        let sawOutput = expectation(description: "run output")
        let capture = RunEventCapture()
        var didSeeOutput = false

        manager.onEvent = { event in
            switch event {
            case let .output(_, _, chunk):
                capture.appendOutput(chunk)
                if !didSeeOutput, capture.output.contains("WwS6P6AzfKHu") {
                    didSeeOutput = true
                    sawOutput.fulfill()
                }
            case let .stateChanged(_, _, state):
                capture.appendState(state)
                if case .completed = state {
                    capture.setFinalState(state)
                    finished.fulfill()
                }
            }
        }

        let session = try manager.start(
            WorkspaceRunStartRequest(
                sessionID: "session-3",
                configurationID: "project::/tmp/devhaven::remote-log",
                configurationName: "Remote Log",
                configurationSource: .projectRunConfiguration,
                projectPath: "/tmp/devhaven",
                rootProjectPath: "/tmp/devhaven",
                executable: .shell(command: """
                password='WwS6P6AzfKHu'
                exec printf '%s\\n' \"$password\"
                """),
                displayCommand: """
                password='WwS6P6AzfKHu'
                exec printf '%s\\n' \"$password\"
                """,
                workingDirectory: "/tmp"
            )
        )

        XCTAssertEqual(session.state, .running)
        wait(for: [sawOutput, finished], timeout: 5)

        XCTAssertEqual(capture.finalState, .completed(exitCode: 0))
        XCTAssertTrue(capture.output.contains("[DevHaven] 执行命令："))
        XCTAssertTrue(capture.output.hasSuffix("WwS6P6AzfKHu\n"))
    }

    func testStartLogsResolvedCommandAndWorkingDirectoryBeforeProcessOutput() throws {
        let logStore = WorkspaceRunLogStore(baseDirectoryURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
        let manager = WorkspaceRunManager(logStore: logStore)
        defer { manager.onEvent = nil }
        let finished = expectation(description: "run finished")
        let sawCommandHeader = expectation(description: "command header")
        let sawProcessOutput = expectation(description: "process output")
        let capture = RunEventCapture()
        var didSeeCommandHeader = false
        var didSeeProcessOutput = false

        manager.onEvent = { event in
            switch event {
            case let .output(_, _, chunk):
                capture.appendOutput(chunk)
                if !didSeeCommandHeader, chunk.contains("[DevHaven] 执行命令：") {
                    didSeeCommandHeader = true
                    sawCommandHeader.fulfill()
                }
                if !didSeeProcessOutput, chunk.contains("ok\n") {
                    didSeeProcessOutput = true
                    sawProcessOutput.fulfill()
                }
            case let .stateChanged(_, _, state):
                if case .completed = state {
                    capture.setFinalState(state)
                    finished.fulfill()
                }
            }
        }

        let session = try manager.start(
            WorkspaceRunStartRequest(
                sessionID: "session-4",
                configurationID: "project::/tmp/devhaven::inspect",
                configurationName: "Inspect",
                configurationSource: .projectRunConfiguration,
                projectPath: "/tmp/devhaven",
                rootProjectPath: "/tmp/devhaven",
                executable: .shell(command: "printf 'ok\\n'; sleep 0.1"),
                displayCommand: "printf 'ok\\n'; sleep 0.1",
                workingDirectory: "/tmp"
            )
        )

        XCTAssertEqual(session.state, .running)
        wait(for: [sawCommandHeader, sawProcessOutput, finished], timeout: 5)

        let output = capture.output
        XCTAssertTrue(output.contains("[DevHaven] 执行目录：/tmp"))
        XCTAssertTrue(output.contains("[DevHaven] 执行命令："))
        XCTAssertTrue(output.contains("printf 'ok\\n'; sleep 0.1"))
        XCTAssertTrue(output.contains("ok\n"))

        let logContent = try String(contentsOfFile: try XCTUnwrap(session.logFilePath), encoding: .utf8)
        XCTAssertTrue(logContent.contains("[DevHaven] 执行目录：/tmp"))
        XCTAssertTrue(logContent.contains("printf 'ok\\n'; sleep 0.1"))
    }

    func testStartSupportsProcessExecutableAndLogsDisplayCommand() throws {
        let logStore = WorkspaceRunLogStore(baseDirectoryURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
        let manager = WorkspaceRunManager(logStore: logStore)
        defer { manager.onEvent = nil }
        let finished = expectation(description: "run finished")
        let sawOutput = expectation(description: "run output")
        let capture = RunEventCapture()
        var didSeeOutput = false

        manager.onEvent = { event in
            switch event {
            case let .output(_, _, chunk):
                capture.appendOutput(chunk)
                if !didSeeOutput, chunk.contains("hello-process") {
                    didSeeOutput = true
                    sawOutput.fulfill()
                }
            case let .stateChanged(_, _, state):
                if case .completed = state {
                    capture.setFinalState(state)
                    finished.fulfill()
                }
            }
        }

        let session = try manager.start(
            WorkspaceRunStartRequest(
                sessionID: "session-5",
                configurationID: "project::/tmp/devhaven::process",
                configurationName: "Process",
                configurationSource: .projectRunConfiguration,
                projectPath: "/tmp/devhaven",
                rootProjectPath: "/tmp/devhaven",
                executable: .process(program: "/bin/echo", arguments: ["hello-process"]),
                displayCommand: "/bin/echo hello-process",
                workingDirectory: "/tmp"
            )
        )

        XCTAssertEqual(session.state, .running)
        wait(for: [sawOutput, finished], timeout: 5)
        XCTAssertEqual(capture.finalState, .completed(exitCode: 0))
        XCTAssertTrue(capture.output.contains("[DevHaven] 执行命令："))
        XCTAssertTrue(capture.output.contains("/bin/echo hello-process"))
        XCTAssertTrue(capture.output.contains("hello-process"))
    }
}

private final class RunEventCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var mutableOutput = ""
    private var mutableFinalState: WorkspaceRunSessionState?
    private var mutableStates = [WorkspaceRunSessionState]()

    var output: String {
        lock.withLock { mutableOutput }
    }

    var finalState: WorkspaceRunSessionState? {
        lock.withLock { mutableFinalState }
    }

    var states: [WorkspaceRunSessionState] {
        lock.withLock { mutableStates }
    }

    func appendOutput(_ chunk: String) {
        lock.withLock {
            mutableOutput += chunk
        }
    }

    func setFinalState(_ state: WorkspaceRunSessionState) {
        lock.withLock {
            mutableFinalState = state
        }
    }

    func appendState(_ state: WorkspaceRunSessionState) {
        lock.withLock {
            mutableStates.append(state)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
