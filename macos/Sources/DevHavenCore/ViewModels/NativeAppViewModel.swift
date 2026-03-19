import Foundation
import Observation

@MainActor
@Observable
public final class NativeAppViewModel {
    @ObservationIgnored private let store: LegacyCompatStore

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

    public struct HeatmapCell: Identifiable, Equatable {
        public let id: String
        public let dateKey: String
        public let intensity: Int
        public let count: Int

        public init(dateKey: String, intensity: Int, count: Int) {
            self.id = dateKey
            self.dateKey = dateKey
            self.intensity = intensity
            self.count = count
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
    public var searchQuery: String
    public var selectedDirectory: String?
    public var selectedTag: String?
    public var selectedDateFilter: NativeDateFilter
    public var selectedGitFilter: NativeGitFilter
    public var isLoading: Bool
    public var errorMessage: String?
    public var isSettingsPresented: Bool
    public var isRecycleBinPresented: Bool
    public var isDetailPanelPresented: Bool
    public var notesDraft: String
    public var todoDraft: String
    public var todoItems: [TodoItem]
    public var readmeFallback: MarkdownDocument?
    public var hasLoadedInitialData: Bool

    public init(store: LegacyCompatStore = LegacyCompatStore()) {
        self.store = store
        self.snapshot = NativeAppSnapshot()
        self.selectedProjectPath = nil
        self.searchQuery = ""
        self.selectedDirectory = nil
        self.selectedTag = nil
        self.selectedDateFilter = .all
        self.selectedGitFilter = .all
        self.isLoading = false
        self.errorMessage = nil
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

    public var heatmapCells: [HeatmapCell] {
        let counts = visibleProjects.reduce(into: [String: Int]()) { partialResult, project in
            for (dateKey, count) in parseGitDaily(project.gitDaily) {
                partialResult[dateKey, default: 0] += count
            }
        }
        let orderedDates = counts.keys.sorted().suffix(70)
        let maxCount = counts.values.max() ?? 0
        return orderedDates.map { dateKey in
            let count = counts[dateKey] ?? 0
            let intensity: Int
            switch count {
            case 0:
                intensity = 0
            default:
                let ratio = maxCount == 0 ? 0 : Double(count) / Double(maxCount)
                if ratio < 0.25 {
                    intensity = 1
                } else if ratio < 0.5 {
                    intensity = 2
                } else if ratio < 0.75 {
                    intensity = 3
                } else {
                    intensity = 4
                }
            }
            return HeatmapCell(dateKey: dateKey, intensity: intensity, count: count)
        }
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
            snapshot = try store.loadSnapshot()
            alignSelectionAfterReload()
            try refreshSelectedProjectDocument()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func refresh() {
        load()
    }

    public func selectProject(_ path: String?) {
        selectedProjectPath = path
        isDetailPanelPresented = path != nil
        do {
            try refreshSelectedProjectDocument()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func closeDetailPanel() {
        isDetailPanelPresented = false
    }

    public func selectDirectory(_ path: String?) {
        selectedDirectory = path
        alignSelectionAfterReload()
    }

    public func selectTag(_ name: String?) {
        selectedTag = name
        alignSelectionAfterReload()
    }

    public func updateDateFilter(_ filter: NativeDateFilter) {
        selectedDateFilter = filter
        alignSelectionAfterReload()
    }

    public func updateGitFilter(_ filter: NativeGitFilter) {
        selectedGitFilter = filter
        alignSelectionAfterReload()
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
            try refreshSelectedProjectDocument()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func saveTodo() {
        guard let project = selectedProject else { return }
        do {
            try store.writeTodoItems(todoItems, for: project.path)
            try refreshSelectedProjectDocument()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func moveProjectToRecycleBin(_ path: String) {
        do {
            let nextPaths = Array(Set(snapshot.appState.recycleBin + [path])).sorted()
            try store.updateRecycleBin(nextPaths)
            load()
            if selectedProjectPath == path {
                isDetailPanelPresented = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func toggleProjectFavorite(_ path: String) {
        var nextAppState = snapshot.appState
        var favorites = Set(nextAppState.favoriteProjectPaths)
        if favorites.contains(path) {
            favorites.remove(path)
        } else {
            favorites.insert(path)
        }
        nextAppState.favoriteProjectPaths = favorites.sorted()
        do {
            try store.updateFavoriteProjectPaths(nextAppState.favoriteProjectPaths)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func restoreProjectFromRecycleBin(_ path: String) {
        do {
            let nextPaths = snapshot.appState.recycleBin.filter { $0 != path }
            try store.updateRecycleBin(nextPaths)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func saveSettings(_ settings: AppSettings) {
        do {
            try store.updateSettings(settings)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func revealSettings() {
        isSettingsPresented = true
    }

    public func revealRecycleBin() {
        isRecycleBinPresented = true
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
        let availablePaths = Set(filteredProjects.map(\.path))
        if let selectedProjectPath, availablePaths.contains(selectedProjectPath) {
            return
        }
        selectedProjectPath = filteredProjects.first?.path ?? visibleProjects.first?.path
    }

    private func refreshSelectedProjectDocument() throws {
        guard let project = selectedProject else {
            notesDraft = ""
            todoDraft = ""
            todoItems = []
            readmeFallback = nil
            return
        }

        let document = try store.loadProjectDocument(at: project.path)
        notesDraft = document.notes ?? ""
        todoItems = document.todoItems
        readmeFallback = document.readmeFallback
    }

    private func matchesAllFilters(project: Project) -> Bool {
        if let selectedDirectory, !project.path.hasPrefix(selectedDirectory) {
            return false
        }
        if let selectedTag, !project.tags.contains(selectedTag) {
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
}

private func parseGitDaily(_ gitDaily: String?) -> [String: Int] {
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

private func hexColor(for color: ColorData) -> String {
    let r = Int(max(0, min(255, round(color.r * 255))))
    let g = Int(max(0, min(255, round(color.g * 255))))
    let b = Int(max(0, min(255, round(color.b * 255))))
    return String(format: "#%02X%02X%02X", r, g, b)
}
