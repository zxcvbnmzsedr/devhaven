import XCTest
@testable import DevHavenCore

@MainActor
final class WorkspaceRunManagerTests: XCTestCase {
    func testStartStreamsOutputAndCompletesSuccessfully() throws {
        let logStore = WorkspaceRunLogStore(baseDirectoryURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
        let manager = WorkspaceRunManager(logStore: logStore)
        let finished = expectation(description: "run finished")
        let sawOutput = expectation(description: "run output")
        let capture = RunEventCapture()

        manager.onEvent = { event in
            switch event {
            case let .output(_, _, chunk):
                capture.appendOutput(chunk)
                if capture.output.contains("world") {
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
                configurationSource: .projectScript,
                projectPath: "/tmp/devhaven",
                rootProjectPath: "/tmp/devhaven",
                command: "printf 'hello\\nworld\\n'; sleep 0.2",
                workingDirectory: "/tmp"
            )
        )

        XCTAssertEqual(session.state, .running)
        wait(for: [sawOutput, finished], timeout: 5)

        XCTAssertEqual(capture.finalState, .completed(exitCode: 0))
        XCTAssertEqual(capture.output, "hello\nworld\n")
        XCTAssertNotNil(session.logFilePath)
        let logContent = try String(contentsOfFile: try XCTUnwrap(session.logFilePath), encoding: .utf8)
        XCTAssertEqual(logContent, "hello\nworld\n")
    }

    func testStopMarksSessionAsStopped() throws {
        let logStore = WorkspaceRunLogStore(baseDirectoryURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
        let manager = WorkspaceRunManager(logStore: logStore)
        let stopped = expectation(description: "run stopped")
        let capture = RunEventCapture()

        manager.onEvent = { event in
            if case let .stateChanged(_, _, state) = event {
                capture.appendState(state)
                if state == .stopped {
                    stopped.fulfill()
                }
            }
        }

        let session = try manager.start(
            WorkspaceRunStartRequest(
                sessionID: "session-2",
                configurationID: "project::/tmp/devhaven::watch",
                configurationName: "Watch",
                configurationSource: .projectScript,
                projectPath: "/tmp/devhaven",
                rootProjectPath: "/tmp/devhaven",
                command: "trap 'exit 0' INT TERM; while true; do sleep 0.1; done",
                workingDirectory: "/tmp"
            )
        )

        manager.stop(sessionID: session.id)
        wait(for: [stopped], timeout: 5)

        XCTAssertTrue(capture.states.contains(.stopping))
        XCTAssertEqual(capture.states.last, .stopped)
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
