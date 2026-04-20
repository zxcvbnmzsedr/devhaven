import Foundation
import CoreGraphics

public enum GitDashboardRange: String, Sendable, CaseIterable, Identifiable {
    case oneMonth
    case threeMonths
    case sixMonths
    case oneYear

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .oneMonth:
            return "最近1个月"
        case .threeMonths:
            return "最近3个月"
        case .sixMonths:
            return "最近6个月"
        case .oneYear:
            return "最近1年"
        }
    }

    public var days: Int {
        switch self {
        case .oneMonth:
            return 30
        case .threeMonths:
            return 90
        case .sixMonths:
            return 180
        case .oneYear:
            return 365
        }
    }
}

public struct GitHeatmapDay: Identifiable, Equatable, Sendable {
    public var id: String { dateKey }
    public var date: Date
    public var dateKey: String
    public var commitCount: Int
    public var intensity: Int
    public var projectPaths: [String]

    public init(date: Date, dateKey: String, commitCount: Int, intensity: Int, projectPaths: [String]) {
        self.date = date
        self.dateKey = dateKey
        self.commitCount = commitCount
        self.intensity = intensity
        self.projectPaths = projectPaths
    }
}

public struct GitActiveProject: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public var path: String
    public var name: String
    public var commitCount: Int

    public init(path: String, name: String, commitCount: Int) {
        self.path = path
        self.name = name
        self.commitCount = commitCount
    }
}

public struct GitDashboardSummary: Equatable, Sendable {
    public var projectCount: Int
    public var gitProjectCount: Int
    public var tagCount: Int
    public var activeDays: Int
    public var totalCommits: Int
    public var maxCommitsInDay: Int
    public var averageCommitsPerDay: Double
    public var activityRate: Double

    public init(
        projectCount: Int,
        gitProjectCount: Int,
        tagCount: Int,
        activeDays: Int,
        totalCommits: Int,
        maxCommitsInDay: Int,
        averageCommitsPerDay: Double,
        activityRate: Double
    ) {
        self.projectCount = projectCount
        self.gitProjectCount = gitProjectCount
        self.tagCount = tagCount
        self.activeDays = activeDays
        self.totalCommits = totalCommits
        self.maxCommitsInDay = maxCommitsInDay
        self.averageCommitsPerDay = averageCommitsPerDay
        self.activityRate = activityRate
    }
}

public struct GitDashboardDailyActivity: Identifiable, Equatable, Sendable {
    public var id: String { dateKey }
    public var date: Date
    public var dateKey: String
    public var commitCount: Int
    public var projectPaths: [String]

    public init(date: Date, dateKey: String, commitCount: Int, projectPaths: [String]) {
        self.date = date
        self.dateKey = dateKey
        self.commitCount = commitCount
        self.projectPaths = projectPaths
    }
}

public struct GitDashboardProjectActivity: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var commitCount: Int
    public var activeDays: Int

    public init(name: String, path: String, commitCount: Int, activeDays: Int) {
        self.name = name
        self.path = path
        self.commitCount = commitCount
        self.activeDays = activeDays
    }
}

public struct GitStatisticsRefreshSummary: Equatable, Sendable {
    public var requestedRepositories: Int
    public var updatedRepositories: Int
    public var failedRepositories: Int

    public init(requestedRepositories: Int, updatedRepositories: Int, failedRepositories: Int) {
        self.requestedRepositories = requestedRepositories
        self.updatedRepositories = updatedRepositories
        self.failedRepositories = failedRepositories
    }

    public init(results: [GitDailyRefreshResult]) {
        self.init(
            requestedRepositories: results.count,
            updatedRepositories: results.reduce(into: 0) { count, result in
                if result.error == nil {
                    count += 1
                }
            },
            failedRepositories: results.reduce(into: 0) { count, result in
                if result.error != nil {
                    count += 1
                }
            }
        )
    }
}

public struct GitDailyRefreshResult: Equatable, Sendable {
    public var path: String
    public var gitDaily: String?
    public var gitCommits: Int?
    public var gitLastCommit: SwiftDate?
    public var gitLastCommitMessage: String?
    public var error: String?

    public init(
        path: String,
        gitDaily: String?,
        gitCommits: Int? = nil,
        gitLastCommit: SwiftDate? = nil,
        gitLastCommitMessage: String? = nil,
        error: String?
    ) {
        self.path = path
        self.gitDaily = gitDaily
        self.gitCommits = gitCommits
        self.gitLastCommit = gitLastCommit
        self.gitLastCommitMessage = gitLastCommitMessage
        self.error = error
    }
}

public struct GitDashboardLayoutPlan: Equatable, Sendable {
    public var statColumnCount: Int
    public var stackSecondarySectionsVertically: Bool

    public init(statColumnCount: Int, stackSecondarySectionsVertically: Bool) {
        self.statColumnCount = statColumnCount
        self.stackSecondarySectionsVertically = stackSecondarySectionsVertically
    }
}

public func buildGitDashboardLayoutPlan(width: CGFloat) -> GitDashboardLayoutPlan {
    switch width {
    case ..<720:
        return GitDashboardLayoutPlan(statColumnCount: 2, stackSecondarySectionsVertically: true)
    case ..<1080:
        return GitDashboardLayoutPlan(statColumnCount: 2, stackSecondarySectionsVertically: true)
    default:
        return GitDashboardLayoutPlan(statColumnCount: 3, stackSecondarySectionsVertically: false)
    }
}

func buildGitHeatmapDays(projects: [Project], days: Int, now: Date = Date()) -> [GitHeatmapDay] {
    let normalizedDays = max(1, days)
    let calendar = Calendar.current
    let endDate = calendar.startOfDay(for: now)
    guard let startDate = calendar.date(byAdding: .day, value: -(normalizedDays - 1), to: endDate) else {
        return []
    }

    let startKey = gitDateKey(startDate)
    let endKey = gitDateKey(endDate)
    var countsByDate = [String: Int]()
    var projectPathsByDate = [String: [String]]()

    for project in projects {
        guard project.isGitRepository else {
            continue
        }
        for (dateKey, count) in parseGitDailyMap(project.gitDaily) where dateKey >= startKey && dateKey <= endKey {
            countsByDate[dateKey, default: 0] += count
            if count > 0 {
                projectPathsByDate[dateKey, default: []].append(project.path)
            }
        }
    }

    let maxCount = countsByDate.values.max() ?? 0
    return (0..<normalizedDays).compactMap { offset in
        guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else {
            return nil
        }
        let dateKey = gitDateKey(date)
        let commitCount = countsByDate[dateKey] ?? 0
        return GitHeatmapDay(
            date: date,
            dateKey: dateKey,
            commitCount: commitCount,
            intensity: calculateHeatmapIntensity(count: commitCount, maxCount: maxCount),
            projectPaths: Array(Set(projectPathsByDate[dateKey] ?? [])).sorted()
        )
    }
}

func buildGitActiveProjects(on dateKey: String, projects: [Project]) -> [GitActiveProject] {
    projects
        .compactMap { project in
            let commitCount = gitCommitCount(on: dateKey, project: project)
            guard commitCount > 0 else {
                return nil
            }
            return GitActiveProject(path: project.path, name: project.name, commitCount: commitCount)
        }
        .sorted { left, right in
            if left.commitCount != right.commitCount {
                return left.commitCount > right.commitCount
            }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
}

func buildGitDashboardSummary(
    projects: [Project],
    tagCount: Int,
    range: GitDashboardRange,
    now: Date = Date()
) -> GitDashboardSummary {
    let data = buildGitHeatmapDays(projects: projects, days: range.days, now: now)
    let totalCommits = data.reduce(into: 0) { $0 += $1.commitCount }
    let activeDays = data.reduce(into: 0) { partialResult, day in
        if day.commitCount > 0 {
            partialResult += 1
        }
    }
    let maxCommitsInDay = data.map(\.commitCount).max() ?? 0
    let projectCount = projects.count
    let gitProjectCount = projects.reduce(into: 0) { partialResult, project in
        if project.isGitRepository {
            partialResult += 1
        }
    }
    let averageCommitsPerDay = data.isEmpty ? 0 : Double(totalCommits) / Double(data.count)
    let activityRate = data.isEmpty ? 0 : Double(activeDays) / Double(data.count)

    return GitDashboardSummary(
        projectCount: projectCount,
        gitProjectCount: gitProjectCount,
        tagCount: tagCount,
        activeDays: activeDays,
        totalCommits: totalCommits,
        maxCommitsInDay: maxCommitsInDay,
        averageCommitsPerDay: averageCommitsPerDay,
        activityRate: activityRate
    )
}

func buildGitDashboardDailyActivities(
    projects: [Project],
    range: GitDashboardRange,
    now: Date = Date()
) -> [GitDashboardDailyActivity] {
    buildGitHeatmapDays(projects: projects, days: range.days, now: now)
        .filter { $0.commitCount > 0 }
        .map {
            GitDashboardDailyActivity(
                date: $0.date,
                dateKey: $0.dateKey,
                commitCount: $0.commitCount,
                projectPaths: $0.projectPaths
            )
        }
        .sorted { $0.date > $1.date }
}

func buildGitDashboardProjectActivities(
    projects: [Project],
    range: GitDashboardRange,
    now: Date = Date()
) -> [GitDashboardProjectActivity] {
    let calendar = Calendar.current
    let endDate = calendar.startOfDay(for: now)
    guard let startDate = calendar.date(byAdding: .day, value: -(range.days - 1), to: endDate) else {
        return []
    }
    let startKey = gitDateKey(startDate)
    let endKey = gitDateKey(endDate)

    return projects
        .compactMap { project in
            let map = parseGitDailyMap(project.gitDaily)
            var commitCount = 0
            var activeDays = 0
            for (dateKey, count) in map where dateKey >= startKey && dateKey <= endKey {
                commitCount += count
                if count > 0 {
                    activeDays += 1
                }
            }
            guard commitCount > 0 else {
                return nil
            }
            return GitDashboardProjectActivity(
                name: project.name,
                path: project.path,
                commitCount: commitCount,
                activeDays: activeDays
            )
        }
        .sorted { left, right in
            if left.commitCount != right.commitCount {
                return left.commitCount > right.commitCount
            }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
}

func gitCommitCount(on dateKey: String, project: Project) -> Int {
    guard project.isGitRepository else {
        return 0
    }
    return parseGitDailyMap(project.gitDaily)[dateKey] ?? 0
}

func parseGitDailyMap(_ gitDaily: String?) -> [String: Int] {
    guard let gitDaily, !gitDaily.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return [:]
    }
    return gitDaily
        .split(separator: ",")
        .reduce(into: [String: Int]()) { result, pair in
            let parts = pair.split(separator: ":")
            guard parts.count == 2, let count = Int(parts[1]) else {
                return
            }
            result[String(parts[0])] = count
        }
}

func gitDateKey(_ date: Date) -> String {
    let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
    let year = components.year ?? 0
    let month = components.month ?? 1
    let day = components.day ?? 1
    return String(format: "%04d-%02d-%02d", year, month, day)
}

private func calculateHeatmapIntensity(count: Int, maxCount: Int) -> Int {
    guard count > 0, maxCount > 0 else {
        return 0
    }
    let ratio = Double(count) / Double(maxCount)
    let level = Int(ceil(ratio * 4))
    return max(1, min(4, level))
}
