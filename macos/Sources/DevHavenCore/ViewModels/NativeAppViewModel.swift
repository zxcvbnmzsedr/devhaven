import Foundation
import Observation

private struct WorktreeCreateContext {
    let request: NativeWorktreeCreateRequest
    let rootProjectPath: String
    let previewPath: String
}

private enum PendingWorkspaceWorktreeCreateStatus: String, Equatable, Sendable {
    case creating
    case failed
}

private struct PendingWorkspaceWorktreeCreateState: Equatable {
    let rootProjectPath: String
    let branch: String
    let baseBranch: String?
    let worktreePath: String
    let createBranch: Bool
    let jobID: String
    let createdAt: SwiftDate
    var status: PendingWorkspaceWorktreeCreateStatus
    var step: NativeWorktreeInitStep
    var message: String
    var error: String?
}

private struct WorkspaceAlignmentStatusProbe: Sendable {
    let projectPath: String
    let targetBranch: String
    let managedWorktreePath: String
    let branches: [NativeGitBranch]
    let worktrees: [NativeGitWorktree]
    let currentBranch: String

    var branchExists: Bool {
        branches.contains(where: { $0.name == targetBranch })
    }

    var occupiedTargetWorktree: NativeGitWorktree? {
        worktrees.first(where: { $0.branch == targetBranch })
    }

    var hasOccupiedTargetCheckout: Bool {
        currentBranch == targetBranch || occupiedTargetWorktree != nil
    }
}

private struct DisplayProjectLookupKey: Hashable {
    let path: String
    let rootProjectPath: String?
}

private struct WorkspaceSidebarProjectionCacheEntry {
    let revision: Int
    let state: WorkspaceSidebarProjectionState
}

private struct WorkspaceAlignmentGroupsCacheEntry {
    let revision: Int
    let groups: [WorkspaceAlignmentGroupProjection]
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
    @ObservationIgnored private let worktreeEnvironmentService: any NativeWorktreeEnvironmentServicing
    @ObservationIgnored private let gitRepositoryService: NativeGitRepositoryService
    @ObservationIgnored private let agentSignalStore: WorkspaceAgentSignalStore
    @ObservationIgnored private let runManager: any WorkspaceRunManaging
    @ObservationIgnored private let workspaceRestoreCoordinator: WorkspaceRestoreCoordinator
    @ObservationIgnored private let workspaceAlignmentRootStore: WorkspaceAlignmentRootStore
    @ObservationIgnored private var workspacePaneSnapshotProvider: WorkspacePaneSnapshotProvider?
    @ObservationIgnored private var projectDocumentLoadTask: Task<Void, Never>?
    @ObservationIgnored private var projectNotesSummaryBackfillTask: Task<Void, Never>?
    @ObservationIgnored private var projectDocumentLoadRevision = 0
    @ObservationIgnored private var isAgentSignalObservationStarted = false
    @ObservationIgnored private var displayProjectCacheByLookupKey: [DisplayProjectLookupKey: Project?] = [:]
    @ObservationIgnored private var projectsByNormalizedPath: [String: Project] = [:]
    @ObservationIgnored private var workspaceSessionIndexByNormalizedPath: [String: Int] = [:]
    @ObservationIgnored private var workspaceSidebarProjectionCache: WorkspaceSidebarProjectionCacheEntry?
    @ObservationIgnored private var workspaceAlignmentGroupsCache: WorkspaceAlignmentGroupsCacheEntry?

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

    public struct WorkspacePresentedTabSnapshot: Equatable, Sendable {
        public let items: [WorkspacePresentedTabItem]
        public let selection: WorkspacePresentedTabSelection?

        public init(items: [WorkspacePresentedTabItem], selection: WorkspacePresentedTabSelection?) {
            self.items = items
            self.selection = selection
        }
    }

    public var snapshot: NativeAppSnapshot {
        didSet {
            noteWorkspaceSidebarProjectionMutation(from: oldValue, to: snapshot)
            if oldValue.projects != snapshot.projects {
                displayProjectCacheByLookupKey.removeAll()
                rebuildProjectLookupIndex()
            }
        }
    }
    public var selectedProjectPath: String?
    public var openWorkspaceSessions: [OpenWorkspaceSessionState] {
        didSet {
            noteWorkspaceSidebarProjectionMutation(from: oldValue, to: openWorkspaceSessions)
            rebuildWorkspaceSessionIndex()
        }
    }
    public var activeWorkspaceProjectPath: String? {
        didSet {
            noteWorkspaceSidebarProjectionMutation(from: oldValue, to: activeWorkspaceProjectPath)
        }
    }
    public var workspaceSideToolWindowState: WorkspaceSideToolWindowState
    public var workspaceBottomToolWindowState: WorkspaceBottomToolWindowState
    public var workspaceFocusedArea: WorkspaceFocusedArea
    private var workspaceDiffTabsByProjectPath: [String: [WorkspaceDiffTabState]]
    private var workspaceSelectedPresentedTabByProjectPath: [String: WorkspacePresentedTabSelection]
    private var attentionStateByProjectPath: [String: WorkspaceAttentionState] {
        didSet {
            noteWorkspaceSidebarProjectionMutation(from: oldValue, to: attentionStateByProjectPath)
        }
    }
    private var agentDisplayOverridesByProjectPath: [String: [String: WorkspaceAgentPresentationOverride]] {
        didSet {
            noteWorkspaceSidebarProjectionMutation(from: oldValue, to: agentDisplayOverridesByProjectPath)
        }
    }
    private var workspaceRunConsoleStateByProjectPath: [String: WorkspaceRunConsoleState]
    private var currentBranchByProjectPath: [String: String] {
        didSet {
            noteWorkspaceSidebarProjectionMutation(from: oldValue, to: currentBranchByProjectPath)
        }
    }
    private var pendingWorkspaceWorktreeCreatesByPath: [String: PendingWorkspaceWorktreeCreateState] {
        didSet {
            noteWorkspaceSidebarProjectionMutation(from: oldValue, to: pendingWorkspaceWorktreeCreatesByPath)
        }
    }
    private var workspaceAlignmentStatusByKey: [String: WorkspaceAlignmentMemberStatus] {
        didSet {
            noteWorkspaceSidebarProjectionMutation(from: oldValue, to: workspaceAlignmentStatusByKey)
        }
    }
    private var workspaceCommitViewModels: [String: WorkspaceCommitViewModel]
    private var workspaceGitViewModels: [String: WorkspaceGitViewModel]
    private var workspaceDiffTabViewModels: [String: WorkspaceDiffTabViewModel]
    public private(set) var workspaceSidebarProjectionRevision: Int
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
    public var requestedSettingsSection: SettingsNavigationSection?
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
        worktreeEnvironmentService: (any NativeWorktreeEnvironmentServicing)? = nil,
        gitRepositoryService: NativeGitRepositoryService = NativeGitRepositoryService(),
        agentSignalStore: WorkspaceAgentSignalStore? = nil,
        runManager: (any WorkspaceRunManaging)? = nil,
        workspaceRestoreStore: WorkspaceRestoreStore? = nil,
        workspaceAlignmentRootStore: WorkspaceAlignmentRootStore? = nil,
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
        self.worktreeEnvironmentService = worktreeEnvironmentService ?? NativeWorktreeEnvironmentService()
        self.gitRepositoryService = gitRepositoryService
        self.agentSignalStore = agentSignalStore ?? WorkspaceAgentSignalStore(
            baseDirectoryURL: store.agentStatusSessionsDirectoryURL
        )
        let resolvedRunManager = runManager ?? WorkspaceRunManager(
            logStore: WorkspaceRunLogStore(baseDirectoryURL: store.backgroundWorkHomeDirectoryURL)
        )
        self.runManager = resolvedRunManager
        self.workspaceRestoreCoordinator = WorkspaceRestoreCoordinator(
            store: workspaceRestoreStore ?? WorkspaceRestoreStore(homeDirectoryURL: store.backgroundWorkHomeDirectoryURL),
            autosaveDelayNanoseconds: workspaceRestoreAutosaveDelayNanoseconds
        )
        self.workspaceAlignmentRootStore = workspaceAlignmentRootStore ?? WorkspaceAlignmentRootStore(
            baseDirectoryURL: store.workspaceRootsDirectoryURL
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
        self.workspaceRunConsoleStateByProjectPath = [:]
        self.currentBranchByProjectPath = [:]
        self.pendingWorkspaceWorktreeCreatesByPath = [:]
        self.workspaceAlignmentStatusByKey = [:]
        self.workspaceCommitViewModels = [:]
        self.workspaceGitViewModels = [:]
        self.workspaceDiffTabViewModels = [:]
        self.workspaceSidebarProjectionRevision = 0
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
        self.requestedSettingsSection = nil
        self.isRecycleBinPresented = false
        self.isDetailPanelPresented = false
        self.worktreeInteractionState = nil
        self.notesDraft = ""
        self.todoDraft = ""
        self.todoItems = []
        self.readmeFallback = nil
        self.hasLoadedInitialData = false
        self.rebuildProjectLookupIndex()
        self.rebuildWorkspaceSessionIndex()

        resolvedRunManager.onEvent = { [weak self] event in
            self?.handleWorkspaceRunManagerEvent(event)
        }
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
            .filter { isWorkspaceSessionOwnedByProjectPool($0, rootProjectPath: $0.projectPath) }
            .map(\.projectPath)
    }

    public var openWorkspaceProjects: [Project] {
        openWorkspaceSessions.compactMap { resolveDisplayProject(for: $0.projectPath, rootProjectPath: $0.rootProjectPath) }
    }

    public var availableWorkspaceProjects: [Project] {
        let openedPaths = Set(openWorkspaceRootProjectPaths)
        return visibleProjects.filter { !openedPaths.contains($0.path) }
    }

    public var workspaceAlignmentProjectOptions: [Project] {
        visibleProjects.filter { !$0.isQuickTerminal }
    }

    public var workspaceSidebarGroups: [WorkspaceSidebarProjectGroup] {
        let showsInAppNotifications = snapshot.appState.settings.workspaceInAppNotificationsEnabled
        let moveNotifiedWorktreeToTop = snapshot.appState.settings.moveNotifiedWorktreeToTop
        let projectsByNormalizedPath = self.projectsByNormalizedPath

        var groups: [WorkspaceSidebarProjectGroup] = openWorkspaceRootProjectPaths.compactMap { rootPath in
            guard let rootProject = projectsByNormalizedPath[rootPath] else {
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
            let transientProject = if let workspaceRootContext = session.workspaceRootContext {
                Project.workspaceRoot(name: workspaceRootContext.workspaceName, path: session.projectPath)
            } else {
                Project.quickTerminal(at: session.projectPath)
            }
            groups.append(WorkspaceSidebarProjectGroup(
                rootProject: transientProject,
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

    public var workspaceAlignmentGroups: [WorkspaceAlignmentGroupProjection] {
        if let cache = workspaceAlignmentGroupsCache,
           cache.revision == workspaceSidebarProjectionRevision {
            return cache.groups
        }

        let projectsByNormalizedPath = self.projectsByNormalizedPath
        let groups = snapshot.appState.workspaceAlignmentGroups.map { definition in
            let aliasByProjectPath = resolvedWorkspaceAlignmentAliases(
                for: definition,
                projectsByNormalizedPath: projectsByNormalizedPath
            )
            let members = definition.effectiveMembers.map { memberDefinition in
                let normalizedProjectPath = normalizePathForCompare(memberDefinition.projectPath)
                let status = workspaceAlignmentStatusByKey[
                    workspaceAlignmentStatusKey(
                        groupID: definition.id,
                        projectPath: memberDefinition.projectPath
                    )
                ] ?? .checking
                let project = projectsByNormalizedPath[normalizedProjectPath]
                let openTarget = workspaceAlignmentOpenTarget(
                    for: normalizedProjectPath,
                    targetBranch: memberDefinition.targetBranch,
                    status: status
                )
                return WorkspaceAlignmentMemberProjection(
                    groupID: definition.id,
                    projectPath: normalizedProjectPath,
                    alias: aliasByProjectPath[normalizedProjectPath] ?? pathLastComponent(normalizedProjectPath),
                    projectName: project?.name ?? pathLastComponent(memberDefinition.projectPath),
                    targetBranch: memberDefinition.targetBranch,
                    branchLabel: workspaceAlignmentBranchLabel(
                        for: normalizedProjectPath,
                        targetBranch: memberDefinition.targetBranch,
                        status: status,
                        openTarget: openTarget
                    ),
                    status: status,
                    openTarget: openTarget
                )
            }
            return WorkspaceAlignmentGroupProjection(definition: definition, members: members)
        }
        workspaceAlignmentGroupsCache = WorkspaceAlignmentGroupsCacheEntry(
            revision: workspaceSidebarProjectionRevision,
            groups: groups
        )
        return groups
    }

    public func workspaceSidebarProjectionState() -> WorkspaceSidebarProjectionState {
        if let cache = workspaceSidebarProjectionCache,
           cache.revision == workspaceSidebarProjectionRevision {
            return cache.state
        }

        let state = WorkspaceSidebarProjectionState(
            groups: workspaceSidebarGroups,
            availableProjects: availableWorkspaceProjects,
            workspaceAlignmentGroups: workspaceAlignmentGroups,
            workspaceAlignmentProjectOptions: workspaceAlignmentProjectOptions
        )
        workspaceSidebarProjectionCache = WorkspaceSidebarProjectionCacheEntry(
            revision: workspaceSidebarProjectionRevision,
            state: state
        )
        return state
    }

    func workspaceAttentionState(for projectPath: String) -> WorkspaceAttentionState? {
        attentionStateByProjectPath[projectPath]
    }

    public func workspaceRunConsoleState(for projectPath: String) -> WorkspaceRunConsoleState? {
        workspaceRunConsoleStateByProjectPath[projectPath]
    }

    public func availableWorkspaceRunConfigurations(in projectPath: String? = nil) -> [WorkspaceRunConfiguration] {
        guard let projectPath = resolveWorkspaceRunProjectPath(projectPath) else {
            return []
        }
        return resolvedWorkspaceRunConfigurations(for: projectPath)
    }

    public func selectedWorkspaceRunConfiguration(in projectPath: String? = nil) -> WorkspaceRunConfiguration? {
        guard let projectPath = resolveWorkspaceRunProjectPath(projectPath) else {
            return nil
        }
        return resolvedSelectedWorkspaceRunConfiguration(for: projectPath)
    }

    public func workspaceRunToolbarState(for projectPath: String? = nil) -> WorkspaceRunToolbarState {
        guard let projectPath = resolveWorkspaceRunProjectPath(projectPath) else {
            return WorkspaceRunToolbarState()
        }

        let configurations = resolvedWorkspaceRunConfigurations(for: projectPath)
        let consoleState = workspaceRunConsoleStateByProjectPath[projectPath] ?? WorkspaceRunConsoleState()
        let selectedConfiguration = resolvedSelectedWorkspaceRunConfiguration(
            for: projectPath,
            configurations: configurations
        )

        return WorkspaceRunToolbarState(
            configurations: configurations,
            selectedConfigurationID: consoleState.selectedConfigurationID ?? selectedConfiguration?.id,
            canRun: selectedConfiguration?.canRun ?? false,
            canStop: consoleState.selectedSession?.state.isActive ?? false,
            hasSessions: !consoleState.sessions.isEmpty,
            isLogsVisible: consoleState.isVisible
        )
    }

    public func selectWorkspaceRunConfiguration(_ configurationID: String, in projectPath: String? = nil) {
        guard let projectPath = resolveWorkspaceRunProjectPath(projectPath) else {
            return
        }
        var state = workspaceRunConsoleStateByProjectPath[projectPath] ?? WorkspaceRunConsoleState()
        state.selectedConfigurationID = configurationID
        workspaceRunConsoleStateByProjectPath[projectPath] = state
    }

    public func runSelectedWorkspaceConfiguration(in projectPath: String? = nil) throws {
        guard let projectPath = resolveWorkspaceRunProjectPath(projectPath),
              let session = openWorkspaceSessions.first(where: { $0.projectPath == projectPath }),
              let configuration = selectedWorkspaceRunConfiguration(in: projectPath)
        else {
            let error = WorkspaceTerminalCommandError.noActiveWorkspace
            errorMessage = error.localizedDescription
            throw error
        }

        guard configuration.canRun else {
            let message = configuration.disabledReason ?? "当前运行配置缺少必要参数，请先完成配置。"
            let error = NSError(domain: "DevHavenCore.WorkspaceRunConfiguration", code: 1, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
            errorMessage = message
            throw error
        }

        var state = workspaceRunConsoleStateByProjectPath[projectPath] ?? WorkspaceRunConsoleState()
        if let existingSession = state.sessions.first(where: { $0.configurationID == configuration.id }),
           existingSession.state.isActive {
            runManager.stop(sessionID: existingSession.id)
        }

        let sessionID = UUID().uuidString
        let placeholderSession = WorkspaceRunSession(
            id: sessionID,
            configurationID: configuration.id,
            configurationName: configuration.name,
            configurationSource: configuration.source,
            projectPath: projectPath,
            rootProjectPath: session.rootProjectPath,
            command: configuration.displayCommand,
            workingDirectory: configuration.workingDirectory,
            state: .starting,
            startedAt: Date()
        )
        if let existingIndex = state.sessions.firstIndex(where: { $0.configurationID == configuration.id }) {
            state.sessions[existingIndex] = placeholderSession
        } else {
            state.sessions.append(placeholderSession)
        }
        state.selectedSessionID = sessionID
        state.selectedConfigurationID = configuration.id
        state.isVisible = true
        workspaceRunConsoleStateByProjectPath[projectPath] = state

        do {
            let runSession = try runManager.start(
                WorkspaceRunStartRequest(
                    sessionID: sessionID,
                    configurationID: configuration.id,
                    configurationName: configuration.name,
                    configurationSource: configuration.source,
                    projectPath: projectPath,
                    rootProjectPath: session.rootProjectPath,
                    executable: configuration.executable,
                    displayCommand: configuration.displayCommand,
                    workingDirectory: configuration.workingDirectory
                )
            )
            var currentState = workspaceRunConsoleStateByProjectPath[projectPath] ?? state
            if let index = currentState.sessions.firstIndex(where: { $0.id == sessionID }) {
                var updatedSession = runSession
                updatedSession.startedAt = currentState.sessions[index].startedAt
                updatedSession.displayBuffer = currentState.sessions[index].displayBuffer
                currentState.sessions[index] = updatedSession
            } else if let index = currentState.sessions.firstIndex(where: { $0.configurationID == configuration.id }) {
                currentState.sessions[index] = runSession
            } else {
                currentState.sessions.append(runSession)
            }
            workspaceRunConsoleStateByProjectPath[projectPath] = currentState
            errorMessage = nil
        } catch {
            let failureBuffer = "启动失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)\n"
            var currentState = workspaceRunConsoleStateByProjectPath[projectPath] ?? state
            let failureSession = WorkspaceRunSession(
                id: sessionID,
                configurationID: configuration.id,
                configurationName: configuration.name,
                configurationSource: configuration.source,
                projectPath: projectPath,
                rootProjectPath: session.rootProjectPath,
                command: configuration.command,
                workingDirectory: configuration.workingDirectory,
                state: .failed(exitCode: -1),
                startedAt: currentState.sessions.first(where: { $0.id == sessionID })?.startedAt ?? Date(),
                endedAt: Date(),
                displayBuffer: failureBuffer
            )
            if let index = currentState.sessions.firstIndex(where: { $0.id == sessionID || $0.configurationID == configuration.id }) {
                currentState.sessions[index] = failureSession
            } else {
                currentState.sessions.append(failureSession)
            }
            workspaceRunConsoleStateByProjectPath[projectPath] = currentState
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            throw error
        }
    }

    public func selectWorkspaceRunSession(_ sessionID: String, in projectPath: String? = nil) {
        guard let projectPath = resolveWorkspaceRunProjectPath(projectPath),
              var state = workspaceRunConsoleStateByProjectPath[projectPath],
              state.sessions.contains(where: { $0.id == sessionID })
        else {
            return
        }
        state.selectedSessionID = sessionID
        state.selectedConfigurationID = state.sessions.first(where: { $0.id == sessionID })?.configurationID
        state.isVisible = true
        workspaceRunConsoleStateByProjectPath[projectPath] = state
    }

    public func stopSelectedWorkspaceRunSession(in projectPath: String? = nil) {
        guard let projectPath = resolveWorkspaceRunProjectPath(projectPath),
              let state = workspaceRunConsoleStateByProjectPath[projectPath],
              let sessionID = state.selectedSession?.id
        else {
            return
        }
        runManager.stop(sessionID: sessionID)
    }

    public func toggleWorkspaceRunConsole(in projectPath: String? = nil) {
        guard let projectPath = resolveWorkspaceRunProjectPath(projectPath),
              var state = workspaceRunConsoleStateByProjectPath[projectPath]
        else {
            return
        }
        state.isVisible.toggle()
        workspaceRunConsoleStateByProjectPath[projectPath] = state
    }

    public func updateWorkspaceRunConsolePanelHeight(_ height: Double, in projectPath: String? = nil) {
        guard let projectPath = resolveWorkspaceRunProjectPath(projectPath),
              var state = workspaceRunConsoleStateByProjectPath[projectPath]
        else {
            return
        }
        state.panelHeight = height
        workspaceRunConsoleStateByProjectPath[projectPath] = state
    }

    public func clearSelectedWorkspaceRunConsoleBuffer(in projectPath: String? = nil) {
        guard let projectPath = resolveWorkspaceRunProjectPath(projectPath),
              var state = workspaceRunConsoleStateByProjectPath[projectPath],
              let selectedSessionID = state.selectedSession?.id,
              let index = state.sessions.firstIndex(where: { $0.id == selectedSessionID })
        else {
            return
        }
        state.sessions[index].displayBuffer = ""
        workspaceRunConsoleStateByProjectPath[projectPath] = state
    }

    public func openSelectedWorkspaceRunLog(in projectPath: String? = nil) throws {
        guard let projectPath = resolveWorkspaceRunProjectPath(projectPath),
              let state = workspaceRunConsoleStateByProjectPath[projectPath],
              let path = state.selectedSession?.logFilePath
        else {
            return
        }
        do {
            try terminalCommandRunner("/usr/bin/open", [path])
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            throw error
        }
    }

    public func saveWorkspaceRunConfigurations(_ runConfigurations: [ProjectRunConfiguration], in projectPath: String? = nil) throws {
        guard let projectPath = resolveWorkspaceRunProjectPath(projectPath),
              let ownerProjectPath = resolveWorkspaceScriptOwnerProjectPath(for: projectPath),
              let ownerIndex = snapshot.projects.firstIndex(where: {
                  normalizePathForCompare($0.path) == normalizePathForCompare(ownerProjectPath)
              })
        else {
            let error = WorkspaceTerminalCommandError.noActiveWorkspace
            errorMessage = error.localizedDescription
            throw error
        }

        var projects = snapshot.projects
        projects[ownerIndex].runConfigurations = runConfigurations
        try persistProjects(projects)
        errorMessage = nil
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
        let previousAttention = attention
        attention.setTaskStatus(status, for: paneID)
        guard attention != previousAttention else {
            return
        }
        attentionStateByProjectPath[projectPath] = attention
    }

    public func recordAgentSignal(_ signal: WorkspaceAgentSessionSignal) {
        guard openWorkspaceProjectPaths.contains(signal.projectPath) else {
            return
        }
        var attention = attentionStateByProjectPath[signal.projectPath] ?? WorkspaceAttentionState()
        let previousAttention = attention
        applyAgentSignal(signal, to: &attention)
        guard attention != previousAttention else {
            return
        }
        attentionStateByProjectPath[signal.projectPath] = attention
    }

    public func clearAgentSignal(projectPath: String, paneID: String) {
        guard var attention = attentionStateByProjectPath[projectPath] else {
            return
        }
        let previousAttention = attention
        attention.clearAgentState(for: paneID)
        guard attention != previousAttention else {
            return
        }
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
        let candidates = attentionStateByProjectPath
            .filter { openPaths.contains($0.key) }
            .flatMap { projectPath, attention in
                attention.agentStateByPaneID.compactMap { entry -> WorkspaceAgentDisplayCandidate? in
                    let (paneID, state) = entry
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
        return WorkspaceAgentDisplayCandidate.observationStableSorted(candidates)
    }

    public func replaceWorkspaceAgentDisplayOverrides(
        _ overridesByProjectPath: [String: [String: WorkspaceAgentPresentationOverride]]
    ) {
        let filteredOverrides = filteredWorkspaceAgentDisplayOverrides(overridesByProjectPath)
        guard agentDisplayOverridesByProjectPath != filteredOverrides else {
            return
        }
        agentDisplayOverridesByProjectPath = filteredOverrides
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
        workspaceController(for: activeWorkspaceProjectPath)
    }

    public var activeWorkspaceRootProjectPath: String? {
        workspaceSession(for: activeWorkspaceProjectPath)?.rootProjectPath
    }

    public var activeWorkspaceRootProject: Project? {
        guard let normalizedRootProjectPath = normalizedOptionalPathForCompare(activeWorkspaceRootProjectPath) else {
            return nil
        }
        return projectsByNormalizedPath[normalizedRootProjectPath]
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

    public func workspacePresentedTabSnapshot(for projectPath: String) -> WorkspacePresentedTabSnapshot {
        let controller = workspaceController(for: projectPath)
        let selected = resolvedWorkspacePresentedTabSelection(for: projectPath, controller: controller)
        let terminalTabs = controller?.tabs.map { tab in
            WorkspacePresentedTabItem(
                id: tab.id,
                title: tab.title,
                selection: .terminal(tab.id),
                isSelected: selected == .terminal(tab.id)
            )
        } ?? []
        let diffTabs = (workspaceDiffTabsByProjectPath[projectPath] ?? []).map { tab in
            WorkspacePresentedTabItem(
                id: tab.id,
                title: tab.title,
                selection: .diff(tab.id),
                isSelected: selected == .diff(tab.id)
            )
        }
        return WorkspacePresentedTabSnapshot(
            items: terminalTabs + diffTabs,
            selection: selected
        )
    }

    public func workspacePresentedTabs(for projectPath: String) -> [WorkspacePresentedTabItem] {
        workspacePresentedTabSnapshot(for: projectPath).items
    }

    public func workspaceSelectedPresentedTab(for projectPath: String) -> WorkspacePresentedTabSelection? {
        workspacePresentedTabSnapshot(for: projectPath).selection
    }

    public func workspaceDiffTabViewModel(for projectPath: String, tabID: String) -> WorkspaceDiffTabViewModel? {
        guard let tab = workspaceDiffTabsByProjectPath[projectPath]?.first(where: { $0.id == tabID }) else {
            return nil
        }
        if let existing = workspaceDiffTabViewModels[tabID] {
            return existing
        }
        let viewModel = WorkspaceDiffTabViewModel(
            tab: tab,
            client: .live(repositoryService: gitRepositoryService)
        )
        workspaceDiffTabViewModels[tabID] = viewModel
        return viewModel
    }

    public var activeWorkspaceSelectedPresentedTab: WorkspacePresentedTabSelection? {
        guard let activeWorkspaceProjectPath else {
            return nil
        }
        return workspaceSelectedPresentedTab(for: activeWorkspaceProjectPath)
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
                    title: pathLastComponent(directory),
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
            .filter { $0.isQuickTerminal && $0.workspaceRootContext == nil }
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
            return RecycleBinItem(path: path, name: pathLastComponent(path), missing: true)
        }
    }

    public func load() {
        isLoading = true
        defer {
            isLoading = false
            hasLoadedInitialData = true
        }

        do {
            projectNotesSummaryBackfillTask?.cancel()
            projectNotesSummaryBackfillTask = nil
            projectDocumentCache.removeAll()
            let shouldApplyWorkspaceRestore = !hasLoadedInitialData && openWorkspaceSessions.isEmpty
            snapshot = try store.loadSnapshot()
            alignSelectionAfterReload()
            if shouldApplyWorkspaceRestore {
                applyWorkspaceRestoreSnapshotIfAvailable()
            }
            scheduleSelectedProjectDocumentRefresh()
            scheduleProjectNotesSummaryBackfillIfNeeded()
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
        let resolvedPath = canonicalWorkspaceSessionPath(for: path) ?? normalizedOptionalPathForCompare(path)

        if resolvedPath == selectedProjectPath, isDetailPanelPresented == (resolvedPath != nil) {
            return
        }
        if let resolvedPath {
            if activeWorkspaceProjectPath != nil, workspaceSession(for: resolvedPath) != nil {
                activeWorkspaceProjectPath = resolvedPath
                isDetailPanelPresented = false
            } else {
                isDetailPanelPresented = true
            }
        } else {
            isDetailPanelPresented = false
        }
        selectedProjectPath = resolvedPath
        scheduleSelectedProjectDocumentRefresh()
        scheduleWorkspaceRestoreAutosave()
    }

    public func enterWorkspace(_ path: String) {
        let normalizedPath = normalizePathForCompare(path)
        selectedProjectPath = normalizedPath
        promoteWorkspaceSessionIfNeeded(for: normalizedPath, rootProjectPath: normalizedPath)
        openWorkspaceSessionIfNeeded(for: normalizedPath, rootProjectPath: normalizedPath)
        activeWorkspaceProjectPath = canonicalWorkspaceSessionPath(for: normalizedPath) ?? normalizedPath
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
           workspaceSession(for: activeWorkspaceProjectPath) != nil {
            activateWorkspaceProject(activeWorkspaceProjectPath)
            return
        }
        if let selectedProjectPath,
           workspaceSession(for: selectedProjectPath) != nil {
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
        guard let canonicalPath = canonicalWorkspaceSessionPath(for: path) else {
            return
        }
        activeWorkspaceProjectPath = canonicalPath
        if !isQuickTerminalSessionPath(canonicalPath) {
            selectedProjectPath = canonicalPath
        }
        if let paneID = workspaceController(for: canonicalPath)?.selectedPane?.id {
            markWorkspaceNotificationsRead(projectPath: canonicalPath, paneID: paneID)
        }
        isDetailPanelPresented = false
        if !isQuickTerminalSessionPath(canonicalPath) {
            scheduleSelectedProjectDocumentRefresh()
        }
        scheduleWorkspaceRestoreAutosave()
    }

    public func closeWorkspaceProject(_ path: String) {
        guard let index = workspaceSessionIndex(for: path) else {
            return
        }

        let normalizedPath = normalizePathForCompare(path)
        let session = openWorkspaceSessions[index]
        let rootProjectPath = session.rootProjectPath
        let workspaceAlignmentGroupID = session.workspaceRootContext?.workspaceID
        let removedPaths: Set<String>
        let shouldCascadeOwnedSessions = normalizePathForCompare(rootProjectPath) == normalizedPath &&
            (session.workspaceAlignmentGroupID == nil || workspaceAlignmentGroupID != nil)
        if shouldCascadeOwnedSessions {
            removedPaths = Set(
                openWorkspaceSessions
                    .filter {
                        let sessionPathMatches = normalizePathForCompare($0.projectPath) == normalizedPath
                        if let workspaceAlignmentGroupID {
                            return sessionPathMatches || $0.workspaceAlignmentGroupID == workspaceAlignmentGroupID
                        }
                        return isWorkspaceSessionOwnedByProjectPool($0, rootProjectPath: path)
                    }
                    .map(\.projectPath)
            )
            openWorkspaceSessions.removeAll { removedPaths.contains($0.projectPath) }
        } else {
            removedPaths = Set([path])
            openWorkspaceSessions.remove(at: index)
        }
        removedPaths.forEach { runManager.stopAll(projectPath: $0) }
        clearWorkspaceRuntimePresentationState(for: removedPaths)
        attentionStateByProjectPath = attentionStateByProjectPath.filter { openWorkspaceProjectPaths.contains($0.key) }
        workspaceRunConsoleStateByProjectPath = workspaceRunConsoleStateByProjectPath.filter { openWorkspaceProjectPaths.contains($0.key) }
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

    public func enterWorkspaceAlignmentGroup(_ id: String) throws {
        let rootPath = try ensureWorkspaceAlignmentRootSession(for: id)
        activateWorkspaceProject(rootPath)
        scheduleWorkspaceRestoreAutosave()
    }

    public func openWorkspaceAlignmentMember(_ member: WorkspaceAlignmentMemberProjection) {
        do {
            _ = try ensureWorkspaceAlignmentRootSession(for: member.groupID)
            switch member.openTarget {
            case let .project(projectPath):
                selectedProjectPath = projectPath
                if let index = workspaceSessionIndex(for: projectPath),
                   openWorkspaceSessions[index].workspaceAlignmentGroupID != nil {
                    openWorkspaceSessions[index].workspaceAlignmentGroupID = member.groupID
                }
                openWorkspaceSessionIfNeeded(
                    for: projectPath,
                    rootProjectPath: projectPath,
                    workspaceAlignmentGroupID: member.groupID
                )
                activeWorkspaceProjectPath = projectPath
                isDetailPanelPresented = false
                scheduleSelectedProjectDocumentRefresh()
                scheduleWorkspaceRestoreAutosave()
            case let .worktree(rootProjectPath, worktreePath):
                openWorkspaceWorktree(
                    worktreePath,
                    from: rootProjectPath,
                    workspaceAlignmentGroupID: member.groupID
                )
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func openWorkspaceWorktree(
        _ worktreePath: String,
        from rootProjectPath: String,
        workspaceAlignmentGroupID: String? = nil
    ) {
        let normalizedRootProjectPath = normalizePathForCompare(rootProjectPath)
        let normalizedWorktreePath = normalizePathForCompare(worktreePath)

        if let pending = pendingWorkspaceWorktreeCreatesByPath[normalizedWorktreePath],
           normalizePathForCompare(pending.rootProjectPath) == normalizedRootProjectPath {
            if pending.status == .creating {
                errorMessage = "该 worktree 正在创建中，请稍候"
            } else {
                errorMessage = pending.error ?? "该 worktree 创建失败，请先重试"
            }
            return
        }

        guard let rootProject = snapshot.projects.first(where: {
            normalizePathForCompare($0.path) == normalizedRootProjectPath
        }) else {
            errorMessage = NativeWorktreeError.invalidProject("项目不存在或已移除").localizedDescription
            return
        }

        guard let worktree = rootProject.worktrees.first(where: {
            normalizePathForCompare($0.path) == normalizedWorktreePath
        }) else {
            errorMessage = NativeWorktreeError.invalidPath("worktree 不存在或已移除").localizedDescription
            return
        }
        if workspaceAlignmentGroupID == nil {
            promoteWorkspaceSessionIfNeeded(for: worktree.path, rootProjectPath: rootProject.path)
        } else if let index = workspaceSessionIndex(for: worktree.path),
                  openWorkspaceSessions[index].workspaceAlignmentGroupID != nil {
            openWorkspaceSessions[index].workspaceAlignmentGroupID = workspaceAlignmentGroupID
            openWorkspaceSessions[index].rootProjectPath = rootProject.path
        }
        selectedProjectPath = worktree.path
        openWorkspaceSessionIfNeeded(
            for: worktree.path,
            rootProjectPath: rootProject.path,
            workspaceAlignmentGroupID: workspaceAlignmentGroupID
        )
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
    public func openActiveWorkspaceDiffTab(
        source: WorkspaceDiffSource,
        preferredTitle: String,
        preferredViewerMode: WorkspaceDiffViewerMode = .sideBySide
    ) -> WorkspaceDiffTabState? {
        guard let activeWorkspaceProjectPath else {
            return nil
        }
        let chain = requestChainForActiveDiffSource(
            source: source,
            preferredTitle: preferredTitle,
            preferredViewerMode: preferredViewerMode
        )
        return openWorkspaceDiffSession(
            projectPath: activeWorkspaceProjectPath,
            chain: chain,
            identityOverride: nil,
            originContext: WorkspaceDiffOriginContext(
                presentedTabSelection: workspaceSelectedPresentedTab(for: activeWorkspaceProjectPath),
                focusedArea: workspaceFocusedArea
            ),
            focusTab: true,
            createIfNeeded: true
        )
    }

    @discardableResult
    public func openActiveWorkspaceDiffSession(
        chain: WorkspaceDiffRequestChain,
        identityOverride: String? = nil
    ) -> WorkspaceDiffTabState? {
        guard let activeWorkspaceProjectPath else {
            return nil
        }
        return openWorkspaceDiffSession(
            projectPath: activeWorkspaceProjectPath,
            chain: chain,
            identityOverride: identityOverride,
            originContext: WorkspaceDiffOriginContext(
                presentedTabSelection: workspaceSelectedPresentedTab(for: activeWorkspaceProjectPath),
                focusedArea: workspaceFocusedArea
            ),
            focusTab: true,
            createIfNeeded: true
        )
    }

    @discardableResult
    public func openActiveWorkspaceCommitDiffPreview(
        repositoryPath: String,
        executionPath: String,
        filePath: String,
        group: WorkspaceCommitChangeGroup?,
        status: WorkspaceCommitChangeStatus?,
        oldPath: String?,
        allChanges: [WorkspaceCommitChange]? = nil,
        preferredTitle: String,
        preferredViewerMode: WorkspaceDiffViewerMode = .sideBySide
    ) -> WorkspaceDiffTabState? {
        guard let request = activeWorkspaceCommitDiffPreviewRequest(
            repositoryPath: repositoryPath,
            executionPath: executionPath,
            filePath: filePath,
            group: group,
            status: status,
            oldPath: oldPath,
            allChanges: allChanges,
            preferredTitle: preferredTitle,
            preferredViewerMode: preferredViewerMode
        ) else {
            return nil
        }
        return syncWorkspaceDiffTab(request, focusTab: true, createIfNeeded: true)
    }

    public func syncActiveWorkspaceCommitDiffPreviewIfNeeded(
        repositoryPath: String,
        executionPath: String,
        filePath: String,
        group: WorkspaceCommitChangeGroup?,
        status: WorkspaceCommitChangeStatus?,
        oldPath: String?,
        allChanges: [WorkspaceCommitChange]? = nil,
        preferredTitle: String,
        preferredViewerMode: WorkspaceDiffViewerMode = .sideBySide
    ) {
        guard let request = activeWorkspaceCommitDiffPreviewRequest(
            repositoryPath: repositoryPath,
            executionPath: executionPath,
            filePath: filePath,
            group: group,
            status: status,
            oldPath: oldPath,
            allChanges: allChanges,
            preferredTitle: preferredTitle,
            preferredViewerMode: preferredViewerMode
        ) else {
            return
        }
        _ = syncWorkspaceDiffTab(request, focusTab: false, createIfNeeded: false)
    }

    @discardableResult
    public func openWorkspaceDiffTab(_ request: WorkspaceDiffOpenRequest) -> WorkspaceDiffTabState {
        syncWorkspaceDiffTab(request, focusTab: true, createIfNeeded: true)
            ?? WorkspaceDiffTabState(
                id: "workspace-diff:\(UUID().uuidString.lowercased())",
                identity: request.identity,
                title: request.preferredTitle,
                source: request.source,
                viewerMode: request.preferredViewerMode,
                requestChain: request.requestChain,
                originContext: request.originContext
            )
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
            workspaceFocusedArea = .terminal
        case let .diff(tabID):
            guard workspaceDiffTabsByProjectPath[resolvedProjectPath]?.contains(where: { $0.id == tabID }) == true else {
                return
            }
            workspaceSelectedPresentedTabByProjectPath[resolvedProjectPath] = .diff(tabID)
            workspaceFocusedArea = .diffTab(tabID)
        }
    }

    public func closeWorkspaceDiffTab(_ tabID: String, in projectPath: String? = nil) {
        guard let resolvedProjectPath = projectPath ?? activeWorkspaceProjectPath,
              var tabs = workspaceDiffTabsByProjectPath[resolvedProjectPath],
              let removedIndex = tabs.firstIndex(where: { $0.id == tabID })
        else {
            return
        }

        let removedTab = tabs[removedIndex]
        let isClosingSelectedTab = resolvedWorkspacePresentedTabSelection(for: resolvedProjectPath) == .diff(tabID)
        tabs.remove(at: removedIndex)
        workspaceDiffTabsByProjectPath[resolvedProjectPath] = tabs
        workspaceDiffTabViewModels[tabID] = nil

        guard isClosingSelectedTab else {
            return
        }

        if restoreOriginContext(for: removedTab, in: resolvedProjectPath, remainingDiffTabs: tabs) {
            return
        }

        if tabs.indices.contains(removedIndex) {
            workspaceSelectedPresentedTabByProjectPath[resolvedProjectPath] = .diff(tabs[removedIndex].id)
            workspaceFocusedArea = .diffTab(tabs[removedIndex].id)
        } else if let previous = tabs.last {
            workspaceSelectedPresentedTabByProjectPath[resolvedProjectPath] = .diff(previous.id)
            workspaceFocusedArea = .diffTab(previous.id)
        } else if let terminalTabID = workspaceController(for: resolvedProjectPath)?.selectedTabId
            ?? workspaceController(for: resolvedProjectPath)?.selectedTab?.id
        {
            workspaceSelectedPresentedTabByProjectPath[resolvedProjectPath] = .terminal(terminalTabID)
            workspaceFocusedArea = .terminal
        } else {
            workspaceSelectedPresentedTabByProjectPath[resolvedProjectPath] = nil
            workspaceFocusedArea = .terminal
        }
    }

    public func syncActiveWorkspaceToolWindowContext() {
        var neededKinds = Set<WorkspaceToolWindowKind>()
        if workspaceSideToolWindowState.isVisible,
           let kind = workspaceSideToolWindowState.activeKind {
            neededKinds.insert(kind)
        }
        if workspaceBottomToolWindowState.isVisible,
           let kind = workspaceBottomToolWindowState.activeKind {
            neededKinds.insert(kind)
        }
        for kind in neededKinds {
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
        let worktreeService = self.worktreeService
        return try await Task.detached(priority: .userInitiated) {
            try worktreeService.listBranches(at: rootProjectPath)
        }.value
    }

    public func listProjectWorktrees(for rootProjectPath: String) async throws -> [NativeGitWorktree] {
        let worktreeService = self.worktreeService
        return try await Task.detached(priority: .userInitiated) {
            try worktreeService.listWorktrees(at: rootProjectPath)
        }.value
    }

    public func currentWorkspaceBranch(for rootProjectPath: String) async throws -> String {
        let worktreeService = self.worktreeService
        return try await Task.detached(priority: .userInitiated) {
            try worktreeService.currentBranch(at: rootProjectPath)
        }.value
    }

    public func refreshProjectWorktrees(_ rootProjectPath: String) async throws {
        let normalizedRootProjectPath = normalizePathForCompare(rootProjectPath)
        guard snapshot.projects.contains(where: { normalizePathForCompare($0.path) == normalizedRootProjectPath }) else {
            throw NativeWorktreeError.invalidProject("项目不存在或已移除")
        }
        let resolvedWorktrees = try await listProjectWorktrees(for: normalizedRootProjectPath)
        let resolvedCurrentBranch = try? await currentWorkspaceBranch(for: normalizedRootProjectPath)
        try syncProjectRepositoryState(
            rootProjectPath: normalizedRootProjectPath,
            gitWorktrees: resolvedWorktrees,
            currentBranch: resolvedCurrentBranch
        )
    }

    public func createWorkspaceAlignmentGroup(
        name: String,
        members: [WorkspaceAlignmentMemberDefinition],
        memberAliases: [String: String] = [:],
        applyRules: Bool
    ) async throws {
        let now = swiftDateFromDate(Date())
        let groupID = UUID().uuidString
        let sanitizedMembers = normalizeWorkspaceAlignmentMemberDefinitions(members)
        let firstMember = sanitizedMembers.first
        let definition = WorkspaceAlignmentGroupDefinition(
            id: groupID,
            name: name,
            targetBranch: firstMember?.targetBranch ?? "",
            baseBranchMode: firstMember?.baseBranchMode ?? .autoDetect,
            specifiedBaseBranch: firstMember?.specifiedBaseBranch,
            projectPaths: sanitizedMembers.map(\.projectPath),
            members: sanitizedMembers,
            rootDirectoryName: makeWorkspaceAlignmentRootDirectoryName(name: name, id: groupID),
            memberAliases: memberAliases,
            createdAt: now,
            updatedAt: now
        )
        var sanitizedDefinition = definition.sanitized()
        sanitizedDefinition.rootDirectoryName = sanitizedDefinition.rootDirectoryName
            ?? makeWorkspaceAlignmentRootDirectoryName(name: sanitizedDefinition.name, id: sanitizedDefinition.id)
        sanitizedDefinition.memberAliases = buildWorkspaceAlignmentMemberAliases(
            for: sanitizedDefinition.projectPaths,
            existing: sanitizedDefinition.memberAliases
        )
        try validateWorkspaceAlignmentGroup(sanitizedDefinition, replacing: nil)
        var groups = snapshot.appState.workspaceAlignmentGroups
        groups.append(sanitizedDefinition)
        try persistWorkspaceAlignmentGroups(groups)
        try await recheckWorkspaceAlignmentGroup(sanitizedDefinition.id)
        if applyRules, !sanitizedDefinition.projectPaths.isEmpty {
            try await applyWorkspaceAlignmentGroup(sanitizedDefinition.id)
        } else {
            _ = try syncWorkspaceAlignmentRootIfPossible(sanitizedDefinition.id)
        }
    }

    public func updateWorkspaceAlignmentGroup(
        id: String,
        name: String,
        members: [WorkspaceAlignmentMemberDefinition],
        memberAliases: [String: String] = [:],
        applyRules: Bool
    ) async throws {
        guard let index = snapshot.appState.workspaceAlignmentGroups.firstIndex(where: { $0.id == id }) else {
            throw NativeWorktreeError.invalidProject("工作区不存在")
        }
        var groups = snapshot.appState.workspaceAlignmentGroups
        var next = groups[index]
        let preservedRootDirectoryName = next.rootDirectoryName ?? makeWorkspaceAlignmentRootDirectoryName(name: next.name, id: next.id)
        let sanitizedMembers = normalizeWorkspaceAlignmentMemberDefinitions(members)
        let firstMember = sanitizedMembers.first
        next.name = name
        next.targetBranch = firstMember?.targetBranch ?? ""
        next.baseBranchMode = firstMember?.baseBranchMode ?? .autoDetect
        next.specifiedBaseBranch = firstMember?.specifiedBaseBranch
        next.projectPaths = sanitizedMembers.map(\.projectPath)
        next.members = sanitizedMembers
        next.updatedAt = swiftDateFromDate(Date())
        next = next.sanitized()
        next.rootDirectoryName = preservedRootDirectoryName
        next.memberAliases = buildWorkspaceAlignmentMemberAliases(for: next.projectPaths, existing: memberAliases)
        try validateWorkspaceAlignmentGroup(next, replacing: id)
        groups[index] = next
        try persistWorkspaceAlignmentGroups(groups)
        clearWorkspaceAlignmentStatuses(for: id)
        try await recheckWorkspaceAlignmentGroup(id)
        if applyRules, !next.projectPaths.isEmpty {
            try await applyWorkspaceAlignmentGroup(id)
        } else {
            _ = try syncWorkspaceAlignmentRootIfPossible(id)
        }
    }

    public func deleteWorkspaceAlignmentGroup(_ id: String) throws {
        let deletedDefinition = snapshot.appState.workspaceAlignmentGroups.first(where: { $0.id == id })
        let groups = snapshot.appState.workspaceAlignmentGroups.filter { $0.id != id }
        try persistWorkspaceAlignmentGroups(groups)
        clearWorkspaceAlignmentStatuses(for: id)
        if let rootSession = openWorkspaceSessions.first(where: { $0.workspaceRootContext?.workspaceID == id }) {
            closeWorkspaceProject(rootSession.projectPath)
        }
        if let deletedDefinition {
            try? workspaceAlignmentRootStore.removeRoot(for: deletedDefinition)
        }
    }

    public func addWorkspaceAlignmentMembers(
        _ members: [WorkspaceAlignmentMemberDefinition],
        memberAliases: [String: String] = [:],
        toWorkspaceAlignmentGroup id: String,
        applyRules: Bool
    ) async throws {
        guard let index = snapshot.appState.workspaceAlignmentGroups.firstIndex(where: { $0.id == id }) else {
            throw NativeWorktreeError.invalidProject("工作区不存在")
        }
        var groups = snapshot.appState.workspaceAlignmentGroups
        let existingMembers = groups[index].effectiveMembers
        let mergedMembers = normalizeWorkspaceAlignmentMemberDefinitions(existingMembers + members)
        groups[index].members = mergedMembers
        groups[index].projectPaths = mergedMembers.map(\.projectPath)
        if groups[index].targetBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let firstTargetBranch = mergedMembers.first?.targetBranch {
            groups[index].targetBranch = firstTargetBranch
        }
        groups[index].updatedAt = swiftDateFromDate(Date())
        groups[index] = groups[index].sanitized()
        groups[index].memberAliases = buildWorkspaceAlignmentMemberAliases(
            for: groups[index].projectPaths,
            existing: groups[index].memberAliases.merging(memberAliases, uniquingKeysWith: { _, new in new })
        )
        try persistWorkspaceAlignmentGroups(groups)
        try await recheckWorkspaceAlignmentGroup(id)
        if applyRules {
            for member in members {
                try await applyWorkspaceAlignmentRule(for: member.projectPath, in: groups[index])
            }
        } else {
            _ = try syncWorkspaceAlignmentRootIfPossible(id)
        }
    }

    public func removeProject(
        _ projectPath: String,
        fromWorkspaceAlignmentGroup id: String
    ) throws {
        guard let index = snapshot.appState.workspaceAlignmentGroups.firstIndex(where: { $0.id == id }) else {
            throw NativeWorktreeError.invalidProject("工作区不存在")
        }
        var groups = snapshot.appState.workspaceAlignmentGroups
        groups[index].members = groups[index].effectiveMembers.filter {
            normalizePathForCompare($0.projectPath) != normalizePathForCompare(projectPath)
        }
        groups[index].projectPaths = groups[index].projectPaths.filter {
            normalizePathForCompare($0) != normalizePathForCompare(projectPath)
        }
        groups[index].updatedAt = swiftDateFromDate(Date())
        groups[index] = groups[index].sanitized()
        groups[index].memberAliases.removeValue(forKey: normalizePathForCompare(projectPath))
        try persistWorkspaceAlignmentGroups(groups)
        workspaceAlignmentStatusByKey.removeValue(forKey: workspaceAlignmentStatusKey(groupID: id, projectPath: projectPath))
        _ = try syncWorkspaceAlignmentRootIfPossible(id)
    }

    public func recheckWorkspaceAlignmentGroup(_ id: String) async throws {
        guard let definition = snapshot.appState.workspaceAlignmentGroups.first(where: { $0.id == id }) else {
            throw NativeWorktreeError.invalidProject("工作区不存在")
        }
        for member in definition.effectiveMembers {
            updateWorkspaceAlignmentStatus(.checking, groupID: id, projectPath: member.projectPath)
            do {
                try await refreshWorkspaceAlignmentProjectStatus(member, in: definition)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                updateWorkspaceAlignmentStatus(.checkFailed(message), groupID: id, projectPath: member.projectPath)
            }
        }
        _ = try syncWorkspaceAlignmentRootIfPossible(id)
    }

    public func applyWorkspaceAlignmentGroup(_ id: String) async throws {
        guard let definition = snapshot.appState.workspaceAlignmentGroups.first(where: { $0.id == id }) else {
            throw NativeWorktreeError.invalidProject("工作区不存在")
        }
        for member in definition.effectiveMembers {
            try await applyWorkspaceAlignmentRule(for: member.projectPath, in: definition)
        }
        _ = try syncWorkspaceAlignmentRootIfPossible(id)
    }

    public func applyWorkspaceAlignmentRule(
        for projectPath: String,
        inWorkspaceAlignmentGroup id: String
    ) async throws {
        guard let definition = snapshot.appState.workspaceAlignmentGroups.first(where: { $0.id == id }) else {
            throw NativeWorktreeError.invalidProject("工作区不存在")
        }
        try await applyWorkspaceAlignmentRule(for: projectPath, in: definition)
        _ = try syncWorkspaceAlignmentRootIfPossible(id)
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
        try beginCreateWorkspaceWorktree(context)
        try await runCreateWorkspaceWorktree(context, autoOpen: autoOpen)
    }

    public func validateStartCreateWorkspaceWorktree(
        from rootProjectPath: String,
        branch: String,
        createBranch: Bool,
        baseBranch: String?,
        targetPath: String? = nil
    ) throws {
        _ = try prepareCreateWorkspaceWorktree(
            from: rootProjectPath,
            branch: branch,
            createBranch: createBranch,
            baseBranch: baseBranch,
            targetPath: targetPath
        )
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
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            var didBeginCreate = false
            do {
                await Task.yield()
                try self.beginCreateWorkspaceWorktree(context)
                didBeginCreate = true
                try await self.runCreateWorkspaceWorktree(context, autoOpen: autoOpen)
            } catch {
                guard !didBeginCreate else {
                    // `runCreateWorkspaceWorktree` 已把失败状态、错误文案和交互锁清理回主状态，这里无需重复处理。
                    return
                }
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
        guard snapshot.projects.contains(where: { $0.path == rootProjectPath }) else {
            throw NativeWorktreeError.invalidProject("项目不存在或已移除")
        }

        let request = NativeWorktreeCreateRequest(
            sourceProjectPath: rootProjectPath,
            branch: branch,
            createBranch: createBranch,
            baseBranch: baseBranch,
            targetPath: targetPath
        )
        let previewPath = try worktreeService.preflightCreateWorktree(request)

        return WorktreeCreateContext(
            request: request,
            rootProjectPath: rootProjectPath,
            previewPath: previewPath
        )
    }

    private func beginCreateWorkspaceWorktree(_ context: WorktreeCreateContext) throws {
        guard worktreeInteractionState == nil else {
            throw NativeWorktreeError.operationInProgress("已有 worktree 创建任务正在进行中，请稍候")
        }
        guard snapshot.projects.contains(where: { $0.path == context.rootProjectPath }) else {
            throw NativeWorktreeError.invalidProject("项目不存在或已移除")
        }

        let now = swiftDateFromDate(Date())
        let jobID = UUID().uuidString
        let normalizedPreviewPath = normalizePathForCompare(context.previewPath)
        let trimmedBranch = context.request.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBaseBranch = context.request.createBranch
            ? context.request.baseBranch?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        pendingWorkspaceWorktreeCreatesByPath[normalizedPreviewPath] = PendingWorkspaceWorktreeCreateState(
            rootProjectPath: context.rootProjectPath,
            branch: trimmedBranch,
            baseBranch: trimmedBaseBranch,
            worktreePath: context.previewPath,
            createBranch: context.request.createBranch,
            jobID: jobID,
            createdAt: now,
            status: .creating,
            step: .pending,
            message: "已创建任务，准备开始…",
            error: nil
        )
        worktreeInteractionState = WorktreeInteractionState(
            rootProjectPath: context.rootProjectPath,
            branch: trimmedBranch,
            baseBranch: trimmedBaseBranch,
            worktreePath: context.previewPath,
            step: .pending,
            message: "准备创建 worktree..."
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
            try await refreshProjectWorktrees(context.rootProjectPath)
            let bootstrapResult = await prepareWorkspaceWorktreeEnvironment(context)

            finishCreateWorkspaceWorktree(
                result,
                rootProjectPath: context.rootProjectPath,
                bootstrapResult: bootstrapResult,
                autoOpen: autoOpen
            )
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            markWorktreeAsFailed(
                worktreePath: context.previewPath,
                rootProjectPath: context.rootProjectPath,
                errorMessage: message
            )
            let cleanupWarning = cleanupFailedWorkspaceWorktreeCreate(context)
            try? await refreshProjectWorktrees(context.rootProjectPath)
            worktreeInteractionState = nil
            if let cleanupWarning, !cleanupWarning.isEmpty {
                errorMessage = "\(message)\n\n清理残留状态时出现告警：\n\(cleanupWarning)"
            } else {
                errorMessage = message
            }
            throw error
        }
    }

    public func retryWorkspaceWorktree(_ worktreePath: String, from rootProjectPath: String) async throws {
        let normalizedWorktreePath = normalizePathForCompare(worktreePath)
        if let pending = pendingWorkspaceWorktreeCreatesByPath[normalizedWorktreePath] {
            guard pending.status != .creating else {
                throw NativeWorktreeError.operationInProgress("该 worktree 正在创建中，请稍候")
            }
            pendingWorkspaceWorktreeCreatesByPath.removeValue(forKey: normalizedWorktreePath)
            try await createWorkspaceWorktree(
                from: rootProjectPath,
                branch: pending.branch,
                createBranch: pending.createBranch,
                baseBranch: pending.baseBranch,
                autoOpen: false,
                targetPath: pending.worktreePath
            )
            return
        }

        guard let worktree = snapshot.projects.first(where: { $0.path == rootProjectPath })?.worktrees.first(where: {
            normalizePathForCompare($0.path) == normalizedWorktreePath
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
        let normalizedWorktreePath = normalizePathForCompare(worktreePath)
        if let pending = pendingWorkspaceWorktreeCreatesByPath[normalizedWorktreePath] {
            guard pending.status != .creating else {
                throw NativeWorktreeError.operationInProgress("该 worktree 正在创建中，无法删除")
            }
            pendingWorkspaceWorktreeCreatesByPath.removeValue(forKey: normalizedWorktreePath)
            let cleanupWarning = cleanupFailedWorkspaceWorktreeCreate(
                WorktreeCreateContext(
                    request: NativeWorktreeCreateRequest(
                        sourceProjectPath: pending.rootProjectPath,
                        branch: pending.branch,
                        createBranch: pending.createBranch,
                        baseBranch: pending.baseBranch,
                        targetPath: pending.worktreePath
                    ),
                    rootProjectPath: pending.rootProjectPath,
                    previewPath: pending.worktreePath
                )
            )
            try? await refreshProjectWorktrees(rootProjectPath)
            if let cleanupWarning, !cleanupWarning.isEmpty {
                errorMessage = cleanupWarning
            }
            return
        }

        guard let projectIndex = snapshot.projects.firstIndex(where: { $0.path == rootProjectPath }) else {
            throw NativeWorktreeError.invalidProject("项目不存在或已移除")
        }
        guard let worktree = snapshot.projects[projectIndex].worktrees.first(where: {
            normalizePathForCompare($0.path) == normalizedWorktreePath
        }) else {
            throw NativeWorktreeError.invalidPath("worktree 不存在或已移除")
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

    public func workspaceWorktreeDeletePresentation(
        for worktreePath: String,
        from rootProjectPath: String
    ) -> WorkspaceWorktreeDeletePresentation? {
        let normalizedWorktreePath = normalizePathForCompare(worktreePath)
        if let pending = pendingWorkspaceWorktreeCreatesByPath[normalizedWorktreePath],
           normalizePathForCompare(pending.rootProjectPath) == normalizePathForCompare(rootProjectPath),
           pending.status != .creating {
            return WorkspaceWorktreeDeletePresentation(
                rootProjectPath: rootProjectPath,
                worktreePath: worktreePath,
                title: "清除失败记录",
                actionTitle: "清除记录",
                message: "将清除这条失败的 worktree 创建记录，并尝试删除残留目录、分支与 Git metadata。不会删除任何已成功创建的 worktree。",
                kind: .clearFailedCreation
            )
        }

        guard let project = snapshot.projects.first(where: {
            normalizePathForCompare($0.path) == normalizePathForCompare(rootProjectPath)
        }) else {
            return nil
        }
        guard let worktree = project.worktrees.first(where: {
            normalizePathForCompare($0.path) == normalizedWorktreePath
        }) else {
            return nil
        }
        return WorkspaceWorktreeDeletePresentation(
            rootProjectPath: rootProjectPath,
            worktreePath: worktreePath,
            title: "删除 worktree",
            actionTitle: "删除",
            message: (worktree.baseBranch?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? "将删除 \(worktreePath)，并丢弃其中未提交修改与未跟踪文件。该 worktree 的本地分支也会一并删除；若分支包含未合并提交，DevHaven 会强制删除它。"
                : "将删除 \(worktreePath)，并丢弃其中未提交修改与未跟踪文件。",
            kind: .deletePersistedWorktree
        )
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
        let mergedProjects = mergeProjectsPreservingOpenedChildWorktrees(
            rebuiltProjects,
            existingProjects: existingProjects
        )
        if mergedProjects != rebuiltProjects {
            try store.updateProjects(mergedProjects)
        }
        applyProjects(mergedProjects)
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
            let notesSummary = projectNotesSummary(from: value)
            let document = ProjectDocumentSnapshot(
                notes: value,
                todoItems: todoItems,
                readmeFallback: readmeFallback
            )
            projectDocumentCache[project.path] = document
            try persistProjectNotesSummary(notesSummary, for: project.path)
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

    public func revealSettings(section: SettingsNavigationSection = .general) {
        requestedSettingsSection = section
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
        requestedSettingsSection = nil
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
        let rootProjectPaths = Set(snapshot.projects.map { normalizePathForCompare($0.path) })
        openWorkspaceSessions.removeAll { session in
            if session.isQuickTerminal { return false }
            let normalizedRootProjectPath = normalizePathForCompare(session.rootProjectPath)
            guard rootProjectPaths.contains(normalizedRootProjectPath) else {
                return true
            }
            if normalizePathForCompare(session.projectPath) == normalizedRootProjectPath {
                return false
            }
            if resolveDisplayProject(for: session.projectPath, rootProjectPath: session.rootProjectPath) != nil {
                return false
            }
            return !shouldPreserveOpenedChildWorktreeSessionDuringReload(session, rootProjectPaths: rootProjectPaths)
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

    private func openedChildWorktrees(
        for rootProjectPath: String,
        in projects: [Project]? = nil
    ) -> [ProjectWorktree] {
        let sourceProjects = projects ?? snapshot.projects
        let normalizedRootProjectPath = normalizePathForCompare(rootProjectPath)
        guard let rootProject = sourceProjects.first(where: {
            normalizePathForCompare($0.path) == normalizedRootProjectPath
        }) else {
            return []
        }

        let openedChildPaths = Set(
            openWorkspaceSessions.compactMap { session -> String? in
                guard isWorkspaceSessionOwnedByProjectPool(session, rootProjectPath: rootProjectPath),
                      normalizePathForCompare(session.projectPath) != normalizedRootProjectPath
                else {
                    return nil
                }
                return normalizePathForCompare(session.projectPath)
            }
        )
        guard !openedChildPaths.isEmpty else {
            return []
        }

        return rootProject.worktrees.filter { worktree in
            openedChildPaths.contains(normalizePathForCompare(worktree.path))
        }
    }

    private func mergeProjectsPreservingOpenedChildWorktrees(
        _ rebuiltProjects: [Project],
        existingProjects: [Project]
    ) -> [Project] {
        guard !rebuiltProjects.isEmpty else {
            return rebuiltProjects
        }

        return rebuiltProjects.map { project in
            let preservedOpenedWorktrees = openedChildWorktrees(
                for: project.path,
                in: existingProjects
            )
            guard !preservedOpenedWorktrees.isEmpty else {
                return project
            }

            var mergedProject = project
            for worktree in preservedOpenedWorktrees where !mergedProject.worktrees.contains(where: {
                normalizePathForCompare($0.path) == normalizePathForCompare(worktree.path)
            }) {
                mergedProject.worktrees.append(worktree)
            }
            mergedProject.worktrees.sort { $0.path < $1.path }
            return mergedProject
        }
    }

    private func shouldPreserveOpenedChildWorktreeSessionDuringReload(
        _ session: OpenWorkspaceSessionState,
        rootProjectPaths: Set<String>
    ) -> Bool {
        guard !session.isQuickTerminal,
              session.workspaceAlignmentGroupID == nil
        else {
            return false
        }
        let normalizedRootProjectPath = normalizePathForCompare(session.rootProjectPath)
        let normalizedProjectPath = normalizePathForCompare(session.projectPath)
        guard normalizedProjectPath != normalizedRootProjectPath else {
            return false
        }
        return rootProjectPaths.contains(normalizedRootProjectPath)
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

    private func scheduleProjectNotesSummaryBackfillIfNeeded() {
        projectNotesSummaryBackfillTask?.cancel()
        projectNotesSummaryBackfillTask = nil

        let missingPaths = snapshot.projects
            .filter { !$0.hasPersistedNotesSummary }
            .map(\.path)
        guard !missingPaths.isEmpty else {
            return
        }

        let backgroundTask = Task.detached(priority: .utility) {
            missingPaths.map { (path: $0, notesSummary: loadProjectNotesSummary(at: $0)) }
        }

        projectNotesSummaryBackfillTask = Task { @MainActor [weak self] in
            let resolvedSummaries = await withTaskCancellationHandler(operation: {
                await backgroundTask.value
            }, onCancel: {
                backgroundTask.cancel()
            })
            guard !Task.isCancelled, let self else {
                return
            }

            self.projectNotesSummaryBackfillTask = nil
            try? self.applyBackfilledProjectNotesSummaries(resolvedSummaries)
        }
    }

    private func applyBackfilledProjectNotesSummaries(
        _ resolvedSummaries: [(path: String, notesSummary: String?)]
    ) throws {
        guard !resolvedSummaries.isEmpty else {
            return
        }

        let summaryByPath = Dictionary(uniqueKeysWithValues: resolvedSummaries.map { ($0.path, $0.notesSummary) })
        let normalizedSummaryPaths = Set(summaryByPath.keys.map(normalizePathForCompare))
        var nextProjects = snapshot.projects
        var didMutate = false

        for index in nextProjects.indices {
            guard !nextProjects[index].hasPersistedNotesSummary else {
                continue
            }
            let projectPath = nextProjects[index].path
            guard normalizedSummaryPaths.contains(normalizePathForCompare(projectPath)) else {
                continue
            }
            nextProjects[index].notesSummary = summaryByPath[projectPath] ?? nil
            nextProjects[index].hasPersistedNotesSummary = true
            didMutate = true
        }

        guard didMutate else {
            return
        }
        try store.updateProjectsNotesSummary(summaryByPath)
        applyProjects(nextProjects)
    }

    private func persistProjectNotesSummary(_ notesSummary: String?, for projectPath: String) throws {
        let normalizedPath = normalizePathForCompare(projectPath)
        guard !normalizedPath.isEmpty else {
            return
        }
        guard let projectIndex = snapshot.projects.firstIndex(where: {
            normalizePathForCompare($0.path) == normalizedPath
        }) else {
            return
        }

        var nextProjects = snapshot.projects
        guard nextProjects[projectIndex].notesSummary != notesSummary || !nextProjects[projectIndex].hasPersistedNotesSummary else {
            return
        }

        nextProjects[projectIndex].notesSummary = notesSummary
        nextProjects[projectIndex].hasPersistedNotesSummary = true
        try store.updateProjectsNotesSummary([nextProjects[projectIndex].path: notesSummary])
        applyProjects(nextProjects)
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

            let normalizedProjectPath = normalizePathForCompare(sessionSnapshot.projectPath)
            let normalizedRootProjectPath = normalizePathForCompare(sessionSnapshot.rootProjectPath)
            let normalizedSessionSnapshot = ProjectWorkspaceRestoreSnapshot(
                projectPath: normalizedProjectPath,
                rootProjectPath: normalizedRootProjectPath,
                isQuickTerminal: sessionSnapshot.isQuickTerminal,
                workspaceRootContext: sessionSnapshot.workspaceRootContext,
                workspaceAlignmentGroupID: sessionSnapshot.workspaceAlignmentGroupID,
                workspaceId: sessionSnapshot.workspaceId,
                selectedTabId: sessionSnapshot.selectedTabId,
                nextTabNumber: sessionSnapshot.nextTabNumber,
                nextPaneNumber: sessionSnapshot.nextPaneNumber,
                tabs: sessionSnapshot.tabs
            )

            let controller = GhosttyWorkspaceController(
                projectPath: normalizedProjectPath,
                workspaceId: sessionSnapshot.workspaceId
            )
            controller.restore(from: normalizedSessionSnapshot)
            registerWorkspaceRestoreObserver(for: controller)

            if normalizedProjectPath == normalizedRootProjectPath, !sessionSnapshot.isQuickTerminal {
                refreshCurrentBranch(for: normalizedProjectPath)
            }

            let restoredWorkspaceRootContext = sessionSnapshot.workspaceRootContext.flatMap { context in
                snapshot.appState.workspaceAlignmentGroups
                    .first(where: { $0.id == context.workspaceID })
                    .map { WorkspaceRootSessionContext(workspaceID: context.workspaceID, workspaceName: $0.name) }
                    ?? context
            }

            return OpenWorkspaceSessionState(
                projectPath: normalizedProjectPath,
                rootProjectPath: normalizedRootProjectPath,
                controller: controller,
                isQuickTerminal: sessionSnapshot.isQuickTerminal,
                workspaceRootContext: restoredWorkspaceRootContext,
                workspaceAlignmentGroupID: sessionSnapshot.workspaceAlignmentGroupID
            )
        }

        guard !restoredSessions.isEmpty else {
            return
        }

        openWorkspaceSessions = restoredSessions
        syncAttentionStateWithOpenSessions()

        let restoredActiveProjectPath = restoredSnapshot.activeProjectPath.flatMap { candidate in
            canonicalWorkspaceSessionPath(for: candidate, in: restoredSessions)
        } ?? restoredSessions.last?.projectPath

        activeWorkspaceProjectPath = restoredActiveProjectPath
        selectedProjectPath = restoredSnapshot.selectedProjectPath.flatMap { candidate in
            if let workspaceSessionPath = canonicalWorkspaceSessionPath(for: candidate, in: restoredSessions) {
                return workspaceSessionPath
            }
            return resolveDisplayProject(for: candidate)?.path
        } ?? restoredActiveProjectPath ?? selectedProjectPath

        if let restoredActiveProjectPath,
           let paneID = workspaceController(for: restoredActiveProjectPath)?.selectedPane?.id {
            markWorkspaceNotificationsRead(projectPath: restoredActiveProjectPath, paneID: paneID)
        }
        isDetailPanelPresented = false
    }

    private func canRestoreWorkspaceSession(_ sessionSnapshot: ProjectWorkspaceRestoreSnapshot) -> Bool {
        if let workspaceAlignmentGroupID = sessionSnapshot.workspaceAlignmentGroupID {
            guard snapshot.appState.workspaceAlignmentGroups.contains(where: { $0.id == workspaceAlignmentGroupID }) else {
                return false
            }
            guard (try? syncWorkspaceAlignmentRootIfPossible(workspaceAlignmentGroupID)) != nil else {
                return false
            }
        }
        if let workspaceRootContext = sessionSnapshot.workspaceRootContext {
            guard snapshot.appState.workspaceAlignmentGroups.contains(where: { $0.id == workspaceRootContext.workspaceID }) else {
                return false
            }
            return (try? syncWorkspaceAlignmentRootIfPossible(workspaceRootContext.workspaceID)) != nil
        }
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

    private func openWorkspaceSessionIfNeeded(
        for path: String,
        rootProjectPath: String,
        isQuickTerminal: Bool = false,
        workspaceRootContext: WorkspaceRootSessionContext? = nil,
        workspaceAlignmentGroupID: String? = nil
    ) {
        let normalizedPath = normalizePathForCompare(path)
        let normalizedRootProjectPath = normalizePathForCompare(rootProjectPath)

        guard workspaceSessionIndex(for: normalizedPath) == nil else {
            return
        }
        let controller = GhosttyWorkspaceController(projectPath: normalizedPath)
        registerWorkspaceRestoreObserver(for: controller)
        openWorkspaceSessions.append(
            OpenWorkspaceSessionState(
                projectPath: normalizedPath,
                rootProjectPath: normalizedRootProjectPath,
                controller: controller,
                isQuickTerminal: isQuickTerminal,
                workspaceRootContext: workspaceRootContext,
                workspaceAlignmentGroupID: workspaceAlignmentGroupID
            )
        )
        if normalizedPath == normalizedRootProjectPath, !isQuickTerminal {
            refreshCurrentBranch(for: normalizedPath)
        }
    }

    private func isWorkspaceSessionOwnedByProjectPool(
        _ session: OpenWorkspaceSessionState,
        rootProjectPath: String
    ) -> Bool {
        guard !session.isQuickTerminal,
              session.workspaceAlignmentGroupID == nil
        else {
            return false
        }
        return session.rootProjectPath == normalizePathForCompare(rootProjectPath)
    }

    private func workspaceSessionIndex(for path: String) -> Int? {
        workspaceSessionIndexByNormalizedPath[normalizePathForCompare(path)]
    }

    private func workspaceSession(for path: String?) -> OpenWorkspaceSessionState? {
        guard let normalizedPath = normalizedOptionalPathForCompare(path),
              let index = workspaceSessionIndexByNormalizedPath[normalizedPath],
              openWorkspaceSessions.indices.contains(index)
        else {
            return nil
        }
        return openWorkspaceSessions[index]
    }

    private func canonicalWorkspaceSessionPath(
        for path: String?,
        in sessions: [OpenWorkspaceSessionState]? = nil
    ) -> String? {
        guard let normalizedPath = normalizedOptionalPathForCompare(path) else {
            return nil
        }
        if let sessions {
            return sessions.first(where: { $0.projectPath == normalizedPath })?.projectPath
        }
        guard let index = workspaceSessionIndexByNormalizedPath[normalizedPath],
              openWorkspaceSessions.indices.contains(index)
        else {
            return nil
        }
        return openWorkspaceSessions[index].projectPath
    }

    private func promoteWorkspaceSessionIfNeeded(for path: String, rootProjectPath: String) {
        guard let index = workspaceSessionIndex(for: path) else {
            return
        }
        openWorkspaceSessions[index].rootProjectPath = normalizePathForCompare(rootProjectPath)
        openWorkspaceSessions[index].workspaceAlignmentGroupID = nil
    }

    private func ensureWorkspaceAlignmentRootSession(for id: String) throws -> String {
        guard let group = workspaceAlignmentGroups.first(where: { $0.id == id }) else {
            throw NativeWorktreeError.invalidProject("工作区不存在")
        }
        if let session = openWorkspaceSessions.first(where: {
            $0.isQuickTerminal && $0.workspaceRootContext?.workspaceID == id
        }) {
            return session.projectPath
        }
        let rootURL = try syncWorkspaceAlignmentRoot(for: group)
        openWorkspaceSessionIfNeeded(
            for: rootURL.path,
            rootProjectPath: rootURL.path,
            isQuickTerminal: true,
            workspaceRootContext: WorkspaceRootSessionContext(
                workspaceID: group.id,
                workspaceName: group.definition.name
            )
        )
        return rootURL.path
    }

    private func isQuickTerminalSessionPath(_ path: String) -> Bool {
        workspaceSession(for: path)?.isQuickTerminal ?? false
    }

    private func resolvedWorkspacePresentedTabSelection(
        for projectPath: String,
        controller: GhosttyWorkspaceController? = nil
    ) -> WorkspacePresentedTabSelection? {
        let controller = controller ?? workspaceController(for: projectPath)
        let terminalTabID = controller?.selectedTabId
            ?? controller?.selectedTab?.id
        let diffTabs = workspaceDiffTabsByProjectPath[projectPath] ?? []

        if let stored = workspaceSelectedPresentedTabByProjectPath[projectPath] {
            switch stored {
            case let .terminal(tabID):
                if controller?.tabs.contains(where: { $0.id == tabID }) == true {
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

    private func requestChainForActiveDiffSource(
        source: WorkspaceDiffSource,
        preferredTitle: String,
        preferredViewerMode: WorkspaceDiffViewerMode
    ) -> WorkspaceDiffRequestChain {
        switch source {
        case let .gitLogCommitFile(repositoryPath, commitHash, filePath):
            return gitLogDiffRequestChain(
                repositoryPath: repositoryPath,
                commitHash: commitHash,
                activeFilePath: filePath,
                activePreferredTitle: preferredTitle,
                preferredViewerMode: preferredViewerMode
            )
        case let .workingTreeChange(repositoryPath, executionPath, filePath, group, status, oldPath):
            return commitDiffRequestChain(
                repositoryPath: repositoryPath,
                executionPath: executionPath,
                activeFilePath: filePath,
                activeGroup: group,
                activeStatus: status,
                activeOldPath: oldPath,
                activePreferredTitle: preferredTitle,
                preferredViewerMode: preferredViewerMode,
                changes: nil
            )
        }
    }

    private func commitDiffRequestChain(
        repositoryPath: String,
        executionPath: String,
        activeFilePath: String,
        activeGroup: WorkspaceCommitChangeGroup?,
        activeStatus: WorkspaceCommitChangeStatus?,
        activeOldPath: String?,
        activePreferredTitle: String,
        preferredViewerMode: WorkspaceDiffViewerMode,
        changes: [WorkspaceCommitChange]?
    ) -> WorkspaceDiffRequestChain {
        let snapshotChanges = changes ?? activeWorkspaceCommitViewModel?.changesSnapshot?.changes
        guard let snapshotChanges, !snapshotChanges.isEmpty else {
            return WorkspaceDiffRequestChain(
                items: [
                    workingTreeRequestItem(
                        repositoryPath: repositoryPath,
                        executionPath: executionPath,
                        filePath: activeFilePath,
                        group: activeGroup,
                        status: activeStatus,
                        oldPath: activeOldPath,
                        title: activePreferredTitle,
                        preferredViewerMode: preferredViewerMode
                    )
                ]
            )
        }

        let items = snapshotChanges.map { change in
            workingTreeRequestItem(
                repositoryPath: repositoryPath,
                executionPath: executionPath,
                filePath: change.path,
                group: change.group,
                status: change.status,
                oldPath: change.oldPath,
                title: change.path == activeFilePath ? activePreferredTitle : "Changes: \(diffDisplayTitle(for: change.path))",
                preferredViewerMode: preferredViewerMode
            )
        }
        let activeIndex = items.firstIndex(where: {
            if case let .workingTreeChange(_, _, filePath, _, _, oldPath) = $0.source {
                return filePath == activeFilePath && oldPath == activeOldPath
            }
            return false
        }) ?? 0
        return WorkspaceDiffRequestChain(items: items, activeIndex: activeIndex)
    }

    private func gitLogDiffRequestChain(
        repositoryPath: String,
        commitHash: String,
        activeFilePath: String,
        activePreferredTitle: String,
        preferredViewerMode: WorkspaceDiffViewerMode
    ) -> WorkspaceDiffRequestChain {
        guard let detail = activeWorkspaceGitViewModel?.logViewModel.selectedCommitDetail,
              detail.hash == commitHash,
              !detail.files.isEmpty
        else {
            return WorkspaceDiffRequestChain(
                items: [
                    gitLogRequestItem(
                        repositoryPath: repositoryPath,
                        commitHash: commitHash,
                        file: WorkspaceGitCommitFileChange(path: activeFilePath, status: .modified),
                        detail: nil,
                        title: activePreferredTitle,
                        preferredViewerMode: preferredViewerMode
                    )
                ]
            )
        }

        let items = detail.files.map { file in
            gitLogRequestItem(
                repositoryPath: repositoryPath,
                commitHash: commitHash,
                file: file,
                detail: detail,
                title: file.path == activeFilePath ? activePreferredTitle : "Commit: \(diffDisplayTitle(for: file.path))",
                preferredViewerMode: preferredViewerMode
            )
        }
        let activeIndex = items.firstIndex(where: {
            if case let .gitLogCommitFile(_, _, filePath) = $0.source {
                return filePath == activeFilePath
            }
            return false
        }) ?? 0
        return WorkspaceDiffRequestChain(items: items, activeIndex: activeIndex)
    }

    private func workingTreeRequestItem(
        repositoryPath: String,
        executionPath: String,
        filePath: String,
        group: WorkspaceCommitChangeGroup?,
        status: WorkspaceCommitChangeStatus?,
        oldPath: String?,
        title: String,
        preferredViewerMode: WorkspaceDiffViewerMode
    ) -> WorkspaceDiffRequestItem {
        WorkspaceDiffRequestItem(
            id: "working-tree|\(executionPath)|\(filePath)",
            title: title,
            source: .workingTreeChange(
                repositoryPath: repositoryPath,
                executionPath: executionPath,
                filePath: filePath,
                group: group,
                status: status,
                oldPath: oldPath
            ),
            preferredViewerMode: preferredViewerMode
        )
    }

    private func gitLogRequestItem(
        repositoryPath: String,
        commitHash: String,
        file: WorkspaceGitCommitFileChange,
        detail: WorkspaceGitCommitDetail?,
        title: String,
        preferredViewerMode: WorkspaceDiffViewerMode
    ) -> WorkspaceDiffRequestItem {
        let timestampText = detail.map { gitDiffTimestampText($0.authorTimestamp) }
        let parentRevision = detail?.parentHashes.first
        return WorkspaceDiffRequestItem(
            id: "git-log|\(repositoryPath)|\(commitHash)|\(file.path)",
            title: title,
            source: .gitLogCommitFile(
                repositoryPath: repositoryPath,
                commitHash: commitHash,
                filePath: file.path
            ),
            preferredViewerMode: preferredViewerMode,
            paneMetadataSeeds: [
                WorkspaceDiffPaneMetadataSeed(
                    role: .left,
                    title: "Before",
                    path: file.oldPath ?? file.path,
                    revision: parentRevision,
                    hash: parentRevision,
                    author: detail?.authorName,
                    timestamp: timestampText
                ),
                WorkspaceDiffPaneMetadataSeed(
                    role: .right,
                    title: "After",
                    path: file.path,
                    oldPath: file.oldPath,
                    revision: detail?.shortHash ?? commitHash,
                    hash: detail?.hash ?? commitHash,
                    author: detail?.authorName,
                    timestamp: timestampText,
                    copyPayloads: [
                        WorkspaceDiffPaneCopyPayload(
                            id: "commit-hash",
                            label: "提交哈希",
                            value: detail?.hash ?? commitHash
                        )
                    ]
                ),
            ]
        )
    }

    private func diffDisplayTitle(for path: String) -> String {
        let fileName = (path as NSString).lastPathComponent
        return fileName.isEmpty ? path : fileName
    }

    private static let gitDiffTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private func gitDiffTimestampText(_ timestamp: TimeInterval) -> String {
        Self.gitDiffTimestampFormatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    private func activeWorkspaceCommitDiffPreviewRequest(
        repositoryPath: String,
        executionPath: String,
        filePath: String,
        group: WorkspaceCommitChangeGroup?,
        status: WorkspaceCommitChangeStatus?,
        oldPath: String?,
        allChanges: [WorkspaceCommitChange]? = nil,
        preferredTitle: String,
        preferredViewerMode: WorkspaceDiffViewerMode
    ) -> WorkspaceDiffOpenRequest? {
        guard let activeWorkspaceProjectPath else {
            return nil
        }
        let chain = commitDiffRequestChain(
            repositoryPath: repositoryPath,
            executionPath: executionPath,
            activeFilePath: filePath,
            activeGroup: group,
            activeStatus: status,
            activeOldPath: oldPath,
            activePreferredTitle: preferredTitle,
            preferredViewerMode: preferredViewerMode,
            changes: allChanges
        )
        guard let activeItem = chain.activeItem else {
            return nil
        }
        return WorkspaceDiffOpenRequest(
            projectPath: activeWorkspaceProjectPath,
            source: activeItem.source,
            preferredTitle: activeItem.title,
            preferredViewerMode: activeItem.preferredViewerMode,
            requestChain: chain,
            identityOverride: commitPreviewIdentity(for: executionPath),
            originContext: WorkspaceDiffOriginContext(
                presentedTabSelection: workspaceSelectedPresentedTab(for: activeWorkspaceProjectPath),
                focusedArea: workspaceFocusedArea
            )
        )
    }

    @discardableResult
    private func openWorkspaceDiffSession(
        projectPath: String,
        chain: WorkspaceDiffRequestChain,
        identityOverride: String? = nil,
        originContext: WorkspaceDiffOriginContext?,
        focusTab: Bool,
        createIfNeeded: Bool
    ) -> WorkspaceDiffTabState? {
        guard let activeItem = chain.activeItem else {
            return nil
        }
        return syncWorkspaceDiffTab(
            WorkspaceDiffOpenRequest(
                projectPath: projectPath,
                source: activeItem.source,
                preferredTitle: activeItem.title,
                preferredViewerMode: activeItem.preferredViewerMode,
                requestChain: chain,
                identityOverride: identityOverride,
                originContext: originContext
            ),
            focusTab: focusTab,
            createIfNeeded: createIfNeeded
        )
    }

    private func commitPreviewIdentity(for executionPath: String) -> String {
        "commit-preview|\(executionPath)"
    }

    @discardableResult
    private func syncWorkspaceDiffTab(
        _ request: WorkspaceDiffOpenRequest,
        focusTab: Bool,
        createIfNeeded: Bool
    ) -> WorkspaceDiffTabState? {
        activeWorkspaceProjectPath = request.projectPath

        if var tabs = workspaceDiffTabsByProjectPath[request.projectPath],
           let existingIndex = tabs.firstIndex(where: { $0.identity == request.identity }) {
            var existing = tabs[existingIndex]
            existing.title = request.preferredTitle
            existing.source = request.source
            existing.viewerMode = request.preferredViewerMode
            existing.requestChain = request.requestChain
            if let originContext = request.originContext {
                existing.originContext = originContext
            }
            tabs[existingIndex] = existing
            workspaceDiffTabsByProjectPath[request.projectPath] = tabs
            if let requestChain = request.requestChain {
                workspaceDiffTabViewModels[existing.id]?.openSession(requestChain)
            } else {
                workspaceDiffTabViewModels[existing.id]?.updateTab(existing)
            }
            if focusTab {
                workspaceSelectedPresentedTabByProjectPath[request.projectPath] = .diff(existing.id)
                workspaceFocusedArea = .diffTab(existing.id)
            }
            return existing
        }

        guard createIfNeeded else {
            return nil
        }

        let tab = WorkspaceDiffTabState(
            id: "workspace-diff:\(UUID().uuidString.lowercased())",
            identity: request.identity,
            title: request.preferredTitle,
            source: request.source,
            viewerMode: request.preferredViewerMode,
            requestChain: request.requestChain,
            originContext: request.originContext
        )
        workspaceDiffTabsByProjectPath[request.projectPath, default: []].append(tab)
        if focusTab {
            workspaceSelectedPresentedTabByProjectPath[request.projectPath] = .diff(tab.id)
            workspaceFocusedArea = .diffTab(tab.id)
        }
        return tab
    }

    private func restoreOriginContext(
        for tab: WorkspaceDiffTabState,
        in projectPath: String,
        remainingDiffTabs: [WorkspaceDiffTabState]
    ) -> Bool {
        guard let originContext = tab.originContext,
              let originSelection = validPresentedTabSelection(
                originContext.presentedTabSelection,
                in: projectPath,
                diffTabs: remainingDiffTabs
              )
        else {
            return false
        }

        selectWorkspacePresentedTab(originSelection, in: projectPath)
        return restoreFocusedArea(
            originContext.focusedArea,
            for: originSelection,
            in: projectPath,
            remainingDiffTabs: remainingDiffTabs
        )
    }

    private func validPresentedTabSelection(
        _ selection: WorkspacePresentedTabSelection?,
        in projectPath: String,
        diffTabs: [WorkspaceDiffTabState]
    ) -> WorkspacePresentedTabSelection? {
        guard let selection else {
            return nil
        }

        switch selection {
        case let .terminal(tabID):
            guard workspaceController(for: projectPath)?.tabs.contains(where: { $0.id == tabID }) == true else {
                return nil
            }
            return .terminal(tabID)
        case let .diff(tabID):
            guard diffTabs.contains(where: { $0.id == tabID }) else {
                return nil
            }
            return .diff(tabID)
        }
    }

    private func restoreFocusedArea(
        _ area: WorkspaceFocusedArea,
        for selection: WorkspacePresentedTabSelection,
        in projectPath: String,
        remainingDiffTabs: [WorkspaceDiffTabState]
    ) -> Bool {
        switch area {
        case .terminal:
            workspaceFocusedArea = .terminal
            return true
        case let .sideToolWindow(kind):
            showWorkspaceSideToolWindow(kind)
            return true
        case let .bottomToolWindow(kind):
            showWorkspaceBottomToolWindow(kind)
            return true
        case let .diffTab(tabID):
            guard validPresentedTabSelection(.diff(tabID), in: projectPath, diffTabs: remainingDiffTabs) != nil else {
                workspaceFocusedArea = defaultFocusedArea(for: selection)
                return false
            }
            workspaceFocusedArea = .diffTab(tabID)
            return true
        }
    }

    private func defaultFocusedArea(for selection: WorkspacePresentedTabSelection) -> WorkspaceFocusedArea {
        switch selection {
        case .terminal:
            return .terminal
        case let .diff(tabID):
            return .diffTab(tabID)
        }
    }

    private func clearWorkspaceRuntimePresentationState(for paths: Set<String>) {
        for path in paths {
            for tab in workspaceDiffTabsByProjectPath[path] ?? [] {
                workspaceDiffTabViewModels[tab.id] = nil
            }
            workspaceDiffTabsByProjectPath[path] = nil
            workspaceSelectedPresentedTabByProjectPath[path] = nil
        }
    }

    private func workspaceController(for projectPath: String? = nil) -> GhosttyWorkspaceController? {
        workspaceSession(for: projectPath ?? activeWorkspaceProjectPath)?.controller
    }

    private func makeProjectRunConfiguration(
        configuration: ProjectRunConfiguration,
        projectPath: String,
        rootProjectPath: String
    ) -> WorkspaceRunConfiguration {
        switch configuration.kind {
        case .customShell:
            let command = configuration.customShell?.command.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return WorkspaceRunConfiguration(
                id: workspaceProjectRunConfigurationID(projectPath: projectPath, configurationID: configuration.id),
                projectPath: projectPath,
                rootProjectPath: rootProjectPath,
                source: .projectRunConfiguration,
                sourceID: configuration.id,
                name: configuration.name,
                executable: .shell(command: command),
                displayCommand: command,
                workingDirectory: projectPath,
                isShared: false,
                canRun: !command.isEmpty,
                disabledReason: command.isEmpty ? "命令为空，请先完善自定义 Shell 配置。" : nil
            )
        case .remoteLogViewer:
            let resolution = resolveRemoteLogViewerExecutable(configuration.remoteLogViewer)
            return WorkspaceRunConfiguration(
                id: workspaceProjectRunConfigurationID(projectPath: projectPath, configurationID: configuration.id),
                projectPath: projectPath,
                rootProjectPath: rootProjectPath,
                source: .projectRunConfiguration,
                sourceID: configuration.id,
                name: configuration.name,
                executable: resolution.executable,
                displayCommand: resolution.displayCommand,
                workingDirectory: projectPath,
                isShared: false,
                canRun: resolution.canRun,
                disabledReason: resolution.disabledReason
            )
        }
    }

    private func workspaceProjectRunConfigurationID(projectPath: String, configurationID: String) -> String {
        "project::\(projectPath)::\(configurationID)"
    }

    private struct RemoteLogViewerExecutableResolution {
        var executable: WorkspaceRunExecutable
        var displayCommand: String
        var canRun: Bool
        var disabledReason: String?
    }

    private func resolveRemoteLogViewerExecutable(_ configuration: ProjectRunRemoteLogViewerConfiguration?) -> RemoteLogViewerExecutableResolution {
        guard let configuration else {
            return RemoteLogViewerExecutableResolution(
                executable: .process(program: "/usr/bin/ssh", arguments: []),
                displayCommand: "/usr/bin/ssh",
                canRun: false,
                disabledReason: "远程日志配置缺失，请重新创建该运行配置。"
            )
        }

        let server = configuration.server.trimmingCharacters(in: .whitespacesAndNewlines)
        let logPath = configuration.logPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !server.isEmpty, !logPath.isEmpty else {
            return RemoteLogViewerExecutableResolution(
                executable: .process(program: "/usr/bin/ssh", arguments: []),
                displayCommand: "/usr/bin/ssh",
                canRun: false,
                disabledReason: "远程日志配置缺少服务器或日志路径。"
            )
        }

        var args = [String]()
        let user = configuration.user?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !user.isEmpty {
            args.append(contentsOf: ["-l", user])
        }
        if let port = configuration.port, port > 0 {
            args.append(contentsOf: ["-p", String(port)])
        }
        let identityFile = configuration.identityFile?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !identityFile.isEmpty {
            args.append(contentsOf: ["-i", identityFile])
        }
        let strictHostKeyChecking = configuration.strictHostKeyChecking?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !strictHostKeyChecking.isEmpty {
            args.append(contentsOf: ["-o", "StrictHostKeyChecking=\(strictHostKeyChecking)"])
        }
        if !configuration.allowPasswordPrompt {
            args.append(contentsOf: ["-o", "BatchMode=yes"])
        }

        let lines = max(1, configuration.lines ?? 200)
        let remoteCommand = remoteTailCommand(logPath: logPath, lines: lines, follow: configuration.follow)
        args.append(server)
        args.append(remoteCommand)

        return RemoteLogViewerExecutableResolution(
            executable: .process(program: "/usr/bin/ssh", arguments: args),
            displayCommand: processDisplayCommand(program: "/usr/bin/ssh", arguments: args),
            canRun: true,
            disabledReason: nil
        )
    }

    private func remoteTailCommand(logPath: String, lines: Int, follow: Bool) -> String {
        var components = ["tail", "-n", String(lines)]
        if follow {
            components.append("-F")
        }
        components.append(shellQuote(logPath))
        return components.joined(separator: " ")
    }

    private func processDisplayCommand(program: String, arguments: [String]) -> String {
        ([program] + arguments.map(shellQuote)).joined(separator: " ")
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func resolveWorkspaceRunProjectPath(_ projectPath: String?) -> String? {
        let candidate = projectPath ?? activeWorkspaceProjectPath
        guard let candidate else {
            return nil
        }
        guard openWorkspaceProjectPaths.contains(candidate) else {
            return nil
        }
        return candidate
    }

    private func resolveWorkspaceScriptOwnerProjectPath(for projectPath: String) -> String? {
        if snapshot.projects.contains(where: { normalizePathForCompare($0.path) == normalizePathForCompare(projectPath) }) {
            return projectPath
        }
        return snapshot.projects.first(where: { project in
            project.worktrees.contains(where: { normalizePathForCompare($0.path) == normalizePathForCompare(projectPath) })
        })?.path
    }

    private func handleWorkspaceRunManagerEvent(_ event: WorkspaceRunManagerEvent) {
        switch event {
        case let .output(projectPath, sessionID, chunk):
            updateWorkspaceRunConsoleState(for: projectPath) { state in
                guard let index = state.sessions.firstIndex(where: { $0.id == sessionID }) else {
                    return
                }
                state.sessions[index].displayBuffer += chunk
            }
        case let .stateChanged(projectPath, sessionID, runState):
            updateWorkspaceRunConsoleState(for: projectPath) { state in
                guard let index = state.sessions.firstIndex(where: { $0.id == sessionID }) else {
                    return
                }
                state.sessions[index].state = runState
                if !runState.isActive {
                    state.sessions[index].endedAt = Date()
                }
            }
        }
    }

    private func updateWorkspaceRunConsoleState(
        for projectPath: String,
        mutate: (inout WorkspaceRunConsoleState) -> Void
    ) {
        guard var state = workspaceRunConsoleStateByProjectPath[projectPath] else {
            return
        }
        mutate(&state)
        workspaceRunConsoleStateByProjectPath[projectPath] = state
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

    private func syncProjectRepositoryState(
        rootProjectPath: String,
        gitWorktrees: [NativeGitWorktree],
        currentBranch: String?
    ) throws {
        let gitWorktreePaths = Set(gitWorktrees.map { normalizePathForCompare($0.path) })
        let stalePendingPaths = pendingWorkspaceWorktreeCreatesByPath.keys.filter { gitWorktreePaths.contains($0) }
        let promotedPendingWorktrees = stalePendingPaths.compactMap { path in
            pendingWorkspaceWorktreeCreatesByPath[path].map(makePromotedPendingWorktree)
        }
        if !stalePendingPaths.isEmpty {
            for path in stalePendingPaths {
                pendingWorkspaceWorktreeCreatesByPath.removeValue(forKey: path)
            }
        }

        if let projectIndex = snapshot.projects.firstIndex(where: {
            normalizePathForCompare($0.path) == rootProjectPath
        }) {
            let storedRootProjectPath = snapshot.projects[projectIndex].path
            let preservedOpenedWorktrees = openedChildWorktrees(for: storedRootProjectPath, in: snapshot.projects)
            let nextWorktrees = buildSyncedWorktrees(
                existingWorktrees: snapshot.projects[projectIndex].worktrees,
                gitWorktrees: gitWorktrees,
                preservedLiveWorktrees: preservedOpenedWorktrees,
                promotedPendingWorktrees: promotedPendingWorktrees
            )

            if snapshot.projects[projectIndex].worktrees != nextWorktrees {
                var projects = snapshot.projects
                projects[projectIndex].worktrees = nextWorktrees
                try persistProjects(projects)
            }

            if let currentBranch, currentBranchByProjectPath[storedRootProjectPath] != currentBranch {
                currentBranchByProjectPath[storedRootProjectPath] = currentBranch
            }
            return
        }

        if let currentBranch, currentBranchByProjectPath[rootProjectPath] != currentBranch {
            currentBranchByProjectPath[rootProjectPath] = currentBranch
        }
    }

    private func persistWorkspaceAlignmentGroups(_ groups: [WorkspaceAlignmentGroupDefinition]) throws {
        try store.updateWorkspaceAlignmentGroups(groups)
        snapshot.appState.workspaceAlignmentGroups = groups
    }

    private func validateWorkspaceAlignmentGroup(
        _ definition: WorkspaceAlignmentGroupDefinition,
        replacing groupID: String?
    ) throws {
        guard !definition.name.isEmpty else {
            throw NativeWorktreeError.invalidProject("工作区名称不能为空")
        }
        let duplicateName = snapshot.appState.workspaceAlignmentGroups.contains {
            $0.id != groupID && $0.name.caseInsensitiveCompare(definition.name) == .orderedSame
        }
        if duplicateName {
            throw NativeWorktreeError.invalidProject("已存在同名工作区")
        }
        let members = definition.effectiveMembers
        let normalizedMemberPaths = members.map { normalizePathForCompare($0.projectPath) }
        if Set(normalizedMemberPaths).count != normalizedMemberPaths.count {
            throw NativeWorktreeError.invalidProject("工作区内存在重复项目")
        }
        for member in members {
            if member.targetBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let projectName = snapshot.projects.first(where: {
                    normalizePathForCompare($0.path) == normalizePathForCompare(member.projectPath)
                })?.name ?? pathLastComponent(member.projectPath)
                throw NativeWorktreeError.invalidBranch("请为 \(projectName) 填写目标 branch")
            }
            if member.baseBranchMode == .specified,
               (member.specifiedBaseBranch?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                let projectName = snapshot.projects.first(where: {
                    normalizePathForCompare($0.path) == normalizePathForCompare(member.projectPath)
                })?.name ?? pathLastComponent(member.projectPath)
                throw NativeWorktreeError.invalidBaseBranch("请为 \(projectName) 填写基线分支")
            }
        }
    }

    private func buildWorkspaceAlignmentMemberAliases(
        for projectPaths: [String],
        existing: [String: String],
        projectsByNormalizedPath: [String: Project]? = nil
    ) -> [String: String] {
        let normalizedPaths = normalizePathList(projectPaths)
        let projectsByNormalizedPath = projectsByNormalizedPath ?? self.projectsByNormalizedPath
        var aliases = [String: String]()
        var usedAliases = Set<String>()

        for path in normalizedPaths {
            let preferredAlias = existing[path]
            let projectName = projectsByNormalizedPath[path]?.name ?? pathLastComponent(path)
            let alias = uniqueWorkspaceAlignmentAlias(
                preferredAlias ?? projectName,
                usedAliases: &usedAliases
            )
            aliases[path] = alias
        }

        return aliases
    }

    private func resolvedWorkspaceAlignmentAliases(
        for definition: WorkspaceAlignmentGroupDefinition,
        projectsByNormalizedPath: [String: Project]? = nil
    ) -> [String: String] {
        buildWorkspaceAlignmentMemberAliases(
            for: definition.effectiveMembers.map(\.projectPath),
            existing: definition.memberAliases,
            projectsByNormalizedPath: projectsByNormalizedPath
        )
    }

    private func workspaceAlignmentMemberDefinition(
        for projectPath: String,
        in definition: WorkspaceAlignmentGroupDefinition
    ) -> WorkspaceAlignmentMemberDefinition? {
        definition.effectiveMembers.first(where: {
            normalizePathForCompare($0.projectPath) == normalizePathForCompare(projectPath)
        })
    }

    private func normalizeWorkspaceAlignmentMemberDefinitions(
        _ members: [WorkspaceAlignmentMemberDefinition]
    ) -> [WorkspaceAlignmentMemberDefinition] {
        var seen = Set<String>()
        return members
            .map { $0.sanitized() }
            .filter { !$0.projectPath.isEmpty }
            .filter { seen.insert(normalizePathForCompare($0.projectPath)).inserted }
    }

    private func uniqueWorkspaceAlignmentAlias(
        _ preferredAlias: String,
        usedAliases: inout Set<String>
    ) -> String {
        let sanitizedBase = sanitizeWorkspaceAlignmentAlias(preferredAlias)
        var candidate = sanitizedBase
        var suffix = 2
        while usedAliases.contains(candidate.lowercased()) {
            candidate = "\(sanitizedBase)-\(suffix)"
            suffix += 1
        }
        usedAliases.insert(candidate.lowercased())
        return candidate
    }

    private func sanitizeWorkspaceAlignmentAlias(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let replaced = trimmed
            .replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        return replaced.isEmpty ? "member" : replaced
    }

    private func syncWorkspaceAlignmentRootIfPossible(_ groupID: String) throws -> URL? {
        guard let group = workspaceAlignmentGroups.first(where: { $0.id == groupID }) else {
            return nil
        }
        return try syncWorkspaceAlignmentRoot(for: group)
    }

    @discardableResult
    private func syncWorkspaceAlignmentRoot(
        for group: WorkspaceAlignmentGroupProjection
    ) throws -> URL {
        try workspaceAlignmentRootStore.syncRoot(for: group)
    }

    private func workspaceAlignmentStatusKey(groupID: String, projectPath: String) -> String {
        "\(groupID)|\(normalizePathForCompare(projectPath))"
    }

    private func updateWorkspaceAlignmentStatus(
        _ status: WorkspaceAlignmentMemberStatus,
        groupID: String,
        projectPath: String
    ) {
        workspaceAlignmentStatusByKey[workspaceAlignmentStatusKey(groupID: groupID, projectPath: projectPath)] = status
    }

    private func clearWorkspaceAlignmentStatuses(for groupID: String) {
        workspaceAlignmentStatusByKey = workspaceAlignmentStatusByKey.filter { !$0.key.hasPrefix("\(groupID)|") }
    }

    private func workspaceAlignmentOpenTarget(
        for projectPath: String,
        targetBranch: String,
        status: WorkspaceAlignmentMemberStatus
    ) -> WorkspaceAlignmentOpenTarget {
        guard case .aligned = status else {
            return .project(projectPath: projectPath)
        }

        let normalizedProjectPath = normalizePathForCompare(projectPath)
        guard let rootProject = projectsByNormalizedPath[normalizedProjectPath] else {
            return .project(projectPath: projectPath)
        }

        let currentBranch = currentBranchByProjectPath[rootProject.path] ?? currentBranchByProjectPath[normalizedProjectPath]
        if currentBranch == targetBranch {
            return .project(projectPath: rootProject.path)
        }

        if let worktree = rootProject.worktrees.first(where: { $0.branch == targetBranch }) {
            return .worktree(rootProjectPath: rootProject.path, worktreePath: worktree.path)
        }

        return .project(projectPath: rootProject.path)
    }

    private func workspaceAlignmentBranchLabel(
        for projectPath: String,
        targetBranch: String,
        status: WorkspaceAlignmentMemberStatus,
        openTarget: WorkspaceAlignmentOpenTarget
    ) -> String {
        switch status {
        case let .currentBranch(branch):
            return branch
        case .aligned, .branchMissing, .worktreeMissing, .checking, .applying, .applyFailed, .checkFailed:
            break
        }

        if let rootProject = snapshot.projects.first(where: {
            normalizePathForCompare($0.path) == normalizePathForCompare(projectPath)
        }) {
            switch openTarget {
            case .project:
                if let currentBranch = currentBranchByProjectPath[rootProject.path] {
                    return currentBranch
                }
            case let .worktree(_, worktreePath):
                if let worktree = rootProject.worktrees.first(where: {
                    normalizePathForCompare($0.path) == normalizePathForCompare(worktreePath)
                }) {
                    return worktree.branch
                }
            }
        }

        return targetBranch
    }

    private func resolveWorkspaceAlignmentBaseBranch(
        for member: WorkspaceAlignmentMemberDefinition
    ) async throws -> String {
        switch member.baseBranchMode {
        case .specified:
            let branch = member.specifiedBaseBranch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !branch.isEmpty else {
                throw NativeWorktreeError.invalidBaseBranch("请填写基线分支")
            }
            return branch
        case .autoDetect:
            let branches = try await listWorkspaceBranches(for: member.projectPath)
            if branches.contains(where: { $0.name == "develop" }) {
                return "develop"
            }
            if let main = branches.first(where: \.isMain)?.name {
                return main
            }
            guard let fallback = branches.first?.name else {
                throw NativeWorktreeError.invalidBaseBranch("无法自动探测基线分支")
            }
            return fallback
        }
    }

    private func refreshWorkspaceAlignmentProjectStatus(
        _ member: WorkspaceAlignmentMemberDefinition,
        in definition: WorkspaceAlignmentGroupDefinition
    ) async throws {
        let probe = try await loadWorkspaceAlignmentStatusProbe(
            projectPath: member.projectPath,
            targetBranch: member.targetBranch
        )
        try syncProjectRepositoryState(
            rootProjectPath: probe.projectPath,
            gitWorktrees: probe.worktrees,
            currentBranch: probe.currentBranch
        )
        let status = resolveWorkspaceAlignmentStatus(from: probe)
        updateWorkspaceAlignmentStatus(status, groupID: definition.id, projectPath: member.projectPath)
    }

    private func loadWorkspaceAlignmentStatusProbe(
        projectPath: String,
        targetBranch: String
    ) async throws -> WorkspaceAlignmentStatusProbe {
        let normalizedProjectPath = normalizePathForCompare(projectPath)
        guard !normalizedProjectPath.isEmpty else {
            throw NativeWorktreeError.invalidProject("项目路径无效")
        }
        let trimmedTargetBranch = targetBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let worktreeService = self.worktreeService
        return try await Task.detached(priority: .userInitiated) {
            let managedWorktreePath = try worktreeService.managedWorktreePath(for: normalizedProjectPath, branch: trimmedTargetBranch)
            let branches = try worktreeService.listBranches(at: normalizedProjectPath)
            let worktrees = try worktreeService.listWorktrees(at: normalizedProjectPath)
            let currentBranch = try worktreeService.currentBranch(at: normalizedProjectPath)
            return WorkspaceAlignmentStatusProbe(
                projectPath: normalizedProjectPath,
                targetBranch: trimmedTargetBranch,
                managedWorktreePath: managedWorktreePath,
                branches: branches,
                worktrees: worktrees,
                currentBranch: currentBranch
            )
        }.value
    }

    private func resolveWorkspaceAlignmentStatus(from probe: WorkspaceAlignmentStatusProbe) -> WorkspaceAlignmentMemberStatus {
        if probe.hasOccupiedTargetCheckout {
            return .aligned
        }

        if !probe.branchExists {
            return .branchMissing
        }

        return .currentBranch(probe.currentBranch)
    }

    private func applyWorkspaceAlignmentRule(
        for projectPath: String,
        in definition: WorkspaceAlignmentGroupDefinition
    ) async throws {
        guard let member = workspaceAlignmentMemberDefinition(
            for: projectPath,
            in: definition
        ) else {
            throw NativeWorktreeError.invalidProject("工作区成员不存在")
        }
        updateWorkspaceAlignmentStatus(.applying, groupID: definition.id, projectPath: projectPath)
        do {
            let normalizedProjectPath = normalizePathForCompare(projectPath)
            let targetBranch = member.targetBranch
            let probe = try await loadWorkspaceAlignmentStatusProbe(
                projectPath: normalizedProjectPath,
                targetBranch: targetBranch
            )
            try syncProjectRepositoryState(
                rootProjectPath: probe.projectPath,
                gitWorktrees: probe.worktrees,
                currentBranch: probe.currentBranch
            )

            if probe.hasOccupiedTargetCheckout {
                updateWorkspaceAlignmentStatus(.aligned, groupID: definition.id, projectPath: projectPath)
                return
            }

            let branchExists = probe.branchExists
            let baseBranch = branchExists ? nil : try await resolveWorkspaceAlignmentBaseBranch(for: member)
            try await createWorkspaceWorktree(
                from: normalizedProjectPath,
                branch: targetBranch,
                createBranch: !branchExists,
                baseBranch: baseBranch,
                autoOpen: false,
                targetPath: probe.managedWorktreePath
            )
            try await refreshWorkspaceAlignmentProjectStatus(member, in: definition)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            updateWorkspaceAlignmentStatus(.applyFailed(message), groupID: definition.id, projectPath: projectPath)
            throw error
        }
    }

    private func orderedSidebarWorktreeItems(
        for rootProject: Project,
        rootProjectPath: String,
        showsInAppNotifications: Bool,
        moveNotifiedWorktreeToTop: Bool
    ) -> [WorkspaceSidebarWorktreeItem] {
        let persistedPaths = Set(rootProject.worktrees.map { normalizePathForCompare($0.path) })
        let persistedItems = rootProject.worktrees.map { worktree -> WorkspaceSidebarWorktreeItem in
            let owningProjectPoolSession = openWorkspaceSessions.first(where: {
                normalizePathForCompare($0.projectPath) == normalizePathForCompare(worktree.path) &&
                    isWorkspaceSessionOwnedByProjectPool($0, rootProjectPath: rootProjectPath)
            })
            let attention = owningProjectPoolSession.flatMap { attentionStateByProjectPath[$0.projectPath] }
            return WorkspaceSidebarWorktreeItem(
                rootProjectPath: rootProjectPath,
                worktree: worktree,
                isOpen: owningProjectPoolSession != nil,
                isActive: owningProjectPoolSession != nil && activeWorkspaceProjectPath == worktree.path,
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
        let pendingItems = pendingWorkspaceWorktreeCreatesByPath.values
            .filter { normalizePathForCompare($0.rootProjectPath) == normalizePathForCompare(rootProjectPath) }
            .filter { !persistedPaths.contains(normalizePathForCompare($0.worktreePath)) }
            .sorted { $0.worktreePath < $1.worktreePath }
            .map { pending -> WorkspaceSidebarWorktreeItem in
                let syntheticWorktree = ProjectWorktree(
                    id: createWorktreeProjectID(path: pending.worktreePath),
                    name: resolveWorktreeName(pending.worktreePath),
                    path: pending.worktreePath,
                    branch: pending.branch,
                    baseBranch: pending.baseBranch,
                    inheritConfig: true,
                    created: pending.createdAt,
                    updatedAt: pending.createdAt
                )
                return WorkspaceSidebarWorktreeItem(
                    rootProjectPath: rootProjectPath,
                    worktree: syntheticWorktree,
                    isOpen: false,
                    isActive: false,
                    notifications: [],
                    unreadNotificationCount: 0,
                    taskStatus: nil,
                    agentState: nil,
                    agentSummary: nil,
                    agentKind: nil,
                    displayStateOverride: pending.status == .creating
                        ? .creating(message: pending.message)
                        : .failed(message: pending.error ?? pending.message),
                    displayInitStepOverride: pending.step,
                    displayInitErrorOverride: pending.error,
                    displayInitMessageOverride: pending.message
                )
            }
        let items = persistedItems + pendingItems
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
        var nextAttentionStateByProjectPath = attentionStateByProjectPath.filter { openPaths.contains($0.key) }
        for path in openPaths {
            guard var attention = nextAttentionStateByProjectPath[path] else {
                continue
            }
            attention.clearAgentStates()
            nextAttentionStateByProjectPath[path] = attention
        }
        for signal in snapshots.values where openPaths.contains(signal.projectPath) {
            var attention = nextAttentionStateByProjectPath[signal.projectPath] ?? WorkspaceAttentionState()
            applyAgentSignal(signal, to: &attention)
            nextAttentionStateByProjectPath[signal.projectPath] = attention
        }
        if attentionStateByProjectPath != nextAttentionStateByProjectPath {
            attentionStateByProjectPath = nextAttentionStateByProjectPath
        }
        pruneWorkspaceAgentDisplayOverrides()
    }

    private func pruneWorkspaceAgentDisplayOverrides() {
        let filteredOverrides = filteredWorkspaceAgentDisplayOverrides(agentDisplayOverridesByProjectPath)
        guard agentDisplayOverridesByProjectPath != filteredOverrides else {
            return
        }
        agentDisplayOverridesByProjectPath = filteredOverrides
    }

    private func filteredWorkspaceAgentDisplayOverrides(
        _ overridesByProjectPath: [String: [String: WorkspaceAgentPresentationOverride]]
    ) -> [String: [String: WorkspaceAgentPresentationOverride]] {
        let validPaneIDsByProjectPath = Dictionary(
            grouping: codexDisplayCandidates(),
            by: \.projectPath
        ).mapValues { Set($0.map(\.paneID)) }

        return overridesByProjectPath.reduce(into: [:]) { result, entry in
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

    private func noteWorkspaceSidebarProjectionMutation<T: Equatable>(
        from oldValue: T,
        to newValue: T
    ) {
        guard oldValue != newValue else {
            return
        }
        workspaceSidebarProjectionRevision &+= 1
    }

    private func rebuildProjectLookupIndex() {
        projectsByNormalizedPath = snapshot.projects.reduce(into: [:]) { result, project in
            let normalizedPath = normalizePathForCompare(project.path)
            guard !normalizedPath.isEmpty else {
                return
            }
            result[normalizedPath] = project
        }
    }

    private func rebuildWorkspaceSessionIndex() {
        workspaceSessionIndexByNormalizedPath = openWorkspaceSessions.enumerated().reduce(into: [:]) { result, element in
            let normalizedPath = normalizePathForCompare(element.element.projectPath)
            guard !normalizedPath.isEmpty else {
                return
            }
            result[normalizedPath] = element.offset
        }
    }

    private func applyAgentSignal(
        _ signal: WorkspaceAgentSessionSignal,
        to attention: inout WorkspaceAttentionState
    ) {
        attention.setAgentState(
            signal.state,
            kind: signal.agentKind,
            summary: signal.summary,
            updatedAt: signal.updatedAt,
            for: signal.paneId
        )
    }

    private func resolvedWorkspaceRunConfigurations(for projectPath: String) -> [WorkspaceRunConfiguration] {
        guard let session = openWorkspaceSessions.first(where: { $0.projectPath == projectPath }),
              let project = resolveDisplayProject(for: projectPath)
        else {
            return []
        }

        return project.runConfigurations.map {
            makeProjectRunConfiguration(
                configuration: $0,
                projectPath: projectPath,
                rootProjectPath: session.rootProjectPath
            )
        }
    }

    private func resolvedSelectedWorkspaceRunConfiguration(
        for projectPath: String,
        configurations: [WorkspaceRunConfiguration]? = nil
    ) -> WorkspaceRunConfiguration? {
        let resolvedConfigurations = configurations ?? resolvedWorkspaceRunConfigurations(for: projectPath)
        guard !resolvedConfigurations.isEmpty else {
            return nil
        }
        let state = workspaceRunConsoleStateByProjectPath[projectPath] ?? WorkspaceRunConsoleState()
        if let selectedConfigurationID = state.selectedConfigurationID,
           let selected = resolvedConfigurations.first(where: { $0.id == selectedConfigurationID }) {
            return selected
        }
        return resolvedConfigurations.first
    }

    private func resolveDisplayProject(for path: String, rootProjectPath: String? = nil) -> Project? {
        let lookupKey = DisplayProjectLookupKey(path: path, rootProjectPath: rootProjectPath)
        if let cachedProject = displayProjectCacheByLookupKey[lookupKey] {
            return cachedProject
        }

        let normalizedPath = normalizePathForCompare(path)
        let resolvedProject: Project?
        if let project = projectsByNormalizedPath[normalizedPath] {
            resolvedProject = project
        } else {
            let rootProject: Project?
            if let rootProjectPath {
                rootProject = normalizedOptionalPathForCompare(rootProjectPath).flatMap { projectsByNormalizedPath[$0] }
            } else {
                rootProject = snapshot.projects.first(where: { project in
                    project.worktrees.contains(where: { normalizePathForCompare($0.path) == normalizedPath })
                })
            }

            if let rootProject,
               let worktree = rootProject.worktrees.first(where: { normalizePathForCompare($0.path) == normalizedPath }) {
                resolvedProject = buildWorktreeVirtualProject(sourceProject: rootProject, worktree: worktree)
            } else {
                resolvedProject = nil
            }
        }

        displayProjectCacheByLookupKey[lookupKey] = resolvedProject
        return resolvedProject
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
        let normalizedWorktreePath = normalizePathForCompare(progress.worktreePath)
        guard var pending = pendingWorkspaceWorktreeCreatesByPath[normalizedWorktreePath] else {
            return
        }
        pending = PendingWorkspaceWorktreeCreateState(
            rootProjectPath: pending.rootProjectPath,
            branch: progress.branch,
            baseBranch: pending.baseBranch ?? progress.baseBranch,
            worktreePath: pending.worktreePath,
            createBranch: pending.createBranch,
            jobID: pending.jobID,
            createdAt: pending.createdAt,
            status: progress.step == .failed ? .failed : .creating,
            step: progress.step,
            message: progress.message,
            error: progress.error
        )
        pendingWorkspaceWorktreeCreatesByPath[normalizedWorktreePath] = pending
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
        bootstrapResult: NativeWorktreeEnvironmentResult,
        autoOpen: Bool
    ) {
        pendingWorkspaceWorktreeCreatesByPath.removeValue(forKey: normalizePathForCompare(result.worktreePath))
        worktreeInteractionState = nil

        if autoOpen {
            openWorkspaceWorktree(result.worktreePath, from: rootProjectPath)
        }
        let warning = [result.warning, formatWorktreeEnvironmentWarning(bootstrapResult)]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: "\n\n")
        if !warning.isEmpty {
            errorMessage = warning
        }
    }

    private func markWorktreeAsFailed(worktreePath: String, rootProjectPath: String, errorMessage: String) {
        let normalizedWorktreePath = normalizePathForCompare(worktreePath)
        guard var pending = pendingWorkspaceWorktreeCreatesByPath[normalizedWorktreePath] else {
            return
        }
        pending = PendingWorkspaceWorktreeCreateState(
            rootProjectPath: pending.rootProjectPath,
            branch: pending.branch,
            baseBranch: pending.baseBranch,
            worktreePath: pending.worktreePath,
            createBranch: pending.createBranch,
            jobID: pending.jobID,
            createdAt: pending.createdAt,
            status: .failed,
            step: .failed,
            message: errorMessage,
            error: errorMessage
        )
        pendingWorkspaceWorktreeCreatesByPath[normalizedWorktreePath] = pending
    }

    private func cleanupFailedWorkspaceWorktreeCreate(_ context: WorktreeCreateContext) -> String? {
        do {
            let cleanup = try worktreeService.cleanupFailedWorktreeCreate(
                NativeWorktreeCleanupRequest(
                    sourceProjectPath: context.rootProjectPath,
                    worktreePath: context.previewPath,
                    branch: context.request.branch,
                    shouldDeleteCreatedBranch: context.request.createBranch
                )
            )
            return cleanup.warning
        } catch {
            return error.localizedDescription
        }
    }

    private func formatWorktreeEnvironmentWarning(_ result: NativeWorktreeEnvironmentResult) -> String? {
        guard let warning = result.warning?.trimmingCharacters(in: .whitespacesAndNewlines),
              !warning.isEmpty else {
            return nil
        }

        var sections = [warning]
        if let failedCommand = result.failedCommand?.trimmingCharacters(in: .whitespacesAndNewlines),
           !failedCommand.isEmpty {
            sections.append("失败命令：\n$ \(failedCommand)")
        }
        let latestOutputLines = result.latestOutputLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !latestOutputLines.isEmpty {
            sections.append("最近输出：\n" + latestOutputLines.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    private func prepareWorkspaceWorktreeEnvironment(_ context: WorktreeCreateContext) async -> NativeWorktreeEnvironmentResult {
        let normalizedWorktreePath = normalizePathForCompare(context.previewPath)
        if var pending = pendingWorkspaceWorktreeCreatesByPath[normalizedWorktreePath] {
            pending.status = .creating
            pending.step = .preparingEnvironment
            pending.message = "执行中：准备工作区环境..."
            pending.error = nil
            pendingWorkspaceWorktreeCreatesByPath[normalizedWorktreePath] = pending
            worktreeInteractionState = WorktreeInteractionState(
                rootProjectPath: context.rootProjectPath,
                branch: pending.branch,
                baseBranch: pending.baseBranch,
                worktreePath: pending.worktreePath,
                step: .preparingEnvironment,
                message: pending.message
            )
        }

        let worktreeEnvironmentService = worktreeEnvironmentService
        let rootProjectPath = context.rootProjectPath
        let previewPath = context.previewPath
        let workspaceName = context.request.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        return await Task.detached(priority: .userInitiated) {
            worktreeEnvironmentService.prepareEnvironment(
                mainRepositoryPath: rootProjectPath,
                worktreePath: previewPath,
                workspaceName: workspaceName
            )
        }.value
    }

    private func upsertWorktree(_ worktrees: inout [ProjectWorktree], worktree: ProjectWorktree) {
        if let index = worktrees.firstIndex(where: { normalizePathForCompare($0.path) == normalizePathForCompare(worktree.path) }) {
            worktrees[index] = worktree
        } else {
            worktrees.append(worktree)
            worktrees.sort { $0.path < $1.path }
        }
    }

    private func makePromotedPendingWorktree(_ pending: PendingWorkspaceWorktreeCreateState) -> ProjectWorktree {
        ProjectWorktree(
            id: createWorktreeProjectID(path: pending.worktreePath),
            name: resolveWorktreeName(pending.worktreePath),
            path: pending.worktreePath,
            branch: pending.branch,
            baseBranch: pending.baseBranch,
            inheritConfig: true,
            created: pending.createdAt,
            updatedAt: pending.createdAt
        )
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

private func normalizedOptionalPathForCompare(_ path: String?) -> String? {
    guard let path else {
        return nil
    }
    let normalizedPath = normalizePathForCompare(path)
    return normalizedPath.isEmpty ? nil : normalizedPath
}

private func pathLastComponent(_ path: String) -> String {
    let lastComponent = (path as NSString).lastPathComponent
    return lastComponent.isEmpty ? path : lastComponent
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

private func loadProjectNotesSummary(at projectPath: String) -> String? {
    let notesURL = URL(fileURLWithPath: projectPath, isDirectory: true).appending(path: "PROJECT_NOTES.md")
    guard FileManager.default.fileExists(atPath: notesURL.path),
          let content = try? String(contentsOf: notesURL, encoding: .utf8)
    else {
        return nil
    }
    return projectNotesSummary(from: content)
}

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
    let notesSummary = loadProjectNotesSummary(at: normalizedPath)

    if let existing = existingByPath[normalizedPath] {
        return Project(
            id: existing.id,
            name: projectURL.lastPathComponent.isEmpty ? normalizedPath : projectURL.lastPathComponent,
            path: normalizedPath,
            tags: existing.tags,
            runConfigurations: existing.runConfigurations,
            worktrees: existing.worktrees,
            mtime: swiftDateFromDate(modificationDate),
            size: size,
            checksum: checksum,
            isGitRepository: isGitRepository,
            gitCommits: existing.gitCommits,
            gitLastCommit: existing.gitLastCommit,
            gitLastCommitMessage: existing.gitLastCommitMessage,
            gitDaily: existing.gitDaily,
            notesSummary: notesSummary,
            created: existing.created,
            checked: swiftDateFromDate(now),
            hasPersistedNotesSummary: true
        )
    }

    return Project(
        id: UUID().uuidString.lowercased(),
        name: projectURL.lastPathComponent.isEmpty ? normalizedPath : projectURL.lastPathComponent,
        path: normalizedPath,
        tags: [],
        runConfigurations: [],
        worktrees: [],
        mtime: swiftDateFromDate(modificationDate),
        size: size,
        checksum: checksum,
        isGitRepository: isGitRepository,
        gitCommits: 0,
        gitLastCommit: .zero,
        gitLastCommitMessage: nil,
        gitDaily: nil,
        notesSummary: notesSummary,
        created: swiftDateFromDate(now),
        checked: swiftDateFromDate(now),
        hasPersistedNotesSummary: true
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
    pathLastComponent(path)
}

private func buildReadyWorktree(path: String, branch: String, now: SwiftDate) -> ProjectWorktree {
    ProjectWorktree(
        id: createWorktreeProjectID(path: path),
        name: resolveWorktreeName(path),
        path: path,
        branch: branch,
        inheritConfig: true,
        created: now,
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
        runConfigurations: sourceProject.runConfigurations,
        worktrees: [],
        mtime: sourceProject.mtime,
        size: sourceProject.size,
        checksum: "worktree:\(worktree.path)",
        isGitRepository: sourceProject.isGitRepository,
        gitCommits: sourceProject.gitCommits,
        gitLastCommit: sourceProject.gitLastCommit,
        gitLastCommitMessage: sourceProject.gitLastCommitMessage,
        gitDaily: sourceProject.gitDaily,
        notesSummary: sourceProject.notesSummary,
        created: worktree.created,
        checked: now,
        hasPersistedNotesSummary: sourceProject.hasPersistedNotesSummary
    )
}

private func buildSyncedWorktrees(
    existingWorktrees: [ProjectWorktree],
    gitWorktrees: [NativeGitWorktree],
    preservedLiveWorktrees: [ProjectWorktree] = [],
    promotedPendingWorktrees: [ProjectWorktree] = []
) -> [ProjectWorktree] {
    let existingByPath = Dictionary(uniqueKeysWithValues: existingWorktrees.map { (normalizePathForCompare($0.path), $0) })
    let promotedPendingByPath = Dictionary(uniqueKeysWithValues: promotedPendingWorktrees.map {
        (normalizePathForCompare($0.path), $0)
    })
    let now = swiftDateFromDate(Date())
    var mergedWorktrees = gitWorktrees
        .map { item -> ProjectWorktree in
            let normalizedPath = normalizePathForCompare(item.path)
            let existing = existingByPath[normalizedPath] ?? promotedPendingByPath[normalizedPath]
            return ProjectWorktree(
                id: existing?.id ?? createWorktreeProjectID(path: item.path),
                name: existing?.name ?? resolveWorktreeName(item.path),
                path: item.path,
                branch: item.branch,
                baseBranch: existing?.baseBranch,
                inheritConfig: existing?.inheritConfig ?? true,
                created: existing?.created ?? now,
                updatedAt: existing?.updatedAt
            )
        }
    for worktree in preservedLiveWorktrees where !mergedWorktrees.contains(where: {
        normalizePathForCompare($0.path) == normalizePathForCompare(worktree.path)
    }) {
        mergedWorktrees.append(
            ProjectWorktree(
                id: worktree.id,
                name: worktree.name,
                path: worktree.path,
                branch: worktree.branch,
                baseBranch: worktree.baseBranch,
                inheritConfig: worktree.inheritConfig,
                created: worktree.created,
                updatedAt: worktree.updatedAt
            )
        )
    }
    return mergedWorktrees.sorted { $0.path < $1.path }
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
