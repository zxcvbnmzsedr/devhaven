import XCTest
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelPathNormalizationTests: XCTestCase {
    func testActivateWorkspaceProjectCanonicalizesEquivalentSessionPath() throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(projects: [fixture.makeProject(name: "Repo")])

        viewModel.enterWorkspace(fixture.repositoryURL.path)
        viewModel.activateWorkspaceProject(fixture.repositoryURL.path + "/")

        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, fixture.repositoryURL.path)
        XCTAssertEqual(viewModel.selectedProjectPath, fixture.repositoryURL.path)
        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [fixture.repositoryURL.path])
    }

    func testWorkspaceAlignmentProjectionResolvesProjectByNormalizedMemberPath() throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }

        let project = fixture.makeProject(name: "Repo")
        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(
            appState: AppStateFile(
                workspaceAlignmentGroups: [
                    WorkspaceAlignmentGroupDefinition(
                        name: "联调",
                        targetBranch: "main",
                        projectPaths: [fixture.repositoryURL.path + "/"]
                    )
                ]
            ),
            projects: [project]
        )

        let member = try XCTUnwrap(viewModel.workspaceAlignmentGroups.first?.members.first)
        XCTAssertEqual(member.projectPath, fixture.repositoryURL.path)
        XCTAssertEqual(member.projectName, "Repo")
        XCTAssertEqual(member.alias, "Repo")
    }
}

private struct PathNormalizationFixture {
    let rootURL: URL
    let homeURL: URL
    let repositoryURL: URL

    static func make() throws -> PathNormalizationFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devhaven-path-normalization-\(UUID().uuidString)", isDirectory: true)
        let homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
        let repositoryURL = rootURL.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        return PathNormalizationFixture(rootURL: rootURL, homeURL: homeURL, repositoryURL: repositoryURL)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    @MainActor
    func makeViewModel() -> NativeAppViewModel {
        NativeAppViewModel(
            store: LegacyCompatStore(homeDirectoryURL: homeURL),
            worktreeService: NativeGitWorktreeService(homeDirectoryURL: homeURL)
        )
    }

    func makeProject(name: String) -> Project {
        let now = Date().timeIntervalSinceReferenceDate
        return Project(
            id: UUID().uuidString,
            name: name,
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
}
