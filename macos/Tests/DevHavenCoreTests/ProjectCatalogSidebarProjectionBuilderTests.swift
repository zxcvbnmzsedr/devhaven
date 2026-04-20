import XCTest
@testable import DevHavenCore

@MainActor
final class ProjectCatalogSidebarProjectionBuilderTests: XCTestCase {
    func testDirectoryRowsIncludeSystemEntriesAndDirectoryCounts() {
        let builder = makeBuilder()
        let app = makeProject(id: "app", name: "App", path: "/repo/app")
        let nested = makeProject(id: "nested", name: "Nested", path: "/repo/app/module")
        let tool = makeProject(id: "tool", name: "Tool", path: "/repo/tool")

        let rows = builder.directoryRows(
            visibleProjects: [app, nested, tool],
            directories: ["/repo/app", "/repo/tool"],
            directProjectPaths: ["/repo/app/", "/repo/missing"]
        )

        XCTAssertEqual(rows.map(\.title), ["全部", "直接添加", "app", "tool"])
        XCTAssertEqual(rows.map(\.count), [3, 1, 2, 1])
        XCTAssertEqual(rows.map(\.isSystemEntry), [true, true, false, false])
        XCTAssertEqual(rows[0].filter, .all)
        XCTAssertEqual(rows[1].filter, .directProjects)
        XCTAssertEqual(rows[2].filter, .directory("/repo/app"))
    }

    func testTagRowsSortByVisibleProjectCountAndPreserveColorHex() {
        let builder = makeBuilder()
        let backend = TagData(name: "backend", color: ColorData(r: 1, g: 0, b: 0, a: 1), hidden: false)
        let frontend = TagData(name: "frontend", color: ColorData(r: 0, g: 0.5, b: 1, a: 1), hidden: false)
        let unused = TagData(name: "unused", color: ColorData(r: 0.1, g: 0.2, b: 0.3, a: 1), hidden: false)

        let rows = builder.tagRows(
            visibleProjects: [
                makeProject(id: "api", name: "API", path: "/repo/api", tags: ["backend"]),
                makeProject(id: "web", name: "Web", path: "/repo/web", tags: ["backend", "frontend"]),
                makeProject(id: "cli", name: "CLI", path: "/repo/cli", tags: []),
            ],
            tags: [frontend, unused, backend]
        )

        XCTAssertEqual(rows.map(\.title), ["全部", "backend", "frontend", "unused"])
        XCTAssertEqual(rows.map(\.count), [3, 2, 1, 0])
        XCTAssertNil(rows[0].colorHex)
        XCTAssertEqual(rows[1].colorHex, "#FF0000")
        XCTAssertEqual(rows[2].colorHex, "#0080FF")
        XCTAssertEqual(rows[3].colorHex, "#1A334D")
    }

    func testHeatmapProjectionBuildsDaysActiveProjectsAndSummary() throws {
        let builder = makeBuilder()
        let now = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 20)))
        let activeA = makeProject(
            id: "active-a",
            name: "Alpha",
            path: "/repo/alpha",
            gitDaily: "2026-04-20:2,2026-04-19:1"
        )
        let activeB = makeProject(
            id: "active-b",
            name: "Beta",
            path: "/repo/beta",
            gitDaily: "2026-04-20:5"
        )
        let inactive = makeProject(
            id: "inactive",
            name: "Inactive",
            path: "/repo/inactive",
            gitDaily: "2026-04-18:9"
        )

        let days = builder.sidebarHeatmapDays(
            visibleProjects: [activeA, activeB, inactive],
            days: 3,
            now: now
        )
        let selectedDay = try XCTUnwrap(days.first(where: { $0.dateKey == "2026-04-20" }))
        let activeProjects = builder.heatmapActiveProjects(
            selectedDateKey: "2026-04-20",
            visibleProjects: [activeA, activeB, inactive]
        )
        let summary = builder.selectedHeatmapSummary(
            selectedDateKey: "2026-04-20",
            activeProjects: activeProjects
        )

        XCTAssertEqual(days.map(\.dateKey), ["2026-04-18", "2026-04-19", "2026-04-20"])
        XCTAssertEqual(selectedDay.commitCount, 7)
        XCTAssertEqual(selectedDay.projectPaths, ["/repo/alpha", "/repo/beta"])
        XCTAssertEqual(activeProjects.map(\.name), ["Beta", "Alpha"])
        XCTAssertEqual(activeProjects.map(\.commitCount), [5, 2])
        XCTAssertEqual(summary, "2026-04-20 · 2 个活跃项目 · 7 次提交")
        XCTAssertTrue(builder.heatmapActiveProjects(selectedDateKey: nil, visibleProjects: [activeA]).isEmpty)
        XCTAssertNil(builder.selectedHeatmapSummary(selectedDateKey: nil, activeProjects: activeProjects))
    }

    func testGitStatisticsLastUpdatedIgnoresZeroAndUsesNewestCheckedTime() throws {
        let builder = makeBuilder()
        let older = Date(timeIntervalSinceReferenceDate: 100)
        let newer = Date(timeIntervalSinceReferenceDate: 300)

        let lastUpdated = builder.gitStatisticsLastUpdated(
            visibleProjects: [
                makeProject(id: "missing", name: "Missing", path: "/repo/missing", checked: 0),
                makeProject(id: "older", name: "Older", path: "/repo/older", checked: older.timeIntervalSinceReferenceDate),
                makeProject(id: "newer", name: "Newer", path: "/repo/newer", checked: newer.timeIntervalSinceReferenceDate),
            ]
        )

        XCTAssertEqual(try XCTUnwrap(lastUpdated), newer)
        XCTAssertNil(builder.gitStatisticsLastUpdated(visibleProjects: [
            makeProject(id: "missing", name: "Missing", path: "/repo/missing", checked: 0),
        ]))
    }

    func testCliSessionItemsOnlyIncludeStandaloneQuickTerminals() {
        let builder = makeBuilder()
        let activeQuickSession = OpenWorkspaceSessionState(
            projectPath: "/tmp/active-quick/",
            controller: GhosttyWorkspaceController(projectPath: "/tmp/active-quick/"),
            isQuickTerminal: true
        )
        let recoverableQuickSession = OpenWorkspaceSessionState(
            projectPath: "/tmp/recoverable-quick",
            controller: GhosttyWorkspaceController(projectPath: "/tmp/recoverable-quick"),
            isQuickTerminal: true
        )
        let workspaceRootSession = OpenWorkspaceSessionState(
            projectPath: "/tmp/workspace-root",
            controller: GhosttyWorkspaceController(projectPath: "/tmp/workspace-root"),
            isQuickTerminal: true,
            workspaceRootContext: WorkspaceRootSessionContext(
                workspaceID: "workspace-1",
                workspaceName: "联调工作区"
            )
        )
        let regularSession = OpenWorkspaceSessionState(
            projectPath: "/repo/project",
            controller: GhosttyWorkspaceController(projectPath: "/repo/project")
        )

        let items = builder.cliSessionItems(
            sessions: [activeQuickSession, recoverableQuickSession, workspaceRootSession, regularSession],
            activeProjectPath: "/tmp/active-quick"
        )

        XCTAssertEqual(items.map(\.projectPath), ["/tmp/active-quick/", "/tmp/recoverable-quick"])
        XCTAssertEqual(items.map(\.statusText), ["已打开", "可恢复"])
        XCTAssertEqual(items[0].title, Project.quickTerminal(at: "/tmp/active-quick/").name)
        XCTAssertEqual(items[0].subtitle, "/tmp/active-quick/")
    }

    func testRecycleBinItemsUseStoredProjectNameOrFallbackLastPathComponent() {
        let builder = makeBuilder()
        let hiddenProject = makeProject(id: "hidden", name: "Hidden App", path: "/repo/hidden")

        let items = builder.recycleBinItems(
            recycleBin: ["/repo/hidden", "/repo/missing"],
            projects: [hiddenProject]
        )

        XCTAssertEqual(items, [
            NativeAppViewModel.RecycleBinItem(path: "/repo/hidden", name: "Hidden App", missing: false),
            NativeAppViewModel.RecycleBinItem(path: "/repo/missing", name: "missing", missing: true),
        ])
    }

    private func makeBuilder() -> ProjectCatalogSidebarProjectionBuilder {
        ProjectCatalogSidebarProjectionBuilder(
            normalizePath: normalizeProjectCatalogSidebarTestPath,
            pathLastComponent: { URL(fileURLWithPath: $0).lastPathComponent }
        )
    }

    private func makeProject(
        id: String,
        name: String,
        path: String,
        tags: [String] = [],
        isGitRepository: Bool = true,
        gitDaily: String? = nil,
        checked: SwiftDate = 0
    ) -> Project {
        Project(
            id: id,
            name: name,
            path: path,
            tags: tags,
            runConfigurations: [],
            worktrees: [],
            mtime: 0,
            size: 0,
            checksum: id,
            isGitRepository: isGitRepository,
            gitCommits: isGitRepository ? 1 : 0,
            gitLastCommit: 0,
            gitDaily: gitDaily,
            created: 0,
            checked: checked
        )
    }
}

private func normalizeProjectCatalogSidebarTestPath(_ path: String) -> String {
    var normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\\", with: "/")
    while normalized.count > 1 && normalized.hasSuffix("/") {
        normalized.removeLast()
    }
    return normalized
}
