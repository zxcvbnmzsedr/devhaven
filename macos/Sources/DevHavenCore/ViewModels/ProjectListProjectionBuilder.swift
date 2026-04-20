import Foundation

@MainActor
final class ProjectListProjectionBuilder {
    private let normalizePath: @MainActor (String) -> String

    init(normalizePath: @escaping @MainActor (String) -> String) {
        self.normalizePath = normalizePath
    }

    func visibleProjects(
        projects: [Project],
        recycleBin: [String]
    ) -> [Project] {
        let hidden = Set(recycleBin)
        return projects.filter { !hidden.contains($0.path) }
    }

    func filteredProjects(
        visibleProjects: [Project],
        searchQuery: String,
        selectedDirectory: NativeAppViewModel.DirectoryFilter,
        directProjectPaths: [String],
        selectedHeatmapDateKey: String?,
        selectedTag: String?,
        selectedDateFilter: NativeDateFilter,
        selectedGitFilter: NativeGitFilter,
        sortOrder: ProjectListSortOrder,
        now: Date = Date()
    ) -> [Project] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let directProjectPathSet = Set(directProjectPaths.map(normalizePath))
        let filtered = visibleProjects.filter {
            matchesAllFilters(
                project: $0,
                query: query,
                selectedDirectory: selectedDirectory,
                directProjectPathSet: directProjectPathSet,
                selectedHeatmapDateKey: selectedHeatmapDateKey,
                selectedTag: selectedTag,
                selectedDateFilter: selectedDateFilter,
                selectedGitFilter: selectedGitFilter,
                now: now
            )
        }
        return sortProjects(filtered, sortOrder: sortOrder)
    }

    private func matchesAllFilters(
        project: Project,
        query: String,
        selectedDirectory: NativeAppViewModel.DirectoryFilter,
        directProjectPathSet: Set<String>,
        selectedHeatmapDateKey: String?,
        selectedTag: String?,
        selectedDateFilter: NativeDateFilter,
        selectedGitFilter: NativeGitFilter,
        now: Date
    ) -> Bool {
        switch selectedDirectory {
        case .all:
            break
        case let .directory(path):
            if !project.path.hasPrefix(path) {
                return false
            }
        case .directProjects:
            if !directProjectPathSet.contains(normalizePath(project.path)) {
                return false
            }
        }

        if let selectedHeatmapDateKey {
            if gitCommitCount(on: selectedHeatmapDateKey, project: project) <= 0 {
                return false
            }
        } else if let selectedTag, !project.tags.contains(selectedTag) {
            return false
        }

        switch selectedGitFilter {
        case .all:
            break
        case .gitOnly where !project.isGitRepository:
            return false
        case .nonGitOnly where project.isGitRepository:
            return false
        default:
            break
        }

        if !matchesDateFilter(project: project, selectedDateFilter: selectedDateFilter, now: now) {
            return false
        }

        guard !query.isEmpty else {
            return true
        }
        return project.name.lowercased().contains(query)
            || project.path.lowercased().contains(query)
            || (project.notesSummary?.lowercased().contains(query) ?? false)
            || project.tags.contains(where: { $0.lowercased().contains(query) })
            || (project.isGitRepository && (project.gitLastCommitMessage?.lowercased().contains(query) ?? false))
    }

    private func matchesDateFilter(
        project: Project,
        selectedDateFilter: NativeDateFilter,
        now: Date
    ) -> Bool {
        guard selectedDateFilter != .all else {
            return true
        }
        guard let date = swiftDateToDate(project.mtime) else {
            return false
        }
        let interval: TimeInterval = selectedDateFilter == .lastDay ? 24 * 60 * 60 : 7 * 24 * 60 * 60
        return now.timeIntervalSince(date) <= interval
    }

    private func sortProjects(
        _ projects: [Project],
        sortOrder: ProjectListSortOrder
    ) -> [Project] {
        switch sortOrder {
        case .defaultOrder:
            return projects
        case .nameAscending:
            return projects.sorted { lhs, rhs in
                compareProjectsByName(lhs: lhs, rhs: rhs, ascending: true)
            }
        case .nameDescending:
            return projects.sorted { lhs, rhs in
                compareProjectsByName(lhs: lhs, rhs: rhs, ascending: false)
            }
        case .modifiedNewestFirst:
            return projects.sorted { lhs, rhs in
                compareProjectsByModifiedTime(lhs: lhs, rhs: rhs, newestFirst: true)
            }
        case .modifiedOldestFirst:
            return projects.sorted { lhs, rhs in
                compareProjectsByModifiedTime(lhs: lhs, rhs: rhs, newestFirst: false)
            }
        }
    }

    private func compareProjectsByName(
        lhs: Project,
        rhs: Project,
        ascending: Bool
    ) -> Bool {
        let comparison = lhs.name.localizedStandardCompare(rhs.name)
        if comparison != .orderedSame {
            return ascending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
        }
        return compareProjectsByModifiedTime(lhs: lhs, rhs: rhs, newestFirst: true)
    }

    private func compareProjectsByModifiedTime(
        lhs: Project,
        rhs: Project,
        newestFirst: Bool
    ) -> Bool {
        if lhs.mtime != rhs.mtime {
            return newestFirst ? lhs.mtime > rhs.mtime : lhs.mtime < rhs.mtime
        }
        let comparison = lhs.name.localizedStandardCompare(rhs.name)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
    }
}
