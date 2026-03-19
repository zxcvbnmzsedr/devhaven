import Foundation
import Observation

@MainActor
@Observable
public final class NativeAppViewModel {
    @ObservationIgnored private let store: LegacyCompatStore
    @ObservationIgnored private var projectDocumentCache = [String: ProjectDocumentSnapshot]()
    @ObservationIgnored private let projectDocumentLoader: @Sendable (String) throws -> ProjectDocumentSnapshot
    @ObservationIgnored private let gitDailyCollector: @Sendable ([String], [GitIdentity]) -> [GitDailyRefreshResult]
    @ObservationIgnored private let gitDailyCollectorAsync: @Sendable ([String], [GitIdentity], @escaping @Sendable (Int, Int) async -> Void) async -> [GitDailyRefreshResult]
    @ObservationIgnored private let terminalCommandRunner: @Sendable (String, [String]) throws -> Void
    @ObservationIgnored private var projectDocumentLoadTask: Task<Void, Never>?
    @ObservationIgnored private var projectDocumentLoadRevision = 0

    public struct DirectoryRow: Identifiable, Equatable {
        public let id: String
        public let path: String?
        public let title: String
        public let count: Int
        public let isSystemEntry: Bool

        public init(path: String?, title: String, count: Int, isSystemEntry: Bool = false) {
            self.id = path ?? title
            self.path = path
            self.title = title
            self.count = count
            self.isSystemEntry = isSystemEntry
        }
    }

    public struct TagRow: Identifiable, Equatable {
        public let id: String
        public let name: String?
        public let title: String
        public let count: Int
        public let colorHex: String?

        public init(name: String?, title: String, count: Int, colorHex: String? = nil) {
            self.id = name ?? title
            self.name = name
            self.title = title
            self.count = count
            self.colorHex = colorHex
        }
    }

    public struct CLISessionItem: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let subtitle: String
        public let statusText: String
    }

    public var snapshot: NativeAppSnapshot
    public var selectedProjectPath: String?
    public var activeWorkspaceProjectPath: String?
    public var activeWorkspaceLaunchRequest: WorkspaceTerminalLaunchRequest?
    public var searchQuery: String
    public var selectedDirectory: String?
    public var selectedTag: String?
    public var selectedHeatmapDateKey: String?
    public var selectedDateFilter: NativeDateFilter
    public var selectedGitFilter: NativeGitFilter
    public var isLoading: Bool
    public var isRefreshingGitStatistics: Bool
    public var gitStatisticsProgressText: String?
    public var isProjectDocumentLoading: Bool
    public var errorMessage: String?
    public var isDashboardPresented: Bool
    public var isSettingsPresented: Bool
    public var isRecycleBinPresented: Bool
    public var isDetailPanelPresented: Bool
    public var notesDraft: String
    public var todoDraft: String
    public var todoItems: [TodoItem]
    public var readmeFallback: MarkdownDocument?
    public var hasLoadedInitialData: Bool

    public init(
        store: LegacyCompatStore = LegacyCompatStore(),
        projectDocumentLoader: (@Sendable (String) throws -> ProjectDocumentSnapshot)? = nil,
        gitDailyCollector: (@Sendable ([String], [GitIdentity]) -> [GitDailyRefreshResult])? = nil,
        gitDailyCollectorAsync: (@Sendable ([String], [GitIdentity], @escaping @Sendable (Int, Int) async -> Void) async -> [GitDailyRefreshResult])? = nil,
        terminalCommandRunner: (@Sendable (String, [String]) throws -> Void)? = nil
    ) {
        self.store = store
        self.projectDocumentLoader = projectDocumentLoader ?? loadProjectDocumentFromDisk
        self.gitDailyCollector = gitDailyCollector ?? collectGitDaily
        self.gitDailyCollectorAsync = gitDailyCollectorAsync ?? collectGitDailyAsync
        self.terminalCommandRunner = terminalCommandRunner ?? Self.runTerminalCommand
        self.snapshot = NativeAppSnapshot()
        self.selectedProjectPath = nil
        self.activeWorkspaceProjectPath = nil
        self.activeWorkspaceLaunchRequest = nil
        self.searchQuery = ""
        self.selectedDirectory = nil
        self.selectedTag = nil
        self.selectedHeatmapDateKey = nil
        self.selectedDateFilter = .all
        self.selectedGitFilter = .all
        self.isLoading = false
        self.isRefreshingGitStatistics = false
        self.gitStatisticsProgressText = nil
        self.isProjectDocumentLoading = false
        self.errorMessage = nil
        self.isDashboardPresented = false
        self.isSettingsPresented = false
        self.isRecycleBinPresented = false
        self.isDetailPanelPresented = false
        self.notesDraft = ""
        self.todoDraft = ""
        self.todoItems = []
        self.readmeFallback = nil
        self.hasLoadedInitialData = false
    }

    public var projectListViewMode: ProjectListViewMode {
        snapshot.appState.settings.projectListViewMode
    }

    public var visibleProjects: [Project] {
        let hidden = Set(snapshot.appState.recycleBin)
        return snapshot.projects.filter { !hidden.contains($0.path) }
    }

    public var filteredProjects: [Project] {
        visibleProjects.filter(matchesAllFilters)
    }

    public var selectedProject: Project? {
        guard let selectedProjectPath else {
            return filteredProjects.first ?? visibleProjects.first
        }
        return snapshot.projects.first(where: { $0.path == selectedProjectPath })
    }

    public var activeWorkspaceProject: Project? {
        guard let activeWorkspaceProjectPath else {
            return nil
        }
        return snapshot.projects.first(where: { $0.path == activeWorkspaceProjectPath })
    }

    public var isWorkspacePresented: Bool {
        activeWorkspaceProject != nil
    }

    public var directoryRows: [DirectoryRow] {
        var rows: [DirectoryRow] = [DirectoryRow(path: nil, title: "全部", count: visibleProjects.count, isSystemEntry: true)]
        rows.append(
            contentsOf: snapshot.appState.directories.map { directory in
                DirectoryRow(
                    path: directory,
                    title: URL(fileURLWithPath: directory).lastPathComponent,
                    count: visibleProjects.filter { $0.path.hasPrefix(directory) }.count
                )
            }
        )
        return rows
    }

    public var tagRows: [TagRow] {
        var counts = [String: Int]()
        for project in visibleProjects {
            for tag in project.tags {
                counts[tag, default: 0] += 1
            }
        }

        var rows: [TagRow] = [TagRow(name: nil, title: "全部", count: visibleProjects.count)]
        rows.append(
            contentsOf: snapshot.appState.tags
                .sorted { (counts[$0.name] ?? 0) > (counts[$1.name] ?? 0) }
                .map { tag in
                    TagRow(
                        name: tag.name,
                        title: tag.name,
                        count: counts[tag.name] ?? 0,
                        colorHex: hexColor(for: tag.color)
                    )
                }
        )
        return rows
    }

    public var sidebarHeatmapDays: [GitHeatmapDay] {
        buildGitHeatmapDays(projects: visibleProjects, days: GitDashboardRange.threeMonths.days)
    }

    public var isHeatmapFilterActive: Bool {
        selectedHeatmapDateKey != nil
    }

    public var heatmapActiveProjects: [GitActiveProject] {
        guard let selectedHeatmapDateKey else {
            return []
        }
        return buildGitActiveProjects(on: selectedHeatmapDateKey, projects: visibleProjects)
    }

    public var selectedHeatmapSummary: String? {
        guard let selectedHeatmapDateKey else {
            return nil
        }
        let totalCommits = heatmapActiveProjects.reduce(into: 0) { $0 += $1.commitCount }
        return "\(selectedHeatmapDateKey) · \(heatmapActiveProjects.count) 个活跃项目 · \(totalCommits) 次提交"
    }

    public var gitStatisticsLastUpdated: Date? {
        visibleProjects
            .map(\.checked)
            .filter { $0 != .zero }
            .max()
            .flatMap(swiftDateToDate)
    }

    public var cliSessionItems: [CLISessionItem] {
        let running = visibleProjects.filter { !($0.worktrees.isEmpty && $0.scripts.isEmpty) }.prefix(4)
        return running.map { project in
            CLISessionItem(
                id: project.id,
                title: project.name,
                subtitle: URL(fileURLWithPath: project.path).lastPathComponent,
                statusText: project.worktrees.isEmpty ? "配置中" : "已关联"
            )
        }
    }

    public var recycleBinItems: [RecycleBinItem] {
        snapshot.appState.recycleBin.map { path in
            if let project = snapshot.projects.first(where: { $0.path == path }) {
                return RecycleBinItem(path: path, name: project.name, missing: false)
            }
            return RecycleBinItem(path: path, name: URL(fileURLWithPath: path).lastPathComponent, missing: true)
        }
    }

    public func load() {
        isLoading = true
        defer {
            isLoading = false
            hasLoadedInitialData = true
        }

        do {
            projectDocumentCache.removeAll()
            snapshot = try store.loadSnapshot()
            alignSelectionAfterReload()
            scheduleSelectedProjectDocumentRefresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func refresh() {
        load()
    }

    @discardableResult
    public func refreshGitStatistics() throws -> GitStatisticsRefreshSummary {
        let targetProjects = visibleProjects.filter { $0.gitCommits > 0 }
        guard !targetProjects.isEmpty else {
            return GitStatisticsRefreshSummary(requestedRepositories: 0, updatedRepositories: 0, failedRepositories: 0)
        }

        isRefreshingGitStatistics = true
        defer { isRefreshingGitStatistics = false }

        let results = gitDailyCollector(targetProjects.map(\.path), snapshot.appState.settings.gitIdentities)
        try store.updateProjectsGitDaily(results)
        load()

        return makeGitStatisticsRefreshSummary(from: results)
    }

    public func refreshGitStatisticsAsync() async throws -> GitStatisticsRefreshSummary {
        let targetProjects = visibleProjects.filter { $0.gitCommits > 0 }
        guard !targetProjects.isEmpty else {
            return GitStatisticsRefreshSummary(requestedRepositories: 0, updatedRepositories: 0, failedRepositories: 0)
        }

        isRefreshingGitStatistics = true
        gitStatisticsProgressText = "正在扫描 \(targetProjects.count) 个 Git 仓库..."
        defer {
            isRefreshingGitStatistics = false
            gitStatisticsProgressText = nil
        }

        let paths = targetProjects.map(\.path)
        let identities = snapshot.appState.settings.gitIdentities
        let collector = gitDailyCollectorAsync
        let results = await collector(paths, identities) { completed, total in
            await MainActor.run {
                if completed < total {
                    self.gitStatisticsProgressText = "正在扫描 \(completed)/\(total) 个 Git 仓库..."
                } else {
                    self.gitStatisticsProgressText = "正在写入统计结果..."
                }
            }
        }

        gitStatisticsProgressText = "正在写入统计结果..."
        try store.updateProjectsGitDaily(results)
        gitStatisticsProgressText = "正在刷新项目列表..."
        load()

        return makeGitStatisticsRefreshSummary(from: results)
    }

    private func makeGitStatisticsRefreshSummary(from results: [GitDailyRefreshResult]) -> GitStatisticsRefreshSummary {
        let failedRepositories = results.reduce(into: 0) { partialResult, result in
            if result.error != nil {
                partialResult += 1
            }
        }
        let updatedRepositories = results.reduce(into: 0) { partialResult, result in
            if result.error == nil {
                partialResult += 1
            }
        }
        return GitStatisticsRefreshSummary(
            requestedRepositories: results.count,
            updatedRepositories: updatedRepositories,
            failedRepositories: failedRepositories
        )
    }

    public func selectProject(_ path: String?) {
        if path == selectedProjectPath, isDetailPanelPresented == (path != nil) {
            return
        }
        if let activeWorkspaceProjectPath, path != activeWorkspaceProjectPath {
            self.activeWorkspaceProjectPath = nil
            self.activeWorkspaceLaunchRequest = nil
        }
        selectedProjectPath = path
        isDetailPanelPresented = path != nil
        scheduleSelectedProjectDocumentRefresh()
    }

    public func enterWorkspace(_ path: String) {
        selectedProjectPath = path
        activeWorkspaceProjectPath = path
        activeWorkspaceLaunchRequest = WorkspaceTerminalLaunchRequest(
            projectPath: path,
            workspaceId: "workspace:\(UUID().uuidString.lowercased())",
            tabId: "tab:\(UUID().uuidString.lowercased())",
            paneId: "pane:\(UUID().uuidString.lowercased())",
            surfaceId: "surface:\(UUID().uuidString.lowercased())",
            terminalSessionId: "session:\(UUID().uuidString.lowercased())"
        )
        isDetailPanelPresented = false
        scheduleSelectedProjectDocumentRefresh()
    }

    public func exitWorkspace() {
        activeWorkspaceProjectPath = nil
        activeWorkspaceLaunchRequest = nil
    }

    public func openActiveWorkspaceInTerminal() throws {
        guard let project = activeWorkspaceProject else {
            let error = WorkspaceTerminalCommandError.noActiveWorkspace
            errorMessage = error.localizedDescription
            throw error
        }

        do {
            try terminalCommandRunner("/usr/bin/open", ["-a", "Terminal", project.path])
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    public func closeDetailPanel() {
        isDetailPanelPresented = false
    }

    public func selectDirectory(_ path: String?) {
        selectedDirectory = path
        reconcileSelectionAfterFilterChange()
    }

    public func selectTag(_ name: String?) {
        selectedTag = name
        reconcileSelectionAfterFilterChange()
    }

    public func selectHeatmapDate(_ dateKey: String?) {
        selectedHeatmapDateKey = dateKey
        reconcileSelectionAfterFilterChange()
    }

    public func clearHeatmapDateFilter() {
        selectedHeatmapDateKey = nil
        reconcileSelectionAfterFilterChange()
    }

    public func updateDateFilter(_ filter: NativeDateFilter) {
        selectedDateFilter = filter
        reconcileSelectionAfterFilterChange()
    }

    public func updateGitFilter(_ filter: NativeGitFilter) {
        selectedGitFilter = filter
        reconcileSelectionAfterFilterChange()
    }

    public func updateProjectListViewMode(_ mode: ProjectListViewMode) {
        guard snapshot.appState.settings.projectListViewMode != mode else {
            return
        }
        var nextSettings = snapshot.appState.settings
        nextSettings.projectListViewMode = mode
        saveSettings(nextSettings)
    }

    public func dismissError() {
        errorMessage = nil
    }

    public func addTodoItem() {
        let text = todoDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        todoItems.append(TodoItem(text: text, done: false))
        todoDraft = ""
    }

    public func toggleTodo(id: TodoItem.ID) {
        guard let index = todoItems.firstIndex(where: { $0.id == id }) else { return }
        todoItems[index].done.toggle()
    }

    public func removeTodo(id: TodoItem.ID) {
        todoItems.removeAll { $0.id == id }
    }

    public func saveNotes() {
        guard let project = selectedProject else { return }
        do {
            let value = notesDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notesDraft
            try store.writeNotes(value, for: project.path)
            let document = ProjectDocumentSnapshot(
                notes: value,
                todoItems: todoItems,
                readmeFallback: readmeFallback
            )
            projectDocumentCache[project.path] = document
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func saveTodo() {
        guard let project = selectedProject else { return }
        do {
            try store.writeTodoItems(todoItems, for: project.path)
            let document = ProjectDocumentSnapshot(
                notes: notesDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notesDraft,
                todoItems: todoItems,
                readmeFallback: readmeFallback
            )
            projectDocumentCache[project.path] = document
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func moveProjectToRecycleBin(_ path: String) {
        do {
            let nextPaths = Array(Set(snapshot.appState.recycleBin + [path])).sorted()
            try store.updateRecycleBin(nextPaths)
            snapshot.appState.recycleBin = nextPaths
            if selectedProjectPath == path {
                isDetailPanelPresented = false
            }
            reconcileSelectionAfterFilterChange()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func toggleProjectFavorite(_ path: String) {
        var favorites = Set(snapshot.appState.favoriteProjectPaths)
        if favorites.contains(path) {
            favorites.remove(path)
        } else {
            favorites.insert(path)
        }
        let nextFavoritePaths = favorites.sorted()
        do {
            try store.updateFavoriteProjectPaths(nextFavoritePaths)
            snapshot.appState.favoriteProjectPaths = nextFavoritePaths
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func restoreProjectFromRecycleBin(_ path: String) {
        do {
            let nextPaths = snapshot.appState.recycleBin.filter { $0 != path }
            try store.updateRecycleBin(nextPaths)
            snapshot.appState.recycleBin = nextPaths
            reconcileSelectionAfterFilterChange()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func saveSettings(_ settings: AppSettings) {
        do {
            try store.updateSettings(settings)
            snapshot.appState.settings = settings
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func revealSettings() {
        isSettingsPresented = true
    }

    public func revealDashboard() {
        isDashboardPresented = true
    }

    public func revealRecycleBin() {
        isRecycleBinPresented = true
    }

    public func hideDashboard() {
        isDashboardPresented = false
    }

    public func hideSettings() {
        isSettingsPresented = false
    }

    public func hideRecycleBin() {
        isRecycleBinPresented = false
    }

    public struct RecycleBinItem: Identifiable, Equatable {
        public var id: String { path }
        public var path: String
        public var name: String
        public var missing: Bool
    }

    private func alignSelectionAfterReload() {
        let allPaths = Set(snapshot.projects.map(\.path))
        if let activeWorkspaceProjectPath, !allPaths.contains(activeWorkspaceProjectPath) {
            self.activeWorkspaceProjectPath = nil
            self.activeWorkspaceLaunchRequest = nil
        }
        let availablePaths = Set(filteredProjects.map(\.path))
        if let selectedProjectPath, availablePaths.contains(selectedProjectPath) {
            return
        }
        selectedProjectPath = filteredProjects.first?.path ?? visibleProjects.first?.path
    }

    private func reconcileSelectionAfterFilterChange() {
        let previousSelectedPath = selectedProjectPath
        alignSelectionAfterReload()
        guard selectedProjectPath != previousSelectedPath else {
            return
        }
        scheduleSelectedProjectDocumentRefresh()
    }

    private func scheduleSelectedProjectDocumentRefresh() {
        projectDocumentLoadTask?.cancel()
        projectDocumentLoadTask = nil
        projectDocumentLoadRevision &+= 1
        let revision = projectDocumentLoadRevision

        guard let project = selectedProject else {
            isProjectDocumentLoading = false
            clearDisplayedProjectDocument(preserveTodoDraft: false)
            return
        }

        if let cached = projectDocumentCache[project.path] {
            isProjectDocumentLoading = false
            applyProjectDocument(cached)
            return
        }

        isProjectDocumentLoading = true
        clearDisplayedProjectDocument(preserveTodoDraft: true)

        let projectPath = project.path
        let loader = projectDocumentLoader
        let backgroundTask = Task.detached(priority: .userInitiated) {
            do {
                return ProjectDocumentLoadOutcome.success(try loader(projectPath))
            } catch {
                return .failure(error.localizedDescription)
            }
        }

        projectDocumentLoadTask = Task { @MainActor [weak self] in
            let outcome = await withTaskCancellationHandler(operation: {
                await backgroundTask.value
            }, onCancel: {
                backgroundTask.cancel()
            })
            guard !Task.isCancelled, let self else {
                return
            }
            guard revision == self.projectDocumentLoadRevision else {
                return
            }

            self.projectDocumentLoadTask = nil
            self.isProjectDocumentLoading = false

            switch outcome {
            case let .success(document):
                self.projectDocumentCache[projectPath] = document
                self.applyProjectDocument(document)
            case let .failure(message):
                self.errorMessage = message
                self.clearDisplayedProjectDocument(preserveTodoDraft: true)
            }
        }
    }

    private func clearDisplayedProjectDocument(preserveTodoDraft: Bool) {
        notesDraft = ""
        if !preserveTodoDraft {
            todoDraft = ""
        }
        todoItems = []
        readmeFallback = nil
    }

    private func applyProjectDocument(_ document: ProjectDocumentSnapshot) {
        notesDraft = document.notes ?? ""
        todoItems = document.todoItems
        readmeFallback = document.readmeFallback
    }

    private func matchesAllFilters(project: Project) -> Bool {
        if let selectedDirectory, !project.path.hasPrefix(selectedDirectory) {
            return false
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
        case .gitOnly where project.gitCommits <= 0:
            return false
        case .nonGitOnly where project.gitCommits > 0:
            return false
        default:
            break
        }
        if !matchesDateFilter(project: project) {
            return false
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return true
        }
        return project.name.lowercased().contains(query)
            || project.path.lowercased().contains(query)
            || project.tags.contains(where: { $0.lowercased().contains(query) })
            || (project.gitLastCommitMessage?.lowercased().contains(query) ?? false)
    }

    private func matchesDateFilter(project: Project) -> Bool {
        guard selectedDateFilter != .all else {
            return true
        }
        guard let date = swiftDateToDate(project.mtime) else {
            return false
        }
        let now = Date()
        let interval: TimeInterval = selectedDateFilter == .lastDay ? 24 * 60 * 60 : 7 * 24 * 60 * 60
        return now.timeIntervalSince(date) <= interval
    }

    public func gitDashboardSummary(for range: GitDashboardRange) -> GitDashboardSummary {
        buildGitDashboardSummary(projects: visibleProjects, tagCount: snapshot.appState.tags.count, range: range)
    }

    public func gitDashboardDailyActivities(for range: GitDashboardRange) -> [GitDashboardDailyActivity] {
        buildGitDashboardDailyActivities(projects: visibleProjects, range: range)
    }

    public func gitDashboardProjectActivities(for range: GitDashboardRange) -> [GitDashboardProjectActivity] {
        buildGitDashboardProjectActivities(projects: visibleProjects, range: range)
    }

    public func gitDashboardHeatmapDays(for range: GitDashboardRange) -> [GitHeatmapDay] {
        buildGitHeatmapDays(projects: visibleProjects, days: range.days)
    }

    private nonisolated static func runTerminalCommand(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw WorkspaceTerminalCommandError.launchFailed("打开 Terminal 失败，退出码 \(process.terminationStatus)。")
        }
    }
}

enum WorkspaceTerminalCommandError: LocalizedError {
    case noActiveWorkspace
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .noActiveWorkspace:
            return "当前没有可打开的工作区。"
        case let .launchFailed(message):
            return message
        }
    }
}

private enum ProjectDocumentLoadOutcome: Sendable {
    case success(ProjectDocumentSnapshot)
    case failure(String)
}

private func loadProjectDocumentFromDisk(_ projectPath: String) throws -> ProjectDocumentSnapshot {
    try LegacyCompatStore().loadProjectDocument(at: projectPath)
}

private func hexColor(for color: ColorData) -> String {
    let r = Int(max(0, min(255, round(color.r * 255))))
    let g = Int(max(0, min(255, round(color.g * 255))))
    let b = Int(max(0, min(255, round(color.b * 255))))
    return String(format: "#%02X%02X%02X", r, g, b)
}
