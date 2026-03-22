import XCTest

final class WorkspaceAgentShellPathScriptTests: XCTestCase {
    func testZshHelperPrependsAgentBinWhenPathWasReset() throws {
        let fixture = try makeFixture()
        let output = try runShell(
            executable: "/bin/zsh",
            arguments: ["-c", "source \"$DEVHAVEN_AGENT_RESOURCES_DIR/shell/devhaven-agent-path.zsh\"; print -r -- \"$PATH\""],
            environment: fixture.environment(path: "/usr/bin:/bin")
        )

        XCTAssertEqual(output.status, 0, output.stderr)
        XCTAssertTrue(
            output.stdout.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(fixture.agentBinDirectoryURL.path + ":"),
            output.stdout
        )
    }

    func testBashHelperPrependsAgentBinWhenPathWasReset() throws {
        let fixture = try makeFixture()
        let output = try runShell(
            executable: "/bin/bash",
            arguments: ["-c", "source \"$DEVHAVEN_AGENT_RESOURCES_DIR/shell/devhaven-agent-path.bash\"; printf '%s\\n' \"$PATH\""],
            environment: fixture.environment(path: "/usr/bin:/bin")
        )

        XCTAssertEqual(output.status, 0, output.stderr)
        XCTAssertTrue(
            output.stdout.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(fixture.agentBinDirectoryURL.path + ":"),
            output.stdout
        )
    }

    func testZshHelperDoesNotDuplicateAgentBin() throws {
        let fixture = try makeFixture()
        let initialPath = "\(fixture.agentBinDirectoryURL.path):/usr/bin:/bin"
        let output = try runShell(
            executable: "/bin/zsh",
            arguments: ["-c", "source \"$DEVHAVEN_AGENT_RESOURCES_DIR/shell/devhaven-agent-path.zsh\"; print -r -- \"$PATH\""],
            environment: fixture.environment(path: initialPath)
        )

        XCTAssertEqual(output.status, 0, output.stderr)
        XCTAssertEqual(
            output.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            initialPath
        )
    }

    func testZshHelperMovesAgentBinToFrontWhenItAlreadyExistsLaterInPath() throws {
        let fixture = try makeFixture()
        let initialPath = "/Users/zhaotianzeng/.nvm/versions/node/v22.22.0/bin:\(fixture.agentBinDirectoryURL.path):/usr/bin:/bin"
        let output = try runShell(
            executable: "/bin/zsh",
            arguments: ["-c", "source \"$DEVHAVEN_AGENT_RESOURCES_DIR/shell/devhaven-agent-path.zsh\"; print -r -- \"$PATH\""],
            environment: fixture.environment(path: initialPath)
        )

        XCTAssertEqual(output.status, 0, output.stderr)
        XCTAssertEqual(
            output.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            "\(fixture.agentBinDirectoryURL.path):/Users/zhaotianzeng/.nvm/versions/node/v22.22.0/bin:/usr/bin:/bin"
        )
    }

    func testBashHelperMovesAgentBinToFrontWhenItAlreadyExistsLaterInPath() throws {
        let fixture = try makeFixture()
        let initialPath = "/Users/zhaotianzeng/.nvm/versions/node/v22.22.0/bin:\(fixture.agentBinDirectoryURL.path):/usr/bin:/bin"
        let output = try runShell(
            executable: "/bin/bash",
            arguments: ["-c", "source \"$DEVHAVEN_AGENT_RESOURCES_DIR/shell/devhaven-agent-path.bash\"; printf '%s\\n' \"$PATH\""],
            environment: fixture.environment(path: initialPath)
        )

        XCTAssertEqual(output.status, 0, output.stderr)
        XCTAssertEqual(
            output.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            "\(fixture.agentBinDirectoryURL.path):/Users/zhaotianzeng/.nvm/versions/node/v22.22.0/bin:/usr/bin:/bin"
        )
    }

    func testGhosttyZshDeferredInitRestoresAgentBinAfterPathReset() throws {
        let fixture = try makeFixture()
        let integrationPath = fixture.ghosttyZshIntegrationURL.path
        let output = try runShell(
            executable: "/bin/zsh",
            arguments: [
                "-c",
                """
                export PATH="/usr/bin:/bin"
                source "\(integrationPath)" >/dev/null 2>&1
                _ghostty_deferred_init >/dev/null 2>&1
                print -r -- "$PATH"
                """
            ],
            environment: fixture.environment(path: "/usr/bin:/bin")
        )

        XCTAssertEqual(output.status, 0, output.stderr)
        XCTAssertTrue(
            output.stdout.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(fixture.agentBinDirectoryURL.path + ":"),
            output.stdout
        )
    }

    func testGhosttyZshDeferredInitMovesAgentBinBackToFrontAfterUserPathReorder() throws {
        let fixture = try makeFixture()
        let integrationPath = fixture.ghosttyZshIntegrationURL.path
        let output = try runShell(
            executable: "/bin/zsh",
            arguments: [
                "-c",
                """
                export PATH="/Users/zhaotianzeng/.nvm/versions/node/v22.22.0/bin:$DEVHAVEN_AGENT_BIN_DIR:/usr/bin:/bin"
                source "\(integrationPath)" >/dev/null 2>&1
                _ghostty_deferred_init >/dev/null 2>&1
                print -r -- "$PATH"
                """
            ],
            environment: fixture.environment(path: "/usr/bin:/bin")
        )

        XCTAssertEqual(output.status, 0, output.stderr)
        XCTAssertEqual(
            output.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            "\(fixture.agentBinDirectoryURL.path):/Users/zhaotianzeng/.nvm/versions/node/v22.22.0/bin:/usr/bin:/bin"
        )
    }

    private func makeFixture() throws -> WorkspaceAgentShellPathFixture {
        try WorkspaceAgentShellPathFixture()
    }
}

private struct WorkspaceAgentShellPathFixture {
    let sourceRootURL: URL
    let agentResourcesURL: URL
    let agentBinDirectoryURL: URL
    let ghosttyZshIntegrationURL: URL
    let homeDirectoryURL: URL
    let zdotdirURL: URL

    init() throws {
        let tempRootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRootURL, withIntermediateDirectories: true)
        sourceRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSourceRootURL = sourceRootURL.appending(path: "Sources/DevHavenApp", directoryHint: .isDirectory)
        agentResourcesURL = appSourceRootURL.appending(path: "AgentResources", directoryHint: .isDirectory)
        agentBinDirectoryURL = agentResourcesURL.appending(path: "bin", directoryHint: .isDirectory)
        ghosttyZshIntegrationURL = appSourceRootURL
            .appending(path: "GhosttyResources/ghostty/shell-integration/zsh/ghostty-integration", directoryHint: .notDirectory)
        homeDirectoryURL = tempRootURL.appending(path: "home", directoryHint: .isDirectory)
        zdotdirURL = tempRootURL.appending(path: "zdotdir", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: homeDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: zdotdirURL, withIntermediateDirectories: true)
    }

    func environment(path: String) -> [String: String] {
        [
            "PATH": path,
            "DEVHAVEN_AGENT_RESOURCES_DIR": agentResourcesURL.path,
            "DEVHAVEN_AGENT_BIN_DIR": agentBinDirectoryURL.path,
            "HOME": homeDirectoryURL.path,
            "ZDOTDIR": zdotdirURL.path
        ]
    }
}

private struct ShellRunOutput {
    let status: Int32
    let stdout: String
    let stderr: String
}

private func runShell(
    executable: String,
    arguments: [String],
    environment: [String: String]
) throws -> ShellRunOutput {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = environment

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return ShellRunOutput(status: process.terminationStatus, stdout: stdout, stderr: stderr)
}
