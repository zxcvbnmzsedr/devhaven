import Foundation
import Observation
import Darwin

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

private struct WorkspaceProjectTreeProjectionCacheEntry {
    let revision: Int
    let projection: WorkspaceProjectTreeDisplayProjection
}

private struct WorkspaceAlignmentGroupsCacheEntry {
    let revision: Int
    let groups: [WorkspaceAlignmentGroupProjection]
}

private struct WorkspaceSidebarGroupIdentity: Hashable {
    let id: String
    let normalizedPath: String
    let transientKind: Project.TransientWorkspaceKind?
}

private struct WorkspaceEditorBatchCloseState {
    let projectPath: String
    let remainingTabIDs: [String]
}

private struct WorkspaceProjectTreeDirectoryLoadResult: Sendable {
    let directoryPath: String
    let childrenByDirectoryPath: [String: [WorkspaceProjectTreeNode]]

    var directChildCount: Int {
        childrenByDirectoryPath[directoryPath]?.count ?? 0
    }

    var loadedDirectoryCount: Int {
        childrenByDirectoryPath.count
    }
}

private final class WorkspaceDirectoryWatcher {
    private let source: DispatchSourceFileSystemObject
    private var isStopped = false

    init?(
        directoryPath: String,
        queue: DispatchQueue = .main,
        onEvent: @escaping @Sendable () -> Void
    ) {
        let fileDescriptor = open(directoryPath, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            return nil
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke],
            queue: queue
        )
        source.setEventHandler(handler: onEvent)
        source.setCancelHandler {
            close(fileDescriptor)
        }
        source.resume()
        self.source = source
    }

    deinit {
        stop()
    }

    func stop() {
        guard !isStopped else {
            return
        }
        isStopped = true
        source.cancel()
    }
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
    @ObservationIgnored private let workspaceProjectTreeDiagnostics: WorkspaceProjectTreeDiagnostics
    @ObservationIgnored private let terminalCommandRunner: @Sendable (String, [String]) throws -> Void
    @ObservationIgnored private let worktreeService: any NativeWorktreeServicing
    @ObservationIgnored private let worktreeEnvironmentService: any NativeWorktreeEnvironmentServicing
    @ObservationIgnored private let gitRepositoryService: NativeGitRepositoryService
    @ObservationIgnored private let gitHubRepositoryService: NativeGitHubRepositoryService
    @ObservationIgnored private let workspaceFileSystemService: WorkspaceFileSystemService
    @ObservationIgnored private let agentSignalStore: WorkspaceAgentSignalStore
    @ObservationIgnored private let runManager: any WorkspaceRunManaging
    @ObservationIgnored private let workspaceRestoreCoordinator: WorkspaceRestoreCoordinator
    @ObservationIgnored private let workspaceAlignmentRootStore: WorkspaceAlignmentRootStore
    @ObservationIgnored private var workspacePaneSnapshotProvider: WorkspacePaneSnapshotProvider?
    @ObservationIgnored private var projectDocumentLoadTask: Task<Void, Never>?
    @ObservationIgnored private var projectNotesSummaryBackfillTask: Task<Void, Never>?
    @ObservationIgnored private var projectDocumentLoadRevision = 0
    @ObservationIgnored private var isAgentSignalObservationStarted = false
    @ObservationIgnored private var lastAppliedAgentSignalSnapshotsByTerminalSessionID: [String: WorkspaceAgentSessionSignal] = [:]
    @ObservationIgnored private var lastAppliedAgentSignalProjectPaths: Set<String> = []
    @ObservationIgnored private var displayProjectCacheByLookupKey: [DisplayProjectLookupKey: Project?] = [:]
    @ObservationIgnored private var cachedCodexDisplayCandidates: [WorkspaceAgentDisplayCandidate] = []
    @ObservationIgnored private var workspacePendingEditorBatchCloseState: WorkspaceEditorBatchCloseState?
    @ObservationIgnored private var workspaceEditorDirectoryWatchersByProjectPath: [String: [String: WorkspaceDirectoryWatcher]] = [:]
    @ObservationIgnored private var workspaceProjectTreeRefreshTasksByProjectPath: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var workspaceProjectTreeRefreshGenerationByProjectPath: [String: Int] = [:]
    @ObservationIgnored private var workspaceWorktreeRefreshTasksByRootProjectPath: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var projectsByNormalizedPath: [String: Project] = [:]
    @ObservationIgnored private var workspaceSessionIndexByNormalizedPath: [String: Int] = [:]
    @ObservationIgnored private var workspaceSidebarProjectionCache: WorkspaceSidebarProjectionCacheEntry?
    @ObservationIgnored private var workspaceProjectTreeProjectionCacheByProjectPath: [String: WorkspaceProjectTreeProjectionCacheEntry] = [:]
    @ObservationIgnored private var workspaceAlignmentGroupsCache: WorkspaceAlignmentGroupsCacheEntry?
    @ObservationIgnored private var workspaceToastDismissTask: Task<Void, Never>?

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
            displayProjectCacheByLookupKey.removeAll()
            rebuildWorkspaceSessionIndex()
            syncMountedWorkspaceProjectPathAfterSessionMutation()
            refreshCodexDisplayCandidates()
        }
    }
    public var activeWorkspaceProjectPath: String? {
        didSet {
            noteWorkspaceSidebarProjectionMutation(from: oldValue, to: activeWorkspaceProjectPath)
            syncMountedWorkspaceProjectPath(
                afterChangingActiveWorkspaceFrom: oldValue,
                to: activeWorkspaceProjectPath
            )
            refreshCodexDisplayCandidates()
        }
    }
    private var hiddenMountedWorkspaceProjectPath: String?
    public var workspaceSideToolWindowState: WorkspaceSideToolWindowState
    public var workspaceBottomToolWindowState: WorkspaceBottomToolWindowState
    public var workspaceFocusedArea: WorkspaceFocusedArea
    public var workspacePendingEditorCloseRequest: WorkspaceEditorCloseRequest?
    private var workspaceProjectTreeStatesByProjectPath: [String: WorkspaceProjectTreeState]
    private var workspaceEditorTabsByProjectPath: [String: [WorkspaceEditorTabState]]
    private var workspaceEditorPresentationByProjectPath: [String: WorkspaceEditorPresentationState]
    private var workspaceEditorRuntimeSessionsByProjectPath: [String: [String: WorkspaceEditorRuntimeSessionState]]
    private var workspaceDiffTabsByProjectPath: [String: [WorkspaceDiffTabState]]
    private var workspaceSelectedPresentedTabByProjectPath: [String: WorkspacePresentedTabSelection] {
        didSet {
            refreshCodexDisplayCandidates()
        }
    }
    private var attentionStateByProjectPath: [String: WorkspaceAttentionState] {
        didSet {
            noteWorkspaceSidebarProjectionMutation(from: oldValue, to: attentionStateByProjectPath)
            refreshCodexDisplayCandidates()
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
    private var workspaceGitHubViewModels: [String: WorkspaceGitHubViewModel]
    private var workspaceDiffTabViewModels: [String: WorkspaceDiffTabViewModel]
    public private(set) var workspaceSidebarProjectionRevision: Int
    public private(set) var codexDisplayCandidatesRevision: Int
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
    public private(set) var workspaceProjectTreeRefreshingProjectPaths: Set<String>
    public private(set) var workspaceToastMessage: String?
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
        workspaceProjectTreeDiagnostics: WorkspaceProjectTreeDiagnostics = .shared,
        terminalCommandRunner: (@Sendable (String, [String]) throws -> Void)? = nil,
        worktreeService: (any NativeWorktreeServicing)? = nil,
        worktreeEnvironmentService: (any NativeWorktreeEnvironmentServicing)? = nil,
        gitRepositoryService: NativeGitRepositoryService = NativeGitRepositoryService(),
        gitHubRepositoryService: NativeGitHubRepositoryService = NativeGitHubRepositoryService(),
        workspaceFileSystemService: WorkspaceFileSystemService = WorkspaceFileSystemService(),
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
        self.workspaceProjectTreeDiagnostics = workspaceProjectTreeDiagnostics
        self.terminalCommandRunner = terminalCommandRunner ?? Self.runTerminalCommand
        self.worktreeService = worktreeService ?? NativeGitWorktreeService()
        self.worktreeEnvironmentService = worktreeEnvironmentService ?? NativeWorktreeEnvironmentService()
        self.gitRepositoryService = gitRepositoryService
        self.gitHubRepositoryService = gitHubRepositoryService
        self.workspaceFileSystemService = workspaceFileSystemService
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
        self.hiddenMountedWorkspaceProjectPath = nil
        self.workspaceSideToolWindowState = WorkspaceSideToolWindowState()
        self.workspaceBottomToolWindowState = WorkspaceBottomToolWindowState()
        self.workspaceFocusedArea = .terminal
        self.workspacePendingEditorCloseRequest = nil
        self.workspacePendingEditorBatchCloseState = nil
        self.workspaceProjectTreeStatesByProjectPath = [:]
        self.workspaceEditorTabsByProjectPath = [:]
        self.workspaceEditorPresentationByProjectPath = [:]
        self.workspaceEditorRuntimeSessionsByProjectPath = [:]
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
        self.workspaceGitHubViewModels = [:]
        self.workspaceDiffTabViewModels = [:]
        self.workspaceSidebarProjectionRevision = 0
        self.codexDisplayCandidatesRevision = 0
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
        self.workspaceProjectTreeRefreshingProjectPaths = []
        self.workspaceToastMessage = nil
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

    public var projectListSortOrder: ProjectListSortOrder {
        snapshot.appState.settings.projectListSortOrder
    }

    public var workspaceSidebarWidth: Double {
        snapshot.appState.settings.workspaceSidebarWidth
    }

    public var visibleProjects: [Project] {
        let hidden = Set(snapshot.appState.recycleBin)
        return snapshot.projects.filter { !hidden.contains($0.path) }
    }

    public var filteredProjects: [Project] {
        sortProjects(visibleProjects.filter(matchesAllFilters))
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

    public var mountedWorkspaceProjectPath: String? {
        if let activeWorkspaceProjectPath {
            return canonicalWorkspaceSessionPath(for: activeWorkspaceProjectPath)
        }
        if let hiddenMountedWorkspaceProjectPath {
            return canonicalWorkspaceSessionPath(for: hiddenMountedWorkspaceProjectPath)
        }
        return nil
    }

    public var activeWorkspaceProjectTreeProject: Project? {
        if let activeWorkspaceProject {
            return activeWorkspaceProject
        }
        guard let session = activeWorkspaceSession,
              let workspaceRootContext = session.workspaceRootContext
        else {
            return nil
        }
        return .workspaceRoot(name: workspaceRootContext.workspaceName, path: session.projectPath)
    }

    public var openWorkspaceProjectPaths: [String] {
        openWorkspaceSessions.map { normalizePathForCompare($0.projectPath) }
    }

    public var openWorkspaceRootProjectPaths: [String] {
        orderedOpenWorkspaceRootProjectPaths()
    }

    public var openWorkspaceProjects: [Project] {
        openWorkspaceSessions.compactMap { resolveDisplayProject(for: $0.projectPath, rootProjectPath: $0.rootProjectPath) }
    }

    public var availableWorkspaceProjects: [Project] {
        let openedPaths = Set(openWorkspaceRootProjectPaths.map(normalizePathForCompare))
        return visibleProjects.filter { !openedPaths.contains(normalizePathForCompare($0.path)) }
    }

    public var workspaceAlignmentProjectOptions: [Project] {
        visibleProjects.filter { !$0.isQuickTerminal }
    }

    public var workspaceSidebarGroups: [WorkspaceSidebarProjectGroup] {
        let showsInAppNotifications = snapshot.appState.settings.workspaceInAppNotificationsEnabled
        let moveNotifiedWorktreeToTop = snapshot.appState.settings.moveNotifiedWorktreeToTop
        let collapsedProjectPaths = Set(
            snapshot.appState.settings.collapsedWorkspaceSidebarProjectPaths.map(normalizePathForCompare)
        )
        let projectsByNormalizedPath = self.projectsByNormalizedPath

        return orderedWorkspaceSidebarGroupIdentities().compactMap { identity in
            if let transientKind = identity.transientKind {
                guard let session = openWorkspaceSessions.first(where: {
                    workspaceSidebarGroupIdentity(for: $0)?.id == identity.id
                }) else {
                    return nil
                }
                let attention = workspaceAttentionState(for: session.projectPath)
                let agentOverrides = agentDisplayOverridesByProjectPath[normalizePathForCompare(session.projectPath)] ?? [:]
                let preferredPaneIDs = preferredSidebarAgentPaneIDs(for: session)
                let transientProject = switch transientKind {
                case .workspaceRoot:
                    Project.workspaceRoot(
                        name: session.workspaceRootContext?.workspaceName ?? pathLastComponent(session.projectPath),
                        path: session.projectPath
                    )
                case .quickTerminal:
                    Project.quickTerminal(at: session.projectPath)
                case .directoryWorkspace:
                    session.transientDisplayProject ?? Project.directoryWorkspace(at: session.projectPath)
                }
                return WorkspaceSidebarProjectGroup(
                    rootProject: transientProject,
                    worktrees: [],
                    isWorktreeListExpanded: true,
                    isActive: normalizedPathsMatch(activeWorkspaceProjectPath, session.projectPath),
                    notifications: showsInAppNotifications ? (attention?.notifications ?? []) : [],
                    unreadNotificationCount: showsInAppNotifications ? (attention?.unreadCount ?? 0) : 0,
                    taskStatus: attention?.taskStatus,
                    agentState: resolvedSidebarAgentState(
                        attention: attention,
                        overridesByPaneID: agentOverrides,
                        preferredPaneIDs: preferredPaneIDs
                    ),
                    agentPhase: resolvedSidebarAgentPhase(
                        attention: attention,
                        overridesByPaneID: agentOverrides,
                        preferredPaneIDs: preferredPaneIDs
                    ),
                    agentAttention: resolvedSidebarAgentAttention(
                        attention: attention,
                        overridesByPaneID: agentOverrides,
                        preferredPaneIDs: preferredPaneIDs
                    ),
                    agentSummary: resolvedSidebarAgentSummary(
                        attention: attention,
                        overridesByPaneID: agentOverrides,
                        preferredPaneIDs: preferredPaneIDs
                    ),
                    agentKind: resolvedSidebarAgentKind(
                        attention: attention,
                        overridesByPaneID: agentOverrides,
                        preferredPaneIDs: preferredPaneIDs
                    )
                )
            }

            let rootPath = identity.normalizedPath
            guard let rootProject = projectsByNormalizedPath[rootPath] else {
                return nil
            }
            let worktrees = orderedSidebarWorktreeItems(
                for: rootProject,
                rootProjectPath: rootPath,
                showsInAppNotifications: showsInAppNotifications,
                moveNotifiedWorktreeToTop: moveNotifiedWorktreeToTop
            )
            let rootAttention = workspaceAttentionState(for: rootPath)
            let rootAgentOverrides = agentDisplayOverridesByProjectPath[rootPath] ?? [:]
            let rootSession = openWorkspaceSessions.first(where: {
                normalizePathForCompare($0.projectPath) == rootPath &&
                    normalizePathForCompare($0.rootProjectPath) == rootPath
            })
            let rootPreferredPaneIDs = preferredSidebarAgentPaneIDs(for: rootSession)
            let rootAgentState = resolvedSidebarAgentState(
                attention: rootAttention,
                overridesByPaneID: rootAgentOverrides,
                preferredPaneIDs: rootPreferredPaneIDs
            )
            let rootAgentPhase = resolvedSidebarAgentPhase(
                attention: rootAttention,
                overridesByPaneID: rootAgentOverrides,
                preferredPaneIDs: rootPreferredPaneIDs
            )
            let rootAgentAttention = resolvedSidebarAgentAttention(
                attention: rootAttention,
                overridesByPaneID: rootAgentOverrides,
                preferredPaneIDs: rootPreferredPaneIDs
            )
            let rootAgentSummary = resolvedSidebarAgentSummary(
                attention: rootAttention,
                overridesByPaneID: rootAgentOverrides,
                preferredPaneIDs: rootPreferredPaneIDs
            )
            let rootAgentKind = resolvedSidebarAgentKind(
                attention: rootAttention,
                overridesByPaneID: rootAgentOverrides,
                preferredPaneIDs: rootPreferredPaneIDs
            )
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
            let isGroupActive = normalizedPathsMatch(activeWorkspaceProjectPath, rootPath) || worktrees.contains(where: \.isActive)
            let groupAgentProjection = makeGroupAgentProjection(
                rootIsActive: normalizedPathsMatch(activeWorkspaceProjectPath, rootPath),
                rootAgentState: rootAgentState,
                rootAgentPhase: rootAgentPhase,
                rootAgentAttention: rootAgentAttention,
                rootAgentSummary: rootAgentSummary,
                rootAgentKind: rootAgentKind,
                rootAgentUpdatedAt: resolvedSidebarAgentUpdatedAt(
                    attention: rootAttention,
                    overridesByPaneID: rootAgentOverrides,
                    preferredPaneIDs: rootPreferredPaneIDs
                ),
                worktrees: worktrees
            )
            return WorkspaceSidebarProjectGroup(
                rootProject: rootProject,
                worktrees: worktrees,
                isWorktreeListExpanded: !collapsedProjectPaths.contains(rootPath),
                isActive: isGroupActive,
                currentBranch: currentBranchByProjectPath[rootPath],
                notifications: notifications,
                unreadNotificationCount: unreadNotificationCount,
                taskStatus: makeGroupTaskStatus(
                    rootProjectPath: rootPath,
                    rootAttention: rootAttention,
                    worktrees: worktrees
                ),
                agentState: groupAgentProjection?.state,
                agentPhase: groupAgentProjection?.phase,
                agentAttention: groupAgentProjection?.attention,
                agentSummary: groupAgentProjection?.summary,
                agentKind: groupAgentProjection?.kind,
                agentUpdatedAt: groupAgentProjection?.updatedAt
            )
        }
    }

    public var workspaceAlignmentGroups: [WorkspaceAlignmentGroupProjection] {
        if let cache = workspaceAlignmentGroupsCache,
           cache.revision == workspaceSidebarProjectionRevision {
            return cache.groups
        }

        let projectsByNormalizedPath = self.projectsByNormalizedPath
        let activeWorkspaceRootGroupID = activeWorkspaceSession?.workspaceRootContext?.workspaceID
        let activeWorkspaceOwnedGroupID = activeWorkspaceSession?.workspaceAlignmentGroupID
        let normalizedActiveWorkspaceProjectPath = normalizedOptionalPathForCompare(activeWorkspaceProjectPath)
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
                let isActive = isActiveWorkspaceAlignmentMember(
                    groupID: definition.id,
                    memberProjectPath: normalizedProjectPath,
                    status: status,
                    openTarget: openTarget,
                    normalizedActiveWorkspaceProjectPath: normalizedActiveWorkspaceProjectPath,
                    activeWorkspaceOwnedGroupID: activeWorkspaceOwnedGroupID
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
                    openTarget: openTarget,
                    isActive: isActive
                )
            }
            let isActive = activeWorkspaceRootGroupID == definition.id ||
                activeWorkspaceOwnedGroupID == definition.id ||
                members.contains(where: \.isActive)
            return WorkspaceAlignmentGroupProjection(
                definition: definition,
                members: members,
                isActive: isActive
            )
        }
        workspaceAlignmentGroupsCache = WorkspaceAlignmentGroupsCacheEntry(
            revision: workspaceSidebarProjectionRevision,
            groups: groups
        )
        return groups
    }

    private func isActiveWorkspaceAlignmentMember(
        groupID: String,
        memberProjectPath: String,
        status: WorkspaceAlignmentMemberStatus,
        openTarget: WorkspaceAlignmentOpenTarget,
        normalizedActiveWorkspaceProjectPath: String?,
        activeWorkspaceOwnedGroupID: String?
    ) -> Bool {
        guard let normalizedActiveWorkspaceProjectPath else {
            return false
        }

        let normalizedMemberProjectPath = normalizePathForCompare(memberProjectPath)
        let normalizedOpenTargetPath = normalizePathForCompare(openTarget.path)

        if let activeWorkspaceOwnedGroupID {
            guard activeWorkspaceOwnedGroupID == groupID else {
                return false
            }
            return normalizedActiveWorkspaceProjectPath == normalizedOpenTargetPath ||
                normalizedActiveWorkspaceProjectPath == normalizedMemberProjectPath
        }

        guard normalizedActiveWorkspaceProjectPath == normalizedOpenTargetPath else {
            return false
        }

        switch openTarget {
        case .worktree:
            return true
        case .project:
            guard case .aligned = status else {
                return false
            }
            return normalizedActiveWorkspaceProjectPath == normalizedMemberProjectPath
        }
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
        attentionStateByProjectPath[normalizePathForCompare(projectPath)]
    }

    public func workspaceRunConsoleState(for projectPath: String) -> WorkspaceRunConsoleState? {
        workspaceRunConsoleStateByProjectPath[normalizePathForCompare(projectPath)]
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
        guard let session = workspaceSession(for: projectPath) else {
            return
        }

        let normalizedProjectPath = normalizePathForCompare(projectPath)
        var attention = attentionStateByProjectPath[normalizedProjectPath] ?? WorkspaceAttentionState()
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
        attentionStateByProjectPath[normalizedProjectPath] = attention
    }

    public func updateWorkspaceTaskStatus(
        projectPath: String,
        paneID: String,
        status: WorkspaceTaskStatus
    ) {
        let normalizedProjectPath = normalizePathForCompare(projectPath)
        var attention = attentionStateByProjectPath[normalizedProjectPath] ?? WorkspaceAttentionState()
        let previousAttention = attention
        attention.setTaskStatus(status, for: paneID)
        guard attention != previousAttention else {
            return
        }
        attentionStateByProjectPath[normalizedProjectPath] = attention
    }

    public func recordAgentSignal(_ signal: WorkspaceAgentSessionSignal) {
        let normalizedProjectPath = normalizePathForCompare(signal.projectPath)
        guard openWorkspaceProjectPaths.contains(normalizedProjectPath) else {
            return
        }
        let normalizedSignal = normalizedAgentSignal(signal)
        var attention = attentionStateByProjectPath[normalizedProjectPath] ?? WorkspaceAttentionState()
        let previousAttention = attention
        applyAgentSignal(normalizedSignal, to: &attention)
        guard attention != previousAttention else {
            return
        }
        invalidateAppliedAgentSignalCache()
        attentionStateByProjectPath[normalizedSignal.projectPath] = attention
    }

    public func clearAgentSignal(projectPath: String, paneID: String) {
        let normalizedProjectPath = normalizePathForCompare(projectPath)
        guard var attention = attentionStateByProjectPath[normalizedProjectPath] else {
            return
        }
        let previousAttention = attention
        attention.clearAgentState(for: paneID)
        guard attention != previousAttention else {
            return
        }
        invalidateAppliedAgentSignalCache()
        attentionStateByProjectPath[normalizedProjectPath] = attention
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
        invalidateAppliedAgentSignalCache()
    }

    public func refreshWorkspaceAgentSignals() {
        applyAgentSignalSnapshots(agentSignalStore.currentSnapshots)
    }

    public func codexDisplayCandidates() -> [WorkspaceAgentDisplayCandidate] {
        refreshCodexDisplayCandidates()
        return cachedCodexDisplayCandidates
    }

    private func refreshCodexDisplayCandidates() {
        let candidates: [WorkspaceAgentDisplayCandidate]
        if let activeWorkspaceProjectPath,
           openWorkspaceProjectPaths.contains(normalizePathForCompare(activeWorkspaceProjectPath)),
           let controller = workspaceController(for: activeWorkspaceProjectPath),
           case let .terminal(selectedTerminalTabID)? = resolvedWorkspacePresentedTabSelection(
               for: activeWorkspaceProjectPath,
               controller: controller
           ),
           let selectedTab = controller.tabs.first(where: { $0.id == selectedTerminalTabID }),
           let attention = workspaceAttentionState(for: activeWorkspaceProjectPath) {
            let visiblePaneIDs = Set(selectedTab.leaves.map(\.id))
            candidates = attention.agentStateByPaneID.compactMap { entry -> WorkspaceAgentDisplayCandidate? in
                let (paneID, state) = entry
                guard visiblePaneIDs.contains(paneID),
                      (state == .running || state == .waiting),
                      attention.agentKindByPaneID[paneID] == .codex
                else {
                    return nil
                }
                return WorkspaceAgentDisplayCandidate(
                    projectPath: activeWorkspaceProjectPath,
                    paneID: paneID,
                    signalSessionID: attention.agentSessionIDByPaneID[paneID],
                    signalState: state,
                    signalPhase: attention.agentPhaseByPaneID[paneID],
                    signalAttention: attention.agentAttentionByPaneID[paneID],
                    signalUpdatedAt: attention.agentUpdatedAtByPaneID[paneID]
                )
            }
        } else {
            candidates = []
        }
        let sortedCandidates = WorkspaceAgentDisplayCandidate.observationStableSorted(candidates)
        guard cachedCodexDisplayCandidates != sortedCandidates else {
            return
        }
        cachedCodexDisplayCandidates = sortedCandidates
        codexDisplayCandidatesRevision &+= 1
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
        let normalizedProjectPath = normalizePathForCompare(projectPath)
        guard var attention = attentionStateByProjectPath[normalizedProjectPath] else {
            return
        }
        attention.markNotificationsRead(for: paneID)
        attentionStateByProjectPath[normalizedProjectPath] = attention
    }

    public func focusWorkspaceNotification(_ notification: WorkspaceTerminalNotification) {
        let normalizedProjectPath = normalizePathForCompare(notification.projectPath)
        guard openWorkspaceProjectPaths.contains(normalizedProjectPath) else {
            return
        }
        activateWorkspaceProject(notification.projectPath)
        guard let controller = workspaceController(for: notification.projectPath) else {
            return
        }
        controller.selectTab(notification.tabId)
        controller.focusPane(notification.paneId)

        guard var attention = attentionStateByProjectPath[normalizedProjectPath] else {
            return
        }
        attention.markNotificationRead(id: notification.id)
        attentionStateByProjectPath[normalizedProjectPath] = attention
    }

    public var activeWorkspaceController: GhosttyWorkspaceController? {
        activeWorkspaceSession?.controller
    }

    public var activeWorkspaceRootProjectPath: String? {
        activeWorkspaceSession?.rootProjectPath
    }

    public var activeWorkspaceHasSelectedPane: Bool {
        activeWorkspaceSession?.controller.selectedPane != nil
    }

    @discardableResult
    public func createWorkspaceTerminalTab(in projectPath: String? = nil) -> WorkspaceTabState? {
        guard let resolvedProjectPath = projectPath ?? activeWorkspaceProjectPath,
              let controller = workspaceController(for: resolvedProjectPath)
        else {
            return nil
        }
        let tab = controller.createTab()
        selectWorkspacePresentedTab(.terminal(tab.id), in: resolvedProjectPath)
        return tab
    }

    @discardableResult
    public func openWorkspaceBrowserTab(
        urlString: String? = nil,
        in projectPath: String? = nil
    ) -> WorkspacePaneItemState? {
        guard let resolvedProjectPath = projectPath ?? activeWorkspaceProjectPath,
              let controller = workspaceController(for: resolvedProjectPath),
              let paneID = controller.selectedPane?.id
        else {
            return nil
        }
        let item = controller.createBrowserItem(inPane: paneID, urlString: urlString)
        if let item {
            workspaceFocusedArea = .browserPaneItem(item.id)
            workspaceSelectedPresentedTabByProjectPath[resolvedProjectPath] = .terminal(controller.selectedTabId ?? "")
            scheduleWorkspaceRestoreAutosave()
        }
        return item
    }

    public func closeWorkspaceBrowserTab(
        _ itemID: String,
        in projectPath: String? = nil
    ) {
        guard let resolvedProjectPath = projectPath ?? activeWorkspaceProjectPath,
              let controller = workspaceController(for: resolvedProjectPath),
              let context = workspacePaneItemContext(for: itemID, in: controller)
        else {
            return
        }
        controller.closePaneItem(inPane: context.pane.id, itemID: itemID)
        if let selectedBrowser = controller.selectedPane?.selectedBrowserState {
            workspaceFocusedArea = .browserPaneItem(selectedBrowser.id)
        } else {
            workspaceFocusedArea = .terminal
        }
        scheduleWorkspaceRestoreAutosave()
    }

    @discardableResult
    public func updateWorkspaceBrowserTabState(
        _ itemID: String,
        in projectPath: String? = nil,
        title: String? = nil,
        urlString: String? = nil,
        isLoading: Bool? = nil
    ) -> WorkspaceBrowserState? {
        guard let resolvedProjectPath = projectPath ?? activeWorkspaceProjectPath,
              let controller = workspaceController(for: resolvedProjectPath),
              let context = workspacePaneItemContext(for: itemID, in: controller)
        else {
            return nil
        }
        let state = controller.updateBrowserState(
            inPane: context.pane.id,
            itemID: itemID,
            title: title,
            urlString: urlString,
            isLoading: isLoading
        )
        if state != nil {
            scheduleWorkspaceRestoreAutosave()
        }
        return state
    }

    public func workspaceBrowserItemState(
        for projectPath: String? = nil,
        itemID: String
    ) -> WorkspaceBrowserState? {
        guard let controller = workspaceController(for: projectPath ?? activeWorkspaceProjectPath),
              let context = workspacePaneItemContext(for: itemID, in: controller)
        else {
            return nil
        }
        return context.item.browserState
    }

    public var activeWorkspaceRootProject: Project? {
        guard let normalizedRootProjectPath = normalizedOptionalPathForCompare(activeWorkspaceRootProjectPath) else {
            return nil
        }
        return projectsByNormalizedPath[normalizedRootProjectPath]
    }

    public var activeWorkspaceRootCurrentBranchName: String? {
        guard let rootProject = activeWorkspaceRootProject else {
            return nil
        }
        return currentBranchByProjectPath[rootProject.path]
            ?? currentBranchByProjectPath[normalizePathForCompare(rootProject.path)]
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

    public var activeWorkspaceGitHubViewModel: WorkspaceGitHubViewModel? {
        guard let rootProjectPath = activeWorkspaceRootProjectPath else {
            return nil
        }
        return workspaceGitHubViewModels[rootProjectPath]
    }

    public var activeWorkspaceState: WorkspaceSessionState? {
        activeWorkspaceController?.sessionState
    }

    public var activeWorkspaceLaunchRequest: WorkspaceTerminalLaunchRequest? {
        activeWorkspaceController?.selectedPane?.request
    }

    public var activeWorkspaceDiffTabs: [WorkspaceDiffTabState] {
        guard let activeWorkspaceProjectPath = resolvedWorkspaceProjectPathKey(nil) else {
            return []
        }
        return workspaceDiffTabsByProjectPath[activeWorkspaceProjectPath] ?? []
    }

    public var activeWorkspaceEditorTabs: [WorkspaceEditorTabState] {
        guard let activeWorkspaceProjectPath = resolvedWorkspaceProjectPathKey(nil) else {
            return []
        }
        return workspaceEditorTabsByProjectPath[activeWorkspaceProjectPath] ?? []
    }

    public var activeWorkspaceEditorPresentationState: WorkspaceEditorPresentationState? {
        guard let activeWorkspaceProjectPath = resolvedWorkspaceProjectPathKey(nil) else {
            return nil
        }
        return workspaceEditorPresentationState(for: activeWorkspaceProjectPath)
    }

    public var activeWorkspaceProjectTreeState: WorkspaceProjectTreeState? {
        guard let activeWorkspaceProjectPath = resolvedWorkspaceProjectPathKey(nil) else {
            return nil
        }
        return workspaceProjectTreeStatesByProjectPath[activeWorkspaceProjectPath]
    }

    public var activeWorkspaceProjectTreeDisplayProjection: WorkspaceProjectTreeDisplayProjection? {
        guard let activeWorkspaceProjectPath = resolvedWorkspaceProjectPathKey(nil),
              let state = workspaceProjectTreeStatesByProjectPath[activeWorkspaceProjectPath]
        else {
            return nil
        }
        return workspaceProjectTreeDisplayProjection(
            for: activeWorkspaceProjectPath,
            state: state
        )
    }

    public var activeWorkspaceProjectTreeIsRefreshing: Bool {
        guard let activeWorkspaceProjectPath = resolvedWorkspaceProjectPathKey(nil) else {
            return false
        }
        return workspaceProjectTreeRefreshingProjectPaths.contains(activeWorkspaceProjectPath)
    }

    public func workspacePresentedTabSnapshot(for projectPath: String) -> WorkspacePresentedTabSnapshot {
        let normalizedProjectPath = normalizePathForCompare(projectPath)
        let controller = workspaceController(for: normalizedProjectPath)
        let selected = resolvedWorkspacePresentedTabSelection(for: normalizedProjectPath, controller: controller)
        let terminalTabs = controller?.tabs.map { tab in
            WorkspacePresentedTabItem(
                id: tab.id,
                title: tab.title,
                selection: .terminal(tab.id),
                isSelected: selected == .terminal(tab.id)
            )
        } ?? []
        let editorTabs = (workspaceEditorTabsByProjectPath[normalizedProjectPath] ?? []).map { tab in
            WorkspacePresentedTabItem(
                id: tab.id,
                title: tab.isDirty ? "● \(tab.title)" : tab.title,
                selection: .editor(tab.id),
                isSelected: selected == .editor(tab.id),
                isPinned: tab.isPinned,
                isPreview: tab.isPreview
            )
        }
        let diffTabs = (workspaceDiffTabsByProjectPath[normalizedProjectPath] ?? []).map { tab in
            WorkspacePresentedTabItem(
                id: tab.id,
                title: tab.title,
                selection: .diff(tab.id),
                isSelected: selected == .diff(tab.id)
            )
        }
        return WorkspacePresentedTabSnapshot(
            items: terminalTabs + editorTabs + diffTabs,
            selection: selected
        )
    }

    public func workspacePresentedTabs(for projectPath: String) -> [WorkspacePresentedTabItem] {
        workspacePresentedTabSnapshot(for: projectPath).items
    }

    public func workspaceEditorPresentationState(for projectPath: String) -> WorkspaceEditorPresentationState? {
        resolvedWorkspaceEditorPresentationState(for: normalizePathForCompare(projectPath))
    }

    public func workspaceSelectedPresentedTab(for projectPath: String) -> WorkspacePresentedTabSelection? {
        workspacePresentedTabSnapshot(for: projectPath).selection
    }

    public func workspaceDiffTabViewModel(for projectPath: String, tabID: String) -> WorkspaceDiffTabViewModel? {
        let normalizedProjectPath = normalizePathForCompare(projectPath)
        guard let tab = workspaceDiffTabsByProjectPath[normalizedProjectPath]?.first(where: { $0.id == tabID }) else {
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

    public func workspaceEditorTabState(for projectPath: String, tabID: String) -> WorkspaceEditorTabState? {
        workspaceEditorTabsByProjectPath[normalizePathForCompare(projectPath)]?.first(where: { $0.id == tabID })
    }

    public func workspaceEditorRuntimeSession(
        for projectPath: String,
        tabID: String
    ) -> WorkspaceEditorRuntimeSessionState {
        let normalizedProjectPath = normalizePathForCompare(projectPath)
        guard workspaceEditorTabState(for: normalizedProjectPath, tabID: tabID) != nil else {
            return WorkspaceEditorRuntimeSessionState()
        }
        return workspaceEditorRuntimeSessionsByProjectPath[normalizedProjectPath]?[tabID]
            ?? WorkspaceEditorRuntimeSessionState()
    }

    public func updateWorkspaceEditorRuntimeSession(
        _ session: WorkspaceEditorRuntimeSessionState,
        tabID: String,
        in projectPath: String? = nil
    ) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath),
              workspaceEditorTabState(for: resolvedProjectPath, tabID: tabID) != nil
        else {
            return
        }

        var sessions = workspaceEditorRuntimeSessionsByProjectPath[resolvedProjectPath] ?? [:]
        if session == WorkspaceEditorRuntimeSessionState() {
            sessions.removeValue(forKey: tabID)
        } else {
            sessions[tabID] = session
        }
        workspaceEditorRuntimeSessionsByProjectPath[resolvedProjectPath] = sessions
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

    public var activeWorkspaceSelectedEditorTabID: String? {
        guard case let .editor(tabID)? = activeWorkspaceSelectedPresentedTab else {
            return nil
        }
        return tabID
    }

    public var isWorkspacePresented: Bool {
        activeWorkspaceSession != nil
    }

    public var canSplitActiveWorkspace: Bool {
        activeWorkspaceHasSelectedPane
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
                statusText: normalizedPathsMatch(activeWorkspaceProjectPath, session.projectPath) ? "已打开" : "可恢复"
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
                paneSnapshotProvider: workspacePaneSnapshotProvider,
                editorRestoreProvider: workspaceEditorRestoreState(for:)
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
        clearDirectoryWorkspacePresentationIfNeeded(for: normalizedPath)
        promoteWorkspaceSessionIfNeeded(for: normalizedPath, rootProjectPath: normalizedPath)
        openWorkspaceSessionIfNeeded(for: normalizedPath, rootProjectPath: normalizedPath)
        scheduleWorkspaceRootWorktreeRefreshIfNeeded(normalizedPath)
        activeWorkspaceProjectPath = canonicalWorkspaceSessionPath(for: normalizedPath) ?? normalizedPath
        selectedProjectPath = normalizedPath
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

    public func enterDirectoryWorkspace(_ path: String) {
        let normalizedPath = normalizePathForCompare(path)
        let transientProject = Project.directoryWorkspace(at: normalizedPath)

        selectedProjectPath = normalizedPath
        promoteWorkspaceSessionIfNeeded(for: normalizedPath, rootProjectPath: normalizedPath)
        openWorkspaceSessionIfNeeded(
            for: normalizedPath,
            rootProjectPath: normalizedPath,
            transientDisplayProject: transientProject
        )
        if let index = workspaceSessionIndex(for: normalizedPath) {
            openWorkspaceSessions[index].transientDisplayProject = transientProject
        }
        scheduleWorkspaceRootWorktreeRefreshIfNeeded(normalizedPath)
        activeWorkspaceProjectPath = canonicalWorkspaceSessionPath(for: normalizedPath) ?? normalizedPath
        selectedProjectPath = normalizedPath
        isDetailPanelPresented = false
        scheduleSelectedProjectDocumentRefresh()
        scheduleWorkspaceRestoreAutosave()
    }

    public func enterOrResumeWorkspace() {
        if let activeWorkspaceProjectPath,
           workspaceSession(for: activeWorkspaceProjectPath) != nil {
            activateWorkspaceProject(activeWorkspaceProjectPath)
            return
        }
        if let mountedWorkspaceProjectPath,
           workspaceSession(for: mountedWorkspaceProjectPath) != nil {
            activateWorkspaceProject(mountedWorkspaceProjectPath)
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

    public func activateWorkspaceSidebarProject(_ path: String) {
        let normalizedPath = normalizePathForCompare(path)

        // 左侧已打开项目里的 root 卡片代表“父项目”语义；
        // 当当前只打开了 worktree / workspace member，而 root 本身还没有 session 时，
        // 需要先补开 root session，避免点击后又回退到某个子 session。
        guard let project = projectsByNormalizedPath[normalizedPath],
              !project.isTransientWorkspaceProject
        else {
            activateWorkspaceProject(normalizedPath)
            return
        }

        if workspaceSessionIndex(for: normalizedPath) != nil {
            clearDirectoryWorkspacePresentationIfNeeded(for: normalizedPath)
            activateWorkspaceProject(normalizedPath)
        } else {
            enterWorkspace(normalizedPath)
        }
        scheduleWorkspaceRootWorktreeRefreshIfNeeded(normalizedPath)
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

    public func moveWorkspaceSidebarGroup(
        _ sourceGroupID: String,
        relativeTo targetGroupID: String,
        insertAfter: Bool
    ) {
        guard sourceGroupID != targetGroupID else {
            return
        }

        let sourceSessions = openWorkspaceSessions.filter {
            workspaceSidebarGroupIdentity(for: $0)?.id == sourceGroupID
        }
        guard !sourceSessions.isEmpty else {
            return
        }

        let remainingSessions = openWorkspaceSessions.filter {
            workspaceSidebarGroupIdentity(for: $0)?.id != sourceGroupID
        }
        let targetIndices = remainingSessions.enumerated().compactMap { element -> Int? in
            workspaceSidebarGroupIdentity(for: element.element)?.id == targetGroupID ? element.offset : nil
        }
        guard let insertionIndex = insertAfter
            ? targetIndices.last.map({ $0 + 1 })
            : targetIndices.first
        else {
            return
        }

        var reorderedSessions = remainingSessions
        reorderedSessions.insert(contentsOf: sourceSessions, at: insertionIndex)
        guard reorderedSessions != openWorkspaceSessions else {
            return
        }

        openWorkspaceSessions = reorderedSessions
        scheduleWorkspaceRestoreAutosave()
    }

    public func closeWorkspaceProject(_ path: String) {
        let normalizedPath = normalizePathForCompare(path)

        guard let index = workspaceSessionIndex(for: path) else {
            let groupedSessionIndices = openWorkspaceSessions.enumerated().compactMap { element -> Int? in
                let session = element.element
                guard !session.isQuickTerminal,
                      normalizePathForCompare(session.rootProjectPath) == normalizedPath
                else {
                    return nil
                }
                return element.offset
            }
            guard !groupedSessionIndices.isEmpty else {
                return
            }

            let removedPaths = Set(groupedSessionIndices.map { openWorkspaceSessions[$0].projectPath })
            let fallbackAnchorIndex = groupedSessionIndices.min() ?? 0

            openWorkspaceSessions.removeAll { removedPaths.contains($0.projectPath) }
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

            if let currentActiveWorkspaceProjectPath = activeWorkspaceProjectPath,
               removedPaths.contains(currentActiveWorkspaceProjectPath) {
                let fallbackIndex = min(fallbackAnchorIndex, openWorkspaceSessions.count - 1)
                let fallbackPath = openWorkspaceSessions[fallbackIndex].projectPath
                activeWorkspaceProjectPath = fallbackPath
                selectedProjectPath = fallbackPath
                isDetailPanelPresented = false
                scheduleSelectedProjectDocumentRefresh()
            }
            scheduleWorkspaceRestoreAutosave()
            return
        }

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
                        return sessionPathMatches || isWorkspaceSessionOwnedByProjectPool($0, rootProjectPath: path)
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

    public func closeWorkspaceSession(_ path: String) {
        guard let index = workspaceSessionIndex(for: path) else {
            return
        }

        let removedPaths = Set([path])
        openWorkspaceSessions.remove(at: index)
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

        if let currentActiveWorkspaceProjectPath = activeWorkspaceProjectPath,
           removedPaths.contains(currentActiveWorkspaceProjectPath) {
            let fallbackIndex = min(index, openWorkspaceSessions.count - 1)
            let fallbackPath = openWorkspaceSessions[fallbackIndex].projectPath
            activeWorkspaceProjectPath = fallbackPath
            selectedProjectPath = fallbackPath
            isDetailPanelPresented = false
            scheduleSelectedProjectDocumentRefresh()
        }
        scheduleWorkspaceRestoreAutosave()
    }

    public func closeWorkspaceProjectWithFeedback(_ path: String) {
        guard workspaceSessionIndex(for: path) != nil else {
            return
        }
        let feedbackMessage = workspaceCloseFeedbackMessage(for: path)
        closeWorkspaceProject(path)
        if let feedbackMessage {
            presentWorkspaceToast(feedbackMessage)
        }
    }

    public func closeWorkspaceSessionWithFeedback(_ path: String) {
        guard workspaceSessionIndex(for: path) != nil else {
            return
        }
        let feedbackMessage = workspaceCloseFeedbackMessage(for: path, includeRegularProject: true)
        closeWorkspaceSession(path)
        if let feedbackMessage {
            presentWorkspaceToast(feedbackMessage)
        }
    }

    public func presentWorkspaceToast(
        _ message: String,
        duration: TimeInterval = 1.5
    ) {
        workspaceToastDismissTask?.cancel()
        workspaceToastMessage = message
        guard duration > 0 else {
            workspaceToastDismissTask = nil
            return
        }
        let delayNanoseconds = UInt64(duration * 1_000_000_000)
        workspaceToastDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                guard let self else {
                    return
                }
                self.workspaceToastDismissTask = nil
                self.workspaceToastMessage = nil
            }
        }
    }

    public func dismissWorkspaceToast() {
        workspaceToastDismissTask?.cancel()
        workspaceToastDismissTask = nil
        workspaceToastMessage = nil
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
                let originalProjectPath = snapshot.projects.first(where: {
                    normalizePathForCompare($0.path) == normalizePathForCompare(projectPath)
                })?.path ?? projectPath
                selectedProjectPath = originalProjectPath
                clearDirectoryWorkspacePresentationIfNeeded(for: projectPath)
                if let index = workspaceSessionIndex(for: projectPath),
                   openWorkspaceSessions[index].workspaceAlignmentGroupID != nil {
                    openWorkspaceSessions[index].workspaceAlignmentGroupID = member.groupID
                }
                openWorkspaceSessionIfNeeded(
                    for: originalProjectPath,
                    rootProjectPath: originalProjectPath,
                    workspaceAlignmentGroupID: member.groupID
                )
                if let index = workspaceSessionIndex(for: originalProjectPath) {
                    openWorkspaceSessions[index].projectPath = originalProjectPath
                    openWorkspaceSessions[index].rootProjectPath = originalProjectPath
                }
                activeWorkspaceProjectPath = originalProjectPath
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

        guard let worktree = resolveWorkspaceWorktree(
            at: normalizedWorktreePath,
            from: normalizedRootProjectPath,
            rootProject: rootProject
        ) else {
            errorMessage = NativeWorktreeError.invalidPath("worktree 不存在或已移除").localizedDescription
            return
        }
        if workspaceAlignmentGroupID == nil {
            clearDirectoryWorkspacePresentationIfNeeded(for: worktree.path)
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
        if let index = workspaceSessionIndex(for: worktree.path),
           workspaceAlignmentGroupID != nil {
            openWorkspaceSessions[index].projectPath = worktree.path
            openWorkspaceSessions[index].rootProjectPath = rootProject.path
        }
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

    public func prepareActiveWorkspaceGitHubViewModel() {
        guard let rootProject = activeWorkspaceRootProject,
              rootProject.isGitRepository,
              let repositoryContext = activeWorkspaceGitRepositoryContext
        else {
            return
        }
        let executionPath = preferredWorkspaceGitExecutionPath(for: rootProject.path)

        if let existing = workspaceGitHubViewModels[rootProject.path] {
            existing.updateRepositoryContext(repositoryContext, executionPath: executionPath)
            return
        }

        workspaceGitHubViewModels[rootProject.path] = WorkspaceGitHubViewModel(
            repositoryContext: repositoryContext,
            executionPath: executionPath,
            client: .live(
                githubService: gitHubRepositoryService,
                gitService: gitRepositoryService
            )
        )
    }

    public func prepareActiveWorkspaceProjectTreeState() {
        guard let activeWorkspaceProjectTreeProject else {
            return
        }
        let normalizedProjectPath = normalizePathForCompare(activeWorkspaceProjectTreeProject.path)
        if workspaceProjectTreeStatesByProjectPath[normalizedProjectPath] == nil,
           !workspaceProjectTreeRefreshingProjectPaths.contains(normalizedProjectPath) {
            refreshWorkspaceProjectTree(for: normalizedProjectPath)
        }
    }

    public func refreshWorkspaceProjectTree(for projectPath: String? = nil) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath) else {
            return
        }
        scheduleWorkspaceProjectTreeRefresh(
            for: resolvedProjectPath,
            preserving: workspaceProjectTreeStatesByProjectPath[resolvedProjectPath]
        )
    }

    public func refreshWorkspaceProjectTreeNode(_ path: String?, in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath) else {
            return
        }
        // 首版先走整棵树重建，优先保证 rename/delete/create 后路径映射与展开态一致。
        scheduleWorkspaceProjectTreeRefresh(
            for: resolvedProjectPath,
            preserving: workspaceProjectTreeStatesByProjectPath[resolvedProjectPath],
            preferredSelectionPath: path
        )
    }

    public func selectWorkspaceProjectTreeNode(_ path: String?, in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath),
              var state = workspaceProjectTreeStatesByProjectPath[resolvedProjectPath]
        else {
            return
        }
        state.selectedPath = state.canonicalDisplayPath(for: path)
        workspaceProjectTreeStatesByProjectPath[resolvedProjectPath] = state
    }

    public func toggleWorkspaceProjectTreeDirectory(_ directoryPath: String, in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath),
              var state = workspaceProjectTreeStatesByProjectPath[resolvedProjectPath]
        else {
            return
        }

        let projection = workspaceProjectTreeDisplayProjection(
            for: resolvedProjectPath,
            state: state
        )
        let normalizedDirectoryPath = projection.aliasMap[normalizePathForCompare(directoryPath)]
            ?? normalizePathForCompare(directoryPath)

        if state.expandedDirectoryPaths.contains(normalizedDirectoryPath) {
            state.expandedDirectoryPaths.remove(normalizedDirectoryPath)
            state.loadingDirectoryPaths.remove(normalizedDirectoryPath)
            workspaceProjectTreeStatesByProjectPath[resolvedProjectPath] = state
            workspaceProjectTreeDiagnostics.recordDirectoryCollapsed(
                projectPath: resolvedProjectPath,
                directoryPath: normalizedDirectoryPath,
                revision: state.revision,
                expandedCount: state.expandedDirectoryPaths.count
            )
            return
        }

        state.expandedDirectoryPaths.insert(normalizedDirectoryPath)
        if let existingChildren = state.childrenByDirectoryPath[normalizedDirectoryPath] {
            state.errorMessage = nil
            workspaceProjectTreeStatesByProjectPath[resolvedProjectPath] = state.canonicalizedForDisplay()
            errorMessage = nil
            preloadWorkspaceProjectTreeVisibleChainsIfNeeded(
                for: normalizedDirectoryPath,
                projectRootPath: resolvedProjectPath,
                children: existingChildren
            )
            return
        }

        state.loadingDirectoryPaths.insert(normalizedDirectoryPath)
        state.errorMessage = nil
        let loadingRevision = state.revision
        workspaceProjectTreeStatesByProjectPath[resolvedProjectPath] = state
        errorMessage = nil
        workspaceProjectTreeDiagnostics.recordDirectoryLoadStarted(
            projectPath: resolvedProjectPath,
            directoryPath: normalizedDirectoryPath,
            revision: loadingRevision
        )

        let projectRootPath = resolvedProjectPath
        let fileSystemService = workspaceFileSystemService
        let startTime = ProcessInfo.processInfo.systemUptime
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let result = try Self.loadWorkspaceProjectTreeChildrenSnapshot(
                    service: fileSystemService,
                    directoryPath: normalizedDirectoryPath,
                    projectRootPath: projectRootPath
                )
                await self?.finishWorkspaceProjectTreeDirectoryLoadSuccess(
                    for: resolvedProjectPath,
                    directoryPath: normalizedDirectoryPath,
                    result: result,
                    startTime: startTime
                )
            } catch {
                let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await self?.finishWorkspaceProjectTreeDirectoryLoadFailure(
                    for: resolvedProjectPath,
                    directoryPath: normalizedDirectoryPath,
                    errorDescription: errorDescription,
                    startTime: startTime
                )
            }
        }
    }

    private func finishWorkspaceProjectTreeDirectoryLoadSuccess(
        for projectPath: String,
        directoryPath: String,
        result: WorkspaceProjectTreeDirectoryLoadResult,
        startTime: TimeInterval
    ) {
        guard var latestState = workspaceProjectTreeStatesByProjectPath[projectPath] else {
            return
        }

        latestState.loadingDirectoryPaths.remove(directoryPath)
        for (path, children) in result.childrenByDirectoryPath {
            latestState.childrenByDirectoryPath[path] = children
        }
        latestState.errorMessage = nil
        latestState.advanceStructureRevision()
        let finalizedState = latestState.canonicalizedForDisplay()
        workspaceProjectTreeStatesByProjectPath[projectPath] = finalizedState
        errorMessage = nil
        workspaceProjectTreeDiagnostics.recordDirectoryLoadFinished(
            projectPath: projectPath,
            directoryPath: directoryPath,
            revision: finalizedState.revision,
            durationMs: elapsedMilliseconds(since: startTime),
            loadedDirectoryCount: result.loadedDirectoryCount,
            directChildCount: result.directChildCount,
            status: "success",
            errorDescription: nil
        )
    }

    private func finishWorkspaceProjectTreeDirectoryLoadFailure(
        for projectPath: String,
        directoryPath: String,
        errorDescription: String,
        startTime: TimeInterval
    ) {
        guard var latestState = workspaceProjectTreeStatesByProjectPath[projectPath] else {
            return
        }

        latestState.loadingDirectoryPaths.remove(directoryPath)
        latestState.errorMessage = errorDescription
        workspaceProjectTreeStatesByProjectPath[projectPath] = latestState
        errorMessage = latestState.errorMessage
        workspaceProjectTreeDiagnostics.recordDirectoryLoadFinished(
            projectPath: projectPath,
            directoryPath: directoryPath,
            revision: latestState.revision,
            durationMs: elapsedMilliseconds(since: startTime),
            loadedDirectoryCount: 0,
            directChildCount: 0,
            status: "failed",
            errorDescription: latestState.errorMessage
        )
    }

    private func preloadWorkspaceProjectTreeVisibleChainsIfNeeded(
        for directoryPath: String,
        projectRootPath: String,
        children: [WorkspaceProjectTreeNode]
    ) {
        let fileSystemService = workspaceFileSystemService
        let startRevision = workspaceProjectTreeStatesByProjectPath[projectRootPath]?.revision ?? 0
        let startTime = ProcessInfo.processInfo.systemUptime
        Task.detached(priority: .utility) { [weak self] in
            guard let self else {
                return
            }
            guard let result = try? Self.preloadWorkspaceProjectTreeVisibleChainsSnapshot(
                service: fileSystemService,
                children: children,
                projectRootPath: projectRootPath
            ), !result.isEmpty else {
                return
            }

            await MainActor.run {
                guard var latestState = self.workspaceProjectTreeStatesByProjectPath[projectRootPath] else {
                    return
                }
                var didMerge = false
                for (path, loadedChildren) in result where latestState.childrenByDirectoryPath[path] != loadedChildren {
                    latestState.childrenByDirectoryPath[path] = loadedChildren
                    didMerge = true
                }
                guard didMerge else {
                    return
                }
                latestState.advanceStructureRevision()
                let finalizedState = latestState.canonicalizedForDisplay()
                self.workspaceProjectTreeStatesByProjectPath[projectRootPath] = finalizedState
                self.workspaceProjectTreeDiagnostics.recordDirectoryLoadFinished(
                    projectPath: projectRootPath,
                    directoryPath: directoryPath,
                    revision: max(startRevision, finalizedState.revision),
                    durationMs: elapsedMilliseconds(since: startTime),
                    loadedDirectoryCount: result.count,
                    directChildCount: children.count,
                    status: "success",
                    errorDescription: nil
                )
            }
        }
    }

    private func scheduleWorkspaceProjectTreeRefresh(
        for projectPath: String,
        preserving state: WorkspaceProjectTreeState?,
        preferredSelectionPath: String? = nil
    ) {
        let normalizedProjectPath = normalizePathForCompare(projectPath)
        let nextGeneration = (workspaceProjectTreeRefreshGenerationByProjectPath[normalizedProjectPath] ?? 0) &+ 1
        workspaceProjectTreeRefreshGenerationByProjectPath[normalizedProjectPath] = nextGeneration
        workspaceProjectTreeRefreshingProjectPaths.insert(normalizedProjectPath)
        workspaceProjectTreeRefreshTasksByProjectPath[normalizedProjectPath]?.cancel()

        let fileSystemService = workspaceFileSystemService
        let startTime = ProcessInfo.processInfo.systemUptime
        workspaceProjectTreeRefreshTasksByProjectPath[normalizedProjectPath] = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let rebuiltState = try Self.buildWorkspaceProjectTreeStateSnapshot(
                    service: fileSystemService,
                    projectPath: normalizedProjectPath,
                    preserving: state
                )
                await self?.finishWorkspaceProjectTreeRefresh(
                    for: normalizedProjectPath,
                    generation: nextGeneration,
                    rebuiltState: rebuiltState,
                    preferredSelectionPath: preferredSelectionPath,
                    startTime: startTime
                )
            } catch is CancellationError {
                await self?.finishWorkspaceProjectTreeRefreshCancellation(
                    for: normalizedProjectPath,
                    generation: nextGeneration
                )
            } catch {
                let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await self?.finishWorkspaceProjectTreeRefreshFailure(
                    for: normalizedProjectPath,
                    generation: nextGeneration,
                    preserving: state,
                    errorDescription: errorDescription
                )
            }
        }
    }

    private func finishWorkspaceProjectTreeRefresh(
        for projectPath: String,
        generation: Int,
        rebuiltState: WorkspaceProjectTreeState,
        preferredSelectionPath: String?,
        startTime: TimeInterval
    ) {
        guard workspaceProjectTreeRefreshGenerationByProjectPath[projectPath] == generation else {
            return
        }

        var finalState = rebuiltState
        if let latestState = workspaceProjectTreeStatesByProjectPath[projectPath] {
            finalState.expandedDirectoryPaths = latestState.expandedDirectoryPaths
                .filter { normalizePathForCompare($0) != normalizePathForCompare(projectPath) }
                .filter { workspaceFileSystemService.directoryExists(at: $0) }
            finalState.loadingDirectoryPaths = latestState.loadingDirectoryPaths
            for (path, children) in latestState.childrenByDirectoryPath {
                guard normalizePathForCompare(path) != normalizePathForCompare(projectPath) else {
                    continue
                }
                finalState.childrenByDirectoryPath[path] = children
            }
            if preferredSelectionPath == nil,
               let latestSelectedPath = latestState.selectedPath,
               FileManager.default.fileExists(atPath: latestSelectedPath) {
                finalState.selectedPath = latestSelectedPath
            }
        }
        if let preferredSelectionPath {
            finalState.selectedPath = finalState.canonicalDisplayPath(for: preferredSelectionPath)
            if finalState.selectedPath == nil,
               FileManager.default.fileExists(atPath: preferredSelectionPath) {
                finalState.selectedPath = normalizePathForCompare(preferredSelectionPath)
            }
        }
        finalState = finalState.canonicalizedForDisplay()
        finalState.errorMessage = nil
        workspaceProjectTreeStatesByProjectPath[projectPath] = finalState
        workspaceProjectTreeRefreshingProjectPaths.remove(projectPath)
        workspaceProjectTreeRefreshTasksByProjectPath[projectPath] = nil
        errorMessage = nil
        workspaceProjectTreeDiagnostics.recordTreeRebuilt(
            projectPath: projectPath,
            revision: finalState.revision,
            durationMs: elapsedMilliseconds(since: startTime),
            rootCount: finalState.rootNodes.count,
            expandedCount: finalState.expandedDirectoryPaths.count
        )
    }

    private func finishWorkspaceProjectTreeRefreshFailure(
        for projectPath: String,
        generation: Int,
        preserving state: WorkspaceProjectTreeState?,
        errorDescription: String
    ) {
        guard workspaceProjectTreeRefreshGenerationByProjectPath[projectPath] == generation else {
            return
        }

        var fallbackState = workspaceProjectTreeStatesByProjectPath[projectPath]
            ?? state
            ?? WorkspaceProjectTreeState(rootProjectPath: projectPath)
        fallbackState.errorMessage = errorDescription
        workspaceProjectTreeStatesByProjectPath[projectPath] = fallbackState
        workspaceProjectTreeRefreshingProjectPaths.remove(projectPath)
        workspaceProjectTreeRefreshTasksByProjectPath[projectPath] = nil
        errorMessage = fallbackState.errorMessage
    }

    private func finishWorkspaceProjectTreeRefreshCancellation(
        for projectPath: String,
        generation: Int
    ) {
        guard workspaceProjectTreeRefreshGenerationByProjectPath[projectPath] == generation else {
            return
        }

        workspaceProjectTreeRefreshingProjectPaths.remove(projectPath)
        workspaceProjectTreeRefreshTasksByProjectPath[projectPath] = nil
    }

    public func openWorkspaceEditorTab(
        for filePath: String,
        in projectPath: String? = nil,
        openingPolicy: WorkspaceEditorTabOpeningPolicy = .regular
    ) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath) else {
            return
        }

        let normalizedFilePath = normalizePathForCompare(filePath)
        var tabs = workspaceEditorTabsByProjectPath[resolvedProjectPath] ?? []

        if let existingIndex = tabs.firstIndex(where: {
            normalizePathForCompare($0.filePath) == normalizedFilePath
        }) {
            let existingTabID = tabs[existingIndex].id
            var existingTab = tabs.remove(at: existingIndex)
            let previousPinnedState = existingTab.isPinned
            applyWorkspaceEditorOpeningPolicy(openingPolicy, to: &existingTab)
            reinsertWorkspaceEditorTab(
                existingTab,
                into: &tabs,
                preferredIndex: previousPinnedState == existingTab.isPinned ? existingIndex : nil
            )
            workspaceEditorTabsByProjectPath[resolvedProjectPath] = tabs
            if openingPolicy == .preview, !existingTab.isPinned {
                assignWorkspaceEditorTab(existingTabID, toActiveGroupIn: resolvedProjectPath)
            }
            activateWorkspaceEditorTab(existingTabID, in: resolvedProjectPath)
            scheduleWorkspaceRestoreAutosave()
            return
        }

        do {
            let document = try workspaceFileSystemService.loadDocument(at: normalizedFilePath)
            let reusedPreviewIndex = openingPolicy == .preview
                ? tabs.firstIndex(where: { $0.isPreview && !$0.isPinned })
                : nil
            let tabID = reusedPreviewIndex.flatMap { tabs.indices.contains($0) ? tabs[$0].id : nil }
                ?? "workspace-editor:\(UUID().uuidString.lowercased())"
            let tab = makeWorkspaceEditorTabState(
                tabID: tabID,
                projectPath: resolvedProjectPath,
                filePath: normalizedFilePath,
                document: document,
                openingPolicy: openingPolicy
            )

            if let reusedPreviewIndex {
                tabs[reusedPreviewIndex] = tab
            } else {
                reinsertWorkspaceEditorTab(tab, into: &tabs)
            }

            workspaceEditorTabsByProjectPath[resolvedProjectPath] = tabs
            if let reusedPreviewIndex, tabs.indices.contains(reusedPreviewIndex) {
                resetWorkspaceEditorRuntimeSession(tab.id, in: resolvedProjectPath)
            }
            syncWorkspaceEditorRuntimeSessions(for: resolvedProjectPath)
            syncWorkspaceEditorDirectoryWatchers(for: resolvedProjectPath)
            assignWorkspaceEditorTab(tab.id, toActiveGroupIn: resolvedProjectPath)
            activateWorkspaceEditorTab(tab.id, in: resolvedProjectPath)
            errorMessage = nil
            scheduleWorkspaceRestoreAutosave()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func previewWorkspaceProjectTreeNode(
        _ path: String,
        in projectPath: String? = nil
    ) {
        guard let itemKind = workspaceFileSystemService.itemKind(at: path) else {
            return
        }

        switch itemKind {
        case .directory:
            return
        case .file:
            openWorkspaceEditorTab(for: path, in: projectPath, openingPolicy: .preview)
        case .symlink:
            if workspaceFileSystemService.symlinkDestinationKind(at: path) == .directory {
                return
            }
            openWorkspaceEditorTab(for: path, in: projectPath, openingPolicy: .preview)
        }
    }

    public func openWorkspaceProjectTreeNode(
        _ path: String,
        in projectPath: String? = nil
    ) {
        guard let itemKind = workspaceFileSystemService.itemKind(at: path) else {
            return
        }

        switch itemKind {
        case .directory:
            return
        case .file:
            openWorkspaceEditorTab(for: path, in: projectPath, openingPolicy: .regular)
        case .symlink:
            if workspaceFileSystemService.symlinkDestinationKind(at: path) == .directory {
                return
            }
            openWorkspaceEditorTab(for: path, in: projectPath, openingPolicy: .regular)
        }
    }

    public func createWorkspaceProjectTreeItem(
        named name: String,
        isDirectory: Bool,
        under targetPath: String? = nil,
        in projectPath: String? = nil
    ) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath) else {
            return
        }

        let parentDirectoryPath = resolveWorkspaceProjectTreeTargetDirectory(
            targetPath: targetPath ?? workspaceProjectTreeStatesByProjectPath[resolvedProjectPath]?.selectedPath,
            projectPath: resolvedProjectPath
        )

        do {
            let createdNode = try (isDirectory
                ? workspaceFileSystemService.createDirectory(named: name, inDirectory: parentDirectoryPath)
                : workspaceFileSystemService.createFile(named: name, inDirectory: parentDirectoryPath))
            var preservedState = workspaceProjectTreeStatesByProjectPath[resolvedProjectPath]
                ?? WorkspaceProjectTreeState(rootProjectPath: resolvedProjectPath)
            preservedState.expandedDirectoryPaths.insert(parentDirectoryPath)
            preservedState.selectedPath = createdNode.path
            scheduleWorkspaceProjectTreeRefresh(
                for: resolvedProjectPath,
                preserving: preservedState,
                preferredSelectionPath: createdNode.path
            )
            if createdNode.isDirectory {
                selectWorkspaceProjectTreeNode(createdNode.path, in: resolvedProjectPath)
            } else {
                openWorkspaceEditorTab(for: createdNode.path, in: resolvedProjectPath)
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func renameWorkspaceProjectTreeNode(
        _ sourcePath: String,
        to newName: String,
        in projectPath: String? = nil
    ) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath) else {
            return
        }

        let normalizedSourcePath = normalizePathForCompare(sourcePath)
        let existingState = workspaceProjectTreeStatesByProjectPath[resolvedProjectPath]

        do {
            let renamedNode = try workspaceFileSystemService.renameItem(at: normalizedSourcePath, to: newName)
            remapWorkspaceEditorTabs(
                in: resolvedProjectPath,
                replacingPathPrefix: normalizedSourcePath,
                with: renamedNode.path
            )
            var preservedState = remapWorkspaceProjectTreeState(
                existingState,
                replacingPathPrefix: normalizedSourcePath,
                with: renamedNode.path
            ) ?? WorkspaceProjectTreeState(rootProjectPath: resolvedProjectPath)
            preservedState.selectedPath = renamedNode.path
            scheduleWorkspaceProjectTreeRefresh(
                for: resolvedProjectPath,
                preserving: preservedState,
                preferredSelectionPath: renamedNode.path
            )
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func trashWorkspaceProjectTreeNode(
        _ path: String,
        in projectPath: String? = nil
    ) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath) else {
            return
        }

        let normalizedPath = normalizePathForCompare(path)
        do {
            try workspaceFileSystemService.trashItem(at: normalizedPath)
            closeWorkspaceEditorTabsUnderPath(normalizedPath, in: resolvedProjectPath)
            var preservedState = workspaceProjectTreeStatesByProjectPath[resolvedProjectPath]
            preservedState?.selectedPath = nil
            scheduleWorkspaceProjectTreeRefresh(
                for: resolvedProjectPath,
                preserving: preservedState,
                preferredSelectionPath: nil
            )
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func updateWorkspaceEditorText(_ text: String, tabID: String, in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath),
              var tabs = workspaceEditorTabsByProjectPath[resolvedProjectPath],
              let index = tabs.firstIndex(where: { $0.id == tabID })
        else {
            return
        }

        let shouldPromotePreviewTab = tabs[index].isPreview && tabs[index].text != text
        let nextContentFingerprint = tabs[index].kind == .text
            ? workspaceEditorContentFingerprint(text)
            : nil
        tabs[index].text = text
        tabs[index].isDirty = nextContentFingerprint != tabs[index].savedContentFingerprint
        if shouldPromotePreviewTab {
            tabs[index].isPreview = false
        }
        workspaceEditorTabsByProjectPath[resolvedProjectPath] = tabs
        if shouldPromotePreviewTab {
            scheduleWorkspaceRestoreAutosave()
        }
    }

    public func checkWorkspaceEditorTabExternalChange(_ tabID: String, in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath),
              let tab = workspaceEditorTabsByProjectPath[resolvedProjectPath]?.first(where: { $0.id == tabID })
        else {
            return
        }

        if !workspaceFileSystemService.itemExists(at: tab.filePath) {
            updateWorkspaceEditorTab(tabID, in: resolvedProjectPath) { current in
                current.externalChangeState = .removedOnDisk
                if current.message?.isEmpty != false || isExternalEditorMessage(current.message) {
                    current.message = "文件已在磁盘上被删除，请关闭标签页或另存为新文件。"
                }
            }
            return
        }

        let diskModificationDate = workspaceFileSystemService.modificationDate(at: tab.filePath)
        let hasChangedOnDisk: Bool = {
            guard let diskModificationDate,
                  let loadedDate = tab.lastLoadedModificationDate
            else {
                return false
            }
            return abs(diskModificationDate - loadedDate) > 0.0001
        }()

        updateWorkspaceEditorTab(tabID, in: resolvedProjectPath) { current in
            if hasChangedOnDisk {
                current.externalChangeState = .modifiedOnDisk
                if current.message?.isEmpty != false || isExternalEditorMessage(current.message) {
                    current.message = current.isDirty
                        ? "检测到文件已被外部修改。为避免覆盖磁盘上的新内容，请先重新载入再决定如何处理。"
                        : "检测到文件已被外部修改，可直接重新载入同步磁盘内容。"
                }
            } else {
                current.externalChangeState = .inSync
                if isExternalEditorMessage(current.message) {
                    current.message = nil
                }
            }
        }
    }

    public func reloadWorkspaceEditorTab(_ tabID: String, in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath),
              let tab = workspaceEditorTabsByProjectPath[resolvedProjectPath]?.first(where: { $0.id == tabID })
        else {
            return
        }

        do {
            let document = try workspaceFileSystemService.loadDocument(at: tab.filePath)
            updateWorkspaceEditorTab(
                tabID,
                in: resolvedProjectPath,
                mutate: { current in
                    current.kind = document.kind
                    current.text = document.text
                    current.isEditable = document.isEditable
                    current.isDirty = false
                    current.isLoading = false
                    current.isSaving = false
                    current.externalChangeState = .inSync
                    current.message = document.message
                    current.lastLoadedModificationDate = document.modificationDate
                    current.savedContentFingerprint = document.contentFingerprint
                }
            )
            refreshWorkspaceProjectTree(for: resolvedProjectPath)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func saveWorkspaceEditorTab(_ tabID: String, in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath),
              let tab = workspaceEditorTabsByProjectPath[resolvedProjectPath]?.first(where: { $0.id == tabID }),
              tab.kind == .text
        else {
            return
        }

        guard tab.isDirty else {
            return
        }

        checkWorkspaceEditorTabExternalChange(tabID, in: resolvedProjectPath)
        guard let latestTab = workspaceEditorTabsByProjectPath[resolvedProjectPath]?.first(where: { $0.id == tabID }) else {
            return
        }
        guard latestTab.externalChangeState == .inSync || !latestTab.isDirty else {
            updateWorkspaceEditorTab(tabID, in: resolvedProjectPath) { current in
                current.isSaving = false
                current.message = current.externalChangeState == .removedOnDisk
                    ? "磁盘上的文件已被删除，当前不能直接保存覆盖。请先重新载入或另存为新文件。"
                    : "检测到磁盘文件已变化，当前保存已阻止。请先重新载入确认差异。"
            }
            errorMessage = workspaceEditorTabsByProjectPath[resolvedProjectPath]?.first(where: { $0.id == tabID })?.message
            return
        }

        updateWorkspaceEditorTab(tabID, in: resolvedProjectPath) { current in
            current.isSaving = true
            current.message = nil
        }

        do {
            let savedDocument = try workspaceFileSystemService.saveTextDocument(latestTab.text, to: latestTab.filePath)
            updateWorkspaceEditorTab(tabID, in: resolvedProjectPath) { current in
                current.kind = savedDocument.kind
                current.text = savedDocument.text
                current.isEditable = savedDocument.isEditable
                current.isDirty = false
                current.isSaving = false
                current.externalChangeState = .inSync
                current.message = savedDocument.message
                current.lastLoadedModificationDate = savedDocument.modificationDate
                current.savedContentFingerprint = savedDocument.contentFingerprint
            }
            refreshWorkspaceProjectTree(for: resolvedProjectPath)
            errorMessage = nil
        } catch {
            updateWorkspaceEditorTab(tabID, in: resolvedProjectPath) { current in
                current.isSaving = false
                current.message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func closeWorkspaceEditorTab(_ tabID: String, in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath) else {
            return
        }
        closeWorkspaceEditorTabs([tabID], in: resolvedProjectPath)
    }

    public func closeOtherWorkspaceEditorTabs(keeping tabID: String, in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath),
              let tabs = workspaceEditorTabsByProjectPath[resolvedProjectPath]
        else {
            return
        }
        let tabIDsToClose = tabs.map(\.id).filter { $0 != tabID }
        closeWorkspaceEditorTabs(tabIDsToClose, in: resolvedProjectPath)
    }

    public func closeWorkspaceEditorTabsToRight(of tabID: String, in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath),
              let tabs = workspaceEditorTabsByProjectPath[resolvedProjectPath],
              let index = tabs.firstIndex(where: { $0.id == tabID })
        else {
            return
        }
        let tabIDsToClose = tabs.suffix(from: index + 1).map(\.id)
        closeWorkspaceEditorTabs(tabIDsToClose, in: resolvedProjectPath)
    }

    public func promoteWorkspaceEditorTabToRegular(_ tabID: String, in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath),
              var tabs = workspaceEditorTabsByProjectPath[resolvedProjectPath],
              let index = tabs.firstIndex(where: { $0.id == tabID })
        else {
            return
        }

        guard tabs[index].isPreview else {
            return
        }

        tabs[index].isPreview = false
        workspaceEditorTabsByProjectPath[resolvedProjectPath] = tabs
        scheduleWorkspaceRestoreAutosave()
    }

    public func setWorkspaceEditorTabPinned(
        _ isPinned: Bool,
        tabID: String,
        in projectPath: String? = nil
    ) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath),
              var tabs = workspaceEditorTabsByProjectPath[resolvedProjectPath],
              let index = tabs.firstIndex(where: { $0.id == tabID })
        else {
            return
        }

        var tab = tabs.remove(at: index)
        let previousPinnedState = tab.isPinned
        let previousPreviewState = tab.isPreview

        tab.isPinned = isPinned
        if isPinned {
            tab.isPreview = false
        }

        guard previousPinnedState != tab.isPinned || previousPreviewState != tab.isPreview else {
            tabs.insert(tab, at: min(index, tabs.count))
            workspaceEditorTabsByProjectPath[resolvedProjectPath] = tabs
            return
        }

        let preferredIndex: Int? = isPinned ? nil : firstUnpinnedWorkspaceEditorInsertionIndex(in: tabs)
        reinsertWorkspaceEditorTab(tab, into: &tabs, preferredIndex: preferredIndex)
        workspaceEditorTabsByProjectPath[resolvedProjectPath] = tabs
        scheduleWorkspaceRestoreAutosave()
    }

    public func confirmWorkspaceEditorCloseRequest() {
        guard let request = workspacePendingEditorCloseRequest else {
            return
        }
        workspacePendingEditorCloseRequest = nil
        let resolvedProjectPath = normalizePathForCompare(request.projectPath)
        forceCloseWorkspaceEditorTab(request.tabID, in: resolvedProjectPath)
        guard let batchCloseState = workspacePendingEditorBatchCloseState,
              normalizePathForCompare(batchCloseState.projectPath) == resolvedProjectPath
        else {
            workspacePendingEditorBatchCloseState = nil
            return
        }
        workspacePendingEditorBatchCloseState = nil
        closeWorkspaceEditorTabs(batchCloseState.remainingTabIDs, in: normalizePathForCompare(batchCloseState.projectPath))
    }

    public func dismissWorkspaceEditorCloseRequest() {
        workspacePendingEditorCloseRequest = nil
        workspacePendingEditorBatchCloseState = nil
    }

    private func forceCloseWorkspaceEditorTab(_ tabID: String, in resolvedProjectPath: String) {
        guard var tabs = workspaceEditorTabsByProjectPath[resolvedProjectPath],
              let removedIndex = tabs.firstIndex(where: { $0.id == tabID })
        else {
            return
        }

        let removedTab = tabs[removedIndex]
        let isClosingSelectedTab = resolvedWorkspacePresentedTabSelection(for: resolvedProjectPath) == .editor(tabID)
        tabs.remove(at: removedIndex)
        workspaceEditorTabsByProjectPath[resolvedProjectPath] = tabs
        removeWorkspaceEditorRuntimeSession(tabID, in: resolvedProjectPath)
        syncWorkspaceEditorRuntimeSessions(for: resolvedProjectPath)
        syncWorkspaceEditorDirectoryWatchers(for: resolvedProjectPath)
        workspaceEditorPresentationByProjectPath[resolvedProjectPath] = removingWorkspaceEditorTab(
            tabID,
            from: resolvedWorkspaceEditorPresentationState(for: resolvedProjectPath),
            projectPath: resolvedProjectPath
        )
        if let treeState = workspaceProjectTreeStatesByProjectPath[resolvedProjectPath],
           treeState.selectedPath == removedTab.filePath {
            selectWorkspaceProjectTreeNode(nil, in: resolvedProjectPath)
        }

        guard isClosingSelectedTab else {
            scheduleWorkspaceRestoreAutosave()
            return
        }

        if let nextEditorTabID = preferredWorkspaceEditorTabAfterClosing(
            tabID,
            removedIndex: removedIndex,
            in: resolvedProjectPath,
            remainingTabs: tabs
        ) {
            activateWorkspaceEditorTab(nextEditorTabID, in: resolvedProjectPath)
        } else if let diffTab = (workspaceDiffTabsByProjectPath[resolvedProjectPath] ?? []).last {
            workspaceSelectedPresentedTabByProjectPath[resolvedProjectPath] = .diff(diffTab.id)
            workspaceFocusedArea = .diffTab(diffTab.id)
        } else if let terminalTabID = workspaceController(for: resolvedProjectPath)?.selectedTabId
            ?? workspaceController(for: resolvedProjectPath)?.selectedTab?.id
        {
            workspaceSelectedPresentedTabByProjectPath[resolvedProjectPath] = .terminal(terminalTabID)
            workspaceFocusedArea = .terminal
        } else {
            workspaceSelectedPresentedTabByProjectPath[resolvedProjectPath] = nil
            workspaceFocusedArea = .terminal
        }

        scheduleWorkspaceRestoreAutosave()
    }

    private func closeWorkspaceEditorTabs(_ tabIDs: [String], in resolvedProjectPath: String) {
        workspacePendingEditorBatchCloseState = nil
        let displayProjectPath = displayWorkspaceProjectPath(for: resolvedProjectPath)

        for (index, tabID) in tabIDs.enumerated() {
            guard let tab = workspaceEditorTabsByProjectPath[resolvedProjectPath]?.first(where: { $0.id == tabID }) else {
                continue
            }

            guard !tab.isDirty else {
                workspacePendingEditorCloseRequest = WorkspaceEditorCloseRequest(
                    projectPath: displayProjectPath,
                    tabID: tabID,
                    title: tab.title,
                    filePath: tab.filePath,
                    isDirty: tab.isDirty,
                    externalChangeState: tab.externalChangeState
                )
                let remainingTabIDs = Array(tabIDs.suffix(from: index + 1))
                workspacePendingEditorBatchCloseState = remainingTabIDs.isEmpty
                    ? nil
                    : WorkspaceEditorBatchCloseState(
                        projectPath: displayProjectPath,
                        remainingTabIDs: remainingTabIDs
                    )
                return
            }

            forceCloseWorkspaceEditorTab(tabID, in: resolvedProjectPath)
        }
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
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath) else {
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
        case let .editor(tabID):
            guard let editorTab = workspaceEditorTabsByProjectPath[resolvedProjectPath]?.first(where: { $0.id == tabID }) else {
                return
            }
            activateWorkspaceEditorTab(tabID, in: resolvedProjectPath)
            selectWorkspaceProjectTreeNode(editorTab.filePath, in: resolvedProjectPath)
        case let .diff(tabID):
            guard workspaceDiffTabsByProjectPath[resolvedProjectPath]?.contains(where: { $0.id == tabID }) == true else {
                return
            }
            workspaceSelectedPresentedTabByProjectPath[resolvedProjectPath] = .diff(tabID)
            workspaceFocusedArea = .diffTab(tabID)
        }

        scheduleWorkspaceRestoreAutosave()
    }

    public func splitWorkspaceEditorActiveGroup(
        axis: WorkspaceSplitAxis,
        in projectPath: String? = nil
    ) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath),
              workspaceEditorTabsByProjectPath[resolvedProjectPath]?.isEmpty == false
        else {
            return
        }

        var presentation = resolvedWorkspaceEditorPresentationState(for: resolvedProjectPath)
            ?? WorkspaceEditorPresentationState()
        if presentation.groups.isEmpty {
            presentation = makeDefaultWorkspaceEditorPresentationState(
                tabs: workspaceEditorTabsByProjectPath[resolvedProjectPath] ?? []
            )
        }

        let activeGroupID = presentation.activeGroupID ?? presentation.groups.first?.id
        guard let activeGroupID,
              let activeGroupIndex = presentation.groups.firstIndex(where: { $0.id == activeGroupID })
        else {
            return
        }

        if presentation.groups.count == 1 {
            let newGroup = WorkspaceEditorGroupState(
                id: "workspace-editor-group:\(UUID().uuidString.lowercased())"
            )
            presentation.groups.insert(newGroup, at: activeGroupIndex + 1)
            presentation.activeGroupID = newGroup.id
            presentation.splitAxis = axis
            presentation.splitRatio = WorkspaceEditorPresentationState.defaultSplitRatio
        } else {
            presentation.activeGroupID = presentation.groups[min(activeGroupIndex + 1, presentation.groups.count - 1)].id
            presentation.splitAxis = axis
        }

        workspaceEditorPresentationByProjectPath[resolvedProjectPath] = normalizedWorkspaceEditorPresentationState(
            presentation,
            projectPath: resolvedProjectPath
        )
        if let selectedTabID = presentation.groups.first(where: { $0.id == presentation.activeGroupID })?.selectedTabID {
            activateWorkspaceEditorTab(selectedTabID, in: resolvedProjectPath)
        }
        scheduleWorkspaceRestoreAutosave()
    }

    public func selectWorkspaceEditorGroup(_ groupID: String, in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath),
              var presentation = resolvedWorkspaceEditorPresentationState(for: resolvedProjectPath),
              let groupIndex = presentation.groups.firstIndex(where: { $0.id == groupID })
        else {
            return
        }

        presentation.activeGroupID = presentation.groups[groupIndex].id
        workspaceEditorPresentationByProjectPath[resolvedProjectPath] = normalizedWorkspaceEditorPresentationState(
            presentation,
            projectPath: resolvedProjectPath
        )
        if let selectedTabID = presentation.groups[groupIndex].selectedTabID {
            activateWorkspaceEditorTab(selectedTabID, in: resolvedProjectPath)
        }
        scheduleWorkspaceRestoreAutosave()
    }

    public func moveWorkspaceEditorTab(
        _ tabID: String,
        toGroup groupID: String,
        in projectPath: String? = nil
    ) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath),
              workspaceEditorTabsByProjectPath[resolvedProjectPath]?.contains(where: { $0.id == tabID }) == true,
              var presentation = resolvedWorkspaceEditorPresentationState(for: resolvedProjectPath),
              let targetGroupIndex = presentation.groups.firstIndex(where: { $0.id == groupID })
        else {
            return
        }

        for index in presentation.groups.indices {
            presentation.groups[index].tabIDs.removeAll(where: { $0 == tabID })
            if presentation.groups[index].selectedTabID == tabID {
                presentation.groups[index].selectedTabID = presentation.groups[index].tabIDs.last
            }
        }

        presentation.groups[targetGroupIndex].tabIDs.append(tabID)
        presentation.groups[targetGroupIndex].selectedTabID = tabID
        presentation.activeGroupID = presentation.groups[targetGroupIndex].id
        workspaceEditorPresentationByProjectPath[resolvedProjectPath] = normalizedWorkspaceEditorPresentationState(
            presentation,
            projectPath: resolvedProjectPath
        )
        activateWorkspaceEditorTab(tabID, in: resolvedProjectPath)
        scheduleWorkspaceRestoreAutosave()
    }

    public func closeWorkspaceEditorGroup(_ groupID: String, in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath),
              var presentation = resolvedWorkspaceEditorPresentationState(for: resolvedProjectPath),
              presentation.groups.count > 1,
              let closingGroupIndex = presentation.groups.firstIndex(where: { $0.id == groupID })
        else {
            return
        }

        let fallbackGroupIndex = closingGroupIndex == 0 ? 1 : 0
        let movedTabIDs = presentation.groups[closingGroupIndex].tabIDs
        for tabID in movedTabIDs where !presentation.groups[fallbackGroupIndex].tabIDs.contains(tabID) {
            presentation.groups[fallbackGroupIndex].tabIDs.append(tabID)
        }
        if presentation.groups[fallbackGroupIndex].selectedTabID == nil {
            presentation.groups[fallbackGroupIndex].selectedTabID = presentation.groups[closingGroupIndex].selectedTabID
                ?? movedTabIDs.last
        }
        presentation.groups.remove(at: closingGroupIndex)
        presentation.activeGroupID = presentation.groups.indices.contains(fallbackGroupIndex)
            ? presentation.groups[fallbackGroupIndex].id
            : presentation.groups.last?.id
        presentation.splitAxis = presentation.groups.count > 1 ? presentation.splitAxis : nil
        workspaceEditorPresentationByProjectPath[resolvedProjectPath] = normalizedWorkspaceEditorPresentationState(
            presentation,
            projectPath: resolvedProjectPath
        )

        if let selectedEditorTabID = activeWorkspaceSelectedEditorTabID,
           workspaceEditorTabsByProjectPath[resolvedProjectPath]?.contains(where: { $0.id == selectedEditorTabID }) == true {
            activateWorkspaceEditorTab(selectedEditorTabID, in: resolvedProjectPath)
        } else if let nextTabID = presentation.groups.last?.selectedTabID ?? presentation.groups.last?.tabIDs.last {
            activateWorkspaceEditorTab(nextTabID, in: resolvedProjectPath)
        }
        scheduleWorkspaceRestoreAutosave()
    }

    public func updateWorkspaceEditorSplitRatio(
        _ ratio: Double,
        in projectPath: String? = nil
    ) {
        guard let resolvedProjectPath = projectPath ?? activeWorkspaceProjectPath,
              var presentation = resolvedWorkspaceEditorPresentationState(for: resolvedProjectPath),
              presentation.groups.count > 1
        else {
            return
        }

        presentation.splitRatio = min(max(ratio, 0.15), 0.85)
        workspaceEditorPresentationByProjectPath[resolvedProjectPath] = presentation
        scheduleWorkspaceRestoreAutosave()
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
            case .project:
                prepareActiveWorkspaceProjectTreeState()
            case .commit:
                prepareActiveWorkspaceCommitViewModel()
            case .git:
                prepareActiveWorkspaceGitViewModel()
            case .github:
                prepareActiveWorkspaceGitHubViewModel()
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

    public func listWorkspaceBaseBranchReferences(
        for rootProjectPath: String
    ) async throws -> [NativeGitBaseBranchReference] {
        let worktreeService = self.worktreeService
        return try await Task.detached(priority: .userInitiated) {
            try worktreeService.listBaseBranchReferences(at: rootProjectPath)
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
            baseBranchMode: firstMember?.baseBranchMode ?? .specified,
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
        next.baseBranchMode = firstMember?.baseBranchMode ?? .specified
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

    public func moveWorkspaceAlignmentGroup(
        _ sourceGroupID: String,
        relativeTo targetGroupID: String,
        insertAfter: Bool
    ) throws {
        guard sourceGroupID != targetGroupID else {
            return
        }

        var groups = snapshot.appState.workspaceAlignmentGroups
        guard let sourceIndex = groups.firstIndex(where: { $0.id == sourceGroupID }) else {
            return
        }

        let sourceGroup = groups.remove(at: sourceIndex)
        guard let targetIndex = groups.firstIndex(where: { $0.id == targetGroupID }) else {
            return
        }

        let insertionIndex = insertAfter ? targetIndex + 1 : targetIndex
        groups.insert(sourceGroup, at: insertionIndex)
        guard groups != snapshot.appState.workspaceAlignmentGroups else {
            return
        }

        try persistWorkspaceAlignmentGroups(groups)
    }

    public func setWorkspaceAlignmentGroupSidebarExpanded(
        _ isExpanded: Bool,
        for id: String
    ) {
        guard let index = snapshot.appState.workspaceAlignmentGroups.firstIndex(where: { $0.id == id }) else {
            return
        }
        guard snapshot.appState.workspaceAlignmentGroups[index].isSidebarExpanded != isExpanded else {
            return
        }

        do {
            var groups = snapshot.appState.workspaceAlignmentGroups
            groups[index].isSidebarExpanded = isExpanded
            try persistWorkspaceAlignmentGroups(groups)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func setAllWorkspaceAlignmentGroupsSidebarExpanded(_ isExpanded: Bool) {
        guard !snapshot.appState.workspaceAlignmentGroups.isEmpty else {
            return
        }
        let hasChange = snapshot.appState.workspaceAlignmentGroups.contains { $0.isSidebarExpanded != isExpanded }
        guard hasChange else {
            return
        }

        do {
            var groups = snapshot.appState.workspaceAlignmentGroups
            for index in groups.indices {
                groups[index].isSidebarExpanded = isExpanded
            }
            try persistWorkspaceAlignmentGroups(groups)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
        let normalizedRootProjectPath = normalizePathForCompare(rootProjectPath)
        guard let projectIndex = snapshot.projects.firstIndex(where: {
            normalizePathForCompare($0.path) == normalizedRootProjectPath
        }) else {
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
        let normalizedRootProjectPath = normalizePathForCompare(rootProjectPath)
        guard snapshot.projects.contains(where: {
            normalizePathForCompare($0.path) == normalizedRootProjectPath
        }) else {
            throw NativeWorktreeError.invalidProject("项目不存在或已移除")
        }

        let request = NativeWorktreeCreateRequest(
            sourceProjectPath: normalizedRootProjectPath,
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
        let normalizedRootProjectPath = normalizePathForCompare(context.rootProjectPath)
        guard snapshot.projects.contains(where: {
            normalizePathForCompare($0.path) == normalizedRootProjectPath
        }) else {
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

        let normalizedRootProjectPath = normalizePathForCompare(rootProjectPath)
        guard let worktree = snapshot.projects.first(where: {
            normalizePathForCompare($0.path) == normalizedRootProjectPath
        })?.worktrees.first(where: {
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

        let normalizedRootProjectPath = normalizePathForCompare(rootProjectPath)
        guard let projectIndex = snapshot.projects.firstIndex(where: {
            normalizePathForCompare($0.path) == normalizedRootProjectPath
        }) else {
            throw NativeWorktreeError.invalidProject("项目不存在或已移除")
        }
        guard let worktree = snapshot.projects[projectIndex].worktrees.first(where: {
            normalizePathForCompare($0.path) == normalizedWorktreePath
        }) else {
            throw NativeWorktreeError.invalidPath("worktree 不存在或已移除")
        }

        let shouldDeleteBranch = worktree.baseBranch?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let removeRequest = NativeWorktreeRemoveRequest(
            sourceProjectPath: rootProjectPath,
            worktreePath: worktree.path,
            branch: worktree.branch,
            shouldDeleteBranch: shouldDeleteBranch
        )
        let result: NativeWorktreeRemoveResult
        do {
            result = try await Task.detached(priority: .userInitiated) {
                try self.worktreeService.removeWorktree(removeRequest)
            }.value
        } catch let error as NativeWorktreeError {
            guard case let .invalidPath(message) = error,
                  shouldTreatMissingPersistedWorktreeAsStaleRecord(message)
            else {
                throw error
            }

            let cleanupResult = try await cleanupMissingWorkspaceWorktreeRecord(
                rootProjectPath: rootProjectPath,
                worktree: worktree,
                shouldDeleteBranch: shouldDeleteBranch
            )
            result = NativeWorktreeRemoveResult(warning: cleanupResult.warning)
        }

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
        let nextDirectProjectPaths = survivingDirectProjectPaths(
            from: directProjectPaths,
            rebuiltProjects: rebuiltProjects
        )

        if nextDirectProjectPaths != snapshot.appState.directProjectPaths {
            try store.updateDirectProjectPaths(nextDirectProjectPaths)
            snapshot.appState.directProjectPaths = nextDirectProjectPaths
        }
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

    public func updateProjectListSortOrder(_ order: ProjectListSortOrder) {
        guard snapshot.appState.settings.projectListSortOrder != order else {
            return
        }
        var nextSettings = snapshot.appState.settings
        nextSettings.projectListSortOrder = order
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

    public func setWorkspaceSidebarProjectExpanded(
        _ isExpanded: Bool,
        for rootProjectPath: String
    ) {
        let normalizedProjectPath = normalizePathForCompare(rootProjectPath)
        guard !normalizedProjectPath.isEmpty else {
            return
        }

        let collapsedPaths = Set(
            snapshot.appState.settings.collapsedWorkspaceSidebarProjectPaths.map(normalizePathForCompare)
        )
        let shouldBeCollapsed = !isExpanded
        guard collapsedPaths.contains(normalizedProjectPath) != shouldBeCollapsed else {
            return
        }

        var nextSettings = snapshot.appState.settings
        if shouldBeCollapsed {
            nextSettings.collapsedWorkspaceSidebarProjectPaths = normalizePathList(
                nextSettings.collapsedWorkspaceSidebarProjectPaths + [normalizedProjectPath]
            )
        } else {
            nextSettings.collapsedWorkspaceSidebarProjectPaths = nextSettings.collapsedWorkspaceSidebarProjectPaths.filter {
                normalizePathForCompare($0) != normalizedProjectPath
            }
        }
        saveSettings(nextSettings)
    }

    public var workspaceEditorDisplayOptions: WorkspaceEditorDisplayOptions {
        snapshot.appState.settings.workspaceEditorDisplayOptions
    }

    public func updateWorkspaceEditorDisplayOptions(_ options: WorkspaceEditorDisplayOptions) {
        guard snapshot.appState.settings.workspaceEditorDisplayOptions != options else {
            return
        }
        var nextSettings = snapshot.appState.settings
        nextSettings.workspaceEditorDisplayOptions = options
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
            if session.isQuickTerminal || session.transientDisplayProject?.isDirectoryWorkspace == true {
                return false
            }
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
              session.transientDisplayProject?.isDirectoryWorkspace != true,
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
            || (project.notesSummary?.lowercased().contains(query) ?? false)
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

    private func sortProjects(_ projects: [Project]) -> [Project] {
        switch projectListSortOrder {
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
            paneSnapshotProvider: workspacePaneSnapshotProvider,
            editorRestoreProvider: workspaceEditorRestoreState(for:)
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
                transientDisplayProject: normalizedTransientDisplayProject(
                    sessionSnapshot.transientDisplayProject,
                    fallbackPath: normalizedProjectPath
                ),
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

            let displayProjectPath = resolveDisplayProject(
                for: normalizedProjectPath,
                rootProjectPath: normalizedRootProjectPath
            )?.path ?? normalizedProjectPath
            let displayRootProjectPath = resolveDisplayProject(
                for: normalizedRootProjectPath,
                rootProjectPath: normalizedRootProjectPath
            )?.path ?? normalizedRootProjectPath

            return OpenWorkspaceSessionState(
                projectPath: displayProjectPath,
                rootProjectPath: displayRootProjectPath,
                controller: controller,
                isQuickTerminal: sessionSnapshot.isQuickTerminal,
                transientDisplayProject: normalizedTransientDisplayProject(
                    sessionSnapshot.transientDisplayProject,
                    fallbackPath: normalizedProjectPath
                ),
                workspaceRootContext: restoredWorkspaceRootContext,
                workspaceAlignmentGroupID: sessionSnapshot.workspaceAlignmentGroupID
            )
        }

        guard !restoredSessions.isEmpty else {
            return
        }

        openWorkspaceSessions = restoredSessions
        syncAttentionStateWithOpenSessions()
        restoreWorkspaceEditorPresentation(from: restoredSnapshot)

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
        if let restoredActiveProjectPath {
            let selection = resolvedWorkspacePresentedTabSelection(for: restoredActiveProjectPath)
            workspaceFocusedArea = selection.map(defaultFocusedArea(for:)) ?? .terminal
        }
        isDetailPanelPresented = false
    }

    private func canRestoreWorkspaceSession(_ sessionSnapshot: ProjectWorkspaceRestoreSnapshot) -> Bool {
        let normalizedProjectPath = normalizePathForCompare(sessionSnapshot.projectPath)
        let normalizedRootProjectPath = normalizePathForCompare(sessionSnapshot.rootProjectPath)

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
            return !normalizedProjectPath.isEmpty
        }
        if sessionSnapshot.transientDisplayProject?.isDirectoryWorkspace == true {
            return workspaceFileSystemService.itemExists(at: normalizedProjectPath)
        }
        guard workspaceFileSystemService.itemExists(at: normalizedProjectPath),
              workspaceFileSystemService.itemExists(at: normalizedRootProjectPath)
        else {
            return false
        }
        return resolveDisplayProject(
            for: normalizedProjectPath,
            rootProjectPath: normalizedRootProjectPath
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
        transientDisplayProject: Project? = nil,
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
                transientDisplayProject: transientDisplayProject,
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
              session.transientDisplayProject?.isDirectoryWorkspace != true,
              session.workspaceAlignmentGroupID == nil
        else {
            return false
        }
        return normalizedPathsMatch(session.rootProjectPath, rootProjectPath)
    }

    private func workspaceSessionIndex(for path: String) -> Int? {
        workspaceSessionIndexByNormalizedPath[normalizePathForCompare(path)]
    }

    private func workspaceSession(for path: String?) -> OpenWorkspaceSessionState? {
        guard let normalizedPath = normalizedOptionalPathForCompare(path) else {
            return nil
        }
        if let index = workspaceSessionIndexByNormalizedPath[normalizedPath],
           openWorkspaceSessions.indices.contains(index) {
            return openWorkspaceSessions[index]
        }
        return openWorkspaceSessions.last(where: {
            !$0.isQuickTerminal &&
                normalizePathForCompare($0.rootProjectPath) == normalizedPath
        })
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
                ?? sessions.last(where: {
                    !$0.isQuickTerminal &&
                        normalizePathForCompare($0.rootProjectPath) == normalizedPath
                })?.projectPath
        }
        guard let index = workspaceSessionIndexByNormalizedPath[normalizedPath],
              openWorkspaceSessions.indices.contains(index)
        else {
            return openWorkspaceSessions.last(where: {
                !$0.isQuickTerminal &&
                    normalizePathForCompare($0.rootProjectPath) == normalizedPath
            })?.projectPath
        }
        return openWorkspaceSessions[index].projectPath
    }

    private func orderedOpenWorkspaceRootProjectPaths() -> [String] {
        var paths: [String] = []
        var seen = Set<String>()

        for session in openWorkspaceSessions where !session.isQuickTerminal {
            let normalizedRootProjectPath = normalizePathForCompare(session.rootProjectPath)
            if seen.insert(normalizedRootProjectPath).inserted {
                paths.append(session.rootProjectPath)
            }
        }

        return paths
    }

    private func orderedWorkspaceSidebarGroupIdentities() -> [WorkspaceSidebarGroupIdentity] {
        var identities: [WorkspaceSidebarGroupIdentity] = []
        var seen = Set<String>()

        for session in openWorkspaceSessions {
            guard let identity = workspaceSidebarGroupIdentity(for: session),
                  seen.insert(identity.id).inserted
            else {
                continue
            }
            identities.append(identity)
        }

        return identities
    }

    private func workspaceSidebarGroupIdentity(
        for session: OpenWorkspaceSessionState
    ) -> WorkspaceSidebarGroupIdentity? {
        if let transientProject = session.transientDisplayProject,
           transientProject.isDirectoryWorkspace {
            return WorkspaceSidebarGroupIdentity(
                id: transientProject.id,
                normalizedPath: normalizePathForCompare(session.projectPath),
                transientKind: .directoryWorkspace
            )
        }
        if session.isQuickTerminal {
            if let workspaceRootContext = session.workspaceRootContext {
                let transientProject = Project.workspaceRoot(
                    name: workspaceRootContext.workspaceName,
                    path: session.projectPath
                )
                return WorkspaceSidebarGroupIdentity(
                    id: transientProject.id,
                    normalizedPath: normalizePathForCompare(session.projectPath),
                    transientKind: .workspaceRoot
                )
            }

            let transientProject = Project.quickTerminal(at: session.projectPath)
            return WorkspaceSidebarGroupIdentity(
                id: transientProject.id,
                normalizedPath: normalizePathForCompare(session.projectPath),
                transientKind: .quickTerminal
            )
        }

        let normalizedRootProjectPath = normalizePathForCompare(session.rootProjectPath)
        guard let rootProject = projectsByNormalizedPath[normalizedRootProjectPath] else {
            return nil
        }
        return WorkspaceSidebarGroupIdentity(
            id: rootProject.id,
            normalizedPath: normalizedRootProjectPath,
            transientKind: nil
        )
    }

    private func promoteWorkspaceSessionIfNeeded(for path: String, rootProjectPath: String) {
        guard let index = workspaceSessionIndex(for: path) else {
            return
        }
        openWorkspaceSessions[index].rootProjectPath = displayWorkspaceProjectPath(for: rootProjectPath)
        openWorkspaceSessions[index].workspaceAlignmentGroupID = nil
    }

    private func clearDirectoryWorkspacePresentationIfNeeded(for path: String) {
        guard let index = workspaceSessionIndex(for: path),
              openWorkspaceSessions[index].transientDisplayProject?.isDirectoryWorkspace == true
        else {
            return
        }
        openWorkspaceSessions[index].transientDisplayProject = nil
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
        if let index = workspaceSessionIndex(for: rootURL.path) {
            openWorkspaceSessions[index].projectPath = rootURL.path
            openWorkspaceSessions[index].rootProjectPath = rootURL.path
        }
        return rootURL.path
    }

    private func isQuickTerminalSessionPath(_ path: String) -> Bool {
        workspaceSession(for: path)?.isQuickTerminal ?? false
    }

    private func workspaceCloseFeedbackMessage(
        for path: String,
        includeRegularProject: Bool = false
    ) -> String? {
        guard let session = workspaceSession(for: path) else {
            return nil
        }
        if let workspaceRootContext = session.workspaceRootContext {
            return "已关闭工作区「\(workspaceRootContext.workspaceName)」"
        }
        if session.isQuickTerminal {
            return "已结束快速终端"
        }
        if includeRegularProject,
           let project = resolveDisplayProject(for: path, rootProjectPath: session.rootProjectPath) {
            return "已关闭项目「\(project.name)」"
        }
        return nil
    }

    private func buildWorkspaceProjectTreeState(
        for projectPath: String,
        preserving existingState: WorkspaceProjectTreeState?
    ) throws -> WorkspaceProjectTreeState {
        try Self.buildWorkspaceProjectTreeStateSnapshot(
            service: workspaceFileSystemService,
            projectPath: projectPath,
            preserving: existingState
        )
    }

    private func rebuildWorkspaceProjectTree(
        for projectPath: String,
        preserving state: WorkspaceProjectTreeState?
    ) throws -> WorkspaceProjectTreeState {
        try buildWorkspaceProjectTreeState(for: projectPath, preserving: state)
    }

    private func resolveWorkspaceProjectTreeTargetDirectory(
        targetPath: String?,
        projectPath: String
    ) -> String {
        guard let targetPath else {
            return projectPath
        }
        switch workspaceFileSystemService.itemKind(at: targetPath) {
        case .directory:
            return normalizePathForCompare(targetPath)
        case .symlink:
            if workspaceFileSystemService.symlinkDestinationKind(at: targetPath) == .directory {
                return normalizePathForCompare(targetPath)
            }
            return workspaceFileSystemService.parentDirectoryPath(for: targetPath)
        case .file:
            return workspaceFileSystemService.parentDirectoryPath(for: targetPath)
        case .none:
            return projectPath
        }
    }

    private func remapWorkspaceProjectTreeState(
        _ state: WorkspaceProjectTreeState?,
        replacingPathPrefix sourcePath: String,
        with destinationPath: String
    ) -> WorkspaceProjectTreeState? {
        guard var state else {
            return nil
        }
        let sourcePrefix = normalizePathForCompare(sourcePath)
        let destinationPrefix = normalizePathForCompare(destinationPath)

        state.expandedDirectoryPaths = Set(
            state.expandedDirectoryPaths.map { remapWorkspacePathPrefix($0, sourcePrefix: sourcePrefix, destinationPrefix: destinationPrefix) }
        )
        state.loadingDirectoryPaths = Set(
            state.loadingDirectoryPaths.map { remapWorkspacePathPrefix($0, sourcePrefix: sourcePrefix, destinationPrefix: destinationPrefix) }
        )
        state.selectedPath = state.selectedPath.map {
            remapWorkspacePathPrefix($0, sourcePrefix: sourcePrefix, destinationPrefix: destinationPrefix)
        }
        return state
    }

    private func loadWorkspaceProjectTreeChildren(
        for directoryPath: String,
        projectRootPath: String,
        into state: inout WorkspaceProjectTreeState
    ) throws {
        let normalizedDirectoryPath = normalizePathForCompare(directoryPath)
        let children = try workspaceFileSystemService.listDirectory(at: normalizedDirectoryPath)
        state.childrenByDirectoryPath[normalizedDirectoryPath] = children
        try preloadVisibleWorkspaceProjectTreeDisplayChains(
            forChildren: children,
            projectRootPath: projectRootPath,
            into: &state
        )
    }

    private func preloadVisibleWorkspaceProjectTreeDisplayChains(
        forChildren children: [WorkspaceProjectTreeNode],
        projectRootPath: String,
        into state: inout WorkspaceProjectTreeState
    ) throws {
        for child in children where child.isDirectory {
            try preloadWorkspaceProjectTreeDisplayChain(
                startingAt: child,
                projectRootPath: projectRootPath,
                into: &state
            )
        }
    }

    private func preloadWorkspaceProjectTreeDisplayChain(
        startingAt node: WorkspaceProjectTreeNode,
        projectRootPath: String,
        into state: inout WorkspaceProjectTreeState
    ) throws {
        guard let sourceRootPath = WorkspaceProjectTreeJavaPackageSupport.javaSourceRoot(
            for: node.path,
            projectRootPath: projectRootPath
        ),
        normalizePathForCompare(node.path) != normalizePathForCompare(sourceRootPath),
        WorkspaceProjectTreeJavaPackageSupport.isPackageDirectoryPath(node.path, within: sourceRootPath)
        else {
            return
        }

        var currentNode = node
        while true {
            let currentPath = normalizePathForCompare(currentNode.path)
            let children = try workspaceFileSystemService.listDirectory(at: currentPath)
            state.childrenByDirectoryPath[currentPath] = children
            guard let nextNode = WorkspaceProjectTreeJavaPackageSupport.compactedChildDirectory(
                children: children,
                sourceRootPath: sourceRootPath
            ) else {
                return
            }
            currentNode = nextNode
        }
    }

    private func workspaceProjectTreeDisplayProjection(
        for projectPath: String,
        state: WorkspaceProjectTreeState
    ) -> WorkspaceProjectTreeDisplayProjection {
        if let cache = workspaceProjectTreeProjectionCacheByProjectPath[projectPath],
           cache.revision == state.revision {
            return cache.projection
        }

        let startTime = ProcessInfo.processInfo.systemUptime
        let projection = state.displayProjection
        workspaceProjectTreeProjectionCacheByProjectPath[projectPath] = WorkspaceProjectTreeProjectionCacheEntry(
            revision: state.revision,
            projection: projection
        )
        workspaceProjectTreeDiagnostics.recordProjectionBuilt(
            projectPath: projectPath,
            revision: state.revision,
            durationMs: elapsedMilliseconds(since: startTime),
            rootCount: projection.rootNodes.count,
            aliasCount: projection.aliasMap.count
        )
        return projection
    }

    nonisolated private static func loadWorkspaceProjectTreeChildrenSnapshot(
        service: WorkspaceFileSystemService,
        directoryPath: String,
        projectRootPath: String
    ) throws -> WorkspaceProjectTreeDirectoryLoadResult {
        let normalizedDirectoryPath = normalizePathForCompare(directoryPath)
        let normalizedProjectRootPath = normalizePathForCompare(projectRootPath)
        let children = try service.listDirectory(at: normalizedDirectoryPath)
        var loadedChildrenByDirectoryPath: [String: [WorkspaceProjectTreeNode]] = [
            normalizedDirectoryPath: children
        ]

        for child in children where child.isDirectory {
            try preloadWorkspaceProjectTreeDisplayChain(
                service: service,
                startingAt: child,
                projectRootPath: normalizedProjectRootPath,
                into: &loadedChildrenByDirectoryPath
            )
        }

        return WorkspaceProjectTreeDirectoryLoadResult(
            directoryPath: normalizedDirectoryPath,
            childrenByDirectoryPath: loadedChildrenByDirectoryPath
        )
    }

    nonisolated private static func buildWorkspaceProjectTreeStateSnapshot(
        service: WorkspaceFileSystemService,
        projectPath: String,
        preserving existingState: WorkspaceProjectTreeState?
    ) throws -> WorkspaceProjectTreeState {
        let normalizedProjectPath = normalizePathForCompare(projectPath)
        var nextState = existingState ?? WorkspaceProjectTreeState(rootProjectPath: normalizedProjectPath)
        nextState.advanceStructureRevision()

        let rootNodes = try service.listDirectory(at: normalizedProjectPath)
        nextState.rootProjectPath = normalizedProjectPath
        nextState.rootNodes = rootNodes
        nextState.childrenByDirectoryPath[normalizedProjectPath] = rootNodes

        let rootProjectionChildren = try preloadWorkspaceProjectTreeVisibleChainsSnapshot(
            service: service,
            children: rootNodes,
            projectRootPath: normalizedProjectPath
        )
        for (path, children) in rootProjectionChildren {
            nextState.childrenByDirectoryPath[path] = children
        }
        nextState.errorMessage = nil

        let expandedPaths = (existingState?.expandedDirectoryPaths ?? [])
            .filter { normalizePathForCompare($0) != normalizedProjectPath }
            .filter { service.directoryExists(at: $0) }

        nextState.expandedDirectoryPaths = Set(expandedPaths)
        nextState.loadingDirectoryPaths = []
        for directoryPath in expandedPaths {
            let result = try loadWorkspaceProjectTreeChildrenSnapshot(
                service: service,
                directoryPath: directoryPath,
                projectRootPath: normalizedProjectPath
            )
            for (path, children) in result.childrenByDirectoryPath {
                nextState.childrenByDirectoryPath[path] = children
            }
        }

        if let selectedPath = existingState?.selectedPath,
           FileManager.default.fileExists(atPath: selectedPath) {
            nextState.selectedPath = selectedPath
        } else {
            nextState.selectedPath = nil
        }

        return nextState.canonicalizedForDisplay()
    }

    nonisolated private static func preloadWorkspaceProjectTreeVisibleChainsSnapshot(
        service: WorkspaceFileSystemService,
        children: [WorkspaceProjectTreeNode],
        projectRootPath: String
    ) throws -> [String: [WorkspaceProjectTreeNode]] {
        let normalizedProjectRootPath = normalizePathForCompare(projectRootPath)
        var loadedChildrenByDirectoryPath: [String: [WorkspaceProjectTreeNode]] = [:]
        for child in children where child.isDirectory {
            try preloadWorkspaceProjectTreeDisplayChain(
                service: service,
                startingAt: child,
                projectRootPath: normalizedProjectRootPath,
                into: &loadedChildrenByDirectoryPath
            )
        }
        return loadedChildrenByDirectoryPath
    }

    nonisolated private static func preloadWorkspaceProjectTreeDisplayChain(
        service: WorkspaceFileSystemService,
        startingAt node: WorkspaceProjectTreeNode,
        projectRootPath: String,
        into loadedChildrenByDirectoryPath: inout [String: [WorkspaceProjectTreeNode]]
    ) throws {
        guard let sourceRootPath = WorkspaceProjectTreeJavaPackageSupport.javaSourceRoot(
            for: node.path,
            projectRootPath: projectRootPath
        ),
        normalizePathForCompare(node.path) != normalizePathForCompare(sourceRootPath),
        WorkspaceProjectTreeJavaPackageSupport.isPackageDirectoryPath(node.path, within: sourceRootPath)
        else {
            return
        }

        var currentNode = node
        while true {
            let currentPath = normalizePathForCompare(currentNode.path)
            let children = try service.listDirectory(at: currentPath)
            loadedChildrenByDirectoryPath[currentPath] = children
            guard let nextNode = WorkspaceProjectTreeJavaPackageSupport.compactedChildDirectory(
                children: children,
                sourceRootPath: sourceRootPath
            ) else {
                return
            }
            currentNode = nextNode
        }
    }

    private func remapWorkspaceEditorTabs(
        in projectPath: String,
        replacingPathPrefix sourcePath: String,
        with destinationPath: String
    ) {
        guard var tabs = workspaceEditorTabsByProjectPath[projectPath] else {
            return
        }
        let sourcePrefix = normalizePathForCompare(sourcePath)
        let destinationPrefix = normalizePathForCompare(destinationPath)

        var didRemap = false
        for index in tabs.indices {
            guard tabs[index].filePath == sourcePrefix || tabs[index].filePath.hasPrefix(sourcePrefix + "/") else {
                continue
            }
            let remappedPath = remapWorkspacePathPrefix(
                tabs[index].filePath,
                sourcePrefix: sourcePrefix,
                destinationPrefix: destinationPrefix
            )
            tabs[index].filePath = remappedPath
            tabs[index].identity = remappedPath
            tabs[index].title = URL(fileURLWithPath: remappedPath).lastPathComponent
            didRemap = true
        }
        workspaceEditorTabsByProjectPath[projectPath] = tabs

        if let selection = workspaceSelectedPresentedTabByProjectPath[projectPath],
           case let .editor(tabID) = selection,
           tabs.contains(where: { $0.id == tabID }) {
            workspaceFocusedArea = .editorTab(tabID)
        }

        if didRemap {
            syncWorkspaceEditorDirectoryWatchers(for: projectPath)
            scheduleWorkspaceRestoreAutosave()
        }
    }

    private func closeWorkspaceEditorTabsUnderPath(_ path: String, in projectPath: String) {
        guard let tabs = workspaceEditorTabsByProjectPath[projectPath], !tabs.isEmpty else {
            return
        }
        let normalizedPath = normalizePathForCompare(path)
        let tabIDsToClose = tabs
            .filter { $0.filePath == normalizedPath || $0.filePath.hasPrefix(normalizedPath + "/") }
            .map(\.id)
        for tabID in tabIDsToClose {
            forceCloseWorkspaceEditorTab(tabID, in: projectPath)
        }
    }

    private func makeWorkspaceEditorTabState(
        tabID: String,
        projectPath: String,
        filePath: String,
        document: WorkspaceEditorDocumentSnapshot,
        openingPolicy: WorkspaceEditorTabOpeningPolicy
    ) -> WorkspaceEditorTabState {
        WorkspaceEditorTabState(
            id: tabID,
            identity: filePath,
            projectPath: projectPath,
            filePath: filePath,
            title: URL(fileURLWithPath: filePath).lastPathComponent,
            isPinned: openingPolicy == .pinned,
            isPreview: openingPolicy == .preview,
            kind: document.kind,
            text: document.text,
            isEditable: document.isEditable,
            externalChangeState: .inSync,
            message: document.message,
            lastLoadedModificationDate: document.modificationDate,
            savedContentFingerprint: document.contentFingerprint
        )
    }

    private func applyWorkspaceEditorOpeningPolicy(
        _ openingPolicy: WorkspaceEditorTabOpeningPolicy,
        to tab: inout WorkspaceEditorTabState
    ) {
        switch openingPolicy {
        case .preview:
            break
        case .regular:
            tab.isPreview = false
        case .pinned:
            tab.isPinned = true
            tab.isPreview = false
        }
    }

    private func reinsertWorkspaceEditorTab(
        _ tab: WorkspaceEditorTabState,
        into tabs: inout [WorkspaceEditorTabState],
        preferredIndex: Int? = nil
    ) {
        if tab.isPinned {
            tabs.insert(tab, at: pinnedWorkspaceEditorInsertionIndex(in: tabs))
            return
        }

        if let preferredIndex {
            let clampedIndex = min(max(preferredIndex, firstUnpinnedWorkspaceEditorInsertionIndex(in: tabs)), tabs.count)
            tabs.insert(tab, at: clampedIndex)
            return
        }

        tabs.append(tab)
    }

    private func pinnedWorkspaceEditorInsertionIndex(in tabs: [WorkspaceEditorTabState]) -> Int {
        tabs.lastIndex(where: \.isPinned).map { $0 + 1 } ?? 0
    }

    private func firstUnpinnedWorkspaceEditorInsertionIndex(in tabs: [WorkspaceEditorTabState]) -> Int {
        tabs.firstIndex(where: { !$0.isPinned }) ?? tabs.count
    }

    private func makeDefaultWorkspaceEditorPresentationState(
        tabs: [WorkspaceEditorTabState]
    ) -> WorkspaceEditorPresentationState {
        guard !tabs.isEmpty else {
            return WorkspaceEditorPresentationState()
        }

        let defaultGroup = WorkspaceEditorGroupState(
            id: "workspace-editor-group:default",
            tabIDs: tabs.map(\.id),
            selectedTabID: tabs.last?.id
        )
        return WorkspaceEditorPresentationState(
            groups: [defaultGroup],
            activeGroupID: defaultGroup.id
        )
    }

    private func normalizedWorkspaceEditorPresentationState(
        _ presentation: WorkspaceEditorPresentationState?,
        availableTabs: [WorkspaceEditorTabState]
    ) -> WorkspaceEditorPresentationState? {
        guard !availableTabs.isEmpty else {
            return nil
        }

        let availableTabIDs = availableTabs.map(\.id)
        let availableTabIDSet = Set(availableTabIDs)
        let sourcePresentation = presentation ?? makeDefaultWorkspaceEditorPresentationState(tabs: availableTabs)

        var seen = Set<String>()
        var normalizedGroups: [WorkspaceEditorGroupState] = sourcePresentation.groups.map { group in
            var filteredTabIDs: [String] = []
            filteredTabIDs.reserveCapacity(group.tabIDs.count)
            for tabID in group.tabIDs where availableTabIDSet.contains(tabID) {
                guard seen.insert(tabID).inserted else {
                    continue
                }
                filteredTabIDs.append(tabID)
            }
            return WorkspaceEditorGroupState(
                id: group.id,
                tabIDs: filteredTabIDs,
                selectedTabID: group.selectedTabID
            )
        }

        if normalizedGroups.count > 2 {
            var mergedGroups = Array(normalizedGroups.prefix(2))
            for group in normalizedGroups.dropFirst(2) {
                for tabID in group.tabIDs where !mergedGroups[1].tabIDs.contains(tabID) {
                    mergedGroups[1].tabIDs.append(tabID)
                }
                if mergedGroups[1].selectedTabID == nil {
                    mergedGroups[1].selectedTabID = group.selectedTabID
                }
            }
            normalizedGroups = mergedGroups
        }

        if normalizedGroups.isEmpty {
            normalizedGroups = makeDefaultWorkspaceEditorPresentationState(tabs: availableTabs).groups
        }

        let preferredActiveGroupID = sourcePresentation.activeGroupID
        let activeGroupIndex = normalizedGroups.firstIndex(where: { $0.id == preferredActiveGroupID })
            ?? normalizedGroups.firstIndex(where: { !$0.tabIDs.isEmpty })
            ?? 0

        let unassignedTabIDs = availableTabIDs.filter { !seen.contains($0) }
        if !unassignedTabIDs.isEmpty {
            normalizedGroups[activeGroupIndex].tabIDs.append(contentsOf: unassignedTabIDs)
        }

        for index in normalizedGroups.indices {
            let selectedTabID = normalizedGroups[index].selectedTabID
            if let selectedTabID,
               normalizedGroups[index].tabIDs.contains(selectedTabID) {
                continue
            }
            normalizedGroups[index].selectedTabID = normalizedGroups[index].tabIDs.last
        }

        return WorkspaceEditorPresentationState(
            groups: normalizedGroups,
            activeGroupID: normalizedGroups[activeGroupIndex].id,
            splitAxis: normalizedGroups.count > 1 ? (sourcePresentation.splitAxis ?? .horizontal) : nil,
            splitRatio: sourcePresentation.splitRatio
        )
    }

    private func normalizedWorkspaceEditorPresentationState(
        _ presentation: WorkspaceEditorPresentationState?,
        projectPath: String
    ) -> WorkspaceEditorPresentationState? {
        normalizedWorkspaceEditorPresentationState(
            presentation,
            availableTabs: workspaceEditorTabsByProjectPath[projectPath] ?? []
        )
    }

    private func resolvedWorkspaceEditorPresentationState(for projectPath: String) -> WorkspaceEditorPresentationState? {
        normalizedWorkspaceEditorPresentationState(
            workspaceEditorPresentationByProjectPath[projectPath],
            projectPath: projectPath
        )
    }

    private func workspaceEditorPresentationStateForRestore(projectPath: String) -> WorkspaceEditorPresentationState? {
        let persistentTabs = (workspaceEditorTabsByProjectPath[projectPath] ?? []).filter { !$0.isPreview }
        return normalizedWorkspaceEditorPresentationState(
            workspaceEditorPresentationByProjectPath[projectPath],
            availableTabs: persistentTabs
        )
    }

    private func activateWorkspaceEditorTab(_ tabID: String, in projectPath: String) {
        guard let editorTab = workspaceEditorTabsByProjectPath[projectPath]?.first(where: { $0.id == tabID }) else {
            return
        }

        var presentation = resolvedWorkspaceEditorPresentationState(for: projectPath)
            ?? makeDefaultWorkspaceEditorPresentationState(tabs: workspaceEditorTabsByProjectPath[projectPath] ?? [])
        if let groupIndex = presentation.groups.firstIndex(where: { $0.tabIDs.contains(tabID) }) {
            presentation.activeGroupID = presentation.groups[groupIndex].id
            presentation.groups[groupIndex].selectedTabID = tabID
        } else {
            presentation = makeDefaultWorkspaceEditorPresentationState(
                tabs: workspaceEditorTabsByProjectPath[projectPath] ?? []
            )
            if let groupIndex = presentation.groups.firstIndex(where: { $0.tabIDs.contains(tabID) }) {
                presentation.activeGroupID = presentation.groups[groupIndex].id
                presentation.groups[groupIndex].selectedTabID = tabID
            }
        }

        workspaceEditorPresentationByProjectPath[projectPath] = normalizedWorkspaceEditorPresentationState(
            presentation,
            projectPath: projectPath
        )
        workspaceSelectedPresentedTabByProjectPath[projectPath] = .editor(tabID)
        workspaceFocusedArea = .editorTab(tabID)
        selectWorkspaceProjectTreeNode(editorTab.filePath, in: projectPath)
    }

    private func assignWorkspaceEditorTab(_ tabID: String, toActiveGroupIn projectPath: String) {
        guard workspaceEditorTabsByProjectPath[projectPath]?.contains(where: { $0.id == tabID }) == true else {
            return
        }

        var presentation = resolvedWorkspaceEditorPresentationState(for: projectPath)
            ?? makeDefaultWorkspaceEditorPresentationState(tabs: workspaceEditorTabsByProjectPath[projectPath] ?? [])
        if presentation.groups.isEmpty {
            presentation = makeDefaultWorkspaceEditorPresentationState(
                tabs: workspaceEditorTabsByProjectPath[projectPath] ?? []
            )
        }

        let activeGroupIndex = presentation.groups.firstIndex(where: { $0.id == presentation.activeGroupID }) ?? 0
        for index in presentation.groups.indices {
            presentation.groups[index].tabIDs.removeAll(where: { $0 == tabID })
            if presentation.groups[index].selectedTabID == tabID {
                presentation.groups[index].selectedTabID = presentation.groups[index].tabIDs.last
            }
        }
        presentation.groups[activeGroupIndex].tabIDs.append(tabID)
        presentation.groups[activeGroupIndex].selectedTabID = tabID
        presentation.activeGroupID = presentation.groups[activeGroupIndex].id

        workspaceEditorPresentationByProjectPath[projectPath] = normalizedWorkspaceEditorPresentationState(
            presentation,
            projectPath: projectPath
        )
    }

    private func removingWorkspaceEditorTab(
        _ tabID: String,
        from presentation: WorkspaceEditorPresentationState?,
        projectPath: String
    ) -> WorkspaceEditorPresentationState? {
        guard var presentation else {
            return normalizedWorkspaceEditorPresentationState(nil, projectPath: projectPath)
        }

        for index in presentation.groups.indices {
            presentation.groups[index].tabIDs.removeAll(where: { $0 == tabID })
            if presentation.groups[index].selectedTabID == tabID {
                presentation.groups[index].selectedTabID = presentation.groups[index].tabIDs.last
            }
        }
        return normalizedWorkspaceEditorPresentationState(presentation, projectPath: projectPath)
    }

    private func preferredWorkspaceEditorTabAfterClosing(
        _ tabID: String,
        removedIndex: Int,
        in projectPath: String,
        remainingTabs: [WorkspaceEditorTabState]
    ) -> String? {
        if let presentation = resolvedWorkspaceEditorPresentationState(for: projectPath),
           let activeGroup = presentation.groups.first(where: { $0.id == presentation.activeGroupID }) {
            if let selectedTabID = activeGroup.selectedTabID {
                return selectedTabID
            }
            if let firstTabID = activeGroup.tabIDs.last {
                return firstTabID
            }
        }

        if remainingTabs.indices.contains(removedIndex) {
            return remainingTabs[removedIndex].id
        }
        return remainingTabs.last?.id
    }

    private func workspaceEditorRestoreState(for projectPath: String) -> WorkspaceEditorRestoreState {
        let tabs = (workspaceEditorTabsByProjectPath[projectPath] ?? [])
            .filter { !$0.isPreview }
            .map {
                WorkspaceEditorTabRestoreSnapshot(
                    id: $0.id,
                    filePath: $0.filePath,
                    title: $0.title,
                    isPinned: $0.isPinned
                )
            }

        return WorkspaceEditorRestoreState(
            tabs: tabs,
            selectedPresentedTab: workspaceRestorePresentedTabSelection(for: projectPath),
            presentation: workspaceEditorPresentationStateForRestore(projectPath: projectPath)
        )
    }

    private func workspaceRestorePresentedTabSelection(for projectPath: String) -> WorkspaceRestorePresentedTabSelection? {
        guard let selection = resolvedWorkspacePresentedTabSelection(for: projectPath) else {
            return nil
        }

        switch selection {
        case let .terminal(tabID):
            return .terminal(tabID)
        case let .editor(tabID):
            guard let editorTab = workspaceEditorTabsByProjectPath[projectPath]?.first(where: { $0.id == tabID }),
                  !editorTab.isPreview
            else {
                return nil
            }
            return .editor(tabID)
        case .diff:
            return nil
        }
    }

    private func restoreWorkspaceEditorPresentation(from snapshot: WorkspaceRestoreSnapshot) {
        let restoredProjectPaths = Set(openWorkspaceProjectPaths)
        workspacePendingEditorCloseRequest = nil
        workspacePendingEditorBatchCloseState = nil
        for projectPath in restoredProjectPaths {
            workspaceEditorDirectoryWatchersByProjectPath[projectPath]?.values.forEach { $0.stop() }
            workspaceEditorDirectoryWatchersByProjectPath[projectPath] = nil
            workspaceEditorTabsByProjectPath[projectPath] = []
            workspaceEditorPresentationByProjectPath[projectPath] = nil
            workspaceEditorRuntimeSessionsByProjectPath[projectPath] = [:]
            workspaceSelectedPresentedTabByProjectPath[projectPath] = nil
        }

        for sessionSnapshot in snapshot.sessions where restoredProjectPaths.contains(sessionSnapshot.projectPath) {
            let projectPath = sessionSnapshot.projectPath
            var restoredTabs: [WorkspaceEditorTabState] = []
            for tabSnapshot in sessionSnapshot.editorTabs {
                let normalizedFilePath = normalizePathForCompare(tabSnapshot.filePath)
                guard let document = try? workspaceFileSystemService.loadDocument(at: normalizedFilePath) else {
                    continue
                }
                reinsertWorkspaceEditorTab(
                    WorkspaceEditorTabState(
                    id: tabSnapshot.id,
                    identity: normalizedFilePath,
                    projectPath: projectPath,
                    filePath: normalizedFilePath,
                    title: tabSnapshot.title,
                    isPinned: tabSnapshot.isPinned,
                    isPreview: false,
                    kind: document.kind,
                    text: document.text,
                    isEditable: document.isEditable,
                    externalChangeState: .inSync,
                    message: document.message,
                    lastLoadedModificationDate: document.modificationDate,
                    savedContentFingerprint: document.contentFingerprint
                    ),
                    into: &restoredTabs
                )
            }
            workspaceEditorTabsByProjectPath[projectPath] = restoredTabs
            syncWorkspaceEditorRuntimeSessions(for: projectPath)
            syncWorkspaceEditorDirectoryWatchers(for: projectPath)
            workspaceEditorPresentationByProjectPath[projectPath] = normalizedWorkspaceEditorPresentationState(
                sessionSnapshot.editorPresentation
                    ?? makeDefaultWorkspaceEditorPresentationState(tabs: restoredTabs),
                projectPath: projectPath
            )

            guard let selectedPresentedTab = sessionSnapshot.selectedPresentedTab else {
                continue
            }

            switch selectedPresentedTab {
            case let .terminal(tabID):
                workspaceSelectedPresentedTabByProjectPath[projectPath] = .terminal(tabID)
            case let .editor(tabID):
                guard workspaceEditorTabsByProjectPath[projectPath]?.contains(where: { $0.id == tabID }) == true else {
                    continue
                }
                workspaceSelectedPresentedTabByProjectPath[projectPath] = .editor(tabID)
            }
        }
    }

    private func remapWorkspacePathPrefix(
        _ path: String,
        sourcePrefix: String,
        destinationPrefix: String
    ) -> String {
        let normalizedPath = normalizePathForCompare(path)
        if normalizedPath == sourcePrefix {
            return destinationPrefix
        }
        guard normalizedPath.hasPrefix(sourcePrefix + "/") else {
            return normalizedPath
        }
        let suffix = String(normalizedPath.dropFirst(sourcePrefix.count))
        return destinationPrefix + suffix
    }

    private func isExternalEditorMessage(_ message: String?) -> Bool {
        guard let message else {
            return false
        }
        return message.hasPrefix("检测到文件已被外部修改")
            || message.hasPrefix("文件已在磁盘上被删除")
            || message.hasPrefix("磁盘上的文件已被删除")
    }

    private func updateWorkspaceEditorTab(
        _ tabID: String,
        in projectPath: String,
        mutate: (inout WorkspaceEditorTabState) -> Void
    ) {
        guard var tabs = workspaceEditorTabsByProjectPath[projectPath],
              let index = tabs.firstIndex(where: { $0.id == tabID })
        else {
            return
        }
        mutate(&tabs[index])
        workspaceEditorTabsByProjectPath[projectPath] = tabs
    }

    private func resetWorkspaceEditorRuntimeSession(_ tabID: String, in projectPath: String) {
        var sessions = workspaceEditorRuntimeSessionsByProjectPath[projectPath] ?? [:]
        sessions.removeValue(forKey: tabID)
        workspaceEditorRuntimeSessionsByProjectPath[projectPath] = sessions
    }

    private func removeWorkspaceEditorRuntimeSession(_ tabID: String, in projectPath: String) {
        resetWorkspaceEditorRuntimeSession(tabID, in: projectPath)
    }

    private func syncWorkspaceEditorRuntimeSessions(for projectPath: String) {
        let validTabIDs = Set((workspaceEditorTabsByProjectPath[projectPath] ?? []).map(\.id))
        guard !validTabIDs.isEmpty else {
            workspaceEditorRuntimeSessionsByProjectPath[projectPath] = [:]
            return
        }

        var sessions = workspaceEditorRuntimeSessionsByProjectPath[projectPath] ?? [:]
        sessions = sessions.filter { validTabIDs.contains($0.key) }
        workspaceEditorRuntimeSessionsByProjectPath[projectPath] = sessions
    }

    private func syncWorkspaceEditorDirectoryWatchers(for projectPath: String) {
        let requiredDirectories = Set(
            (workspaceEditorTabsByProjectPath[projectPath] ?? []).map {
                workspaceFileSystemService.parentDirectoryPath(for: $0.filePath)
            }
        )
        var watchers = workspaceEditorDirectoryWatchersByProjectPath[projectPath] ?? [:]

        for directoryPath in Set(watchers.keys).subtracting(requiredDirectories) {
            watchers.removeValue(forKey: directoryPath)?.stop()
        }

        for directoryPath in requiredDirectories where watchers[directoryPath] == nil {
            let normalizedDirectoryPath = normalizePathForCompare(directoryPath)
            let watcher = WorkspaceDirectoryWatcher(directoryPath: normalizedDirectoryPath) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.handleWorkspaceEditorDirectoryEvent(
                        normalizedDirectoryPath,
                        projectPath: projectPath
                    )
                }
            }
            if let watcher {
                watchers[normalizedDirectoryPath] = watcher
            }
        }

        workspaceEditorDirectoryWatchersByProjectPath[projectPath] = watchers
    }

    private func handleWorkspaceEditorDirectoryEvent(_ directoryPath: String, projectPath: String) {
        let normalizedDirectoryPath = normalizePathForCompare(directoryPath)
        let tabIDs = (workspaceEditorTabsByProjectPath[projectPath] ?? [])
            .filter {
                workspaceFileSystemService.parentDirectoryPath(for: $0.filePath) == normalizedDirectoryPath
            }
            .map(\.id)
        guard !tabIDs.isEmpty else {
            syncWorkspaceEditorDirectoryWatchers(for: projectPath)
            return
        }
        for tabID in tabIDs {
            checkWorkspaceEditorTabExternalChange(tabID, in: projectPath)
        }
    }

    private func resolvedWorkspacePresentedTabSelection(
        for projectPath: String,
        controller: GhosttyWorkspaceController? = nil
    ) -> WorkspacePresentedTabSelection? {
        let controller = controller ?? workspaceController(for: projectPath)
        let terminalTabID = controller?.selectedTabId
            ?? controller?.selectedTab?.id
        let editorTabs = workspaceEditorTabsByProjectPath[projectPath] ?? []
        let diffTabs = workspaceDiffTabsByProjectPath[projectPath] ?? []

        if let stored = workspaceSelectedPresentedTabByProjectPath[projectPath] {
            switch stored {
            case let .terminal(tabID):
                if controller?.tabs.contains(where: { $0.id == tabID }) == true {
                    return .terminal(tabID)
                }
            case let .editor(tabID):
                if editorTabs.contains(where: { $0.id == tabID }) {
                    return .editor(tabID)
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
        case let .editor(tabID):
            guard workspaceEditorTabsByProjectPath[projectPath]?.contains(where: { $0.id == tabID }) == true else {
                return nil
            }
            return .editor(tabID)
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
        case let .browserPaneItem(itemID):
            guard case .terminal = selection,
                  let controller = workspaceController(for: projectPath),
                  workspacePaneItemContext(for: itemID, in: controller)?.item.isBrowser == true
            else {
                workspaceFocusedArea = defaultFocusedArea(for: selection)
                return false
            }
            workspaceFocusedArea = .browserPaneItem(itemID)
            return true
        case let .sideToolWindow(kind):
            showWorkspaceSideToolWindow(kind)
            return true
        case let .bottomToolWindow(kind):
            showWorkspaceBottomToolWindow(kind)
            return true
        case let .editorTab(tabID):
            guard validPresentedTabSelection(.editor(tabID), in: projectPath, diffTabs: remainingDiffTabs) != nil else {
                workspaceFocusedArea = defaultFocusedArea(for: selection)
                return false
            }
            workspaceFocusedArea = .editorTab(tabID)
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
        case let .editor(tabID):
            return .editorTab(tabID)
        case let .diff(tabID):
            return .diffTab(tabID)
        }
    }

    private func clearWorkspaceRuntimePresentationState(for paths: Set<String>) {
        for path in paths {
            workspaceEditorDirectoryWatchersByProjectPath[path]?.values.forEach { $0.stop() }
            workspaceEditorDirectoryWatchersByProjectPath[path] = nil
            workspaceProjectTreeRefreshTasksByProjectPath[path]?.cancel()
            workspaceProjectTreeRefreshTasksByProjectPath[path] = nil
            workspaceProjectTreeRefreshGenerationByProjectPath[path] = nil
            workspaceProjectTreeRefreshingProjectPaths.remove(path)
            workspaceEditorTabsByProjectPath[path] = nil
            workspaceEditorPresentationByProjectPath[path] = nil
            workspaceEditorRuntimeSessionsByProjectPath[path] = nil
            for tab in workspaceDiffTabsByProjectPath[path] ?? [] {
                workspaceDiffTabViewModels[tab.id] = nil
            }
            workspaceProjectTreeStatesByProjectPath[path] = nil
            workspaceProjectTreeProjectionCacheByProjectPath[path] = nil
            workspaceDiffTabsByProjectPath[path] = nil
            workspaceSelectedPresentedTabByProjectPath[path] = nil
        }
    }

    private var activeWorkspaceSession: OpenWorkspaceSessionState? {
        workspaceSessionWithoutNormalizing(for: activeWorkspaceProjectPath)
            ?? workspaceSession(for: activeWorkspaceProjectPath)
    }

    private func workspaceController(for projectPath: String? = nil) -> GhosttyWorkspaceController? {
        let resolvedPath = projectPath ?? activeWorkspaceProjectPath
        return workspaceSessionWithoutNormalizing(for: resolvedPath)?.controller
            ?? workspaceSession(for: resolvedPath)?.controller
    }

    private func syncMountedWorkspaceProjectPath(
        afterChangingActiveWorkspaceFrom oldValue: String?,
        to newValue: String?
    ) {
        if let newValue,
           let canonicalPath = canonicalWorkspaceSessionPath(for: newValue) {
            hiddenMountedWorkspaceProjectPath = canonicalPath
            return
        }

        if let oldValue,
           let canonicalPath = canonicalWorkspaceSessionPath(for: oldValue) {
            hiddenMountedWorkspaceProjectPath = canonicalPath
            return
        }

        syncMountedWorkspaceProjectPathAfterSessionMutation()
    }

    private func syncMountedWorkspaceProjectPathAfterSessionMutation() {
        if let activeWorkspaceProjectPath,
           let canonicalPath = canonicalWorkspaceSessionPath(for: activeWorkspaceProjectPath) {
            hiddenMountedWorkspaceProjectPath = canonicalPath
            return
        }

        if let hiddenMountedWorkspaceProjectPath,
           let canonicalPath = canonicalWorkspaceSessionPath(for: hiddenMountedWorkspaceProjectPath) {
            self.hiddenMountedWorkspaceProjectPath = canonicalPath
            return
        }

        hiddenMountedWorkspaceProjectPath = nil
    }

    private func workspacePaneItemContext(
        for itemID: String,
        in controller: GhosttyWorkspaceController
    ) -> (pane: WorkspacePaneState, item: WorkspacePaneItemState)? {
        for tab in controller.tabs {
            for pane in tab.leaves {
                if let item = pane.items.first(where: { $0.id == itemID }) {
                    return (pane, item)
                }
            }
        }
        return nil
    }

    private func workspaceSessionWithoutNormalizing(for path: String?) -> OpenWorkspaceSessionState? {
        guard let path else {
            return nil
        }
        return openWorkspaceSessions.first(where: { $0.projectPath == path })
    }

    private func resolvedWorkspaceProjectPathKey(_ projectPath: String?) -> String? {
        guard let projectPath = projectPath ?? activeWorkspaceProjectPath else {
            return nil
        }
        return normalizedOptionalPathForCompare(projectPath)
    }

    private func normalizedPathsMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        normalizedOptionalPathForCompare(lhs) == normalizedOptionalPathForCompare(rhs)
    }

    private func displayWorkspaceProjectPath(for projectPath: String) -> String {
        resolveDisplayProject(for: projectPath, rootProjectPath: projectPath)?.path ?? projectPath
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
                state.sessions[index].appendDisplayChunk(chunk)
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

    private func scheduleWorkspaceRootWorktreeRefreshIfNeeded(_ rootProjectPath: String) {
        let normalizedRootProjectPath = normalizePathForCompare(rootProjectPath)
        guard !normalizedRootProjectPath.isEmpty,
              let project = projectsByNormalizedPath[normalizedRootProjectPath],
              project.isGitRepository,
              !project.isTransientWorkspaceProject,
              workspaceWorktreeRefreshTasksByRootProjectPath[normalizedRootProjectPath] == nil
        else {
            return
        }

        workspaceWorktreeRefreshTasksByRootProjectPath[normalizedRootProjectPath] = Task { [weak self] in
            guard let self else {
                return
            }
            defer {
                Task { @MainActor [weak self] in
                    self?.workspaceWorktreeRefreshTasksByRootProjectPath.removeValue(forKey: normalizedRootProjectPath)
                }
            }
            try? await self.refreshProjectWorktrees(normalizedRootProjectPath)
        }
    }

    private func resolveWorkspaceWorktree(
        at normalizedWorktreePath: String,
        from normalizedRootProjectPath: String,
        rootProject: Project
    ) -> ProjectWorktree? {
        if let worktree = rootProject.worktrees.first(where: {
            normalizePathForCompare($0.path) == normalizedWorktreePath
        }) {
            return worktree
        }

        do {
            let resolvedWorktrees = try worktreeService.listWorktrees(at: rootProject.path)
            let resolvedCurrentBranch = try? worktreeService.currentBranch(at: rootProject.path)
            try syncProjectRepositoryState(
                rootProjectPath: normalizedRootProjectPath,
                gitWorktrees: resolvedWorktrees,
                currentBranch: resolvedCurrentBranch
            )
        } catch {
            return nil
        }

        return snapshot.projects.first(where: {
            normalizePathForCompare($0.path) == normalizedRootProjectPath
        })?.worktrees.first(where: {
            normalizePathForCompare($0.path) == normalizedWorktreePath
        })
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
            if member.specifiedBaseBranch?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                let projectName = snapshot.projects.first(where: {
                    normalizePathForCompare($0.path) == normalizePathForCompare(member.projectPath)
                })?.name ?? pathLastComponent(member.projectPath)
                throw NativeWorktreeError.invalidBaseBranch("请为 \(projectName) 选择基线分支")
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
        let branch = member.specifiedBaseBranch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !branch.isEmpty else {
            if member.baseBranchMode == .autoDetect {
                throw NativeWorktreeError.invalidBaseBranch("旧工作区配置仍在使用自动探测，请重新选择基线分支")
            }
            throw NativeWorktreeError.invalidBaseBranch("请选择基线分支")
        }
        return branch
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
            let visibleSidebarSession = openWorkspaceSessions.first(where: {
                normalizePathForCompare($0.projectPath) == normalizePathForCompare(worktree.path) &&
                    !$0.isQuickTerminal &&
                    normalizePathForCompare($0.rootProjectPath) == normalizePathForCompare(rootProjectPath)
            })
            let attention = visibleSidebarSession.flatMap { workspaceAttentionState(for: $0.projectPath) }
            let paneOverrides = agentDisplayOverridesByPaneID(for: worktree.path)
            let preferredPaneIDs = preferredSidebarAgentPaneIDs(for: visibleSidebarSession)
            return WorkspaceSidebarWorktreeItem(
                rootProjectPath: rootProjectPath,
                worktree: worktree,
                isOpen: visibleSidebarSession != nil,
                isActive: visibleSidebarSession != nil && normalizedPathsMatch(activeWorkspaceProjectPath, worktree.path),
                notifications: showsInAppNotifications ? (attention?.notifications ?? []) : [],
                unreadNotificationCount: showsInAppNotifications ? (attention?.unreadCount ?? 0) : 0,
                taskStatus: attention.map(\.taskStatus),
                agentState: resolvedSidebarAgentState(
                    attention: attention,
                    overridesByPaneID: paneOverrides,
                    preferredPaneIDs: preferredPaneIDs
                ),
                agentPhase: resolvedSidebarAgentPhase(
                    attention: attention,
                    overridesByPaneID: paneOverrides,
                    preferredPaneIDs: preferredPaneIDs
                ),
                agentAttention: resolvedSidebarAgentAttention(
                    attention: attention,
                    overridesByPaneID: paneOverrides,
                    preferredPaneIDs: preferredPaneIDs
                ),
                agentSummary: resolvedSidebarAgentSummary(
                    attention: attention,
                    overridesByPaneID: paneOverrides,
                    preferredPaneIDs: preferredPaneIDs
                ),
                agentKind: resolvedSidebarAgentKind(
                    attention: attention,
                    overridesByPaneID: paneOverrides,
                    preferredPaneIDs: preferredPaneIDs
                ),
                agentUpdatedAt: resolvedSidebarAgentUpdatedAt(
                    attention: attention,
                    overridesByPaneID: paneOverrides,
                    preferredPaneIDs: preferredPaneIDs
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
                    agentPhase: nil,
                    agentAttention: nil,
                    agentSummary: nil,
                    agentKind: nil,
                    agentUpdatedAt: nil,
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

    private func preferredSidebarAgentPaneIDs(
        for session: OpenWorkspaceSessionState?
    ) -> Set<String> {
        guard let session else {
            return []
        }
        let projectPath = normalizePathForCompare(session.projectPath)
        let controller = session.controller

        if case let .terminal(selectedTerminalTabID)? = resolvedWorkspacePresentedTabSelection(
            for: projectPath,
            controller: controller
        ),
           let selectedTab = controller.tabs.first(where: { $0.id == selectedTerminalTabID }) {
            return Set(selectedTab.leaves.map(\.id))
        }

        if let selectedTab = controller.selectedTab {
            return Set(selectedTab.leaves.map(\.id))
        }

        return []
    }

    private func resolvedSidebarAgentState(
        attention: WorkspaceAttentionState?,
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride],
        preferredPaneIDs: Set<String>
    ) -> WorkspaceAgentState? {
        guard let attention else {
            return nil
        }
        return preferredPaneIDs.isEmpty
            ? attention.resolvedAgentState(overridesByPaneID: overridesByPaneID)
            : attention.resolvedAgentState(
                overridesByPaneID: overridesByPaneID,
                preferringPaneIDs: preferredPaneIDs
            )
    }

    private func resolvedSidebarAgentPhase(
        attention: WorkspaceAttentionState?,
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride],
        preferredPaneIDs: Set<String>
    ) -> WorkspaceAgentPhase? {
        guard let attention else {
            return nil
        }
        return preferredPaneIDs.isEmpty
            ? attention.resolvedAgentPhase(overridesByPaneID: overridesByPaneID)
            : attention.resolvedAgentPhase(
                overridesByPaneID: overridesByPaneID,
                preferringPaneIDs: preferredPaneIDs
            )
    }

    private func resolvedSidebarAgentAttention(
        attention: WorkspaceAttentionState?,
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride],
        preferredPaneIDs: Set<String>
    ) -> WorkspaceAgentAttentionRequirement? {
        guard let attention else {
            return nil
        }
        return preferredPaneIDs.isEmpty
            ? attention.resolvedAgentAttention(overridesByPaneID: overridesByPaneID)
            : attention.resolvedAgentAttention(
                overridesByPaneID: overridesByPaneID,
                preferringPaneIDs: preferredPaneIDs
            )
    }

    private func resolvedSidebarAgentSummary(
        attention: WorkspaceAttentionState?,
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride],
        preferredPaneIDs: Set<String>
    ) -> String? {
        guard let attention else {
            return nil
        }
        return preferredPaneIDs.isEmpty
            ? attention.resolvedAgentSummary(overridesByPaneID: overridesByPaneID)
            : attention.resolvedAgentSummary(
                overridesByPaneID: overridesByPaneID,
                preferringPaneIDs: preferredPaneIDs
            )
    }

    private func resolvedSidebarAgentKind(
        attention: WorkspaceAttentionState?,
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride],
        preferredPaneIDs: Set<String>
    ) -> WorkspaceAgentKind? {
        guard let attention else {
            return nil
        }
        return preferredPaneIDs.isEmpty
            ? attention.resolvedAgentKind(overridesByPaneID: overridesByPaneID)
            : attention.resolvedAgentKind(
                overridesByPaneID: overridesByPaneID,
                preferringPaneIDs: preferredPaneIDs
            )
    }

    private func resolvedSidebarAgentUpdatedAt(
        attention: WorkspaceAttentionState?,
        overridesByPaneID: [String: WorkspaceAgentPresentationOverride],
        preferredPaneIDs: Set<String>
    ) -> Date? {
        guard let attention else {
            return nil
        }
        return preferredPaneIDs.isEmpty
            ? attention.resolvedAgentUpdatedAt(overridesByPaneID: overridesByPaneID)
            : attention.resolvedAgentUpdatedAt(
                overridesByPaneID: overridesByPaneID,
                preferringPaneIDs: preferredPaneIDs
            )
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
        if workspaceAttentionState(for: rootProjectPath) != nil || worktrees.contains(where: { $0.taskStatus != nil }) {
            return .idle
        }
        return nil
    }

    private struct SidebarGroupAgentProjection {
        var state: WorkspaceAgentState
        var phase: WorkspaceAgentPhase?
        var attention: WorkspaceAgentAttentionRequirement?
        var summary: String?
        var kind: WorkspaceAgentKind?
        var updatedAt: Date?
    }

    private func makeGroupAgentProjection(
        rootIsActive: Bool,
        rootAgentState: WorkspaceAgentState?,
        rootAgentPhase: WorkspaceAgentPhase?,
        rootAgentAttention: WorkspaceAgentAttentionRequirement?,
        rootAgentSummary: String?,
        rootAgentKind: WorkspaceAgentKind?,
        rootAgentUpdatedAt: Date?,
        worktrees: [WorkspaceSidebarWorktreeItem]
    ) -> SidebarGroupAgentProjection? {
        let activeWorktreeCandidates = worktrees.compactMap { worktree -> SidebarGroupAgentCandidate? in
            guard worktree.isActive, let state = worktree.agentState else {
                return nil
            }
            return SidebarGroupAgentCandidate(
                state: state,
                phase: worktree.agentPhase,
                attention: worktree.agentAttention,
                summary: worktree.agentSummary,
                kind: worktree.agentKind,
                updatedAt: worktree.agentUpdatedAt,
                isActive: true,
                isOpen: worktree.isOpen
            )
        }
        if let prioritizedActiveWorktree = prioritizedSidebarAgentCandidate(from: activeWorktreeCandidates) {
            return SidebarGroupAgentProjection(
                state: prioritizedActiveWorktree.state,
                phase: prioritizedActiveWorktree.phase,
                attention: prioritizedActiveWorktree.attention,
                summary: prioritizedActiveWorktree.summary,
                kind: prioritizedActiveWorktree.kind,
                updatedAt: prioritizedActiveWorktree.updatedAt
            )
        }

        var fallbackCandidates = worktrees.compactMap { worktree -> SidebarGroupAgentCandidate? in
            guard let state = worktree.agentState else {
                return nil
            }
            return SidebarGroupAgentCandidate(
                state: state,
                phase: worktree.agentPhase,
                attention: worktree.agentAttention,
                summary: worktree.agentSummary,
                kind: worktree.agentKind,
                updatedAt: worktree.agentUpdatedAt,
                isActive: worktree.isActive,
                isOpen: worktree.isOpen
            )
        }
        if let rootAgentState {
            fallbackCandidates.append(
                SidebarGroupAgentCandidate(
                    state: rootAgentState,
                    phase: rootAgentPhase,
                    attention: rootAgentAttention,
                    summary: rootAgentSummary,
                    kind: rootAgentKind,
                    updatedAt: rootAgentUpdatedAt,
                    isActive: rootIsActive,
                    isOpen: rootIsActive,
                    isRoot: true
                )
            )
        }

        guard let prioritizedCandidate = prioritizedSidebarAgentCandidate(from: fallbackCandidates) else {
            return nil
        }
        return SidebarGroupAgentProjection(
            state: prioritizedCandidate.state,
            phase: prioritizedCandidate.phase,
            attention: prioritizedCandidate.attention,
            summary: prioritizedCandidate.summary,
            kind: prioritizedCandidate.kind,
            updatedAt: prioritizedCandidate.updatedAt
        )
    }

    private func prioritizedSidebarAgentCandidate(
        from candidates: [SidebarGroupAgentCandidate]
    ) -> SidebarGroupAgentCandidate? {
        candidates.max { lhs, rhs in
            if lhs.activityPriority != rhs.activityPriority {
                return lhs.activityPriority < rhs.activityPriority
            }
            if (lhs.attention?.priority ?? 0) != (rhs.attention?.priority ?? 0) {
                return (lhs.attention?.priority ?? 0) < (rhs.attention?.priority ?? 0)
            }
            if lhs.state.priority != rhs.state.priority {
                return lhs.state.priority < rhs.state.priority
            }
            if (lhs.updatedAt ?? .distantPast) != (rhs.updatedAt ?? .distantPast) {
                return (lhs.updatedAt ?? .distantPast) < (rhs.updatedAt ?? .distantPast)
            }
            if lhs.isRoot != rhs.isRoot {
                return lhs.isRoot && !rhs.isRoot
            }
            return false
        }
    }

    private struct SidebarGroupAgentCandidate {
        var state: WorkspaceAgentState
        var phase: WorkspaceAgentPhase?
        var attention: WorkspaceAgentAttentionRequirement?
        var summary: String?
        var kind: WorkspaceAgentKind?
        var updatedAt: Date?
        var isActive: Bool
        var isOpen: Bool
        var isRoot: Bool = false

        var activityPriority: Int {
            if isActive {
                return 2
            }
            if isOpen {
                return 1
            }
            return 0
        }
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
        let normalizedSnapshots = normalizedAgentSignalSnapshots(snapshots)
        let openPaths = Set(openWorkspaceProjectPaths)
        guard lastAppliedAgentSignalProjectPaths != openPaths ||
                lastAppliedAgentSignalSnapshotsByTerminalSessionID != normalizedSnapshots
        else {
            return
        }

        let previousSnapshots = lastAppliedAgentSignalSnapshotsByTerminalSessionID
        var nextAttentionStateByProjectPath = attentionStateByProjectPath.filter { openPaths.contains($0.key) }

        for (terminalSessionID, previousSignal) in previousSnapshots {
            guard openPaths.contains(previousSignal.projectPath) else {
                continue
            }
            if let currentSignal = snapshots[terminalSessionID],
               currentSignal.projectPath == previousSignal.projectPath,
               currentSignal.paneId == previousSignal.paneId {
                continue
            }
            guard var attention = nextAttentionStateByProjectPath[previousSignal.projectPath] else {
                continue
            }
            attention.clearAgentState(for: previousSignal.paneId)
            nextAttentionStateByProjectPath[previousSignal.projectPath] = attention
        }

        for (terminalSessionID, signal) in normalizedSnapshots where openPaths.contains(signal.projectPath) {
            if previousSnapshots[terminalSessionID] == signal {
                continue
            }
            var attention = nextAttentionStateByProjectPath[signal.projectPath] ?? WorkspaceAttentionState()
            applyAgentSignal(signal, to: &attention)
            nextAttentionStateByProjectPath[signal.projectPath] = attention
        }

        if attentionStateByProjectPath != nextAttentionStateByProjectPath {
            attentionStateByProjectPath = nextAttentionStateByProjectPath
        }
        lastAppliedAgentSignalProjectPaths = openPaths
        lastAppliedAgentSignalSnapshotsByTerminalSessionID = normalizedSnapshots
        pruneWorkspaceAgentDisplayOverrides()
    }

    private func invalidateAppliedAgentSignalCache() {
        lastAppliedAgentSignalProjectPaths = []
        lastAppliedAgentSignalSnapshotsByTerminalSessionID = [:]
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
        guard !overridesByProjectPath.isEmpty else {
            return [:]
        }

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
            signal.effectiveState,
            kind: signal.agentKind,
            sessionID: signal.sessionId,
            phase: signal.effectivePhase,
            attention: signal.effectiveAttention,
            summary: signal.summary,
            updatedAt: signal.updatedAt,
            for: signal.paneId
        )
    }

    private func agentDisplayOverridesByPaneID(for projectPath: String) -> [String: WorkspaceAgentPresentationOverride] {
        agentDisplayOverridesByProjectPath[normalizePathForCompare(projectPath)] ?? [:]
    }

    private func normalizedAgentSignalSnapshots(
        _ snapshots: [String: WorkspaceAgentSessionSignal]
    ) -> [String: WorkspaceAgentSessionSignal] {
        snapshots.reduce(into: [:]) { partialResult, entry in
            partialResult[entry.key] = normalizedAgentSignal(entry.value)
        }
    }

    private func normalizedAgentSignal(
        _ signal: WorkspaceAgentSessionSignal
    ) -> WorkspaceAgentSessionSignal {
        var normalized = signal
        normalized.projectPath = normalizePathForCompare(signal.projectPath)
        if let resolvedPaneID = currentPaneID(for: signal),
           resolvedPaneID != signal.paneId {
            normalized.paneId = resolvedPaneID
        }
        return normalized
    }

    private func currentPaneID(
        for signal: WorkspaceAgentSessionSignal
    ) -> String? {
        guard let controller = workspaceController(for: signal.projectPath) else {
            return nil
        }
        for tab in controller.tabs {
            for pane in tab.leaves {
                if pane.items.contains(where: {
                    $0.id == signal.surfaceId || $0.request.terminalSessionId == signal.terminalSessionId
                }) {
                    return pane.id
                }
            }
        }
        return nil
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
            } else if let session = workspaceSessionWithoutNormalizing(for: normalizedPath)
                        ?? workspaceSession(for: normalizedPath) {
                resolvedProject = session.transientDisplayProject
            } else {
                resolvedProject = nil
            }
        }

        displayProjectCacheByLookupKey[lookupKey] = resolvedProject
        return resolvedProject
    }

    private func normalizedTransientDisplayProject(
        _ project: Project?,
        fallbackPath: String
    ) -> Project? {
        guard let project else {
            return nil
        }
        if project.isDirectoryWorkspace {
            return Project.directoryWorkspace(at: fallbackPath)
        }
        return project
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

    private func cleanupMissingWorkspaceWorktreeRecord(
        rootProjectPath: String,
        worktree: ProjectWorktree,
        shouldDeleteBranch: Bool
    ) async throws -> NativeWorktreeCleanupResult {
        let request = NativeWorktreeCleanupRequest(
            sourceProjectPath: rootProjectPath,
            worktreePath: worktree.path,
            branch: worktree.branch,
            shouldDeleteCreatedBranch: shouldDeleteBranch
        )
        let worktreeService = self.worktreeService
        return try await Task.detached(priority: .userInitiated) {
            try worktreeService.cleanupFailedWorktreeCreate(request)
        }.value
    }

    private func shouldTreatMissingPersistedWorktreeAsStaleRecord(_ message: String) -> Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines) == "worktree 不存在或已移除"
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
    var normalized = canonicalPathForFileSystemCompare(trimmed)
        .replacingOccurrences(of: "\\", with: "/")
    while normalized.count > 1 && normalized.hasSuffix("/") {
        normalized.removeLast()
    }
    return normalized
}

private func canonicalPathForFileSystemCompare(_ path: String) -> String {
    let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
    let fileManager = FileManager.default
    var ancestorPath = standardizedPath
    var trailingComponents = [String]()

    while ancestorPath != "/", !fileManager.fileExists(atPath: ancestorPath) {
        let lastComponent = (ancestorPath as NSString).lastPathComponent
        guard !lastComponent.isEmpty else {
            break
        }
        trailingComponents.insert(lastComponent, at: 0)
        ancestorPath = (ancestorPath as NSString).deletingLastPathComponent
        if ancestorPath.isEmpty {
            ancestorPath = "/"
            break
        }
    }

    let canonicalAncestorPath = realpathString(ancestorPath) ?? ancestorPath
    guard !trailingComponents.isEmpty else {
        return canonicalAncestorPath
    }

    return trailingComponents.reduce(canonicalAncestorPath as NSString) { partial, component in
        partial.appendingPathComponent(component) as NSString
    } as String
}

private func realpathString(_ path: String) -> String? {
    guard !path.isEmpty else {
        return nil
    }
    return path.withCString { pointer in
        guard let resolvedPointer = realpath(pointer, nil) else {
            return nil
        }
        defer { free(resolvedPointer) }
        return String(cString: resolvedPointer)
    }
}

private func elapsedMilliseconds(since startTime: TimeInterval) -> Int {
    max(0, Int(((ProcessInfo.processInfo.systemUptime - startTime) * 1000).rounded()))
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

private func survivingDirectProjectPaths(
    from directProjectPaths: [String],
    rebuiltProjects: [Project]
) -> [String] {
    let rebuiltProjectPaths = Set(rebuiltProjects.map { normalizePathForCompare($0.path) })
    return normalizePathList(
        directProjectPaths.filter { rebuiltProjectPaths.contains(normalizePathForCompare($0)) }
    )
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
