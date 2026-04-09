import XCTest
import Darwin
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

        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, fixture.canonicalPath(fixture.repositoryURL.path))
        XCTAssertEqual(viewModel.selectedProjectPath, fixture.canonicalPath(fixture.repositoryURL.path))
        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [fixture.canonicalPath(fixture.repositoryURL.path)])
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
        XCTAssertEqual(member.projectPath, fixture.canonicalPath(fixture.repositoryURL.path))
        XCTAssertEqual(member.projectName, "Repo")
        XCTAssertEqual(member.alias, "Repo")
    }

    func testEnterDirectoryWorkspaceCreatesTransientDisplayProject() throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }

        let directoryURL = fixture.rootURL.appendingPathComponent("workspace-root", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let viewModel = fixture.makeViewModel()
        viewModel.enterDirectoryWorkspace(directoryURL.path)

        XCTAssertEqual(viewModel.activeWorkspaceProjectPath, fixture.canonicalPath(directoryURL.path))
        XCTAssertEqual(viewModel.selectedProjectPath, fixture.canonicalPath(directoryURL.path))
        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [fixture.canonicalPath(directoryURL.path)])
        XCTAssertEqual(viewModel.activeWorkspaceProject?.path, fixture.canonicalPath(directoryURL.path))
        XCTAssertEqual(viewModel.activeWorkspaceProject?.name, "workspace-root")
        XCTAssertEqual(viewModel.activeWorkspaceProject?.isDirectoryWorkspace, true)
        XCTAssertEqual(viewModel.openWorkspaceProjects.map(\.path), [fixture.canonicalPath(directoryURL.path)])
        XCTAssertEqual(viewModel.workspaceSidebarGroups.first?.rootProject.path, fixture.canonicalPath(directoryURL.path))
        XCTAssertEqual(viewModel.workspaceSidebarGroups.first?.rootProject.isDirectoryWorkspace, true)
    }

    func testDirectoryWorkspaceSurvivesFilterSelectionReconciliation() throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }

        let directoryURL = fixture.rootURL.appendingPathComponent("workspace-root", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(projects: [fixture.makeProject(name: "Repo")])
        viewModel.enterDirectoryWorkspace(directoryURL.path)

        viewModel.selectDirectory(.all)
        viewModel.updateGitFilter(.all)

        XCTAssertTrue(viewModel.isWorkspacePresented)
        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [fixture.canonicalPath(directoryURL.path)])
        XCTAssertEqual(viewModel.activeWorkspaceProject?.isDirectoryWorkspace, true)
    }

    func testEnterWorkspacePromotesDirectoryWorkspaceBackToRegularProject() throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }

        let project = fixture.makeProject(name: "Repo")
        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(projects: [project])

        viewModel.enterDirectoryWorkspace(fixture.repositoryURL.path)
        XCTAssertEqual(viewModel.openWorkspaceSessions.first?.transientDisplayProject?.isDirectoryWorkspace, true)
        XCTAssertEqual(viewModel.workspaceSidebarGroups.first?.rootProject.isDirectoryWorkspace, true)

        viewModel.enterWorkspace(fixture.repositoryURL.path)

        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [fixture.canonicalPath(fixture.repositoryURL.path)])
        XCTAssertEqual(viewModel.activeWorkspaceProject?.name, "Repo")
        XCTAssertEqual(viewModel.activeWorkspaceProject?.isDirectoryWorkspace, false)
        XCTAssertNil(viewModel.openWorkspaceSessions.first?.transientDisplayProject)
        XCTAssertEqual(viewModel.workspaceSidebarGroups.first?.rootProject.name, "Repo")
        XCTAssertEqual(viewModel.workspaceSidebarGroups.first?.rootProject.isDirectoryWorkspace, false)
    }

    func testActivateWorkspaceSidebarProjectPromotesDirectoryWorkspaceBackToRegularProject() throws {
        let fixture = try PathNormalizationFixture.make()
        defer { fixture.cleanup() }

        let project = fixture.makeProject(name: "Repo")
        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(projects: [project])

        viewModel.enterDirectoryWorkspace(fixture.repositoryURL.path)
        XCTAssertEqual(viewModel.openWorkspaceSessions.first?.transientDisplayProject?.isDirectoryWorkspace, true)
        XCTAssertEqual(viewModel.workspaceSidebarGroups.first?.rootProject.isDirectoryWorkspace, true)

        viewModel.activateWorkspaceSidebarProject(fixture.repositoryURL.path)

        XCTAssertEqual(viewModel.openWorkspaceProjectPaths, [fixture.canonicalPath(fixture.repositoryURL.path)])
        XCTAssertEqual(viewModel.activeWorkspaceProject?.name, "Repo")
        XCTAssertEqual(viewModel.activeWorkspaceProject?.isDirectoryWorkspace, false)
        XCTAssertNil(viewModel.openWorkspaceSessions.first?.transientDisplayProject)
        XCTAssertEqual(viewModel.workspaceSidebarGroups.first?.rootProject.isDirectoryWorkspace, false)
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

    func canonicalPath(_ path: String) -> String {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return standardizedPath.withCString { pointer in
            guard let resolvedPointer = realpath(pointer, nil) else {
                return standardizedPath
            }
            defer { free(resolvedPointer) }
            return String(cString: resolvedPointer)
        }
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
