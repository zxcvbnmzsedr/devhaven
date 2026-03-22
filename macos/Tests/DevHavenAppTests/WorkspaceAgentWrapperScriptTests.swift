import XCTest
@testable import DevHavenApp
@testable import DevHavenCore

final class WorkspaceAgentWrapperScriptTests: XCTestCase {
    func testCodexNotifyScriptWritesWaitingSignalFromTurnCompletePayload() throws {
        let fixture = try makeFixture()

        let output = try runScript(
            fixture.codexNotifyPath,
            arguments: [
                #"{"type":"agent-turn-complete","session_id":"codex-session-1","last-assistant-message":"已完成当前回合"}"#
            ],
            environment: fixture.environment
        )

        XCTAssertEqual(output.status, 0, output.stderr)

        let signal = try fixture.readSignal()
        XCTAssertEqual(signal.agentKind, .codex)
        XCTAssertEqual(signal.state, .waiting)
        XCTAssertEqual(signal.sessionId, "codex-session-1")
        XCTAssertEqual(signal.summary, "已完成当前回合")
    }

    func testCodexNotifyScriptIgnoresUnknownPayloadWithoutOverwritingExistingSignal() throws {
        let fixture = try makeFixture()
        try fixture.writeSignal(
            WorkspaceAgentSessionSignal(
                projectPath: "/tmp/devhaven",
                workspaceId: "workspace:test",
                tabId: "tab:test",
                paneId: "pane:test",
                surfaceId: "surface:test",
                terminalSessionId: "session:test",
                agentKind: .codex,
                sessionId: "codex-session-1",
                pid: 42,
                state: .running,
                summary: "Codex 正在运行",
                detail: nil,
                updatedAt: Date(timeIntervalSince1970: 200)
            )
        )

        let output = try runScript(
            fixture.codexNotifyPath,
            arguments: [
                #"{"type":"session-created","session_id":"codex-session-1","msg":"ignored"}"#
            ],
            environment: fixture.environment
        )

        XCTAssertEqual(output.status, 0, output.stderr)

        let signal = try fixture.readSignal()
        XCTAssertEqual(signal.state, .running)
        XCTAssertEqual(signal.summary, "Codex 正在运行")
    }

    func testClaudeHookWritesWaitingSignalJSON() throws {
        let fixture = try makeFixture()
        let output = try runScript(
            fixture.claudeHookPath,
            arguments: ["Notification"],
            environment: fixture.environment,
            standardInput: """
            {"session_id":"claude-session-1","message":"Claude needs your attention"}
            """
        )

        XCTAssertEqual(output.status, 0, output.stderr)

        let signal = try fixture.readSignal()
        XCTAssertEqual(signal.agentKind, .claude)
        XCTAssertEqual(signal.state, .waiting)
        XCTAssertEqual(signal.sessionId, "claude-session-1")
    }

    func testClaudeSessionEndDoesNotOverwriteCompletedSignalToIdle() throws {
        let fixture = try makeFixture()
        let environment = fixture.environment.merging([
            "DEVHAVEN_TERMINAL_SESSION_ID": "workspace:slash/session:1"
        ], uniquingKeysWith: { _, rhs in rhs })

        let stopOutput = try runScript(
            fixture.claudeHookPath,
            arguments: ["Stop"],
            environment: environment,
            standardInput: """
            {"session_id":"claude-session-1","message":"Claude finished"}
            """
        )
        XCTAssertEqual(stopOutput.status, 0, stopOutput.stderr)

        let sessionEndOutput = try runScript(
            fixture.claudeHookPath,
            arguments: ["SessionEnd"],
            environment: environment,
            standardInput: """
            {"session_id":"claude-session-1"}
            """
        )
        XCTAssertEqual(sessionEndOutput.status, 0, sessionEndOutput.stderr)

        let signal = try fixture.readSignal()
        XCTAssertEqual(signal.agentKind, .claude)
        XCTAssertEqual(signal.state, .completed)
        XCTAssertEqual(signal.sessionId, "claude-session-1")
    }

    func testCodexWrapperWritesCompletedSignalWhenUnderlyingProcessExits() throws {
        let fixture = try makeFixture()
        let output = try runScript(
            fixture.codexWrapperPath,
            arguments: ["run", "echo", "hello"],
            environment: fixture.environment.merging([
                "DEVHAVEN_TEST_REAL_CODEX": fixture.fakeCodexPath.path
            ], uniquingKeysWith: { _, rhs in rhs })
        )

        XCTAssertEqual(output.status, 0, output.stderr)

        let signal = try fixture.readSignal()
        XCTAssertEqual(signal.agentKind, .codex)
        XCTAssertEqual(signal.state, .completed)
    }

    func testCodexWrapperWritesSignalWhenTerminalSessionIdContainsSlash() throws {
        let fixture = try makeFixture()
        let output = try runScript(
            fixture.codexWrapperPath,
            arguments: ["run", "echo", "hello"],
            environment: fixture.environment.merging([
                "DEVHAVEN_TERMINAL_SESSION_ID": "workspace:slash/session:1",
                "DEVHAVEN_TEST_REAL_CODEX": fixture.fakeCodexPath.path
            ], uniquingKeysWith: { _, rhs in rhs })
        )

        XCTAssertEqual(output.status, 0, output.stderr)

        let signals = try fixture.readAllSignals()
        XCTAssertEqual(signals.count, 1)
        XCTAssertEqual(signals.first?.terminalSessionId, "workspace:slash/session:1")
        XCTAssertEqual(signals.first?.state, .completed)
    }

    func testCodexWrapperInjectsNotifyOverrideIntoUnderlyingInvocation() throws {
        let fixture = try makeFixture()

        let output = try runScript(
            fixture.codexWrapperPath,
            arguments: ["--help"],
            environment: fixture.environment.merging([
                "DEVHAVEN_TEST_REAL_CODEX": fixture.fakeCodexPath.path
            ], uniquingKeysWith: { _, rhs in rhs })
        )

        XCTAssertEqual(output.status, 0, output.stderr)

        let invocation = try fixture.recordedCodexInvocation()
        XCTAssertTrue(invocation.contains("-c"), "Codex wrapper 应向真实 Codex 注入 config override")
        XCTAssertTrue(
            invocation.contains(where: {
                $0.contains(#"notify=[""#) && $0.contains("devhaven-codex-notify")
            }),
            "Codex wrapper 应注入 DevHaven notify 脚本"
        )
        XCTAssertTrue(
            invocation.contains("tui.notifications=true"),
            "Codex wrapper 应显式打开 Codex TUI 通知"
        )
    }

    func testClaudeWrapperPassesThroughOutsideDevHavenEnvironment() throws {
        let fixture = try makeFixture()
        let signalDirectoryURL = fixture.signalDirectoryURL
        try FileManager.default.createDirectory(at: signalDirectoryURL, withIntermediateDirectories: true)

        let output = try runScript(
            fixture.claudeWrapperPath,
            arguments: ["--version"],
            environment: [
                "PATH": "\(fixture.fakeBinaryDirectoryURL.path):/usr/bin:/bin:/usr/sbin:/sbin",
                "DEVHAVEN_TEST_REAL_CLAUDE": fixture.fakeClaudePath.path
            ]
        )

        XCTAssertEqual(output.status, 0, output.stderr)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: signalDirectoryURL.appending(path: "session:test.json").path
            )
        )
    }

    private func makeFixture() throws -> WorkspaceAgentWrapperFixture {
        try WorkspaceAgentWrapperFixture()
    }
}

private struct WorkspaceAgentWrapperFixture {
    let rootURL: URL
    let signalDirectoryURL: URL
    let fakeBinaryDirectoryURL: URL
    let fakeClaudePath: URL
    let fakeCodexPath: URL
    let fakeCodexInvocationLogPath: URL
    let claudeWrapperPath: String
    let codexWrapperPath: String
    let codexNotifyPath: String
    let claudeHookPath: String
    let environment: [String: String]

    init() throws {
        let systemPath = "/usr/bin:/bin:/usr/sbin:/sbin"
        rootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        signalDirectoryURL = rootURL.appending(path: "signals", directoryHint: .isDirectory)
        fakeBinaryDirectoryURL = rootURL.appending(path: "bin", directoryHint: .isDirectory)
        fakeClaudePath = fakeBinaryDirectoryURL.appending(path: "claude", directoryHint: .notDirectory)
        fakeCodexPath = fakeBinaryDirectoryURL.appending(path: "codex", directoryHint: .notDirectory)
        fakeCodexInvocationLogPath = rootURL.appending(path: "fake-codex-argv.txt", directoryHint: .notDirectory)

        try FileManager.default.createDirectory(at: signalDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fakeBinaryDirectoryURL, withIntermediateDirectories: true)

        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/DevHavenApp/AgentResources", directoryHint: .isDirectory)

        claudeWrapperPath = sourceRoot.appending(path: "bin/claude", directoryHint: .notDirectory).path
        codexWrapperPath = sourceRoot.appending(path: "bin/codex", directoryHint: .notDirectory).path
        codexNotifyPath = sourceRoot.appending(path: "bin/devhaven-codex-notify", directoryHint: .notDirectory).path
        claudeHookPath = sourceRoot.appending(path: "hooks/devhaven-claude-hook", directoryHint: .notDirectory).path

        try """
        #!/usr/bin/env bash
        exit 0
        """.write(to: fakeClaudePath, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        printf '%s\n' "$@" > "$DEVHAVEN_TEST_CODEX_ARGS_FILE"
        exit 0
        """.write(to: fakeCodexPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeClaudePath.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCodexPath.path)

        environment = [
            "PATH": "\(fakeBinaryDirectoryURL.path):\(systemPath)",
            "DEVHAVEN_PROJECT_PATH": "/tmp/devhaven",
            "DEVHAVEN_WORKSPACE_ID": "workspace:test",
            "DEVHAVEN_TAB_ID": "tab:test",
            "DEVHAVEN_PANE_ID": "pane:test",
            "DEVHAVEN_SURFACE_ID": "surface:test",
            "DEVHAVEN_TERMINAL_SESSION_ID": "session:test",
            "DEVHAVEN_AGENT_SIGNAL_DIR": signalDirectoryURL.path,
            "DEVHAVEN_AGENT_RESOURCES_DIR": sourceRoot.path,
            "DEVHAVEN_TEST_CODEX_ARGS_FILE": fakeCodexInvocationLogPath.path,
            "DEVHAVEN_TEST_REAL_CLAUDE": fakeClaudePath.path,
            "DEVHAVEN_TEST_REAL_CODEX": fakeCodexPath.path
        ]
    }

    func readSignal() throws -> WorkspaceAgentSessionSignal {
        let signals = try readAllSignals()
        XCTAssertEqual(signals.count, 1)
        guard let signal = signals.first else {
            throw NSError(domain: "WorkspaceAgentWrapperScriptTests", code: 1)
        }
        return signal
    }

    func readAllSignals() throws -> [WorkspaceAgentSessionSignal] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: signalDirectoryURL,
            includingPropertiesForKeys: nil
        )
        return try urls
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map {
                let data = try Data(contentsOf: $0)
                return try JSONDecoder().decode(WorkspaceAgentSessionSignal.self, from: data)
            }
    }

    func writeSignal(_ signal: WorkspaceAgentSessionSignal) throws {
        let fileURL = signalDirectoryURL.appending(
            path: WorkspaceAgentSignalStore.signalFileName(for: signal.terminalSessionId),
            directoryHint: .notDirectory
        )
        let data = try JSONEncoder().encode(signal)
        try data.write(to: fileURL)
    }

    func recordedCodexInvocation() throws -> [String] {
        guard FileManager.default.fileExists(atPath: fakeCodexInvocationLogPath.path) else {
            return []
        }
        let content = try String(contentsOf: fakeCodexInvocationLogPath, encoding: .utf8)
        return content
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }
}

private struct ScriptRunOutput {
    let status: Int32
    let stdout: String
    let stderr: String
}

private func runScript(
    _ path: String,
    arguments: [String] = [],
    environment: [String: String],
    standardInput: String = ""
) throws -> ScriptRunOutput {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.environment = environment

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    let stdinPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    process.standardInput = stdinPipe

    try process.run()
    if !standardInput.isEmpty {
        stdinPipe.fileHandleForWriting.write(Data(standardInput.utf8))
    }
    try stdinPipe.fileHandleForWriting.close()
    process.waitUntilExit()

    let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return ScriptRunOutput(status: process.terminationStatus, stdout: stdout, stderr: stderr)
}
