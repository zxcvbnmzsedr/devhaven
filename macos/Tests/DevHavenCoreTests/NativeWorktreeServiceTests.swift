import XCTest
@testable import DevHavenCore

final class NativeWorktreeServiceTests: XCTestCase {
    func testManagedWorktreePathUsesHomeDevHavenWorktreesDirectory() throws {
        let fixture = try GitWorktreeFixture()
        let repositoryURL = try fixture.createRepository(named: "devhaven-main")
        let service = NativeGitWorktreeService(homeDirectoryURL: fixture.homeURL)

        let targetPath = try service.managedWorktreePath(for: repositoryURL.path(), branch: "feature/demo")

        XCTAssertEqual(
            targetPath,
            fixture.homeURL
                .appending(path: ".devhaven", directoryHint: .isDirectory)
                .appending(path: "worktrees", directoryHint: .isDirectory)
                .appending(path: "devhaven-main", directoryHint: .isDirectory)
                .appending(path: "feature/demo", directoryHint: .isDirectory)
                .path()
        )
    }

    func testCreateWorktreeUsesRemoteBaseBranchAndPreparesEnvironment() throws {
        let fixture = try GitWorktreeFixture()
        let remoteURL = try fixture.createBareRemote(named: "origin.git")
        let repositoryURL = try fixture.cloneRepository(remoteURL: remoteURL, named: "sample-app")
        try fixture.run(["git", "checkout", "-b", "main"], at: repositoryURL)
        try fixture.createInitialCommit(in: repositoryURL, fileName: "README.md", content: "hello\n", message: "init")
        try fixture.run(["git", "push", "-u", "origin", "HEAD"], at: repositoryURL)
        try fixture.run(["git", "checkout", "-b", "develop"], at: repositoryURL)
        try fixture.run(["git", "push", "-u", "origin", "develop"], at: repositoryURL)
        try fixture.run(["git", "checkout", "main"], at: repositoryURL)
        try fixture.run(["git", "branch", "-D", "develop"], at: repositoryURL)

        let projectConfigURL = repositoryURL.appending(path: ".devhaven", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: projectConfigURL, withIntermediateDirectories: true)
        try #"{"setup":["printf ready > worktree-setup.txt"]}"#.write(
            to: projectConfigURL.appending(path: "config.json"),
            atomically: true,
            encoding: .utf8
        )

        let service = NativeGitWorktreeService(homeDirectoryURL: fixture.homeURL)
        let progressRecorder = ProgressRecorder()

        let result = try service.createWorktree(
            NativeWorktreeCreateRequest(
                sourceProjectPath: repositoryURL.path(),
                branch: "feature/remote-base",
                createBranch: true,
                baseBranch: "develop"
            ),
            progress: { update in
                progressRecorder.append(update)
            }
        )

        XCTAssertEqual(result.branch, "feature/remote-base")
        XCTAssertEqual(result.baseBranch, "develop")
        XCTAssertNil(result.warning)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.worktreePath))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: URL(fileURLWithPath: result.worktreePath).appending(path: ".devhaven/config.json").path()
            )
        )
        XCTAssertEqual(
            try String(
                contentsOf: URL(fileURLWithPath: result.worktreePath).appending(path: "worktree-setup.txt"),
                encoding: .utf8
            ),
            "ready"
        )
        XCTAssertEqual(
            progressRecorder.items.map(\.step),
            [.checkingBranch, .creatingWorktree, .preparingEnvironment, .syncing, .ready]
        )
        let listedWorktrees = try service.listWorktrees(at: repositoryURL.path)
        XCTAssertEqual(listedWorktrees.count, 1)
        XCTAssertEqual(listedWorktrees.first?.branch, "feature/remote-base")
        XCTAssertEqual(
            listedWorktrees.first.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path },
            URL(fileURLWithPath: result.worktreePath).standardizedFileURL.path
        )
    }

    func testRemoveWorktreeDeletesManagedBranchWhenRequested() throws {
        let fixture = try GitWorktreeFixture()
        let repositoryURL = try fixture.createRepository(named: "sample-app")
        let service = NativeGitWorktreeService(homeDirectoryURL: fixture.homeURL)
        let created = try service.createWorktree(
            NativeWorktreeCreateRequest(
                sourceProjectPath: repositoryURL.path(),
                branch: "feature/delete-me",
                createBranch: true,
                baseBranch: "main"
            ),
            progress: { _ in }
        )

        let result = try service.removeWorktree(
            NativeWorktreeRemoveRequest(
                sourceProjectPath: repositoryURL.path(),
                worktreePath: created.worktreePath,
                branch: created.branch,
                shouldDeleteBranch: true
            )
        )

        XCTAssertNil(result.warning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: created.worktreePath))
        XCTAssertEqual(try service.listWorktrees(at: repositoryURL.path), [])
        let branchNames = try fixture.gitOutput(["git", "branch", "--list", "feature/delete-me"], at: repositoryURL)
        XCTAssertTrue(branchNames.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

private struct GitWorktreeFixture {
    let homeURL: URL

    init() throws {
        homeURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    }

    func createRepository(named name: String) throws -> URL {
        let url = homeURL.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try run(["git", "init", "-b", "main"], at: url)
        try createInitialCommit(in: url, fileName: "README.md", content: "hello\n", message: "init")
        return url
    }

    func createBareRemote(named name: String) throws -> URL {
        let url = homeURL.appending(path: name, directoryHint: .isDirectory)
        try run(["git", "init", "--bare", url.path()], at: homeURL)
        return url
    }

    func cloneRepository(remoteURL: URL, named name: String) throws -> URL {
        let url = homeURL.appending(path: name, directoryHint: .isDirectory)
        try run(["git", "clone", remoteURL.path(), url.path()], at: homeURL)
        return url
    }

    func createInitialCommit(in repositoryURL: URL, fileName: String, content: String, message: String) throws {
        let fileURL = repositoryURL.appending(path: fileName)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        try run(["git", "add", fileName], at: repositoryURL)
        try run(
            ["git", "commit", "-m", message],
            at: repositoryURL,
            environment: [
                "GIT_AUTHOR_NAME": "DevHaven",
                "GIT_AUTHOR_EMAIL": "devhaven@example.com",
                "GIT_COMMITTER_NAME": "DevHaven",
                "GIT_COMMITTER_EMAIL": "devhaven@example.com",
            ]
        )
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
            throw XCTSkip("命令执行失败：\(arguments.joined(separator: " "))\n\(output.stderr)")
        }

        return output
    }
}

private struct ProcessOutput {
    let stdout: String
    let stderr: String
}

private final class ProgressRecorder: @unchecked Sendable {
    private(set) var items = [NativeWorktreeProgress]()

    func append(_ progress: NativeWorktreeProgress) {
        items.append(progress)
    }
}
