import Foundation

@MainActor
final class ProjectCatalogSidebarProjectionBuilder {
    private let normalizePath: @MainActor (String) -> String
    private let pathLastComponent: @MainActor (String) -> String

    init(
        normalizePath: @escaping @MainActor (String) -> String,
        pathLastComponent: @escaping @MainActor (String) -> String
    ) {
        self.normalizePath = normalizePath
        self.pathLastComponent = pathLastComponent
    }

    func directoryRows(
        visibleProjects: [Project],
        directories: [String],
        directProjectPaths: [String]
    ) -> [NativeAppViewModel.DirectoryRow] {
        let directProjectPathSet = Set(directProjectPaths.map(normalizePath))
        var rows: [NativeAppViewModel.DirectoryRow] = [
            NativeAppViewModel.DirectoryRow(
                filter: .all,
                title: "全部",
                count: visibleProjects.count,
                isSystemEntry: true
            ),
        ]
        rows.append(
            NativeAppViewModel.DirectoryRow(
                filter: .directProjects,
                title: "直接添加",
                count: visibleProjects.filter { directProjectPathSet.contains(normalizePath($0.path)) }.count,
                isSystemEntry: true
            )
        )
        rows.append(
            contentsOf: directories.map { directory in
                NativeAppViewModel.DirectoryRow(
                    filter: .directory(directory),
                    title: pathLastComponent(directory),
                    count: visibleProjects.filter { $0.path.hasPrefix(directory) }.count
                )
            }
        )
        return rows
    }

    func tagRows(
        visibleProjects: [Project],
        tags: [TagData]
    ) -> [NativeAppViewModel.TagRow] {
        var counts = [String: Int]()
        for project in visibleProjects {
            for tag in project.tags {
                counts[tag, default: 0] += 1
            }
        }

        var rows: [NativeAppViewModel.TagRow] = [
            NativeAppViewModel.TagRow(name: nil, title: "全部", count: visibleProjects.count),
        ]
        rows.append(
            contentsOf: tags
                .sorted { (counts[$0.name] ?? 0) > (counts[$1.name] ?? 0) }
                .map { tag in
                    NativeAppViewModel.TagRow(
                        name: tag.name,
                        title: tag.name,
                        count: counts[tag.name] ?? 0,
                        colorHex: hexColor(for: tag.color)
                    )
                }
        )
        return rows
    }

    func sidebarHeatmapDays(
        visibleProjects: [Project],
        days: Int = GitDashboardRange.threeMonths.days,
        now: Date = Date()
    ) -> [GitHeatmapDay] {
        buildGitHeatmapDays(projects: visibleProjects, days: days, now: now)
    }

    func heatmapActiveProjects(
        selectedDateKey: String?,
        visibleProjects: [Project]
    ) -> [GitActiveProject] {
        guard let selectedDateKey else {
            return []
        }
        return buildGitActiveProjects(on: selectedDateKey, projects: visibleProjects)
    }

    func selectedHeatmapSummary(
        selectedDateKey: String?,
        activeProjects: [GitActiveProject]
    ) -> String? {
        guard let selectedDateKey else {
            return nil
        }
        let totalCommits = activeProjects.reduce(into: 0) { $0 += $1.commitCount }
        return "\(selectedDateKey) · \(activeProjects.count) 个活跃项目 · \(totalCommits) 次提交"
    }

    func gitStatisticsLastUpdated(visibleProjects: [Project]) -> Date? {
        visibleProjects
            .map(\.checked)
            .filter { $0 != .zero }
            .max()
            .flatMap(swiftDateToDate)
    }

    func cliSessionItems(
        sessions: [OpenWorkspaceSessionState],
        activeProjectPath: String?
    ) -> [NativeAppViewModel.CLISessionItem] {
        sessions
            .filter { $0.isQuickTerminal && $0.workspaceRootContext == nil }
            .map { session in
                NativeAppViewModel.CLISessionItem(
                    projectPath: session.projectPath,
                    title: Project.quickTerminal(at: session.projectPath).name,
                    subtitle: session.projectPath,
                    statusText: normalizePath(activeProjectPath ?? "") == normalizePath(session.projectPath) ? "已打开" : "可恢复"
                )
            }
    }

    func recycleBinItems(
        recycleBin: [String],
        projects: [Project]
    ) -> [NativeAppViewModel.RecycleBinItem] {
        recycleBin.map { path in
            if let project = projects.first(where: { $0.path == path }) {
                return NativeAppViewModel.RecycleBinItem(path: path, name: project.name, missing: false)
            }
            return NativeAppViewModel.RecycleBinItem(path: path, name: pathLastComponent(path), missing: true)
        }
    }
}
