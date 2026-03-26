import Foundation
import Observation

private struct WorktreeCreateContext {
    let request: NativeWorktreeCreateRequest
    let rootProjectPath: String
    let previewPath: String
}

@MainActor
@Observable
public final class NativeAppViewModel {
    @ObservationIgnored private let store: LegacyCompatStore
    @ObservationIgnored private var projectDocumentCache = [String: ProjectDocumentSnapshot]()
    @ObservationIgnored private let projectDocumentLoader: @Sendable (String) throws -> ProjectDocumentSnapshot
    @ObservationIgnored private let gitDailyCollector: @Sendable ([String], [GitIdentity]) -> [GitDailyRefreshResult]
    @ObservationIgnored private let gitDailyCollectorAsync: @Sendable ([String], [GitIdentity], @escaping @Sendable (Int, Int) async -> Void) async -> [GitDailyRefreshResult]
    @ObservationIgnored private let projectCatalogRefresher: @Sendable (ProjectCatalogRefreshRequest) async throws -> [Project]
    @ObservationIgnored private let workspaceLaunchDiagnostics: WorkspaceLaunchDiagnostics
    @ObservationIgnored private let projectImportDiagnostics: ProjectImportDiagnostics
    @ObservationIgnored private let terminalCommandRunner: @Sendable (String, [String]) throws -> Void
    @ObservationIgnored private let worktreeService: any NativeWorktreeServicing
    @ObservationIgnored private let gitRepositoryService: NativeGitRepositoryService
    @ObservationIgnored private let agentSignalStore: WorkspaceAgentSignalStore
    @ObservationIgnored private let workspaceRestoreCoordinator: WorkspaceRestoreCoordinator
    @ObservationIgnored private var workspacePaneSnapshotProvider: WorkspacePaneSnapshotProvider?
    @ObservationIgnored private var projectDocumentLoadTask: Task<Void, Never>?
    @ObservationIgnored private var projectDocumentLoadRevision = 0
    @ObservationIgnored private var isAgentSignalObservationStarted = false

    public enum DirectoryFilter: Equatable, Sendable {
        case all
        case directory(String)
        case directProjects
    }

    public struct DirectoryRow: Identifiable, Equatable {
        public let id: String
        public let filter: DirectoryFilter
        public let title: String
        public let count: Int
        public let isSystemEntry: Bool

        public init(filter: DirectoryFilter, title: String, count: Int, isSystemEntry: Bool = false) {
            self.id = switch filter {
            case .all:
                "all"
            case .directProjects:
                "direct-projects"
            case let .directory(path):
                path
            }
            self.filter = filter
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
        public let projectPath: String
        public let title: String
        public let subtitle: String
        public let statusText: String

        public var id: String { projectPath }
    }

    public var snapshot: NativeAppSnapshot
    public var selectedProjectPath: String?
    public var openWorkspaceSessions: [OpenWorkspaceSessionState]
    public var activeWorkspaceProjectPath: String?
    public var workspaceSideToolWindowState: WorkspaceSideToolWindowState
    public var workspaceBottomToolWindowState: WorkspaceBottomToolWindowState
    public var workspaceFocusedArea: WorkspaceFocusedArea
    private var workspaceDiffTabsByProjectPath: [String: [WorkspaceDiffTabState]]
    private var workspaceSelectedPresentedTabByProjectPath: [String: WorkspacePresentedTabSelection]
    private var attentionStateByProjectPath: [String: WorkspaceAttentionState]
    private var agentDisplayOverridesByProjectPath: [String: [String: WorkspaceAgentPresentationOverride]]
    private var currentBranchByProjectPath: [String: String]
    private var workspaceCommitViewModels: [String: WorkspaceCommitViewModel]
    private var workspaceGitViewModels: [String: WorkspaceGitViewModel]
    public var searchQuery: String
    public var selectedDirectory: DirectoryFilter
    public var selectedTag: String?
    public var selectedHeatmapDateKey: String?
    public var selectedDateFilter: NativeDateFilter
    public var selectedGitFilter: NativeGitFilter
    public var isLoading: Bool
    public var isRefreshingGitStatistics: Bool
    public var isRefreshingProjectCatalog: Bool
    public var gitStatisticsProgressText: String?
    public var isProjectDocumentLoading: Bool
    public var errorMessage: String?
    public var isDashboardPresented: Bool
    public var isSettingsPresented: Bool
    public var isRecycleBinPresented: Bool
    public var isDetailPanelPresented: Bool
    public var worktreeInteractionState: WorktreeInteractionState?
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
        projectCatalogRefresher: (@Sendable (ProjectCatalogRefreshRequest) async throws -> [Project])? = nil,
        workspaceLaunchDiagnostics: WorkspaceLaunchDiagnostics = .shared,
        projectImportDiagnostics: ProjectImportDiagnostics = .shared,
        terminalCommandRunner: (@Sendable (String, [String]) throws -> Void)? = nil,
        worktreeService: (any NativeWorktreeServicing)? = nil,
        gitRepositoryService: NativeGitRepositoryService = NativeGitRepositoryService(),
        agentSignalStore: WorkspaceAgentSignalStore? = nil,
        workspaceRestoreStore: WorkspaceRestoreStore? = nil,
        workspaceRestoreAutosaveDelayNanoseconds: UInt64 = 400_000_000
    ) {
        self.store = store
        self.projectDocumentLoader = projectDocumentLoader ?? loadProjectDocumentFromDisk
        self.gitDailyCollector = gitDailyCollector ?? collectGitDaily
        self.gitDailyCollectorAsync = gitDailyCollectorAsync ?? collectGitDailyAsync
        self.projectCatalogRefresher = projectCatalogRefresher ?? rebuildProjectCatalogSnapshot
        self.workspaceLaunchDiagnostics = workspaceLaunchDiagnostics
        self.projectImportDiagnostics = projectImportDiagnostics
        self.terminalCommandRunner = terminalCommandRunner ?? Self.runTerminalCommand
        self.worktreeService = worktreeService ?? NativeGitWorktreeService()
        self.gitRepositoryService = gitRepositoryService
        self.agentSignalStore = agentSignalStore ?? WorkspaceAgentSignalStore(
            baseDirectoryURL: store.agentStatusSessionsDirectoryURL
        )
        self.workspaceRestoreCoordinator = WorkspaceRestoreCoordinator(
            store: workspaceRestoreStore ?? WorkspaceRestoreStore(homeDirectoryURL: store.backgroundWorkHomeDirectoryURL),
            autosaveDelayNanoseconds: workspaceRestoreAutosaveDelayNanoseconds
        )
        self.workspacePaneSnapshotProvider = nil
        self.snapshot = NativeAppSnapshot()
        self.selectedProjectPath = nil
        self.openWorkspaceSessions = []
        self.activeWorkspaceProjectPath = nil
        self.workspaceSideToolWindowState = WorkspaceSideToolWindowState()
        self.workspaceBottomToolWindowState = WorkspaceBottomToolWindowState()
        self.workspaceFocusedArea = .terminal
        self.workspaceDiffTabsByProjectPath = [:]
        self.workspaceSelectedPresentedTabByProjectPath = [:]
        self.attentionStateByProjectPath = [:]
        self.agentDisplayOverridesByProjectPath = [:]
        self.currentBranchByProjectPath = [:]
        self.workspaceCommitViewModels = [:]
        self.workspaceGitViewModels = [:]
        self.searchQuery = ""
        self.selectedDirectory = .all
        self.selectedTag = nil
        self.selectedHeatmapDateKey = nil
        self.selectedDateFilter = .all
        self.selectedGitFilter = .all
        self.isLoading = false
        self.isRefreshingGitStatistics = false
        self.isRefreshingProjectCatalog = false
        self.gitStatisticsProgressText = nil
        self.isProjectDocumentLoading = false
        self.errorMessage = nil
        self.isDashboardPresented = false
        self.isSettingsPresented = false
        self.isRecycleBinPresented = false
        self.isDetailPanelPresented = false
        self.worktreeInteractionState = nil
        self.notesDraft = ""
        self.todoDraft = ""
        self.todoItems = []
        self.readmeFallback = nil
        self.hasLoadedInitialData = false
    }

    public var projectListViewMode: ProjectListViewMode {
        snapshot.appState.settings.projectListViewMode
    }

    public var workspaceSidebarWidth: Double {
        snapshot.appState.settings.workspaceSidebarWidth
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
        return resolveDisplayProject(for: selectedProjectPath)
    }

    public var activeWorkspaceProject: Project? {
        guard let activeWorkspaceProjectPath else {
            return nil
        }
        return resolveDisplayProject(for: activeWorkspaceProjectPath)
    }

    public var openWorkspaceProjectPaths: [String] {
        openWorkspaceSessions.map(\.projectPath)
    }

    public var openWorkspaceRootProjectPaths: [String] {
        openWorkspaceSessions
            .filter { $0.rootProjectPath == $0.projectPath }
            .map(\.projectPath)
    }

    public var openWorkspaceProjects: [Project] {
        openWorkspaceSessions.compactMap { resolveDisplayProject(for: $0.projectPath, rootProjectPath: $0.rootProjectPath) }
    }

    public var availableWorkspaceProjects: [Project] {
        let openedPaths = Set(openWorkspaceRootProjectPaths)
        return visibleProjects.filter { !openedPaths.contains($0.path) }
    }

    public var workspaceSidebarGroups: [WorkspaceSidebarProjectGroup] {
        let showsInAppNotifications = snapshot.appState.settings.workspaceInAppNotificationsEnabled
        let moveNotifiedWorktreeToTop = snapshot.appState.settings.moveNotifiedWorktreeToTop

        var groups: [WorkspaceSidebarProjectGroup] = openWorkspaceRootProjectPaths.compactMap { rootPath in
            guard let rootProject = snapshot.projects.first(where: { $0.path == rootPath }) else {
                return nil
            }
            let worktrees = orderedSidebarWorktreeItems(
                for: rootProject,
                rootProjectPath: rootPath,
                showsInAppNotifications: showsInAppNotifications,
                moveNotifiedWorktreeToTop: moveNotifiedWorktreeToTop
            )
            let rootAttention = attentionStateByProjectPath[rootPath]
            let rootAgentOverrides = agentDisplayOverridesByProjectPath[rootPath] ?? [:]
            let rootAgentState = rootAttention?.resolvedAgentState(overridesByPaneID: rootAgentOverrides)
            let rootAgentSummary = rootAttention?.resolvedAgentSummary(overridesByPaneID: rootAgentOverrides)
            let rootAgentKind = rootAttention?.resolvedAgentKind(overridesByPaneID: rootAgentOverrides)
            let notifications = showsInAppNotifications
                ? ([rootAttention?.notifications ?? []] + worktrees.map(\.notifications))
                    .flatMap { $0 }
                    .sorted { $0.createdAt > $1.createdAt }
                : []
            let unreadNotificationCount = showsInAppNotifications
                ? (rootAttention?.unreadCount ?? 0)
                    + worktrees.reduce(into: 0) { count, item in
                        count += item.unreadNotificationCount
                    }
                : 0
            return WorkspaceSidebarProjectGroup(
                rootProject: rootProject,
                worktrees: worktrees,
                isActive: activeWorkspaceProjectPath == rootPath,
                currentBranch: currentBranchByProjectPath[rootPath],
                notifications: notifications,
                unreadNotificationCount: unreadNotificationCount,
                taskStatus: makeGroupTaskStatus(
                    rootProjectPath: rootPath,
                    rootAttention: rootAttention,
                    worktrees: worktrees
                ),
                agentState: makeGroupAgentState(
                    rootAgentState: rootAgentState
                ),
                agentSummary: makeGroupAgentSummary(
                    rootAgentState: rootAgentState,
                    rootAgentSummary: rootAgentSummary
                ),
                agentKind: makeGroupAgentKind(
                    rootAgentState: rootAgentState,
                    rootAgentKind: rootAgentKind
                )
            )
        }
        for session in openWorkspaceSessions where session.isQuickTerminal {
            let attention = attentionStateByProjectPath[session.projectPath]
            let agentOverrides = agentDisplayOverridesByProjectPath[session.projectPath] ?? [:]
            groups.append(WorkspaceSidebarProjectGroup(
                rootProject: .quickTerminal(at: session.projectPath),
                worktrees: [],
                isActive: activeWorkspaceProjectPath == session.projectPath,
                notifications: showsInAppNotifications ? (attention?.notifications ?? []) : [],
                unreadNotificationCount: showsInAppNotifications ? (attention?.unreadCount ?? 0) : 0,
                taskStatus: attention?.taskStatus,
                agentState: attention?.resolvedAgentState(overridesByPaneID: agentOverrides),
                agentSummary: attention?.resolvedAgentSummary(overridesByPaneID: agentOverrides),
                agentKind: attention?.resolvedAgentKind(overridesByPaneID: agentOverrides)
            ))
        }
        return groups
    }

    func workspaceAttentionState(for projectPath: String) -> WorkspaceAttentionState? {
        attentionStateByProjectPath[projectPath]
    }

    public func recordWorkspaceNotification(
        projectPath: String,
        tabID: String,
        paneID: String,
        title: String,
        body: String,
        createdAt: Date = Date()
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(trimmedTitle.isEmpty && trimmedBody.isEmpty) else {
            return
        }
        guard snapshot.appState.settings.workspaceInAppNotificationsEnabled else {
            return
        }
        guard let session = openWorkspaceSessions.first(where: { $0.projectPath == projectPath }) else {
            return
        }

        var attention = attentionStateByProjectPath[projectPath] ?? WorkspaceAttentionState()
        attention.appendNotification(
            WorkspaceTerminalNotification(
                projectPath: projectPath,
                rootProjectPath: session.rootProjectPath,
                workspaceId: session.controller.workspaceId,
                tabId: tabID,
                paneId: paneID,
                title: trimmedTitle,
                body: trimmedBody,
                createdAt: createdAt,
                isRead: isWorkspacePaneCurrentlyFocused(projectPath: projectPath, tabID: tabID, paneID: paneID)
            )
        )
        attentionStateByProjectPath[projectPath] = attention
    }

    public func updateWorkspaceTaskStatus(
        projectPath: String,
        paneID: String,
        status: WorkspaceTaskStatus
    ) {
        var attention = attentionStateByProjectPath[projectPath] ?? WorkspaceAttentionState()
        attention.setTaskStatus(status, for: paneID)
        attentionStateByProjectPath[projectPath] = attention
    }

    public func recordAgentSignal(_ signal: WorkspaceAgentSessionSignal) {
        guard openWorkspaceProjectPaths.contains(signal.projectPath) else {
            return
        }
        var attention = attentionStateByProjectPath[signal.projectPath] ?? WorkspaceAttentionState()
        attention.setAgentState(
            signal.state,
            kind: signal.agentKind,
            summary: signal.summary,
            updatedAt: signal.updatedAt,
            for: signal.paneId
        )
        attentionStateByProjectPath[signal.projectPath] = attention
    }

    public func clearAgentSignal(projectPath: String, paneID: String) {
        guard var attention = attentionStateByProjectPath[projectPath] else {
            return
        }
        attention.clearAgentState(for: paneID)
        attentionStateByProjectPath[projectPath] = attention
    }

    public func startWorkspaceAgentSignalObservation() {
        guard !isAgentSignalObservationStarted else {
            refreshWorkspaceAgentSignals()
            return
        }
        agentSignalStore.onSignalsChange = { [weak self] snapshots in
            Task { @MainActor in
                self?.applyAgentSignalSnapshots(snapshots)
            }
        }
        do {
            try agentSignalStore.start()
            isAgentSignalObservationStarted = true
            applyAgentSignalSnapshots(agentSignalStore.currentSnapshots)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func stopWorkspaceAgentSignalObservation() {
        guard isAgentSignalObservationStarted else {
            return
        }
        agentSignalStore.stop()
        isAgentSignalObservationStarted = false
    }

    public func refreshWorkspaceAgentSignals() {
        applyAgentSignalSnapshots(agentSignalStore.currentSnapshots)
    }

    public func codexDisplayCandidates() -> [WorkspaceAgentDisplayCandidate] {
        let openPaths = Set(openWorkspaceProjectPaths)
        return attentionStateByProjectPath
            .filter { openPaths.contains($0.key) }
            .flatMap { projectPath, attention in
                attention.agentStateByPaneID.compactMap { paneID, state in
                    guard (state == .running || state == .waiting),
                          attention.agentKindByPaneID[paneID] == .codex
                    else {
                        return nil
                    }
                    return WorkspaceAgentDisplayCandidate(
                        projectPath: projectPath,
                        paneID: paneID,
                        signalState: state
                    )
                }
            }
    }

    public func replaceWorkspaceAgentDisplayOverrides(
        _ overridesByProjectPath: [String: [String: WorkspaceAgentPresentationOverride]]
    ) {
        agentDisplayOverridesByProjectPath = overridesByProjectPath
        pruneWorkspaceAgentDisplayOverrides()
    }

    public func markWorkspaceNotificationsRead(projectPath: String, paneID: String) {
        guard var attention = attentionStateByProjectPath[projectPath] else {
            return
        }
        attention.markNotificationsRead(for: paneID)
        attentionStateByProjectPath[projectPath] = attention
    }

    public func focusWorkspaceNotification(_ notification: WorkspaceTerminalNotification) {
        guard openWorkspaceProjectPaths.contains(notification.projectPath) else {
            return
        }
        activateWorkspaceProject(notification.projectPath)
        guard let controller = workspaceController(for: notification.projectPath) else {
            return
        }
        controller.selectTab(notification.tabId)
        controller.focusPane(notification.paneId)

        guard var attention = attentionStateByProjectPath[notification.projectPath] else {
            return
        }
        attention.markNotificationRead(id: notification.id)
        attentionStateByProjectPath[notification.projectPath] = attention
    }

    public var activeWorkspaceController: GhosttyWorkspaceController? {
        guard let activeWorkspaceProjectPath else {
            return nil
        }
        return openWorkspaceSessions.first(where: { $0.projectPath == activeWorkspaceProjectPath })?.controller
    }

    public var activeWorkspaceRootProjectPath: String? {
        guard let activeWorkspaceProjectPath else {
            return nil
        }
        return openWorkspaceSessions.first(where: { $0.projectPath == activeWorkspaceProjectPath })?.rootProjectPath
    }

    public var activeWorkspaceRootProject: Project? {
        guard let activeWorkspaceRootProjectPath else {
            return nil
        }
        return snapshot.projects.first(where: { $0.path == activeWorkspaceRootProjectPath })
    }

    public var activeWorkspaceGitRepositoryContext: WorkspaceGitRepositoryContext? {
        guard let rootProject = activeWorkspaceRootProject,
              rootProject.isGitRepository
        else {
            return nil
        }
        return WorkspaceGitRepositoryContext(
            rootProjectPath: rootProject.path,
            repositoryPath: rootProject.path
        )
    }

    public var activeWorkspaceCommitRepositoryContext: WorkspaceCommitRepositoryContext? {
        guard let rootProject = activeWorkspaceRootProject,
              rootProject.isGitRepository
        else {
            return nil
        }
        return WorkspaceCommitRepositoryContext(
            rootProjectPath: rootProject.path,
            repositoryPath: rootProject.path,
            executionPath: preferredWorkspaceGitExecutionPath(for: rootProject.path)
        )
    }

    public var activeWorkspaceCommitViewModel: WorkspaceCommitViewModel? {
        guard let rootProjectPath = activeWorkspaceRootProjectPath else {
            return nil
        }
        return workspaceCommitViewModels[rootProjectPath]
    }

    public var activeWorkspaceGitViewModel: WorkspaceGitViewModel? {
        guard let rootProjectPath = activeWorkspaceRootProjectPath else {
            return nil
        }
        return workspaceGitViewModels[rootProjectPath]
    }

    public var activeWorkspaceState: WorkspaceSessionState? {
        activeWorkspaceController?.sessionState
    }

    public var activeWorkspaceLaunchRequest: WorkspaceTerminalLaunchRequest? {
        activeWorkspaceController?.selectedPane?.request
    }

    public var activeWorkspaceDiffTabs: [WorkspaceDiffTabState] {
        guard let activeWorkspaceProjectPath else {
            return []
        }
        return workspaceDiffTabsByProjectPath[activeWorkspaceProjectPath] ?? []
    }

    public var activeWorkspaceSelectedPresentedTab: WorkspacePresentedTabSelection? {
        guard let activeWorkspaceProjectPath else {
            return nil
        }
        return resolvedWorkspacePresentedTabSelection(for: activeWorkspaceProjectPath)
    }

    public var activeWorkspaceSelectedDiffTabID: String? {
        guard case let .diff(tabID)? = activeWorkspaceSelectedPresentedTab else {
            return nil
        }
        return tabID
    }

    public var isWorkspacePresented: Bool {
        activeWorkspaceProjectPath != nil && activeWorkspaceController != nil
    }

    public var canSplitActiveWorkspace: Bool {
        activeWorkspaceController?.selectedPane != nil
    }

    public var directoryRows: [DirectoryRow] {
        var rows: [DirectoryRow] = [DirectoryRow(filter: .all, title: "全部", count: visibleProjects.count, isSystemEntry: true)]
        rows.append(
            DirectoryRow(
                filter: .directProjects,
                title: "直接添加",
                count: visibleProjects.filter { directProjectPathSet.contains(normalizePathForCompare($0.path)) }.count,
                isSystemEntry: true
            )
        )
        rows.append(
            contentsOf: snapshot.appState.directories.map { directory in
                DirectoryRow(
                    filter: .directory(directory),
                    title: URL(fileURLWithPath: directory).lastPathComponent,
                    count: visibleProjects.filter { $0.path.hasPrefix(directory) }.count
                )
            }
        )
        return rows
    }

    public var isDirectProjectsDirectorySelected: Bool {
        if case .directProjects = selectedDirectory {
            return true
        }
        return false
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
        openWorkspaceSessions
            .filter(\.isQuickTerminal)
            .map { session in
            CLISessionItem(
                projectPath: session.projectPath,
                title: Project.quickTerminal(at: session.projectPath).name,
                subtitle: session.projectPath,
                statusText: activeWorkspaceProjectPath == session.projectPath ? "已打开" : "可恢复"
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
            let shouldApplyWorkspaceRestore = !hasLoadedInitialData && openWorkspaceSessions.isEmpty
            snapshot = try store.loadSnapshot()
            alignSelectionAfterReload()
            if shouldApplyWorkspaceRestore {
                applyWorkspaceRestoreSnapshotIfAvailable()
            }
            scheduleSelectedProjectDocumentRefresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func setWorkspacePaneSnapshotProvider(_ provider: WorkspacePaneSnapshotProvider?) {
        workspacePaneSnapshotProvider = provider
    }

    public func flushWorkspaceRestoreSnapshotNow() {
        do {
            try workspaceRestoreCoordinator.flushNow(
                activeProjectPath: activeWorkspaceProjectPath,
                selectedProjectPath: selectedProjectPath,
                sessions: openWorkspaceSessions,
                paneSnapshotProvider: workspacePaneSnapshotProvider
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func refresh() {
        guard !isRefreshingProjectCatalog else {
            return
        }
        guard !snapshot.appState.directories.isEmpty || !snapshot.appState.directProjectPaths.isEmpty else {
            load()
            return
        }
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                try await self.refreshProjectCatalog()
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    public func refreshGitStatistics() throws -> GitStatisticsRefreshSummary {
        let targetProjects = visibleProjects.filter(\.isGitRepository)
        guard !targetProjects.isEmpty else {
            return GitStatisticsRefreshSummary(requestedRepositories: 0, updatedRepositories: 0, failedRepositories: 0)
        }

        isRefreshingGitStatistics = true
        defer { isRefreshingGitStatistics = false }

        let results = gitDailyCollector(targetProjects.map(\.path), snapshot.appState.settings.gitIdentities)
        try store.updateProjectsGitMetadata(results)
        load()

        return makeGitStatisticsRefreshSummary(from: results)
    }

    public func refreshGitStatisticsAsync() async throws -> GitStatisticsRefreshSummary {
        let targetProjects = visibleProjects.filter(\.isGitRepository)
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
        try store.updateProjectsGitMetadata(results)
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
        if let path {
            if activeWorkspaceProjectPath != nil, openWorkspaceProjectPaths.contains(path) {
                activeWorkspaceProjectPath = path
                isDetailPanelPresented = false
            } else {
                isDetailPanelPresented = true
            }
        } else {
            isDetailPanelPresented = false
        }
        selectedProjectPath = path
        scheduleSelectedProjectDocumentRefresh()
        scheduleWorkspaceRestoreAutosave()
    }

    public func enterWorkspace(_ path: String) {
        selectedProjectPath = path
        openWorkspaceSessionIfNeeded(for: path, rootProjectPath: path)
        activeWorkspaceProjectPath = path
        isDetailPanelPresented = false
        if let controller = activeWorkspaceController {
            workspaceLaunchDiagnostics.recordEntryRequested(
                workspace: controller.sessionState,
                openSessionCount: openWorkspaceSessions.count
            )
        }
        scheduleSelectedProjectDocumentRefresh()
        scheduleWorkspaceRestoreAutosave()
    }

    public func enterOrResumeWorkspace() {
        if let activeWorkspaceProjectPath,
           openWorkspaceProjectPaths.contains(activeWorkspaceProjectPath) {
            activateWorkspaceProject(activeWorkspaceProjectPath)
            return
        }
        if let selectedProjectPath,
           openWorkspaceProjectPaths.contains(selectedProjectPath) {
            activateWorkspaceProject(selectedProjectPath)
            return
        }
        if let fallbackProjectPath = openWorkspaceSessions.last?.projectPath {
            activateWorkspaceProject(fallbackProjectPath)
            return
        }
        openQuickTerminal()
    }

    public func openQuickTerminal() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        openWorkspaceSessionIfNeeded(for: homePath, rootProjectPath: homePath, isQuickTerminal: true)
        activateWorkspaceProject(homePath)
        scheduleWorkspaceRestoreAutosave()
    }

    public func activateWorkspaceProject(_ path: String) {
        guard openWorkspaceProjectPaths.contains(path) else {
            return
        }
        activeWorkspaceProjectPath = path
        if !isQuickTerminalSessionPath(path) {
            selectedProjectPath = path
        }
        if let paneID = workspaceController(for: path)?.selectedPane?.id {
            markWorkspaceNotificationsRead(projectPath: path, paneID: paneID)
        }
        isDetailPanelPresented = false
        if !isQuickTerminalSessionPath(path) {
            scheduleSelectedProjectDocumentRefresh()
        }
        scheduleWorkspaceRestoreAutosave()
    }

    public func closeWorkspaceProject(_ path: String) {
        guard let index = openWorkspaceSessions.firstIndex(where: { $0.projectPath == path }) else {
            return
        }

        let rootProjectPath = openWorkspaceSessions[index].rootProjectPath
        let removedPaths: Set<String>
        if rootProjectPath == path {
            removedPaths = Set(openWorkspaceSessions.filter { $0.rootProjectPath == path }.map(\.projectPath))
            openWorkspaceSessions.removeAll { removedPaths.contains($0.projectPath) }
        } else {
            removedPaths = Set([path])
            openWorkspaceSessions.remove(at: index)
        }
        clearWorkspaceRuntimePresentationState(for: removedPaths)
        attentionStateByProjectPath = attentionStateByProjectPath.filter { openWorkspaceProjectPaths.contains($0.key) }
        pruneWorkspaceAgentDisplayOverrides()

        if openWorkspaceSessions.isEmpty {
            activeWorkspaceProjectPath = nil
            isDetailPanelPresented = false
            scheduleWorkspaceRestoreAutosave()
            return
        }

        if let currentActiveWorkspaceProjectPath = activeWorkspaceProjectPath, removedPaths.contains(currentActiveWorkspaceProjectPath) {
            let fallbackIndex = min(index, openWorkspaceSessions.count - 1)
            let fallbackPath = openWorkspaceSessions[fallbackIndex].projectPath
            activeWorkspaceProjectPath = fallbackPath
            selectedProjectPath = fallbackPath
            isDetailPanelPresented = false
            scheduleSelectedProjectDocumentRefresh()
        }
        scheduleWorkspaceRestoreAutosave()
    }

    public func exitWorkspace() {
        activeWorkspaceProjectPath = nil
        isDetailPanelPresented = false
        scheduleWorkspaceRestoreAutosave()
    }

    public func openWorkspaceWorktree(_ worktreePath: String, from rootProjectPath: String) {
        guard let rootProject = snapshot.projects.first(where: { $0.path == rootProjectPath }) else {
            errorMessage = NativeWorktreeError.invalidProject("项目不存在或已移除").localizedDescription
            return
        }
        guard let worktree = rootProject.worktrees.first(where: { $0.path == worktreePath }) else {
            errorMessage = NativeWorktreeError.invalidPath("worktree 不存在或已移除").localizedDescription
            return
        }
        if worktree.status == "creating" {
            errorMessage = "该 worktree 正在创建中，请稍候"
            return
        }
        if worktree.status == "failed" {
            errorMessage = worktree.initError ?? "该 worktree 创建失败，请先重试"
            return
        }
        selectedProjectPath = worktree.path
        openWorkspaceSessionIfNeeded(for: worktree.path, rootProjectPath: rootProjectPath)
        activeWorkspaceProjectPath = worktree.path
        isDetailPanelPresented = false
        scheduleSelectedProjectDocumentRefresh()
        scheduleWorkspaceRestoreAutosave()
    }

    public func prepareActiveWorkspaceGitViewModel() {
        guard let rootProject = activeWorkspaceRootProject,
              rootProject.isGitRepository,
              let repositoryContext = activeWorkspaceGitRepositoryContext
        else {
            return
        }

        let executionWorktrees = workspaceGitExecutionContexts(for: rootProject)
        let preferredExecutionPath = preferredWorkspaceGitExecutionPath(for: rootProject.path)

        if let existing = workspaceGitViewModels[rootProject.path] {
            existing.updateRepositoryContext(
                repositoryContext,
                executionWorktrees: executionWorktrees,
                preferredExecutionWorktreePath: preferredExecutionPath
            )
            return
        }

        workspaceGitViewModels[rootProject.path] = WorkspaceGitViewModel(
            repositoryContext: repositoryContext,
            executionWorktrees: executionWorktrees,
            preferredExecutionWorktreePath: preferredExecutionPath,
            client: .live(service: gitRepositoryService)
        )
    }

    public func prepareActiveWorkspaceCommitViewModel() {
        guard let rootProject = activeWorkspaceRootProject,
              rootProject.isGitRepository,
              let repositoryContext = activeWorkspaceCommitRepositoryContext
        else {
            return
        }

        if let existing = workspaceCommitViewModels[rootProject.path] {
            existing.updateRepositoryContext(repositoryContext)
            return
        }

        workspaceCommitViewModels[rootProject.path] = WorkspaceCommitViewModel(
            repositoryContext: repositoryContext,
            client: .live(service: gitRepositoryService)
        )
    }

    public func toggleWorkspaceToolWindow(_ kind: WorkspaceToolWindowKind) {
        switch kind.placement {
        case .side:
            if workspaceSideToolWindowState.activeKind == kind, workspaceSideToolWindowState.isVisible {
                hideWorkspaceSideToolWindow()
                return
            }
            showWorkspaceSideToolWindow(kind)
        case .bottom:
            if workspaceBottomToolWindowState.activeKind == kind, workspaceBottomToolWindowState.isVisible {
                hideWorkspaceBottomToolWindow()
                return
            }
            showWorkspaceBottomToolWindow(kind)
        }
    }

    public func showWorkspaceSideToolWindow(_ kind: WorkspaceToolWindowKind) {
        guard kind.placement == .side else {
            return
        }
        workspaceSideToolWindowState.activeKind = kind
        workspaceSideToolWindowState.isVisible = true
        workspaceSideToolWindowState.width = workspaceSideToolWindowState.lastExpandedWidth
        syncActiveWorkspaceToolWindowContext()
        workspaceFocusedArea = .sideToolWindow(kind)
    }

    public func hideWorkspaceSideToolWindow() {
        if workspaceSideToolWindowState.isVisible {
            workspaceSideToolWindowState.lastExpandedWidth = workspaceSideToolWindowState.width
        }
        workspaceSideToolWindowState.isVisible = false
        if case .sideToolWindow = workspaceFocusedArea {
            workspaceFocusedArea = .terminal
        }
    }

    public func updateWorkspaceSideToolWindowWidth(_ width: Double) {
        let clamped = max(220, width)
        workspaceSideToolWindowState.width = clamped
        workspaceSideToolWindowState.lastExpandedWidth = clamped
    }

    public func showWorkspaceBottomToolWindow(_ kind: WorkspaceToolWindowKind) {
        guard kind.placement == .bottom else {
            return
        }
        workspaceBottomToolWindowState.activeKind = kind
        workspaceBottomToolWindowState.isVisible = true
        workspaceBottomToolWindowState.height = workspaceBottomToolWindowState.lastExpandedHeight
        syncActiveWorkspaceToolWindowContext()
        workspaceFocusedArea = .bottomToolWindow(kind)
    }

    public func hideWorkspaceBottomToolWindow() {
        if workspaceBottomToolWindowState.isVisible {
            workspaceBottomToolWindowState.lastExpandedHeight = workspaceBottomToolWindowState.height
        }
        workspaceBottomToolWindowState.isVisible = false
        if case .bottomToolWindow = workspaceFocusedArea {
            workspaceFocusedArea = .terminal
        }
    }

    public func updateWorkspaceBottomToolWindowHeight(_ height: Double) {
        let clamped = max(160, height)
        workspaceBottomToolWindowState.height = clamped
        workspaceBottomToolWindowState.lastExpandedHeight = clamped
    }

    public func setWorkspaceFocusedArea(_ area: WorkspaceFocusedArea) {
        workspaceFocusedArea = area
    }

    @discardableResult
    public func openWorkspaceDiffTab(_ request: WorkspaceDiffOpenRequest) -> WorkspaceDiffTabState {
        activeWorkspaceProjectPath = request.projectPath

        if let existing = workspaceDiffTabsByProjectPath[request.projectPath]?.first(where: { $0.identity == request.identity }) {
            workspaceSelectedPresentedTabByProjectPath[request.projectPath] = .diff(existing.id)
            return existing
        }

        let tab = WorkspaceDiffTabState(
            id: "workspace-diff:\(UUID().uuidString.lowercased())",
            identity: request.identity,
            title: request.preferredTitle,
            source: request.source,
            viewerMode: request.preferredViewerMode
        )
        workspaceDiffTabsByProjectPath[request.projectPath, default: []].append(tab)
        workspaceSelectedPresentedTabByProjectPath[request.projectPath] = .diff(tab.id)
        return tab
    }

    public func selectWorkspacePresentedTab(_ selection: WorkspacePresentedTabSelection, in projectPath: String? = nil) {
        guard let resolvedProjectPath = projectPath ?? activeWorkspaceProjectPath else {
            return
        }

        switch selection {
        case let .terminal(tabID):
            guard workspaceController(for: resolvedProjectPath)?.tabs.contains(where: { $0.id == tabID }) == true else {
                return
            }
            workspaceController(for: resolvedProjectPath)?.selectTab(tabID)
            workspaceSelectedPresentedTabByProjectPath[resolvedProjectPath] = .terminal(tabID)
        case let .diff(tabID):
            guard workspaceDiffTabsByProjectPath[resolvedProjectPath]?.contains(where: { $0.id == tabID }) == true else {
                return
            }
            workspaceSelectedPresentedTabByProjectPath[resolvedProjectPath] = .diff(tabID)
        }
    }

    public func closeWorkspaceDiffTab(_ tabID: String, in projectPath: String? = nil) {
        guard let resolvedProjectPath = projectPath ?? activeWorkspaceProjectPath,
              var tabs = workspaceDiffTabsByProjectPath[resolvedProjectPath],
              let removedIndex = tabs.firstIndex(where: { $0.id == tabID })
        else {
            return
        }

        tabs.remove(at: removedIndex)
        workspaceDiffTabsByProjectPath[resolvedProjectPath] = tabs

        guard activeWorkspaceSelectedPresentedTab == .diff(tabID) else {
            return
        }

        if tabs.indices.contains(removedIndex) {
            workspaceSelectedPresentedTabByProjectPath[resolvedProjectPath] = .diff(tabs[removedIndex].id)
        } else if let previous = tabs.last {
            workspaceSelectedPresentedTabByProjectPath[resolvedProjectPath] = .diff(previous.id)
        } else if let terminalTabID = workspaceController(for: resolvedProjectPath)?.selectedTabId
            ?? workspaceController(for: resolvedProjectPath)?.selectedTab?.id
        {
            workspaceSelectedPresentedTabByProjectPath[resolvedProjectPath] = .terminal(terminalTabID)
        } else {
            workspaceSelectedPresentedTabByProjectPath[resolvedProjectPath] = nil
        }
    }

    public func syncActiveWorkspaceToolWindowContext() {
        if workspaceSideToolWindowState.isVisible,
           let kind = workspaceSideToolWindowState.activeKind {
            switch kind {
            case .commit:
                prepareActiveWorkspaceCommitViewModel()
            case .git:
                prepareActiveWorkspaceGitViewModel()
            }
        }

        if workspaceBottomToolWindowState.isVisible,
           let kind = workspaceBottomToolWindowState.activeKind {
            switch kind {
            case .commit:
                prepareActiveWorkspaceCommitViewModel()
            case .git:
                prepareActiveWorkspaceGitViewModel()
            }
        }
    }

    public func createWorkspaceTab(in projectPath: String? = nil) {
        _ = workspaceController(for: projectPath)?.createTab()
    }

    public func selectWorkspaceTab(_ tabID: String, in projectPath: String? = nil) {
        workspaceController(for: projectPath)?.selectTab(tabID)
    }

    public func moveWorkspaceTab(_ tabID: String, by amount: Int, in projectPath: String? = nil) {
        workspaceController(for: projectPath)?.moveTab(id: tabID, by: amount)
    }

    public func closeWorkspaceTab(_ tabID: String, in projectPath: String? = nil) {
        workspaceController(for: projectPath)?.closeTab(tabID)
    }

    public func closeWorkspaceOtherTabs(keeping tabID: String, in projectPath: String? = nil) {
        workspaceController(for: projectPath)?.closeOtherTabs(keeping: tabID)
    }

    public func closeWorkspaceTabsToRight(of tabID: String, in projectPath: String? = nil) {
        workspaceController(for: projectPath)?.closeTabsToRight(of: tabID)
    }

    public func gotoPreviousWorkspaceTab(in projectPath: String? = nil) {
        workspaceController(for: projectPath)?.gotoPreviousTab()
    }

    public func gotoNextWorkspaceTab(in projectPath: String? = nil) {
        workspaceController(for: projectPath)?.gotoNextTab()
    }

    public func gotoLastWorkspaceTab(in projectPath: String? = nil) {
        workspaceController(for: projectPath)?.gotoLastTab()
    }

    public func gotoWorkspaceTab(at index: Int, in projectPath: String? = nil) {
        workspaceController(for: projectPath)?.gotoTab(at: index)
    }

    public func splitWorkspaceFocusedPane(direction: WorkspacePaneSplitDirection, in projectPath: String? = nil) {
        _ = workspaceController(for: projectPath)?.splitFocusedPane(direction: direction)
    }

    public func splitActiveWorkspaceRight() {
        splitWorkspaceFocusedPane(direction: .right)
    }

    public func focusWorkspacePane(_ paneID: String, in projectPath: String? = nil) {
        workspaceController(for: projectPath)?.focusPane(paneID)
    }

    public func focusWorkspacePane(direction: WorkspacePaneFocusDirection, in projectPath: String? = nil) {
        workspaceController(for: projectPath)?.focusPane(direction: direction)
    }

    public func closeWorkspacePane(_ paneID: String?, in projectPath: String? = nil) {
        workspaceController(for: projectPath)?.closePane(paneID)
    }

    public func resizeWorkspaceFocusedPane(direction: WorkspacePaneSplitDirection, amount: UInt16, in projectPath: String? = nil) {
        workspaceController(for: projectPath)?.resizeFocusedPane(direction: direction, amount: amount)
    }

    public func equalizeWorkspaceSplits(in projectPath: String? = nil) {
        workspaceController(for: projectPath)?.equalizeSelectedTabSplits()
    }

    public func toggleWorkspaceFocusedPaneZoom(in projectPath: String? = nil) {
        workspaceController(for: projectPath)?.toggleZoomOnFocusedPane()
    }

    public func setWorkspaceSelectedTabSplitRatio(at path: WorkspacePaneTree.Path, ratio: Double, in projectPath: String? = nil) {
        workspaceController(for: projectPath)?.setSelectedTabSplitRatio(at: path, ratio: ratio)
    }

    public func updateWorkspaceTabTitle(_ title: String, for tabID: String, in projectPath: String? = nil) {
        workspaceController(for: projectPath)?.updateTitle(for: tabID, title: title)
    }

    public func openWorkspaceInTerminal(_ projectPath: String? = nil) throws {
        let resolvedProjectPath = projectPath ?? activeWorkspaceProjectPath
        guard let resolvedProjectPath,
              let project = resolveDisplayProject(for: resolvedProjectPath)
        else {
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

    public func openActiveWorkspaceInTerminal() throws {
        try openWorkspaceInTerminal()
    }

    public func managedWorktreePathPreview(for rootProjectPath: String, branch: String) throws -> String {
        try worktreeService.managedWorktreePath(for: rootProjectPath, branch: branch)
    }

    public func listWorkspaceBranches(for rootProjectPath: String) async throws -> [NativeGitBranch] {
        try await Task.detached(priority: .userInitiated) {
            try self.worktreeService.listBranches(at: rootProjectPath)
        }.value
    }

    public func listProjectWorktrees(for rootProjectPath: String) async throws -> [NativeGitWorktree] {
        try await Task.detached(priority: .userInitiated) {
            try self.worktreeService.listWorktrees(at: rootProjectPath)
        }.value
    }

    public func refreshProjectWorktrees(_ rootProjectPath: String) async throws {
        let gitWorktrees = try await listProjectWorktrees(for: rootProjectPath)
        guard let projectIndex = snapshot.projects.firstIndex(where: { $0.path == rootProjectPath }) else {
            throw NativeWorktreeError.invalidProject("项目不存在或已移除")
        }
        var projects = snapshot.projects
        projects[projectIndex].worktrees = buildSyncedWorktrees(
            existingWorktrees: projects[projectIndex].worktrees,
            gitWorktrees: gitWorktrees
        )
        try persistProjects(projects)
        refreshCurrentBranch(for: rootProjectPath)
    }

    public func addExistingWorkspaceWorktree(
        from rootProjectPath: String,
        worktreePath: String,
        branch: String,
        autoOpen: Bool
    ) throws {
        guard let projectIndex = snapshot.projects.firstIndex(where: { $0.path == rootProjectPath }) else {
            throw NativeWorktreeError.invalidProject("项目不存在或已移除")
        }

        let now = swiftDateFromDate(Date())
        let nextWorktree = buildReadyWorktree(path: worktreePath, branch: branch, now: now)
        var projects = snapshot.projects
        var project = projects[projectIndex]
        if let existingIndex = project.worktrees.firstIndex(where: { normalizePathForCompare($0.path) == normalizePathForCompare(worktreePath) }) {
            project.worktrees[existingIndex] = nextWorktree
        } else {
            project.worktrees.append(nextWorktree)
            project.worktrees.sort { $0.path < $1.path }
        }
        projects[projectIndex] = project
        try persistProjects(projects)

        if autoOpen {
            openWorkspaceWorktree(worktreePath, from: rootProjectPath)
        }
    }

    public func createWorkspaceWorktree(
        from rootProjectPath: String,
        branch: String,
        createBranch: Bool,
        baseBranch: String?,
        autoOpen: Bool,
        targetPath: String? = nil
    ) async throws {
        let context = try prepareCreateWorkspaceWorktree(
            from: rootProjectPath,
            branch: branch,
            createBranch: createBranch,
            baseBranch: baseBranch,
            targetPath: targetPath
        )
        try await runCreateWorkspaceWorktree(context, autoOpen: autoOpen)
    }

    public func startCreateWorkspaceWorktree(
        from rootProjectPath: String,
        branch: String,
        createBranch: Bool,
        baseBranch: String?,
        autoOpen: Bool,
        targetPath: String? = nil
    ) throws {
        let context = try prepareCreateWorkspaceWorktree(
            from: rootProjectPath,
            branch: branch,
            createBranch: createBranch,
            baseBranch: baseBranch,
            targetPath: targetPath
        )
        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                try await self.runCreateWorkspaceWorktree(context, autoOpen: autoOpen)
            } catch {
                // `runCreateWorkspaceWorktree` 已把失败状态、错误文案和交互锁清理回主状态，这里无需重复处理。
            }
        }
    }

    private func prepareCreateWorkspaceWorktree(
        from rootProjectPath: String,
        branch: String,
        createBranch: Bool,
        baseBranch: String?,
        targetPath: String?
    ) throws -> WorktreeCreateContext {
        guard worktreeInteractionState == nil else {
            throw NativeWorktreeError.operationInProgress("已有 worktree 创建任务正在进行中，请稍候")
        }
        guard let projectIndex = snapshot.projects.firstIndex(where: { $0.path == rootProjectPath }) else {
            throw NativeWorktreeError.invalidProject("项目不存在或已移除")
        }

        let request = NativeWorktreeCreateRequest(
            sourceProjectPath: rootProjectPath,
            branch: branch,
            createBranch: createBranch,
            baseBranch: baseBranch,
            targetPath: targetPath
        )
        let previewPath = try worktreeService.managedWorktreePath(for: rootProjectPath, branch: branch)
        let now = swiftDateFromDate(Date())
        let creatingWorktree = ProjectWorktree(
            id: createWorktreeProjectID(path: previewPath),
            name: resolveWorktreeName(previewPath),
            path: previewPath,
            branch: branch.trimmingCharacters(in: .whitespacesAndNewlines),
            baseBranch: createBranch ? baseBranch?.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            inheritConfig: true,
            created: now,
            status: "creating",
            initStep: NativeWorktreeInitStep.pending.rawValue,
            initMessage: "已创建任务，准备开始…",
            initError: nil,
            initJobId: UUID().uuidString,
            updatedAt: now
        )

        var projects = snapshot.projects
        upsertWorktree(&projects[projectIndex].worktrees, worktree: creatingWorktree)
        try persistProjects(projects)
        worktreeInteractionState = WorktreeInteractionState(
            rootProjectPath: rootProjectPath,
            branch: creatingWorktree.branch,
            baseBranch: creatingWorktree.baseBranch,
            worktreePath: creatingWorktree.path,
            step: .pending,
            message: "准备创建 worktree..."
        )

        return WorktreeCreateContext(
            request: request,
            rootProjectPath: rootProjectPath,
            previewPath: previewPath
        )
    }

    private func runCreateWorkspaceWorktree(
        _ context: WorktreeCreateContext,
        autoOpen: Bool
    ) async throws {
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try self.worktreeService.createWorktree(context.request) { progress in
                    Task { @MainActor in
                        self.applyWorktreeProgress(progress, rootProjectPath: context.rootProjectPath)
                    }
                }
            }.value

            finishCreateWorkspaceWorktree(
                result,
                rootProjectPath: context.rootProjectPath,
                autoOpen: autoOpen
            )
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            markWorktreeAsFailed(
                worktreePath: context.previewPath,
                rootProjectPath: context.rootProjectPath,
                errorMessage: message
            )
            worktreeInteractionState = nil
            errorMessage = message
            throw error
        }
    }

    public func retryWorkspaceWorktree(_ worktreePath: String, from rootProjectPath: String) async throws {
        guard let worktree = snapshot.projects.first(where: { $0.path == rootProjectPath })?.worktrees.first(where: {
            normalizePathForCompare($0.path) == normalizePathForCompare(worktreePath)
        }) else {
            throw NativeWorktreeError.invalidPath("worktree 不存在或已移除")
        }

        try await createWorkspaceWorktree(
            from: rootProjectPath,
            branch: worktree.branch,
            createBranch: (worktree.baseBranch?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false),
            baseBranch: worktree.baseBranch,
            autoOpen: false,
            targetPath: worktree.path
        )
    }

    public func deleteWorkspaceWorktree(_ worktreePath: String, from rootProjectPath: String) async throws {
        guard let projectIndex = snapshot.projects.firstIndex(where: { $0.path == rootProjectPath }) else {
            throw NativeWorktreeError.invalidProject("项目不存在或已移除")
        }
        guard let worktree = snapshot.projects[projectIndex].worktrees.first(where: {
            normalizePathForCompare($0.path) == normalizePathForCompare(worktreePath)
        }) else {
            throw NativeWorktreeError.invalidPath("worktree 不存在或已移除")
        }
        if worktree.status == "creating" {
            throw NativeWorktreeError.operationInProgress("该 worktree 正在创建中，无法删除")
        }

        let result = try await Task.detached(priority: .userInitiated) {
            try self.worktreeService.removeWorktree(
                NativeWorktreeRemoveRequest(
                    sourceProjectPath: rootProjectPath,
                    worktreePath: worktree.path,
                    branch: worktree.branch,
                    shouldDeleteBranch: (worktree.baseBranch?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                )
            )
        }.value

        var projects = snapshot.projects
        projects[projectIndex].worktrees.removeAll { normalizePathForCompare($0.path) == normalizePathForCompare(worktree.path) }
        closeWorkspaceProject(worktree.path)
        try persistProjects(projects)
        if let warning = result.warning, !warning.isEmpty {
            errorMessage = warning
        }
    }

    public func closeDetailPanel() {
        isDetailPanelPresented = false
    }

    public func addProjectDirectory(_ path: String) throws {
        let normalizedPath = try validateImportedDirectoryPath(path, diagnostics: projectImportDiagnostics)

        let nextDirectories = normalizePathList(snapshot.appState.directories + [normalizedPath])
        guard nextDirectories != snapshot.appState.directories else {
            errorMessage = nil
            return
        }
        try store.updateDirectories(nextDirectories)
        snapshot.appState.directories = nextDirectories
        projectImportDiagnostics.recordDirectoryPersisted(path: normalizedPath, totalCount: nextDirectories.count)
        errorMessage = nil
    }

    public func removeProjectDirectory(_ path: String) async throws {
        let normalizedPath = normalizePathForCompare(path)
        guard !normalizedPath.isEmpty else {
            return
        }

        let nextDirectories = snapshot.appState.directories.filter {
            normalizePathForCompare($0) != normalizedPath
        }
        guard nextDirectories != snapshot.appState.directories else {
            errorMessage = nil
            return
        }

        try store.updateDirectories(nextDirectories)
        snapshot.appState.directories = nextDirectories
        if case let .directory(selectedPath) = selectedDirectory,
           normalizePathForCompare(selectedPath) == normalizedPath {
            selectedDirectory = .all
        }

        if nextDirectories.isEmpty && snapshot.appState.directProjectPaths.isEmpty {
            try persistProjects([])
            applyProjects([])
        } else {
            try await refreshProjectCatalog()
        }
        errorMessage = nil
    }

    public func addDirectProjects(_ paths: [String]) async throws {
        let normalizedPaths = normalizePathList(paths)
        guard !normalizedPaths.isEmpty else {
            return
        }

        let existingDirectProjectPaths = Set(snapshot.appState.directProjectPaths.map(normalizePathForCompare))
        var importablePaths = [String]()
        var importErrors = [String]()
        for path in normalizedPaths {
            if existingDirectProjectPaths.contains(path) {
                continue
            }
            do {
                importablePaths.append(try validateImportedDirectoryPath(path, diagnostics: projectImportDiagnostics))
            } catch {
                importErrors.append((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }

        guard !importablePaths.isEmpty else {
            if let firstError = importErrors.first {
                projectImportDiagnostics.recordFailure(action: .addProjects, errorDescription: firstError)
                throw ProjectImportError.importRejected(firstError)
            }
            errorMessage = nil
            return
        }

        let existingProjects = snapshot.projects
        let builtProjects = await Task.detached(priority: .userInitiated) {
            buildProjects(paths: importablePaths, existing: existingProjects)
        }.value
        let builtProjectPaths = Set(builtProjects.map { normalizePathForCompare($0.path) })
        let acceptedProjectPaths = importablePaths.filter { builtProjectPaths.contains(normalizePathForCompare($0)) }
        guard !acceptedProjectPaths.isEmpty else {
            throw ProjectImportError.importRejected("所选目录无法作为项目导入，请确认目录可访问且不是 Git worktree。")
        }
        let nextProjects = mergeProjectsByPath(existing: existingProjects, updates: builtProjects)
        let nextDirectProjectPaths = normalizePathList(snapshot.appState.directProjectPaths + acceptedProjectPaths)

        try store.updateDirectProjectPaths(nextDirectProjectPaths)
        snapshot.appState.directProjectPaths = nextDirectProjectPaths
        try persistProjects(nextProjects)
        projectImportDiagnostics.recordDirectProjectsPersisted(
            requestedCount: normalizedPaths.count,
            acceptedCount: acceptedProjectPaths.count,
            rejectedCount: normalizedPaths.count - acceptedProjectPaths.count,
            totalCount: nextDirectProjectPaths.count
        )
        errorMessage = importErrors.isEmpty ? nil : importErrors.joined(separator: "\n")
    }

    public func refreshProjectCatalog() async throws {
        guard !snapshot.appState.directories.isEmpty || !snapshot.appState.directProjectPaths.isEmpty else {
            return
        }
        guard !isRefreshingProjectCatalog else {
            return
        }

        let directories = snapshot.appState.directories
        let directProjectPaths = snapshot.appState.directProjectPaths
        let existingProjects = snapshot.projects
        let refreshRequest = ProjectCatalogRefreshRequest(
            directories: directories,
            directProjectPaths: directProjectPaths,
            existingProjects: existingProjects,
            storeHomeDirectoryURL: store.backgroundWorkHomeDirectoryURL
        )
        let refresher = projectCatalogRefresher

        isRefreshingProjectCatalog = true
        defer { isRefreshingProjectCatalog = false }

        let rebuiltProjects = try await Task.detached(priority: .userInitiated) {
            try await refresher(refreshRequest)
        }.value
        applyProjects(rebuiltProjects)
        errorMessage = nil
    }

    public func selectDirectory(_ filter: DirectoryFilter) {
        selectedDirectory = filter
        reconcileSelectionAfterFilterChange()
    }

    public func removeDirectProject(_ path: String) {
        let normalizedPath = normalizePathForCompare(path)
        guard !normalizedPath.isEmpty else {
            return
        }

        let nextPaths = snapshot.appState.directProjectPaths.filter { normalizePathForCompare($0) != normalizedPath }
        guard nextPaths != snapshot.appState.directProjectPaths else {
            errorMessage = nil
            return
        }

        do {
            try store.updateDirectProjectPaths(nextPaths)
            snapshot.appState.directProjectPaths = nextPaths
            reconcileSelectionAfterFilterChange()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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

    public func updateWorkspaceSidebarWidth(_ width: Double) {
        guard snapshot.appState.settings.workspaceSidebarWidth != width else {
            return
        }
        var nextSettings = snapshot.appState.settings
        nextSettings.workspaceSidebarWidth = width
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
        let rootProjectPaths = Set(snapshot.projects.map(\.path))
        openWorkspaceSessions.removeAll { session in
            if session.isQuickTerminal { return false }
            return !rootProjectPaths.contains(session.rootProjectPath) || resolveDisplayProject(for: session.projectPath, rootProjectPath: session.rootProjectPath) == nil
        }
        syncAttentionStateWithOpenSessions()
        if let activeWorkspaceProjectPath, !openWorkspaceProjectPaths.contains(activeWorkspaceProjectPath) {
            self.activeWorkspaceProjectPath = openWorkspaceSessions.last?.projectPath
        }
        if let activeWorkspaceProjectPath {
            selectedProjectPath = activeWorkspaceProjectPath
            return
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
        switch selectedDirectory {
        case .all:
            break
        case let .directory(path):
            if !project.path.hasPrefix(path) {
                return false
            }
        case .directProjects:
            if !directProjectPathSet.contains(normalizePathForCompare(project.path)) {
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
            || (project.isGitRepository && (project.gitLastCommitMessage?.lowercased().contains(query) ?? false))
    }

    private var directProjectPathSet: Set<String> {
        Set(snapshot.appState.directProjectPaths.map(normalizePathForCompare))
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

    private func scheduleWorkspaceRestoreAutosave() {
        workspaceRestoreCoordinator.scheduleAutosave(
            activeProjectPath: activeWorkspaceProjectPath,
            selectedProjectPath: selectedProjectPath,
            sessions: openWorkspaceSessions,
            paneSnapshotProvider: workspacePaneSnapshotProvider
        )
    }

    private func applyWorkspaceRestoreSnapshotIfAvailable() {
        guard let restoredSnapshot = workspaceRestoreCoordinator.loadSnapshot() else {
            return
        }

        let restoredSessions = restoredSnapshot.sessions.compactMap { sessionSnapshot -> OpenWorkspaceSessionState? in
            guard canRestoreWorkspaceSession(sessionSnapshot) else {
                return nil
            }

            let controller = GhosttyWorkspaceController(
                projectPath: sessionSnapshot.projectPath,
                workspaceId: sessionSnapshot.workspaceId
            )
            controller.restore(from: sessionSnapshot)
            registerWorkspaceRestoreObserver(for: controller)

            if sessionSnapshot.projectPath == sessionSnapshot.rootProjectPath, !sessionSnapshot.isQuickTerminal {
                refreshCurrentBranch(for: sessionSnapshot.projectPath)
            }

            return OpenWorkspaceSessionState(
                projectPath: sessionSnapshot.projectPath,
                rootProjectPath: sessionSnapshot.rootProjectPath,
                controller: controller,
                isQuickTerminal: sessionSnapshot.isQuickTerminal
            )
        }

        guard !restoredSessions.isEmpty else {
            return
        }

        openWorkspaceSessions = restoredSessions
        syncAttentionStateWithOpenSessions()

        let restoredActiveProjectPath = restoredSnapshot.activeProjectPath.flatMap { candidate in
            openWorkspaceProjectPaths.contains(candidate) ? candidate : nil
        } ?? restoredSessions.last?.projectPath

        activeWorkspaceProjectPath = restoredActiveProjectPath
        selectedProjectPath = restoredSnapshot.selectedProjectPath.flatMap { candidate in
            if openWorkspaceProjectPaths.contains(candidate) {
                return candidate
            }
            return resolveDisplayProject(for: candidate) == nil ? nil : candidate
        } ?? restoredActiveProjectPath ?? selectedProjectPath

        if let restoredActiveProjectPath,
           let paneID = workspaceController(for: restoredActiveProjectPath)?.selectedPane?.id {
            markWorkspaceNotificationsRead(projectPath: restoredActiveProjectPath, paneID: paneID)
        }
        isDetailPanelPresented = false
    }

    private func canRestoreWorkspaceSession(_ sessionSnapshot: ProjectWorkspaceRestoreSnapshot) -> Bool {
        if sessionSnapshot.isQuickTerminal {
            return !sessionSnapshot.projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return resolveDisplayProject(
            for: sessionSnapshot.projectPath,
            rootProjectPath: sessionSnapshot.rootProjectPath
        ) != nil
    }

    private func registerWorkspaceRestoreObserver(for controller: GhosttyWorkspaceController) {
        controller.onChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleWorkspaceRestoreAutosave()
            }
        }
    }

    private func openWorkspaceSessionIfNeeded(for path: String, rootProjectPath: String, isQuickTerminal: Bool = false) {
        guard !openWorkspaceProjectPaths.contains(path) else {
            return
        }
        let controller = GhosttyWorkspaceController(projectPath: path)
        registerWorkspaceRestoreObserver(for: controller)
        openWorkspaceSessions.append(
            OpenWorkspaceSessionState(
                projectPath: path,
                rootProjectPath: rootProjectPath,
                controller: controller,
                isQuickTerminal: isQuickTerminal
            )
        )
        if path == rootProjectPath, !isQuickTerminal {
            refreshCurrentBranch(for: path)
        }
    }

    private func isQuickTerminalSessionPath(_ path: String) -> Bool {
        openWorkspaceSessions.first(where: { $0.projectPath == path })?.isQuickTerminal ?? false
    }

    private func resolvedWorkspacePresentedTabSelection(for projectPath: String) -> WorkspacePresentedTabSelection? {
        let terminalTabID = workspaceController(for: projectPath)?.selectedTabId
            ?? workspaceController(for: projectPath)?.selectedTab?.id
        let diffTabs = workspaceDiffTabsByProjectPath[projectPath] ?? []

        if let stored = workspaceSelectedPresentedTabByProjectPath[projectPath] {
            switch stored {
            case let .terminal(tabID):
                if workspaceController(for: projectPath)?.tabs.contains(where: { $0.id == tabID }) == true {
                    return .terminal(tabID)
                }
            case let .diff(tabID):
                if diffTabs.contains(where: { $0.id == tabID }) {
                    return .diff(tabID)
                }
            }
        }

        return terminalTabID.map(WorkspacePresentedTabSelection.terminal)
    }

    private func clearWorkspaceRuntimePresentationState(for paths: Set<String>) {
        for path in paths {
            workspaceDiffTabsByProjectPath[path] = nil
            workspaceSelectedPresentedTabByProjectPath[path] = nil
        }
    }

    private func workspaceController(for projectPath: String? = nil) -> GhosttyWorkspaceController? {
        let targetProjectPath = projectPath ?? activeWorkspaceProjectPath
        guard let targetProjectPath else {
            return nil
        }
        return openWorkspaceSessions.first(where: { $0.projectPath == targetProjectPath })?.controller
    }

    private func preferredWorkspaceGitExecutionPath(for rootProjectPath: String) -> String {
        if let activeWorkspaceProjectPath,
           openWorkspaceSessions.contains(where: {
               $0.projectPath == activeWorkspaceProjectPath && $0.rootProjectPath == rootProjectPath
           })
        {
            return activeWorkspaceProjectPath
        }
        return rootProjectPath
    }

    private func workspaceGitExecutionContexts(for rootProject: Project) -> [WorkspaceGitWorktreeContext] {
        let rootContext = WorkspaceGitWorktreeContext(
            path: rootProject.path,
            displayName: rootProject.name,
            branchName: currentBranchByProjectPath[rootProject.path],
            isRootProject: true
        )
        let worktreeContexts = rootProject.worktrees.map { worktree in
            WorkspaceGitWorktreeContext(
                path: worktree.path,
                displayName: worktree.name,
                branchName: worktree.branch,
                isRootProject: false
            )
        }
        return [rootContext] + worktreeContexts
    }

    private func refreshCurrentBranch(for projectPath: String) {
        if let branch = try? worktreeService.currentBranch(at: projectPath) {
            currentBranchByProjectPath[projectPath] = branch
        }
    }

    private func orderedSidebarWorktreeItems(
        for rootProject: Project,
        rootProjectPath: String,
        showsInAppNotifications: Bool,
        moveNotifiedWorktreeToTop: Bool
    ) -> [WorkspaceSidebarWorktreeItem] {
        let items = rootProject.worktrees.map { worktree -> WorkspaceSidebarWorktreeItem in
            let attention = attentionStateByProjectPath[worktree.path]
            return WorkspaceSidebarWorktreeItem(
                rootProjectPath: rootProjectPath,
                worktree: worktree,
                isOpen: openWorkspaceProjectPaths.contains(worktree.path),
                isActive: activeWorkspaceProjectPath == worktree.path,
                notifications: showsInAppNotifications ? (attention?.notifications ?? []) : [],
                unreadNotificationCount: showsInAppNotifications ? (attention?.unreadCount ?? 0) : 0,
                taskStatus: attention.map(\.taskStatus),
                agentState: attention?.resolvedAgentState(
                    overridesByPaneID: agentDisplayOverridesByProjectPath[worktree.path] ?? [:]
                ),
                agentSummary: attention?.resolvedAgentSummary(
                    overridesByPaneID: agentDisplayOverridesByProjectPath[worktree.path] ?? [:]
                ),
                agentKind: attention?.resolvedAgentKind(
                    overridesByPaneID: agentDisplayOverridesByProjectPath[worktree.path] ?? [:]
                )
            )
        }
        guard moveNotifiedWorktreeToTop, showsInAppNotifications else {
            return items
        }
        let originalIndices = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.path, $0.offset) })
        return items.sorted { lhs, rhs in
            if compareSidebarWorktreeItems(lhs, rhs) {
                return true
            }
            if compareSidebarWorktreeItems(rhs, lhs) {
                return false
            }
            return (originalIndices[lhs.path] ?? 0) < (originalIndices[rhs.path] ?? 0)
        }
    }

    private func compareSidebarWorktreeItems(
        _ lhs: WorkspaceSidebarWorktreeItem,
        _ rhs: WorkspaceSidebarWorktreeItem
    ) -> Bool {
        if lhs.hasUnreadNotifications != rhs.hasUnreadNotifications {
            return lhs.hasUnreadNotifications && !rhs.hasUnreadNotifications
        }

        let lhsDate = lhs.notifications.first?.createdAt
        let rhsDate = rhs.notifications.first?.createdAt
        switch (lhsDate, rhsDate) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate > rhsDate
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return false
        }
    }

    private func makeGroupTaskStatus(
        rootProjectPath: String,
        rootAttention: WorkspaceAttentionState?,
        worktrees: [WorkspaceSidebarWorktreeItem]
    ) -> WorkspaceTaskStatus? {
        let statuses = [rootAttention?.taskStatus] + worktrees.map(\.taskStatus)
        if statuses.contains(.running) {
            return .running
        }
        if attentionStateByProjectPath[rootProjectPath] != nil || worktrees.contains(where: { $0.taskStatus != nil }) {
            return .idle
        }
        return nil
    }

    private func makeGroupAgentState(
        rootAgentState: WorkspaceAgentState?
    ) -> WorkspaceAgentState? {
        rootAgentState
    }

    private func makeGroupAgentSummary(
        rootAgentState: WorkspaceAgentState?,
        rootAgentSummary: String?
    ) -> String? {
        guard rootAgentState != nil,
              let rootAgentSummary,
              !rootAgentSummary.isEmpty
        else {
            return nil
        }
        return rootAgentSummary
    }

    private func makeGroupAgentKind(
        rootAgentState: WorkspaceAgentState?,
        rootAgentKind: WorkspaceAgentKind?
    ) -> WorkspaceAgentKind? {
        guard rootAgentState != nil else {
            return nil
        }
        return rootAgentKind
    }

    private func isWorkspacePaneCurrentlyFocused(
        projectPath: String,
        tabID: String,
        paneID: String
    ) -> Bool {
        guard activeWorkspaceProjectPath == projectPath,
              let controller = workspaceController(for: projectPath)
        else {
            return false
        }
        return controller.selectedTabId == tabID && controller.selectedPane?.id == paneID
    }

    private func syncAttentionStateWithOpenSessions() {
        let activePaths = Set(openWorkspaceProjectPaths)
        attentionStateByProjectPath = attentionStateByProjectPath.filter { activePaths.contains($0.key) }
        agentDisplayOverridesByProjectPath = agentDisplayOverridesByProjectPath.filter { activePaths.contains($0.key) }
        if isAgentSignalObservationStarted {
            applyAgentSignalSnapshots(agentSignalStore.currentSnapshots)
        }
    }

    private func applyAgentSignalSnapshots(_ snapshots: [String: WorkspaceAgentSessionSignal]) {
        let openPaths = Set(openWorkspaceProjectPaths)
        for path in openPaths {
            if var attention = attentionStateByProjectPath[path] {
                attention.clearAgentStates()
                attentionStateByProjectPath[path] = attention
            }
        }
        for signal in snapshots.values where openPaths.contains(signal.projectPath) {
            recordAgentSignal(signal)
        }
        pruneWorkspaceAgentDisplayOverrides()
    }

    private func pruneWorkspaceAgentDisplayOverrides() {
        let validPaneIDsByProjectPath = Dictionary(
            grouping: codexDisplayCandidates(),
            by: \.projectPath
        ).mapValues { Set($0.map(\.paneID)) }

        agentDisplayOverridesByProjectPath = agentDisplayOverridesByProjectPath.reduce(into: [:]) { result, entry in
            guard let validPaneIDs = validPaneIDsByProjectPath[entry.key] else {
                return
            }
            let filteredOverrides = entry.value.filter { validPaneIDs.contains($0.key) }
            guard !filteredOverrides.isEmpty else {
                return
            }
            result[entry.key] = filteredOverrides
        }
    }

    private func resolveDisplayProject(for path: String, rootProjectPath: String? = nil) -> Project? {
        if let project = snapshot.projects.first(where: { $0.path == path }) {
            return project
        }

        let rootProject: Project?
        if let rootProjectPath {
            rootProject = snapshot.projects.first(where: { $0.path == rootProjectPath })
        } else {
            rootProject = snapshot.projects.first(where: { project in
                project.worktrees.contains(where: { normalizePathForCompare($0.path) == normalizePathForCompare(path) })
            })
        }

        guard let rootProject,
              let worktree = rootProject.worktrees.first(where: { normalizePathForCompare($0.path) == normalizePathForCompare(path) })
        else {
            return nil
        }
        return buildWorktreeVirtualProject(sourceProject: rootProject, worktree: worktree)
    }

    private func persistProjects(_ projects: [Project]) throws {
        try store.updateProjects(projects)
        applyProjects(projects)
    }

    private func applyProjects(_ projects: [Project]) {
        snapshot.projects = projects
        alignSelectionAfterReload()
        scheduleSelectedProjectDocumentRefresh()
    }

    private func applyWorktreeProgress(_ progress: NativeWorktreeProgress, rootProjectPath: String) {
        guard let projectIndex = snapshot.projects.firstIndex(where: { $0.path == rootProjectPath }) else {
            return
        }
        let now = swiftDateFromDate(Date())
        let current = snapshot.projects[projectIndex].worktrees.first(where: {
            normalizePathForCompare($0.path) == normalizePathForCompare(progress.worktreePath)
        })
        let nextWorktree = ProjectWorktree(
            id: current?.id ?? createWorktreeProjectID(path: progress.worktreePath),
            name: current?.name ?? resolveWorktreeName(progress.worktreePath),
            path: progress.worktreePath,
            branch: progress.branch,
            baseBranch: current?.baseBranch ?? progress.baseBranch,
            inheritConfig: current?.inheritConfig ?? true,
            created: current?.created ?? now,
            status: progress.step == .ready ? "ready" : progress.step == .failed ? "failed" : "creating",
            initStep: progress.step.rawValue,
            initMessage: progress.message,
            initError: progress.error,
            initJobId: current?.initJobId,
            updatedAt: now
        )
        var projects = snapshot.projects
        upsertWorktree(&projects[projectIndex].worktrees, worktree: nextWorktree)
        try? persistProjects(projects)
        worktreeInteractionState = WorktreeInteractionState(
            rootProjectPath: rootProjectPath,
            branch: progress.branch,
            baseBranch: progress.baseBranch,
            worktreePath: progress.worktreePath,
            step: progress.step,
            message: progress.message
        )
    }

    private func finishCreateWorkspaceWorktree(
        _ result: NativeWorktreeCreateResult,
        rootProjectPath: String,
        autoOpen: Bool
    ) {
        guard let projectIndex = snapshot.projects.firstIndex(where: { $0.path == rootProjectPath }) else {
            worktreeInteractionState = nil
            return
        }

        let now = swiftDateFromDate(Date())
        let current = snapshot.projects[projectIndex].worktrees.first(where: {
            normalizePathForCompare($0.path) == normalizePathForCompare(result.worktreePath)
        })
        let readyWorktree = ProjectWorktree(
            id: current?.id ?? createWorktreeProjectID(path: result.worktreePath),
            name: current?.name ?? resolveWorktreeName(result.worktreePath),
            path: result.worktreePath,
            branch: result.branch,
            baseBranch: current?.baseBranch ?? result.baseBranch,
            inheritConfig: current?.inheritConfig ?? true,
            created: current?.created ?? now,
            status: "ready",
            initStep: NativeWorktreeInitStep.ready.rawValue,
            initMessage: result.warning == nil ? "创建完成" : "创建完成（环境初始化存在告警）",
            initError: result.warning,
            initJobId: current?.initJobId,
            updatedAt: now
        )
        var projects = snapshot.projects
        upsertWorktree(&projects[projectIndex].worktrees, worktree: readyWorktree)
        try? persistProjects(projects)
        worktreeInteractionState = nil

        if autoOpen {
            openWorkspaceWorktree(result.worktreePath, from: rootProjectPath)
        }
        if let warning = result.warning, !warning.isEmpty {
            errorMessage = warning
        }
    }

    private func markWorktreeAsFailed(worktreePath: String, rootProjectPath: String, errorMessage: String) {
        guard let projectIndex = snapshot.projects.firstIndex(where: { $0.path == rootProjectPath }) else {
            return
        }
        let now = swiftDateFromDate(Date())
        guard let current = snapshot.projects[projectIndex].worktrees.first(where: {
            normalizePathForCompare($0.path) == normalizePathForCompare(worktreePath)
        }) else {
            return
        }
        let failedWorktree = ProjectWorktree(
            id: current.id,
            name: current.name,
            path: current.path,
            branch: current.branch,
            baseBranch: current.baseBranch,
            inheritConfig: current.inheritConfig,
            created: current.created,
            status: "failed",
            initStep: NativeWorktreeInitStep.failed.rawValue,
            initMessage: errorMessage,
            initError: errorMessage,
            initJobId: current.initJobId,
            updatedAt: now
        )
        var projects = snapshot.projects
        upsertWorktree(&projects[projectIndex].worktrees, worktree: failedWorktree)
        try? persistProjects(projects)
    }

    private func upsertWorktree(_ worktrees: inout [ProjectWorktree], worktree: ProjectWorktree) {
        if let index = worktrees.firstIndex(where: { normalizePathForCompare($0.path) == normalizePathForCompare(worktree.path) }) {
            worktrees[index] = worktree
        } else {
            worktrees.append(worktree)
            worktrees.sort { $0.path < $1.path }
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

private func normalizePathForCompare(_ path: String) -> String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return ""
    }
    var normalized = URL(fileURLWithPath: trimmed).standardizedFileURL.path
        .replacingOccurrences(of: "\\", with: "/")
    while normalized.count > 1 && normalized.hasSuffix("/") {
        normalized.removeLast()
    }
    return normalized
}

private func normalizePathList(_ paths: [String]) -> [String] {
    var seen = Set<String>()
    return paths
        .map(normalizePathForCompare)
        .filter { !$0.isEmpty }
        .filter { seen.insert($0).inserted }
}

private enum ProjectImportError: LocalizedError {
    case importRejected(String)
    case unsupportedGitWorktree(String)
    case invalidDirectory(String)

    var errorDescription: String? {
        switch self {
        case let .importRejected(message):
            return message
        case let .unsupportedGitWorktree(path):
            return "不支持导入 Git worktree：\(path)"
        case let .invalidDirectory(path):
            return "无法读取目录：\(path)"
        }
    }
}

@MainActor
private func validateImportedDirectoryPath(
    _ path: String,
    diagnostics: ProjectImportDiagnostics
) throws -> String {
    let normalizedPath = normalizePathForCompare(path)
    guard !normalizedPath.isEmpty else {
        let error = ProjectImportError.invalidDirectory(path)
        diagnostics.recordValidationRejected(path: path, reason: error.localizedDescription)
        throw error
    }

    let directoryURL = URL(fileURLWithPath: normalizedPath, isDirectory: true)
    let keys: Set<URLResourceKey> = [.isDirectoryKey]
    guard let resourceValues = try? directoryURL.resourceValues(forKeys: keys),
          resourceValues.isDirectory == true
    else {
        let error = ProjectImportError.invalidDirectory(normalizedPath)
        diagnostics.recordValidationRejected(path: normalizedPath, reason: error.localizedDescription)
        throw error
    }
    guard !isGitWorktree(directoryURL) else {
        let error = ProjectImportError.unsupportedGitWorktree(normalizedPath)
        diagnostics.recordValidationRejected(path: normalizedPath, reason: error.localizedDescription)
        throw error
    }
    diagnostics.recordValidationAccepted(path: normalizedPath)
    return normalizedPath
}

private func mergeProjectsByPath(existing: [Project], updates: [Project]) -> [Project] {
    let updatesByPath = Dictionary(uniqueKeysWithValues: updates.map { (normalizePathForCompare($0.path), $0) })
    let existingPaths = Set(existing.map { normalizePathForCompare($0.path) })

    var nextProjects = existing.map { project in
        updatesByPath[normalizePathForCompare(project.path)] ?? project
    }
    for project in updates where !existingPaths.contains(normalizePathForCompare(project.path)) {
        nextProjects.append(project)
    }
    return nextProjects
}

public struct ProjectCatalogRefreshRequest: Sendable {
    public let directories: [String]
    public let directProjectPaths: [String]
    public let existingProjects: [Project]
    public let storeHomeDirectoryURL: URL

    public init(directories: [String], directProjectPaths: [String], existingProjects: [Project], storeHomeDirectoryURL: URL) {
        self.directories = directories
        self.directProjectPaths = directProjectPaths
        self.existingProjects = existingProjects
        self.storeHomeDirectoryURL = storeHomeDirectoryURL
    }
}

private let maxProjectDiscoveryDepth = 6

private func rebuildProjectCatalogSnapshot(_ request: ProjectCatalogRefreshRequest) async throws -> [Project] {
    let discoveredPaths = discoverProjects(in: request.directories)
    let nextPaths = normalizePathList(discoveredPaths + request.directProjectPaths)
    let rebuiltProjects = buildProjects(paths: nextPaths, existing: request.existingProjects)
    try LegacyCompatStore(homeDirectoryURL: request.storeHomeDirectoryURL).updateProjects(rebuiltProjects)
    return rebuiltProjects
}

private func discoverProjects(in directories: [String]) -> [String] {
    let discovered = directories.flatMap(scanDirectoryWithGit)
    return normalizePathList(discovered).sorted()
}

private func scanDirectoryWithGit(_ path: String) -> [String] {
    let rootURL = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    guard FileManager.default.fileExists(atPath: rootURL.path) else {
        return []
    }

    var results: [String] = []
    if isGitRepo(rootURL), !isGitWorktree(rootURL) {
        results.append(rootURL.path)
    }

    let childDirectories = childDirectories(of: rootURL, shouldSkip: shouldSkipDirectDirectory)
    for directoryURL in childDirectories where !isGitWorktree(directoryURL) {
        results.append(directoryURL.path)
    }
    results.append(contentsOf: childDirectories.flatMap { collectNestedGitRepos(in: $0, depth: 1) })
    return results
}

private func collectNestedGitRepos(in directoryURL: URL, depth: Int) -> [String] {
    guard depth < maxProjectDiscoveryDepth else {
        return []
    }

    if isGitRepo(directoryURL) {
        return isGitWorktree(directoryURL) ? [] : [directoryURL.path]
    }

    let childDirectories = childDirectories(of: directoryURL, shouldSkip: shouldSkipRecursiveDirectory)
    return childDirectories.flatMap { collectNestedGitRepos(in: $0, depth: depth + 1) }
}

private func childDirectories(of rootURL: URL, shouldSkip: (String) -> Bool) -> [URL] {
    let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
    guard let contents = try? FileManager.default.contentsOfDirectory(
        at: rootURL,
        includingPropertiesForKeys: Array(keys),
        options: [.skipsSubdirectoryDescendants]
    ) else {
        return []
    }

    return contents.filter { candidate in
        let resourceValues = try? candidate.resourceValues(forKeys: keys)
        let isDirectory = resourceValues?.isDirectory == true
        let isSymbolicLink = resourceValues?.isSymbolicLink == true
        return isDirectory && !isSymbolicLink && !shouldSkip(candidate.lastPathComponent)
    }
}

private func shouldSkipDirectDirectory(_ name: String) -> Bool {
    name.hasPrefix(".")
}

private func shouldSkipRecursiveDirectory(_ name: String) -> Bool {
    guard !name.hasPrefix(".") else {
        return true
    }
    return [".git", "node_modules", "target", "dist", "build"].contains(name)
}

private func buildProjects(paths: [String], existing: [Project]) -> [Project] {
    let existingByPath = Dictionary(uniqueKeysWithValues: existing.map { (normalizePathForCompare($0.path), $0) })
    return paths.compactMap { createProject(path: $0, existingByPath: existingByPath) }
}

private func createProject(path: String, existingByPath: [String: Project]) -> Project? {
    let normalizedPath = normalizePathForCompare(path)
    let projectURL = URL(fileURLWithPath: normalizedPath, isDirectory: true)
    guard !isGitWorktree(projectURL) else {
        return nil
    }

    let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
    guard let resourceValues = try? projectURL.resourceValues(forKeys: keys),
          resourceValues.isDirectory == true
    else {
        return nil
    }

    let now = Date()
    let modificationDate = resourceValues.contentModificationDate ?? now
    let size = Int64(resourceValues.fileSize ?? 0)
    let checksum = "\(Int(modificationDate.timeIntervalSince1970))_\(size)"
    let isGitRepository = isGitRepo(projectURL)

    if let existing = existingByPath[normalizedPath] {
        return Project(
            id: existing.id,
            name: projectURL.lastPathComponent.isEmpty ? normalizedPath : projectURL.lastPathComponent,
            path: normalizedPath,
            tags: existing.tags,
            scripts: existing.scripts,
            worktrees: existing.worktrees,
            mtime: swiftDateFromDate(modificationDate),
            size: size,
            checksum: checksum,
            isGitRepository: isGitRepository,
            gitCommits: existing.gitCommits,
            gitLastCommit: existing.gitLastCommit,
            gitLastCommitMessage: existing.gitLastCommitMessage,
            gitDaily: existing.gitDaily,
            created: existing.created,
            checked: swiftDateFromDate(now)
        )
    }

    return Project(
        id: UUID().uuidString.lowercased(),
        name: projectURL.lastPathComponent.isEmpty ? normalizedPath : projectURL.lastPathComponent,
        path: normalizedPath,
        tags: [],
        scripts: [],
        worktrees: [],
        mtime: swiftDateFromDate(modificationDate),
        size: size,
        checksum: checksum,
        isGitRepository: isGitRepository,
        gitCommits: 0,
        gitLastCommit: .zero,
        gitLastCommitMessage: nil,
        gitDaily: nil,
        created: swiftDateFromDate(now),
        checked: swiftDateFromDate(now)
    )
}

private struct ProjectGitInfo {
    let commitCount: Int
    let lastCommit: SwiftDate
    let lastCommitMessage: String?
}

private func loadGitInfo(for path: String) -> ProjectGitInfo {
    let projectURL = URL(fileURLWithPath: path, isDirectory: true)
    guard isGitRepo(projectURL), !isGitWorktree(projectURL) else {
        return ProjectGitInfo(commitCount: 0, lastCommit: .zero, lastCommitMessage: nil)
    }

    let commitCount = Int(runGitCommand(in: path, arguments: ["rev-list", "--count", "HEAD"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
    let logOutput = runGitCommand(in: path, arguments: ["log", "--format=%ct%x1f%s", "-n", "1"])
    let (lastCommitUnix, lastCommitMessage) = parseLastCommitLogOutput(logOutput)
    return ProjectGitInfo(
        commitCount: commitCount,
        lastCommit: lastCommitUnix > 0 ? swiftDateFromDate(Date(timeIntervalSince1970: lastCommitUnix)) : .zero,
        lastCommitMessage: lastCommitMessage
    )
}

private func parseLastCommitLogOutput(_ output: String?) -> (TimeInterval, String?) {
    guard let output else {
        return (0, nil)
    }
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return (0, nil)
    }

    let parts = trimmed.split(separator: "\u{1f}", maxSplits: 1, omittingEmptySubsequences: false)
    let lastCommit = TimeInterval(parts.first ?? "") ?? 0
    let message = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    return (lastCommit, message.isEmpty ? nil : message)
}

private func runGitCommand(in path: String, arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = URL(fileURLWithPath: path, isDirectory: true)

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        try process.run()
    } catch {
        return nil
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        return nil
    }
    return String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
}

private func isGitRepo(_ url: URL) -> Bool {
    guard !isGitWorktree(url) else {
        return false
    }
    return FileManager.default.fileExists(atPath: url.appending(path: ".git", directoryHint: .notDirectory).path)
        || FileManager.default.fileExists(atPath: url.appending(path: ".git", directoryHint: .isDirectory).path)
}

private func isGitWorktree(_ url: URL) -> Bool {
    let gitURL = url.appending(path: ".git", directoryHint: .notDirectory)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: gitURL.path, isDirectory: &isDirectory),
          !isDirectory.boolValue,
          let resolvedGitDir = resolveGitDirFromFile(gitURL)
    else {
        return false
    }
    return resolvedGitDir.pathComponents.contains("worktrees")
}

private func resolveGitDirFromFile(_ gitFileURL: URL) -> URL? {
    guard let content = try? String(contentsOf: gitFileURL, encoding: .utf8) else {
        return nil
    }
    guard let firstLine = content.split(whereSeparator: \.isNewline).first?.trimmingCharacters(in: .whitespacesAndNewlines),
          firstLine.hasPrefix("gitdir:")
    else {
        return nil
    }
    let rawPath = String(firstLine.dropFirst("gitdir:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rawPath.isEmpty else {
        return nil
    }
    let candidateURL = URL(fileURLWithPath: rawPath)
    if candidateURL.path.hasPrefix("/") {
        return candidateURL
    }
    return gitFileURL.deletingLastPathComponent().appending(path: rawPath).standardizedFileURL
}

private func createWorktreeProjectID(path: String) -> String {
    "worktree:\(path)"
}

private func resolveWorktreeName(_ path: String) -> String {
    URL(fileURLWithPath: path).lastPathComponent
}

private func buildReadyWorktree(path: String, branch: String, now: SwiftDate) -> ProjectWorktree {
    ProjectWorktree(
        id: createWorktreeProjectID(path: path),
        name: resolveWorktreeName(path),
        path: path,
        branch: branch,
        inheritConfig: true,
        created: now,
        status: "ready",
        initStep: NativeWorktreeInitStep.ready.rawValue,
        initMessage: "已添加现有 worktree",
        initError: nil,
        initJobId: nil,
        updatedAt: now
    )
}

private func buildWorktreeVirtualProject(sourceProject: Project, worktree: ProjectWorktree) -> Project {
    let now = swiftDateFromDate(Date())
    return Project(
        id: createWorktreeProjectID(path: worktree.path),
        name: worktree.name,
        path: worktree.path,
        tags: sourceProject.tags,
        scripts: sourceProject.scripts,
        worktrees: [],
        mtime: sourceProject.mtime,
        size: sourceProject.size,
        checksum: "worktree:\(worktree.path)",
        isGitRepository: sourceProject.isGitRepository,
        gitCommits: sourceProject.gitCommits,
        gitLastCommit: sourceProject.gitLastCommit,
        gitLastCommitMessage: sourceProject.gitLastCommitMessage,
        gitDaily: sourceProject.gitDaily,
        created: worktree.created,
        checked: now
    )
}

private func buildSyncedWorktrees(existingWorktrees: [ProjectWorktree], gitWorktrees: [NativeGitWorktree]) -> [ProjectWorktree] {
    let existingByPath = Dictionary(uniqueKeysWithValues: existingWorktrees.map { (normalizePathForCompare($0.path), $0) })
    let now = swiftDateFromDate(Date())
    return gitWorktrees
        .map { item -> ProjectWorktree in
            let existing = existingByPath[normalizePathForCompare(item.path)]
            return ProjectWorktree(
                id: existing?.id ?? createWorktreeProjectID(path: item.path),
                name: existing?.name ?? resolveWorktreeName(item.path),
                path: item.path,
                branch: item.branch,
                baseBranch: existing?.baseBranch,
                inheritConfig: existing?.inheritConfig ?? true,
                created: existing?.created ?? now,
                status: existing?.status,
                initStep: existing?.initStep,
                initMessage: existing?.initMessage,
                initError: existing?.initError,
                initJobId: existing?.initJobId,
                updatedAt: existing?.updatedAt
            )
        }
        .sorted { $0.path < $1.path }
}

private func swiftDateFromDate(_ date: Date) -> SwiftDate {
    date.timeIntervalSinceReferenceDate
}

private func hexColor(for color: ColorData) -> String {
    let r = Int(max(0, min(255, round(color.r * 255))))
    let g = Int(max(0, min(255, round(color.g * 255))))
    let b = Int(max(0, min(255, round(color.b * 255))))
    return String(format: "#%02X%02X%02X", r, g, b)
}
