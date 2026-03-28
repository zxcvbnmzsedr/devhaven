import XCTest
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelWorkspaceAlignmentTests: XCTestCase {
    func testRootCheckoutOfTargetBranchIsReportedAsAlignedAndApplyDoesNotCreateManagedWorktree() async throws {
        let fixture = try GitWorkspaceAlignmentFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "develop")
        try fixture.commit(fileName: "README.md", content: "hello")
        try fixture.git(in: fixture.repositoryURL, ["checkout", "-b", "feature/payment"])

        let viewModel = fixture.makeViewModel()
        let group = WorkspaceAlignmentGroupDefinition(
            name: "支付链路",
            targetBranch: "feature/payment",
            projectPaths: [fixture.repositoryURL.path]
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [group]),
            projects: [fixture.makeProject()]
        )

        try await viewModel.recheckWorkspaceAlignmentGroup(group.id)

        let memberAfterRecheck = try XCTUnwrap(viewModel.workspaceAlignmentGroups.first?.members.first)
        XCTAssertEqual(memberAfterRecheck.status, .aligned)
        XCTAssertEqual(memberAfterRecheck.openTarget, .project(projectPath: fixture.repositoryURL.path))

        let managedPath = try viewModel.managedWorktreePathPreview(
            for: fixture.repositoryURL.path,
            branch: "feature/payment"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedPath))

        try await viewModel.applyWorkspaceAlignmentGroup(group.id)

        let memberAfterApply = try XCTUnwrap(viewModel.workspaceAlignmentGroups.first?.members.first)
        XCTAssertEqual(memberAfterApply.status, .aligned)
        XCTAssertEqual(memberAfterApply.openTarget, .project(projectPath: fixture.repositoryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedPath))
    }

    func testExistingCheckoutInAnotherWorktreeIsReusedInsteadOfCreatingManagedWorktree() async throws {
        let fixture = try GitWorkspaceAlignmentFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "develop")
        try fixture.commit(fileName: "README.md", content: "hello")

        let existingWorktreeURL = fixture.rootURL.appendingPathComponent("existing-feature-worktree", isDirectory: true)
        try fixture.git(
            in: fixture.repositoryURL,
            ["worktree", "add", existingWorktreeURL.path, "-b", "feature/payment", "develop"]
        )
        let expectedWorktreePath = existingWorktreeURL.resolvingSymlinksInPath().path

        let viewModel = fixture.makeViewModel()
        let group = WorkspaceAlignmentGroupDefinition(
            name: "支付链路",
            targetBranch: "feature/payment",
            projectPaths: [fixture.repositoryURL.path]
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [group]),
            projects: [fixture.makeProject()]
        )

        try await viewModel.recheckWorkspaceAlignmentGroup(group.id)

        let memberAfterRecheck = try XCTUnwrap(viewModel.workspaceAlignmentGroups.first?.members.first)
        XCTAssertEqual(memberAfterRecheck.status, .aligned)
        assertWorktreeOpenTarget(
            memberAfterRecheck.openTarget,
            rootProjectPath: fixture.repositoryURL.path,
            worktreePath: expectedWorktreePath
        )
        XCTAssertEqual(
            viewModel.snapshot.projects.first?.worktrees.map { canonicalPath($0.path) },
            [canonicalPath(expectedWorktreePath)]
        )

        let managedPath = try viewModel.managedWorktreePathPreview(
            for: fixture.repositoryURL.path,
            branch: "feature/payment"
        )
        XCTAssertNotEqual(managedPath, expectedWorktreePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedPath))

        try await viewModel.applyWorkspaceAlignmentGroup(group.id)

        let memberAfterApply = try XCTUnwrap(viewModel.workspaceAlignmentGroups.first?.members.first)
        XCTAssertEqual(memberAfterApply.status, .aligned)
        assertWorktreeOpenTarget(
            memberAfterApply.openTarget,
            rootProjectPath: fixture.repositoryURL.path,
            worktreePath: expectedWorktreePath
        )
        XCTAssertEqual(
            viewModel.snapshot.projects.first?.worktrees.map { canonicalPath($0.path) },
            [canonicalPath(expectedWorktreePath)]
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedPath))
    }

    func testEnterWorkspaceAlignmentGroupCreatesWorkspaceRootSessionAndManifest() async throws {
        let fixture = try GitWorkspaceAlignmentFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel()
        let group = WorkspaceAlignmentGroupDefinition(
            name: "支付链路联调",
            targetBranch: "main",
            projectPaths: [fixture.repositoryURL.path]
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [group]),
            projects: [fixture.makeProject()]
        )

        try await viewModel.recheckWorkspaceAlignmentGroup(group.id)
        try viewModel.enterWorkspaceAlignmentGroup(group.id)

        let activePath = try XCTUnwrap(viewModel.activeWorkspaceProjectPath)
        XCTAssertTrue(activePath.hasPrefix(fixture.homeURL.appendingPathComponent(".devhaven/workspaces", isDirectory: true).path))

        let session = try XCTUnwrap(viewModel.openWorkspaceSessions.first(where: { $0.projectPath == activePath }))
        XCTAssertTrue(session.isQuickTerminal)
        XCTAssertEqual(session.workspaceRootContext?.workspaceID, group.id)
        XCTAssertEqual(session.workspaceRootContext?.workspaceName, group.name)

        let manifestURL = URL(fileURLWithPath: activePath, isDirectory: true).appendingPathComponent("WORKSPACE.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(WorkspaceAlignmentRootManifest.self, from: manifestData)

        XCTAssertEqual(manifest.id, group.id)
        XCTAssertEqual(manifest.name, group.name)
        XCTAssertEqual(manifest.members.count, 1)
        XCTAssertEqual(manifest.members.first?.projectPath, fixture.repositoryURL.path)
        XCTAssertEqual(manifest.members.first?.openPath, fixture.repositoryURL.path)

        let alias = try XCTUnwrap(manifest.members.first?.alias)
        let aliasURL = URL(fileURLWithPath: activePath, isDirectory: true).appendingPathComponent(alias)
        XCTAssertTrue(FileManager.default.fileExists(atPath: aliasURL.path))
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: aliasURL.path)
        XCTAssertEqual(canonicalPath(destination), canonicalPath(fixture.repositoryURL.path))
    }

    func testMemberSpecificTargetBranchOverridesLegacyGroupTargetBranch() async throws {
        let fixture = try GitWorkspaceAlignmentFixture.make()
        defer { fixture.cleanup() }

        try fixture.initializeRepository(defaultBranch: "main")
        try fixture.commit(fileName: "README.md", content: "hello")

        let viewModel = fixture.makeViewModel()
        let group = WorkspaceAlignmentGroupDefinition(
            name: "混合协同",
            targetBranch: "",
            projectPaths: [fixture.repositoryURL.path],
            members: [
                WorkspaceAlignmentMemberDefinition(
                    projectPath: fixture.repositoryURL.path,
                    targetBranch: "main"
                )
            ]
        )
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(workspaceAlignmentGroups: [group]),
            projects: [fixture.makeProject()]
        )

        try await viewModel.recheckWorkspaceAlignmentGroup(group.id)

        let member = try XCTUnwrap(viewModel.workspaceAlignmentGroups.first?.members.first)
        XCTAssertEqual(member.targetBranch, "main")
        XCTAssertEqual(member.status, .aligned)
        XCTAssertEqual(member.openTarget, .project(projectPath: fixture.repositoryURL.path))
    }

    private func assertWorktreeOpenTarget(
        _ target: WorkspaceAlignmentOpenTarget,
        rootProjectPath: String,
        worktreePath: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .worktree(actualRootProjectPath, actualWorktreePath) = target else {
            XCTFail("期望 worktree open target，实际为 \(target)", file: file, line: line)
            return
        }
        XCTAssertEqual(actualRootProjectPath, rootProjectPath, file: file, line: line)
        XCTAssertEqual(canonicalPath(actualWorktreePath), canonicalPath(worktreePath), file: file, line: line)
    }
}

private enum GitWorkspaceAlignmentFixtureError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(message):
            message
        }
    }
}

private struct GitWorkspaceAlignmentFixture {
    let rootURL: URL
    let homeURL: URL
    let repositoryURL: URL

    static func make() throws -> GitWorkspaceAlignmentFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devhaven-workspace-alignment-\(UUID().uuidString)", isDirectory: true)
        let homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
        let repositoryURL = rootURL.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        return GitWorkspaceAlignmentFixture(rootURL: rootURL, homeURL: homeURL, repositoryURL: repositoryURL)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func initializeRepository(defaultBranch: String) throws {
        try git(in: repositoryURL, ["init", "-b", defaultBranch])
        try git(in: repositoryURL, ["config", "user.name", "DevHaven Tests"])
        try git(in: repositoryURL, ["config", "user.email", "devhaven-tests@example.com"])
    }

    func commit(fileName: String, content: String) throws {
        let fileURL = repositoryURL.appendingPathComponent(fileName)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        try git(in: repositoryURL, ["add", fileName])
        try git(in: repositoryURL, ["commit", "-m", "init"])
    }

    @MainActor
    func makeViewModel() -> NativeAppViewModel {
        NativeAppViewModel(
            store: LegacyCompatStore(homeDirectoryURL: homeURL),
            worktreeService: NativeGitWorktreeService(homeDirectoryURL: homeURL)
        )
    }

    func makeProject() -> Project {
        let now = Date().timeIntervalSinceReferenceDate
        return Project(
            id: UUID().uuidString,
            name: repositoryURL.lastPathComponent,
            path: repositoryURL.path,
            tags: [],
            runConfigurations: [],
            worktrees: [],
            mtime: now,
            size: 0,
            checksum: UUID().uuidString,
            isGitRepository: true,
            gitCommits: 1,
            gitLastCommit: now,
            created: now,
            checked: now
        )
    }

    @discardableResult
    func git(in directoryURL: URL, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directoryURL

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let message = [stdoutText, stderrText]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? "未知错误"
            throw GitWorkspaceAlignmentFixtureError.commandFailed("git \(arguments.joined(separator: " ")) 失败：\(message)")
        }
        return stdoutText
    }
}

private func canonicalPath(_ path: String) -> String {
    NSString(string: path).resolvingSymlinksInPath
}
