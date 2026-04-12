import XCTest
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelProjectCatalogRefreshTests: XCTestCase {
    func testRefreshProjectCatalogRemovesMissingDirectProjectPathsAndStaleProjects() async throws {
        let fixture = try ProjectCatalogRefreshFixture.make()
        defer { fixture.cleanup() }

        try fixture.store.updateDirectProjectPaths([fixture.missingProjectPath, fixture.existingProjectPath])
        try fixture.store.updateProjects([
            fixture.makeProject(path: fixture.missingProjectPath),
            fixture.makeProject(path: fixture.existingProjectPath)
        ])

        let viewModel = NativeAppViewModel(store: fixture.store)
        viewModel.load()

        try await viewModel.refreshProjectCatalog()

        XCTAssertEqual(
            canonicalizedPaths(viewModel.snapshot.appState.directProjectPaths),
            canonicalizedPaths([fixture.existingProjectPath])
        )
        XCTAssertEqual(
            canonicalizedPaths(viewModel.snapshot.projects.map(\.path)),
            canonicalizedPaths([fixture.existingProjectPath])
        )

        let reloadedSnapshot = try fixture.store.loadSnapshot()
        XCTAssertEqual(
            canonicalizedPaths(reloadedSnapshot.appState.directProjectPaths),
            canonicalizedPaths([fixture.existingProjectPath])
        )
        XCTAssertEqual(
            canonicalizedPaths(reloadedSnapshot.projects.map(\.path)),
            canonicalizedPaths([fixture.existingProjectPath])
        )
    }
}

private struct ProjectCatalogRefreshFixture {
    let rootURL: URL
    let homeURL: URL
    let existingProjectPath: String
    let missingProjectPath: String
    let store: LegacyCompatStore

    static func make() throws -> ProjectCatalogRefreshFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devhaven-project-refresh-\(UUID().uuidString)", isDirectory: true)
        let homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
        let projectsURL = rootURL.appendingPathComponent("projects", isDirectory: true)
        let existingProjectURL = projectsURL.appendingPathComponent("existing-project", isDirectory: true)

        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: existingProjectURL, withIntermediateDirectories: true)

        return ProjectCatalogRefreshFixture(
            rootURL: rootURL,
            homeURL: homeURL,
            existingProjectPath: existingProjectURL.resolvingSymlinksInPath().path,
            missingProjectPath: projectsURL
                .appendingPathComponent("missing-project", isDirectory: true)
                .resolvingSymlinksInPath()
                .path,
            store: LegacyCompatStore(homeDirectoryURL: homeURL)
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func makeProject(path: String) -> Project {
        Project(
            id: path,
            name: URL(fileURLWithPath: path).lastPathComponent,
            path: path,
            tags: [],
            runConfigurations: [],
            worktrees: [],
            mtime: 0,
            size: 0,
            checksum: "",
            isGitRepository: false,
            gitCommits: 0,
            gitLastCommit: 0,
            gitLastCommitMessage: nil,
            gitDaily: nil,
            notesSummary: nil,
            created: 0,
            checked: 0
        )
    }
}

private func canonicalizedPaths(_ paths: [String]) -> [String] {
    paths.map { URL(fileURLWithPath: $0, isDirectory: true).resolvingSymlinksInPath().path }
}
