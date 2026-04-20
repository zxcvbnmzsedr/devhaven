import XCTest
@testable import DevHavenCore

@MainActor
final class ProjectListProjectionBuilderTests: XCTestCase {
    func testVisibleProjectsExcludesRecycleBinPathsWithoutReordering() {
        let builder = makeBuilder()
        let first = makeProject(id: "first", name: "First", path: "/repo/first")
        let hidden = makeProject(id: "hidden", name: "Hidden", path: "/repo/hidden")
        let second = makeProject(id: "second", name: "Second", path: "/repo/second")

        let visible = builder.visibleProjects(
            projects: [first, hidden, second],
            recycleBin: [hidden.path]
        )

        XCTAssertEqual(visible.map(\.id), ["first", "second"])
    }

    func testFilteredProjectsMatchesQueryAcrossNotesTagsAndGitMessage() {
        let builder = makeBuilder()
        let notesProject = makeProject(
            id: "notes",
            name: "Payments",
            path: "/repo/payments",
            tags: ["backend"],
            notesSummary: "供应商报价聚合与回调排障"
        )
        let tagProject = makeProject(
            id: "tag",
            name: "Gateway",
            path: "/repo/gateway",
            tags: ["报价工具"]
        )
        let commitProject = makeProject(
            id: "commit",
            name: "Console",
            path: "/repo/console",
            gitLastCommitMessage: "fix 报价同步"
        )
        let otherProject = makeProject(id: "other", name: "Other", path: "/repo/other")

        let filtered = builder.filteredProjects(
            visibleProjects: [notesProject, tagProject, commitProject, otherProject],
            searchQuery: "报价",
            selectedDirectory: .all,
            directProjectPaths: [],
            selectedHeatmapDateKey: nil,
            selectedTag: nil,
            selectedDateFilter: .all,
            selectedGitFilter: .all,
            sortOrder: .defaultOrder
        )

        XCTAssertEqual(filtered.map(\.id), ["notes", "tag", "commit"])
    }

    func testFilteredProjectsCombinesDirectoryDirectGitAndDateFilters() {
        let builder = makeBuilder()
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let matching = makeProject(
            id: "matching",
            name: "Matching",
            path: "/repo/app",
            isGitRepository: true,
            mtime: now.timeIntervalSinceReferenceDate - 60
        )
        let outsideDirectProjects = makeProject(
            id: "outside-direct",
            name: "Outside Direct",
            path: "/repo/other",
            isGitRepository: true,
            mtime: now.timeIntervalSinceReferenceDate - 60
        )
        let stale = makeProject(
            id: "stale",
            name: "Stale",
            path: "/repo/stale",
            isGitRepository: true,
            mtime: now.timeIntervalSinceReferenceDate - 8 * 24 * 60 * 60
        )
        let nonGit = makeProject(
            id: "non-git",
            name: "Non Git",
            path: "/repo/non-git",
            isGitRepository: false,
            mtime: now.timeIntervalSinceReferenceDate - 60
        )

        let filtered = builder.filteredProjects(
            visibleProjects: [matching, outsideDirectProjects, stale, nonGit],
            searchQuery: "",
            selectedDirectory: .directProjects,
            directProjectPaths: ["/repo/app/", "/repo/stale/", "/repo/non-git/"],
            selectedHeatmapDateKey: nil,
            selectedTag: nil,
            selectedDateFilter: .lastWeek,
            selectedGitFilter: .gitOnly,
            sortOrder: .defaultOrder,
            now: now
        )

        XCTAssertEqual(filtered.map(\.id), ["matching"])
    }

    func testHeatmapDateFilterOverridesSelectedTag() {
        let builder = makeBuilder()
        let activeProject = makeProject(
            id: "active",
            name: "Active",
            path: "/repo/active",
            tags: ["other"],
            gitDaily: "2026-04-20:3"
        )
        let taggedButInactive = makeProject(
            id: "tagged",
            name: "Tagged",
            path: "/repo/tagged",
            tags: ["selected"],
            gitDaily: "2026-04-19:4"
        )

        let filtered = builder.filteredProjects(
            visibleProjects: [activeProject, taggedButInactive],
            searchQuery: "",
            selectedDirectory: .all,
            directProjectPaths: [],
            selectedHeatmapDateKey: "2026-04-20",
            selectedTag: "selected",
            selectedDateFilter: .all,
            selectedGitFilter: .all,
            sortOrder: .defaultOrder
        )

        XCTAssertEqual(filtered.map(\.id), ["active"])
    }

    func testSortOrderUsesNameAndModifiedTimeTieBreakers() {
        let builder = makeBuilder()
        let betaOlder = makeProject(id: "beta-old", name: "Beta", path: "/repo/beta-old", mtime: 10)
        let betaNewer = makeProject(id: "beta-new", name: "Beta", path: "/repo/beta-new", mtime: 20)
        let alpha = makeProject(id: "alpha", name: "Alpha", path: "/repo/alpha", mtime: 5)

        let nameAscending = builder.filteredProjects(
            visibleProjects: [betaOlder, betaNewer, alpha],
            searchQuery: "",
            selectedDirectory: .all,
            directProjectPaths: [],
            selectedHeatmapDateKey: nil,
            selectedTag: nil,
            selectedDateFilter: .all,
            selectedGitFilter: .all,
            sortOrder: .nameAscending
        )
        let modifiedNewest = builder.filteredProjects(
            visibleProjects: [betaOlder, betaNewer, alpha],
            searchQuery: "",
            selectedDirectory: .all,
            directProjectPaths: [],
            selectedHeatmapDateKey: nil,
            selectedTag: nil,
            selectedDateFilter: .all,
            selectedGitFilter: .all,
            sortOrder: .modifiedNewestFirst
        )

        XCTAssertEqual(nameAscending.map(\.id), ["alpha", "beta-new", "beta-old"])
        XCTAssertEqual(modifiedNewest.map(\.id), ["beta-new", "beta-old", "alpha"])
    }

    private func makeBuilder() -> ProjectListProjectionBuilder {
        ProjectListProjectionBuilder(normalizePath: normalizeProjectListProjectionTestPath)
    }

    private func makeProject(
        id: String,
        name: String,
        path: String,
        tags: [String] = [],
        isGitRepository: Bool = true,
        mtime: SwiftDate = 0,
        notesSummary: String? = nil,
        gitLastCommitMessage: String? = nil,
        gitDaily: String? = nil
    ) -> Project {
        Project(
            id: id,
            name: name,
            path: path,
            tags: tags,
            runConfigurations: [],
            worktrees: [],
            mtime: mtime,
            size: 0,
            checksum: id,
            isGitRepository: isGitRepository,
            gitCommits: isGitRepository ? 1 : 0,
            gitLastCommit: mtime,
            gitLastCommitMessage: gitLastCommitMessage,
            gitDaily: gitDaily,
            notesSummary: notesSummary,
            created: mtime,
            checked: mtime
        )
    }
}

private func normalizeProjectListProjectionTestPath(_ path: String) -> String {
    var normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\\", with: "/")
    while normalized.count > 1 && normalized.hasSuffix("/") {
        normalized.removeLast()
    }
    return normalized
}
