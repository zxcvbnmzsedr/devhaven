import XCTest
@testable import DevHavenCore

final class NativeGitCommitWorkflowServiceTests: XCTestCase {
    func testLoadChangesSnapshotBuildsCommitChangesWithDefaultInclusion() throws {
        let fixture = try CommitWorkflowFixture()
        let repositoryURL = try fixture.createRepository(named: "commit-workflow-status")

        try "tracked staged\n".write(
            to: repositoryURL.appending(path: "staged.txt"),
            atomically: true,
            encoding: .utf8
        )
        try fixture.run(["git", "add", "staged.txt"], at: repositoryURL)

        try "hello\nupdated\n".write(
            to: repositoryURL.appending(path: "README.md"),
            atomically: true,
            encoding: .utf8
        )

        let service = NativeGitCommitWorkflowService()
        let snapshot = try service.loadChangesSnapshot(at: repositoryURL.path())

        XCTAssertTrue(snapshot.changes.contains(where: { $0.path == "staged.txt" && $0.group == .staged && $0.isIncludedByDefault }))
        XCTAssertTrue(snapshot.changes.contains(where: { $0.path == "README.md" && $0.group == .unstaged && !$0.isIncludedByDefault }))
    }

    func testLoadDiffPreviewReturnsWorkingTreePatch() throws {
        let fixture = try CommitWorkflowFixture()
        let repositoryURL = try fixture.createRepository(named: "commit-workflow-diff")
        try "hello\ndiff-preview\n".write(
            to: repositoryURL.appending(path: "README.md"),
            atomically: true,
            encoding: .utf8
        )

        let service = NativeGitCommitWorkflowService()
        let diff = try service.loadDiffPreview(at: repositoryURL.path(), filePath: "README.md")

        XCTAssertTrue(diff.contains("diff --git"))
        XCTAssertTrue(diff.contains("+diff-preview"))
    }

    func testExecuteCommitConsumesInclusionPathsInsteadOfCommittingEverything() throws {
        let fixture = try CommitWorkflowFixture()
        let repositoryURL = try fixture.createRepository(named: "commit-workflow-inclusion")

        try "hello\nincluded\n".write(
            to: repositoryURL.appending(path: "README.md"),
            atomically: true,
            encoding: .utf8
        )
        try "ignored\n".write(
            to: repositoryURL.appending(path: "IGNORED.txt"),
            atomically: true,
            encoding: .utf8
        )

        let service = NativeGitCommitWorkflowService()
        try service.executeCommit(
            at: repositoryURL.path(),
            request: WorkspaceCommitExecutionRequest(
                action: .commit,
                message: "feat: include readme only",
                includedPaths: ["README.md"],
                options: WorkspaceCommitOptionsState()
            )
        )

        let changedPaths = try fixture.gitOutput(["git", "show", "--name-only", "--format=", "HEAD"], at: repositoryURL)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        XCTAssertEqual(changedPaths, ["README.md"])
    }

    func testExecuteCommitAndPushSurfacesPushHookFailureAsInteractionRequired() throws {
        let fixture = try CommitWorkflowFixture()
        let remoteURL = try fixture.createBareRepository(named: "commit-workflow-remote.git")
        let repositoryURL = try fixture.createRepository(named: "commit-workflow-source")
        try fixture.run(["git", "remote", "add", "origin", remoteURL.path()], at: repositoryURL)
        try fixture.run(["git", "push", "-u", "origin", "main"], at: repositoryURL)

        let hookURL = repositoryURL
            .appending(path: ".git", directoryHint: .isDirectory)
            .appending(path: "hooks", directoryHint: .isDirectory)
            .appending(path: "pre-push")
        try FileManager.default.createDirectory(at: hookURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
#!/bin/sh
echo "pre-push hook requires terminal" 1>&2
exit 1
""".write(to: hookURL, atomically: true, encoding: .utf8)
        try fixture.run(["chmod", "+x", hookURL.path], at: repositoryURL)

        try "hello\npush-fail\n".write(
            to: repositoryURL.appending(path: "README.md"),
            atomically: true,
            encoding: .utf8
        )

        let service = NativeGitCommitWorkflowService()
        XCTAssertThrowsError(
            try service.executeCommit(
                at: repositoryURL.path(),
                request: WorkspaceCommitExecutionRequest(
                    action: .commitAndPush,
                    message: "feat: trigger pre-push hook",
                    includedPaths: ["README.md"],
                    options: WorkspaceCommitOptionsState()
                )
            )
        ) { error in
            guard case let WorkspaceGitCommandError.interactionRequired(command, reason) = error else {
                return XCTFail("应返回 interactionRequired，实际：\(error)")
            }
            XCTAssertTrue(command.contains("push"))
            XCTAssertTrue(reason.contains("hooks"))
        }
    }

    func testExecuteCommitRejectsUnknownInclusionPath() throws {
        let fixture = try CommitWorkflowFixture()
        let repositoryURL = try fixture.createRepository(named: "commit-workflow-invalid-inclusion")
        try "hello\nvalid-change\n".write(
            to: repositoryURL.appending(path: "README.md"),
            atomically: true,
            encoding: .utf8
        )

        let service = NativeGitCommitWorkflowService()
        XCTAssertThrowsError(
            try service.executeCommit(
                at: repositoryURL.path(),
                request: WorkspaceCommitExecutionRequest(
                    action: .commit,
                    message: "feat: invalid path",
                    includedPaths: ["NOT-EXISTS.txt"],
                    options: WorkspaceCommitOptionsState()
                )
            )
        ) { error in
            guard case let WorkspaceGitCommandError.operationRejected(message) = error else {
                return XCTFail("应返回 operationRejected，实际：\(error)")
            }
            XCTAssertTrue(message.contains("included paths"))
        }
    }
}

private struct CommitWorkflowFixture {
    let homeURL: URL

    init() throws {
        homeURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    }

    func createRepository(named name: String) throws -> URL {
        let url = homeURL.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try run(["git", "init", "-b", "main"], at: url)
        _ = try createCommit(in: url, message: "init", fileName: "README.md", content: "hello\n")
        return url
    }

    func createBareRepository(named name: String) throws -> URL {
        let url = homeURL.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try run(["git", "init", "--bare", "--initial-branch=main"], at: url)
        return url
    }

    @discardableResult
    func createCommit(
        in repositoryURL: URL,
        message: String,
        fileName: String,
        content: String
    ) throws -> String {
        let fileURL = repositoryURL.appending(path: fileName)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        try run(["git", "add", fileName], at: repositoryURL)
        try run(["git", "commit", "-m", message], at: repositoryURL, environment: gitIdentityEnvironment())
        return try gitOutput(["git", "rev-parse", "HEAD"], at: repositoryURL).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func gitOutput(_ arguments: [String], at repositoryURL: URL) throws -> String {
        try run(arguments, at: repositoryURL).stdout
    }

    @discardableResult
    func run(_ arguments: [String], at currentDirectoryURL: URL, environment: [String: String] = [:]) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let output = ProcessOutput(
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )

        guard process.terminationStatus == 0 else {
            throw CommitWorkflowFixtureError.commandFailed(
                arguments.joined(separator: " "),
                output.stderr.isEmpty ? output.stdout : output.stderr
            )
        }

        return output
    }

    func gitIdentityEnvironment(
        name: String = "DevHaven",
        email: String = "devhaven@example.com"
    ) -> [String: String] {
        [
            "GIT_AUTHOR_NAME": name,
            "GIT_AUTHOR_EMAIL": email,
            "GIT_COMMITTER_NAME": name,
            "GIT_COMMITTER_EMAIL": email,
        ]
    }
}

private struct ProcessOutput {
    let stdout: String
    let stderr: String
}

private enum CommitWorkflowFixtureError: Error, LocalizedError {
    case commandFailed(String, String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, message):
            return "命令执行失败：\(command)\n\(message)"
        }
    }
}
