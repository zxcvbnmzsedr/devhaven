import XCTest
@testable import DevHavenCore

@MainActor
final class NativeAppViewModelProjectSortingTests: XCTestCase {
    func testFilteredProjectsUsesDefaultOrderByDefault() throws {
        let fixture = try ProjectSortingFixture.make()
        defer { fixture.cleanup() }

        let first = fixture.makeProject(name: "Beta", path: "/tmp/beta", mtime: 10)
        let second = fixture.makeProject(name: "Alpha", path: "/tmp/alpha", mtime: 20)
        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(projects: [first, second])

        XCTAssertEqual(viewModel.filteredProjects.map(\.path), [first.path, second.path])
    }

    func testFilteredProjectsUsesNameAscendingSortOrder() throws {
        let fixture = try ProjectSortingFixture.make()
        defer { fixture.cleanup() }

        let beta = fixture.makeProject(name: "Beta", path: "/tmp/beta", mtime: 10)
        let alpha = fixture.makeProject(name: "Alpha", path: "/tmp/alpha", mtime: 20)
        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(projects: [beta, alpha])

        viewModel.updateProjectListSortOrder(.nameAscending)

        XCTAssertEqual(viewModel.filteredProjects.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(viewModel.projectListSortOrder, .nameAscending)
    }

    func testFilteredProjectsUsesModifiedNewestFirstSortOrder() throws {
        let fixture = try ProjectSortingFixture.make()
        defer { fixture.cleanup() }

        let older = fixture.makeProject(name: "Older", path: "/tmp/older", mtime: 10)
        let newer = fixture.makeProject(name: "Newer", path: "/tmp/newer", mtime: 20)
        let viewModel = fixture.makeViewModel()
        viewModel.snapshot = NativeAppSnapshot(projects: [older, newer])

        viewModel.updateProjectListSortOrder(.modifiedNewestFirst)

        XCTAssertEqual(viewModel.filteredProjects.map(\.name), ["Newer", "Older"])
    }

    func testUpdateProjectListSortOrderPersistsSetting() throws {
        let fixture = try ProjectSortingFixture.make()
        defer { fixture.cleanup() }

        let viewModel = fixture.makeViewModel()

        viewModel.updateProjectListSortOrder(.modifiedOldestFirst)

        XCTAssertEqual(viewModel.snapshot.appState.settings.projectListSortOrder, .modifiedOldestFirst)
        let reloadedSettings = try fixture.store.loadSnapshot().appState.settings
        XCTAssertEqual(reloadedSettings.projectListSortOrder, .modifiedOldestFirst)
    }

    func testProjectListSortOrderToggleForNameColumnCyclesAscendingThenDescending() {
        XCTAssertEqual(ProjectListSortOrder.defaultOrder.toggled(for: .name), .nameAscending)
        XCTAssertEqual(ProjectListSortOrder.nameAscending.toggled(for: .name), .nameDescending)
    }

    func testProjectListSortOrderToggleForModifiedTimeCyclesNewestThenOldest() {
        XCTAssertEqual(ProjectListSortOrder.defaultOrder.toggled(for: .modifiedTime), .modifiedNewestFirst)
        XCTAssertEqual(ProjectListSortOrder.modifiedNewestFirst.toggled(for: .modifiedTime), .modifiedOldestFirst)
    }
}

private struct ProjectSortingFixture {
    let rootURL: URL
    let homeURL: URL
    let store: LegacyCompatStore

    static func make() throws -> ProjectSortingFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devhaven-project-sorting-\(UUID().uuidString)", isDirectory: true)
        let homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        let store = LegacyCompatStore(homeDirectoryURL: homeURL)
        return ProjectSortingFixture(rootURL: rootURL, homeURL: homeURL, store: store)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    @MainActor
    func makeViewModel() -> NativeAppViewModel {
        NativeAppViewModel(store: store)
    }

    func makeProject(name: String, path: String, mtime: SwiftDate) -> Project {
        Project(
            id: path,
            name: name,
            path: path,
            tags: [],
            runConfigurations: [],
            worktrees: [],
            mtime: mtime,
            size: 0,
            checksum: "",
            isGitRepository: true,
            gitCommits: 0,
            gitLastCommit: mtime,
            gitLastCommitMessage: nil,
            gitDaily: nil,
            notesSummary: nil,
            created: mtime,
            checked: mtime
        )
    }
}
