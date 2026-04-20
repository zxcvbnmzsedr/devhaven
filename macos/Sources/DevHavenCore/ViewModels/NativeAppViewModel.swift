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

private struct WorkspaceSidebarProjectionCacheEntry {
    let revision: Int
    let state: WorkspaceSidebarProjectionState
}

private struct WorkspaceAlignmentGroupsCacheEntry {
    let revision: Int
    let groups: [WorkspaceAlignmentGroupProjection]
}

final class WorkspaceDirectoryWatcher: WorkspaceEditorDirectoryWatching {
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
    private let workspacePresentationState: WorkspacePresentationState
    private let workspaceProjectTreeStateStore: WorkspaceProjectTreeStateStore
    @ObservationIgnored private lazy var workspaceFeatureViewModelStore = WorkspaceFeatureViewModelStore(
        gitRepositoryService: gitRepositoryService,
        gitHubRepositoryService: gitHubRepositoryService,
        normalizePath: { normalizePathForCompare($0) },
        persistGitSelection: { [weak self] (rootProjectPath: String, familyID: String, executionPath: String) in
            self?.workspaceSelectedGitRepositoryFamilyIDByRootProjectPath[rootProjectPath] = familyID
            self?.workspaceSelectedGitExecutionPathByRootProjectPath[rootProjectPath] = executionPath
        },
        resolveSelectionSnapshot: { [weak self] (rootProjectPath: String) in
            self?.gitSelectionSnapshot(for: rootProjectPath)
        }
    )
    @ObservationIgnored private lazy var workspaceDiffViewModelStore = WorkspaceDiffViewModelStore(
        repositoryService: gitRepositoryService,
        normalizePath: { normalizePathForCompare($0) }
    )
    @ObservationIgnored private lazy var workspaceAttentionController = WorkspaceAttentionController(
        normalizePath: { normalizePathForCompare($0) },
        openProjectPaths: { [weak self] in self?.openWorkspaceProjectPaths ?? [] },
        activeProjectPath: { [weak self] in self?.activeWorkspaceProjectPath },
        notificationsEnabled: { [weak self] in
            self?.snapshot.appState.settings.workspaceInAppNotificationsEnabled ?? false
        },
        workspaceSession: { [weak self] in self?.workspaceSession(for: $0) },
        workspaceController: { [weak self] in self?.workspaceController(for: $0) },
        resolvedPresentedTabSelection: { [weak self] in
            self?.resolvedWorkspacePresentedTabSelection(for: $0, controller: $1)
        },
        isWorkspacePaneCurrentlyFocused: { [weak self] in
            self?.isWorkspacePaneCurrentlyFocused(projectPath: $0, tabID: $1, paneID: $2) ?? false
        },
        currentPaneIDForSignal: { [weak self] in self?.currentPaneID(for: $0) },
        attentionStateByProjectPath: { [weak self] in self?.attentionStateByProjectPath ?? [:] },
        setAttentionStateByProjectPath: { [weak self] in self?.attentionStateByProjectPath = $0 },
        agentDisplayOverridesByProjectPath: { [weak self] in self?.agentDisplayOverridesByProjectPath ?? [:] },
        setAgentDisplayOverridesByProjectPath: { [weak self] in self?.agentDisplayOverridesByProjectPath = $0 },
        reportError: { [weak self] in self?.errorMessage = $0 },
        codexDisplayCandidatesDidChange: { [weak self] _ in
            guard let self else {
                return
            }
            self.codexDisplayCandidatesRevision &+= 1
        },
        agentSignalStore: agentSignalStore
    )
    @ObservationIgnored lazy var workspaceDiffRequestBuilder = WorkspaceDiffRequestBuilder(
        commitChanges: { [weak self] in self?.activeWorkspaceCommitViewModel?.changesSnapshot?.changes },
        selectedGitCommitDetail: { [weak self] in self?.activeWorkspaceGitViewModel?.logViewModel.selectedCommitDetail }
    )
    @ObservationIgnored private lazy var workspaceRunConfigurationBuilder = WorkspaceRunConfigurationBuilder(
        normalizePath: { normalizePathForCompare($0) },
        projects: { [weak self] in self?.snapshot.projects ?? [] },
        resolveDisplayProject: { [weak self] in self?.resolveDisplayProject(for: $0) }
    )
    @ObservationIgnored private lazy var projectListProjectionBuilder = ProjectListProjectionBuilder(
        normalizePath: { normalizePathForCompare($0) }
    )
    @ObservationIgnored private lazy var projectCatalogSidebarProjectionBuilder = ProjectCatalogSidebarProjectionBuilder(
        normalizePath: { normalizePathForCompare($0) },
        pathLastComponent: { pathLastComponent($0) }
    )
    @ObservationIgnored lazy var workspaceRunController = WorkspaceRunController(
        runManager: runManager,
        terminalCommandRunner: terminalCommandRunner,
        normalizePath: { normalizePathForCompare($0) },
        activeProjectPath: { [weak self] in self?.activeWorkspaceProjectPath },
        openProjectPaths: { [weak self] in self?.openWorkspaceProjectPaths ?? [] },
        workspaceSession: { [weak self] in self?.workspaceSession(for: $0) },
        availableConfigurations: { [weak self] in self?.resolvedWorkspaceRunConfigurations(for: $0) ?? [] },
        reportError: { [weak self] in self?.errorMessage = $0 }
    )
    @ObservationIgnored private lazy var workspaceDisplayProjectResolver = WorkspaceDisplayProjectResolver(
        normalizePath: { normalizePathForCompare($0) },
        normalizeOptionalPath: { normalizedOptionalPathForCompare($0) },
        projects: { [weak self] in self?.snapshot.projects ?? [] },
        projectsByNormalizedPath: { [weak self] in self?.projectsByNormalizedPath ?? [:] },
        workspaceSessionWithoutNormalizing: { [weak self] in self?.workspaceSessionWithoutNormalizing(for: $0) },
        workspaceSession: { [weak self] in self?.workspaceSession(for: $0) },
        buildWorktreeVirtualProject: { sourceProject, worktree in
            buildWorktreeVirtualProject(sourceProject: sourceProject, worktree: worktree)
        }
    )
    @ObservationIgnored private lazy var workspaceProjectProjectionBuilder = WorkspaceProjectProjectionBuilder(
        normalizePath: { normalizePathForCompare($0) },
        resolveDisplayProject: { [weak self] in self?.resolveDisplayProject(for: $0, rootProjectPath: $1) },
        canonicalSessionPath: { [weak self] in self?.canonicalWorkspaceSessionPath(for: $0) },
        exactSession: { [weak self] in self?.workspaceSessionWithoutNormalizing(for: $0) },
        session: { [weak self] in self?.workspaceSession(for: $0) }
    )
    @ObservationIgnored private lazy var workspaceSessionDisplayMapper = WorkspaceSessionDisplayMapper(
        normalizePath: { normalizePathForCompare($0) },
        resolveDisplayProject: { [weak self] in self?.resolveDisplayProject(for: $0, rootProjectPath: $1) }
    )
    @ObservationIgnored private lazy var workspaceSessionPathResolver = WorkspaceSessionPathResolver(
        normalizePath: { normalizePathForCompare($0) },
        normalizeOptionalPath: { normalizedOptionalPathForCompare($0) }
    )
    @ObservationIgnored private lazy var workspaceRestoreSelectionResolver = WorkspaceRestoreSelectionResolver(
        sessionPathResolver: workspaceSessionPathResolver,
        displayProjectPath: { [weak self] in
            self?.workspaceSessionDisplayMapper.displayProjectPath(for: $0, fallbackPath: $0) ?? $0
        }
    )
    @ObservationIgnored private lazy var workspaceGitSelectionResolver = WorkspaceGitSelectionResolver(
        normalizePath: { normalizePathForCompare($0) },
        rootProjectForPath: { [weak self] in self?.projectsByNormalizedPath[$0] },
        activeProjectPath: { [weak self] in self?.activeWorkspaceProjectPath },
        openWorkspaceSessions: { [weak self] in self?.openWorkspaceSessions ?? [] },
        currentBranchByProjectPath: { [weak self] in self?.currentBranchByProjectPath ?? [:] },
        storedFamilyID: { [weak self] in self?.workspaceSelectedGitRepositoryFamilyIDByRootProjectPath[$0] },
        storedExecutionPath: { [weak self] in self?.workspaceSelectedGitExecutionPathByRootProjectPath[$0] },
        resolveDisplayProject: { [weak self] in self?.resolveDisplayProject(for: $0, rootProjectPath: $1) },
        liveRootRepositoryPath: { liveWorkspaceRootRepositoryPath(for: $0) }
    )
    @ObservationIgnored private lazy var workspaceAlignmentDefinitionResolver = WorkspaceAlignmentDefinitionResolver(
        normalizePath: { normalizePathForCompare($0) },
        normalizePathList: { normalizePathList($0) },
        pathLastComponent: { pathLastComponent($0) },
        projectsByNormalizedPath: { [weak self] in self?.projectsByNormalizedPath ?? [:] },
        existingDefinitions: { [weak self] in self?.snapshot.appState.workspaceAlignmentGroups ?? [] }
    )
    @ObservationIgnored private lazy var workspaceProjectTreeController = WorkspaceProjectTreeController(
        stateStore: workspaceProjectTreeStateStore,
        fileSystemService: workspaceFileSystemService,
        diagnostics: workspaceProjectTreeDiagnostics,
        normalizePath: { normalizePathForCompare($0) },
        resolveProjectPath: { [weak self] in self?.resolvedWorkspaceProjectPathKey($0) },
        activeProjectTreeProject: { [weak self] in self?.activeWorkspaceProjectTreeProject },
        syncGitSelection: { [weak self] rootProjectPath, selectedPath in
            self?.syncWorkspaceGitSelectionFromProjectTreeSelectionIfNeeded(
                rootProjectPath: rootProjectPath,
                selectedPath: selectedPath
            )
        },
        reportError: { [weak self] in self?.errorMessage = $0 }
    )
    @ObservationIgnored private lazy var workspaceSidebarProjectionBuilder = WorkspaceSidebarProjectionBuilder(
        normalizePath: { normalizePathForCompare($0) },
        openWorkspaceSessions: { [weak self] in self?.openWorkspaceSessions ?? [] },
        activeProjectPath: { [weak self] in self?.activeWorkspaceProjectPath },
        projectsByNormalizedPath: { [weak self] in self?.projectsByNormalizedPath ?? [:] },
        currentBranchByProjectPath: { [weak self] in self?.currentBranchByProjectPath ?? [:] },
        attentionStateByProjectPath: { [weak self] in self?.attentionStateByProjectPath ?? [:] },
        agentDisplayOverridesByProjectPath: { [weak self] in self?.agentDisplayOverridesByProjectPath ?? [:] },
        pendingWorktreeCreates: { [weak self] in
            self?.pendingWorkspaceWorktreeCreatesByPath.values.map { pending in
                WorkspaceSidebarPendingWorktreeCreate(
                    rootProjectPath: pending.rootProjectPath,
                    branch: pending.branch,
                    baseBranch: pending.baseBranch,
                    worktreePath: pending.worktreePath,
                    createdAt: pending.createdAt,
                    status: pending.status == .creating ? .creating : .failed,
                    step: pending.step,
                    message: pending.message,
                    error: pending.error
                )
            } ?? []
        },
        resolvedPresentedTabSelection: { [weak self] in
            self?.resolvedWorkspacePresentedTabSelection(for: $0, controller: $1)
        }
    )
    @ObservationIgnored private lazy var workspaceAlignmentProjectionBuilder = WorkspaceAlignmentProjectionBuilder(
        normalizePath: { normalizePathForCompare($0) },
        activeProjectPath: { [weak self] in self?.activeWorkspaceProjectPath },
        activeWorkspaceRootGroupID: { [weak self] in self?.activeWorkspaceSession?.workspaceRootContext?.workspaceID },
        activeWorkspaceOwnedGroupID: { [weak self] in self?.activeWorkspaceSession?.workspaceAlignmentGroupID },
        projectsByNormalizedPath: { [weak self] in self?.projectsByNormalizedPath ?? [:] },
        currentBranchByProjectPath: { [weak self] in self?.currentBranchByProjectPath ?? [:] },
        aliasesForGroup: { [weak self] definition, projectsByNormalizedPath in
            self?.resolvedWorkspaceAlignmentAliases(
                for: definition,
                projectsByNormalizedPath: projectsByNormalizedPath
            ) ?? [:]
        },
        statusForMember: { [weak self] groupID, projectPath in
            guard let self else {
                return nil
            }
            return self.workspaceAlignmentStatusByKey[
                self.workspaceAlignmentStatusKey(groupID: groupID, projectPath: projectPath)
            ]
        }
    )
    @ObservationIgnored private lazy var workspaceToolWindowCoordinator = WorkspaceToolWindowCoordinator(
        presentationState: workspacePresentationState,
        supportsKind: { [weak self] in self?.workspaceToolWindowKindIsSupported($0) ?? false },
        prepareProjectTree: { [weak self] in self?.prepareActiveWorkspaceProjectTreeState() },
        prepareCommit: { [weak self] in self?.prepareActiveWorkspaceCommitViewModel() },
        prepareGit: { [weak self] in
            self?.prepareActiveWorkspaceGitHubViewModel()
            self?.prepareActiveWorkspaceGitViewModel()
        }
    )
    @ObservationIgnored private lazy var workspacePresentedTabCoordinator = WorkspacePresentedTabCoordinator(
        presentationState: workspacePresentationState,
        controllerForProject: { [weak self] in self?.workspaceController(for: $0) },
        editorTabsForProject: { [weak self] in self?.workspaceEditorTabsByProjectPath[$0] ?? [] },
        activateEditorTab: { [weak self] in
            _ = self?.workspaceEditorPresentationCoordinator.activateTab($0, in: $1)
        },
        selectProjectTreeNode: { [weak self] in self?.selectWorkspaceProjectTreeNode($0, in: $1) },
        showSideToolWindow: { [weak self] in self?.showWorkspaceSideToolWindow($0) },
        showBottomToolWindow: { [weak self] in self?.showWorkspaceBottomToolWindow($0) },
        isBrowserPaneItem: { [weak self] itemID, projectPath in
            guard let controller = self?.workspaceController(for: projectPath) else {
                return false
            }
            return self?.workspacePaneItemContext(for: itemID, in: controller)?.item.isBrowser == true
        },
        removeDiffViewModel: { [weak self] in self?.workspaceDiffViewModelStore.remove(tabID: $0) }
    )
    @ObservationIgnored private let workspacePresentedTabSnapshotBuilder = WorkspacePresentedTabSnapshotBuilder()
    @ObservationIgnored private lazy var workspaceEditorPresentationStore = WorkspaceEditorPresentationStore(
        presentationState: workspacePresentationState,
        editorTabsForProject: { [weak self] in self?.workspaceEditorTabsByProjectPath[$0] ?? [] }
    )
    @ObservationIgnored private lazy var workspaceEditorTabStore = WorkspaceEditorTabStore(
        normalizePath: { normalizePathForCompare($0) }
    )
    @ObservationIgnored private let workspaceEditorDocumentStore = WorkspaceEditorDocumentStore()
    @ObservationIgnored private let workspaceEditorCloseCoordinator = WorkspaceEditorCloseCoordinator()
    @ObservationIgnored private let workspaceAlignmentStatusResolver = WorkspaceAlignmentStatusResolver()
    @ObservationIgnored private lazy var workspaceEditorRuntimeCoordinator = WorkspaceEditorRuntimeCoordinator(
        editorTabsForProject: { [weak self] in self?.workspaceEditorTabsByProjectPath[$0] ?? [] },
        parentDirectoryPath: { [weak self] in self?.workspaceFileSystemService.parentDirectoryPath(for: $0) ?? $0 },
        normalizePath: { normalizePathForCompare($0) },
        runtimeSessionsForProject: { [weak self] in self?.workspaceEditorRuntimeSessionsByProjectPath[$0] ?? [:] },
        setRuntimeSessions: { [weak self] projectPath, sessions in
            self?.workspaceEditorRuntimeSessionsByProjectPath[projectPath] = sessions
        },
        createWatcher: { directoryPath, onEvent in
            WorkspaceDirectoryWatcher(directoryPath: directoryPath, onEvent: onEvent)
        },
        handleTabsChangedInDirectory: { [weak self] tabIDs, projectPath in
            for tabID in tabIDs {
                self?.checkWorkspaceEditorTabExternalChange(tabID, in: projectPath)
            }
        }
    )
    @ObservationIgnored private lazy var workspaceEditorPresentationCoordinator = WorkspaceEditorPresentationCoordinator(
        presentationState: workspacePresentationState,
        editorTabsForProject: { [weak self] in self?.workspaceEditorTabsByProjectPath[$0] ?? [] },
        presentationStore: workspaceEditorPresentationStore,
        selectProjectTreeNode: { [weak self] in self?.selectWorkspaceProjectTreeNode($0, in: $1) }
    )
    @ObservationIgnored private var workspacePaneSnapshotProvider: WorkspacePaneSnapshotProvider?
    @ObservationIgnored private var projectDocumentLoadTask: Task<Void, Never>?
    @ObservationIgnored private var projectNotesSummaryBackfillTask: Task<Void, Never>?
    @ObservationIgnored private var projectDocumentLoadRevision = 0
    @ObservationIgnored private var workspaceWorktreeRefreshTasksByRootProjectPath: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var projectsByNormalizedPath: [String: Project] = [:]
    @ObservationIgnored private var workspaceSessionIndexByNormalizedPath: [String: Int] = [:]
    @ObservationIgnored private var workspaceSidebarProjectionCache: WorkspaceSidebarProjectionCacheEntry?
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
                workspaceDisplayProjectResolver.clearCache()
                rebuildProjectLookupIndex()
            }
            refreshActiveWorkspaceGitSelectionState()
        }
    }
    public var selectedProjectPath: String?
    public var openWorkspaceSessions: [OpenWorkspaceSessionState] {
        didSet {
            noteWorkspaceSidebarProjectionMutation(from: oldValue, to: openWorkspaceSessions)
            workspaceDisplayProjectResolver.clearCache()
            rebuildWorkspaceSessionIndex()
            syncMountedWorkspaceProjectPathAfterSessionMutation()
            refreshCodexDisplayCandidates()
            refreshActiveWorkspaceGitSelectionState()
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
            refreshActiveWorkspaceGitSelectionState()
        }
    }
    private var hiddenMountedWorkspaceProjectPath: String?
    public private(set) var activeWorkspaceSupportsGitToolWindows: Bool
    // Keep SwiftUI render/getter paths on stored state instead of rediscovering repositories inline.
    private var activeWorkspaceGitSelectionSnapshotCache: WorkspaceGitSelectionSnapshot?
    public var workspaceSideToolWindowState: WorkspaceSideToolWindowState {
        get { workspacePresentationState.sideToolWindowState }
        set { workspacePresentationState.sideToolWindowState = newValue }
    }
    public var workspaceBottomToolWindowState: WorkspaceBottomToolWindowState {
        get { workspacePresentationState.bottomToolWindowState }
        set { workspacePresentationState.bottomToolWindowState = newValue }
    }
    public var workspaceFocusedArea: WorkspaceFocusedArea {
        get { workspacePresentationState.focusedArea }
        set { workspacePresentationState.focusedArea = newValue }
    }
    public var workspacePendingEditorCloseRequest: WorkspaceEditorCloseRequest?
    private var workspaceProjectTreeStatesByProjectPath: [String: WorkspaceProjectTreeState] {
        get { workspaceProjectTreeStateStore.statesByProjectPath }
        set { workspaceProjectTreeStateStore.statesByProjectPath = newValue }
    }
    private var workspaceProjectTreeRefreshTasksByProjectPath: [String: Task<Void, Never>] {
        get { workspaceProjectTreeStateStore.refreshTasksByProjectPath }
        set { workspaceProjectTreeStateStore.refreshTasksByProjectPath = newValue }
    }
    private var workspaceProjectTreeRefreshGenerationByProjectPath: [String: Int] {
        get { workspaceProjectTreeStateStore.refreshGenerationByProjectPath }
        set { workspaceProjectTreeStateStore.refreshGenerationByProjectPath = newValue }
    }
    private var workspaceProjectTreeProjectionCacheByProjectPath: [String: (revision: Int, projection: WorkspaceProjectTreeDisplayProjection)] {
        get { workspaceProjectTreeStateStore.projectionCacheByProjectPath }
        set { workspaceProjectTreeStateStore.projectionCacheByProjectPath = newValue }
    }
    private var workspaceEditorTabsByProjectPath: [String: [WorkspaceEditorTabState]]
    private var workspaceEditorPresentationByProjectPath: [String: WorkspaceEditorPresentationState] {
        get { workspacePresentationState.editorPresentationByProjectPath }
        set { workspacePresentationState.editorPresentationByProjectPath = newValue }
    }
    private var workspaceEditorRuntimeSessionsByProjectPath: [String: [String: WorkspaceEditorRuntimeSessionState]] {
        get { workspacePresentationState.editorRuntimeSessionsByProjectPath }
        set { workspacePresentationState.editorRuntimeSessionsByProjectPath = newValue }
    }
    private var workspaceDiffTabsByProjectPath: [String: [WorkspaceDiffTabState]] {
        get { workspacePresentationState.diffTabsByProjectPath }
        set { workspacePresentationState.diffTabsByProjectPath = newValue }
    }
    private var workspaceSelectedPresentedTabByProjectPath: [String: WorkspacePresentedTabSelection] {
        get { workspacePresentationState.selectedPresentedTabsByProjectPath }
        set {
            workspacePresentationState.selectedPresentedTabsByProjectPath = newValue
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
    private var currentBranchByProjectPath: [String: String] {
        didSet {
            noteWorkspaceSidebarProjectionMutation(from: oldValue, to: currentBranchByProjectPath)
            refreshActiveWorkspaceGitSelectionState()
        }
    }
    private var workspaceSelectedGitRepositoryFamilyIDByRootProjectPath: [String: String] {
        didSet {
            refreshActiveWorkspaceGitSelectionState()
        }
    }
    private var workspaceSelectedGitExecutionPathByRootProjectPath: [String: String] {
        didSet {
            refreshActiveWorkspaceGitSelectionState()
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
    public private(set) var workspaceProjectTreeRefreshingProjectPaths: Set<String> {
        get { workspaceProjectTreeStateStore.refreshingProjectPaths }
        set { workspaceProjectTreeStateStore.refreshingProjectPaths = newValue }
    }
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
        self.workspacePresentationState = WorkspacePresentationState()
        self.workspaceProjectTreeStateStore = WorkspaceProjectTreeStateStore()
        self.workspacePaneSnapshotProvider = nil
        self.snapshot = NativeAppSnapshot()
        self.selectedProjectPath = nil
        self.openWorkspaceSessions = []
        self.activeWorkspaceProjectPath = nil
        self.hiddenMountedWorkspaceProjectPath = nil
        self.activeWorkspaceSupportsGitToolWindows = false
        self.activeWorkspaceGitSelectionSnapshotCache = nil
        self.workspacePendingEditorCloseRequest = nil
        self.workspaceEditorTabsByProjectPath = [:]
        self.attentionStateByProjectPath = [:]
        self.agentDisplayOverridesByProjectPath = [:]
        self.currentBranchByProjectPath = [:]
        self.workspaceSelectedGitRepositoryFamilyIDByRootProjectPath = [:]
        self.workspaceSelectedGitExecutionPathByRootProjectPath = [:]
        self.pendingWorkspaceWorktreeCreatesByPath = [:]
        self.workspaceAlignmentStatusByKey = [:]
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
        _ = workspaceRunController
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
        projectListProjectionBuilder.visibleProjects(
            projects: snapshot.projects,
            recycleBin: snapshot.appState.recycleBin
        )
    }

    public var filteredProjects: [Project] {
        projectListProjectionBuilder.filteredProjects(
            visibleProjects: visibleProjects,
            searchQuery: searchQuery,
            selectedDirectory: selectedDirectory,
            directProjectPaths: snapshot.appState.directProjectPaths,
            selectedHeatmapDateKey: selectedHeatmapDateKey,
            selectedTag: selectedTag,
            selectedDateFilter: selectedDateFilter,
            selectedGitFilter: selectedGitFilter,
            sortOrder: projectListSortOrder
        )
    }

    public var selectedProject: Project? {
        workspaceProjectProjectionBuilder.selectedProject(
            selectedProjectPath: selectedProjectPath,
            filteredProjects: filteredProjects,
            visibleProjects: visibleProjects
        )
    }

    public var activeWorkspaceProject: Project? {
        workspaceProjectProjectionBuilder.activeWorkspaceProject(activeProjectPath: activeWorkspaceProjectPath)
    }

    public var mountedWorkspaceProjectPath: String? {
        workspaceProjectProjectionBuilder.mountedWorkspaceProjectPath(
            activeProjectPath: activeWorkspaceProjectPath,
            hiddenMountedProjectPath: hiddenMountedWorkspaceProjectPath
        )
    }

    public var activeWorkspaceProjectTreeProject: Project? {
        workspaceProjectProjectionBuilder.activeWorkspaceProjectTreeProject(
            activeProject: activeWorkspaceProject,
            activeSession: activeWorkspaceSession
        )
    }

    public var openWorkspaceProjectPaths: [String] {
        workspaceProjectProjectionBuilder.openWorkspaceProjectPaths(sessions: openWorkspaceSessions)
    }

    public var openWorkspaceRootProjectPaths: [String] {
        workspaceProjectProjectionBuilder.openWorkspaceRootProjectPaths(sessions: openWorkspaceSessions)
    }

    public var openWorkspaceProjects: [Project] {
        workspaceProjectProjectionBuilder.openWorkspaceProjects(sessions: openWorkspaceSessions)
    }

    public var availableWorkspaceProjects: [Project] {
        workspaceProjectProjectionBuilder.availableWorkspaceProjects(
            visibleProjects: visibleProjects,
            openRootProjectPaths: openWorkspaceRootProjectPaths
        )
    }

    public var workspaceAlignmentProjectOptions: [Project] {
        workspaceProjectProjectionBuilder.workspaceAlignmentProjectOptions(visibleProjects: visibleProjects)
    }

    public var workspaceSidebarGroups: [WorkspaceSidebarProjectGroup] {
        workspaceSidebarProjectionBuilder.groups(
            showsInAppNotifications: snapshot.appState.settings.workspaceInAppNotificationsEnabled,
            moveNotifiedWorktreeToTop: snapshot.appState.settings.moveNotifiedWorktreeToTop,
            collapsedProjectPaths: Set(
                snapshot.appState.settings.collapsedWorkspaceSidebarProjectPaths.map(normalizePathForCompare)
            )
        )
    }

    public var workspaceAlignmentGroups: [WorkspaceAlignmentGroupProjection] {
        if let cache = workspaceAlignmentGroupsCache,
           cache.revision == workspaceSidebarProjectionRevision {
            return cache.groups
        }

        let groups = workspaceAlignmentProjectionBuilder.groups(
            definitions: snapshot.appState.workspaceAlignmentGroups
        )
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
        workspaceAttentionController.workspaceAttentionState(for: projectPath)
    }

    public func saveWorkspaceRunConfigurations(_ runConfigurations: [ProjectRunConfiguration], in projectPath: String? = nil) throws {
        guard let projectPath = resolveWorkspaceRunProjectPath(projectPath),
              let ownerProjectPath = workspaceRunConfigurationBuilder.ownerProjectPath(for: projectPath),
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
        workspaceAttentionController.recordWorkspaceNotification(
            projectPath: projectPath,
            tabID: tabID,
            paneID: paneID,
            title: title,
            body: body,
            createdAt: createdAt
        )
    }

    public func updateWorkspaceTaskStatus(
        projectPath: String,
        paneID: String,
        status: WorkspaceTaskStatus
    ) {
        workspaceAttentionController.updateWorkspaceTaskStatus(
            projectPath: projectPath,
            paneID: paneID,
            status: status
        )
    }

    public func recordAgentSignal(_ signal: WorkspaceAgentSessionSignal) {
        workspaceAttentionController.recordAgentSignal(signal)
    }

    public func clearAgentSignal(projectPath: String, paneID: String) {
        workspaceAttentionController.clearAgentSignal(projectPath: projectPath, paneID: paneID)
    }

    public func startWorkspaceAgentSignalObservation() {
        workspaceAttentionController.startWorkspaceAgentSignalObservation()
    }

    public func stopWorkspaceAgentSignalObservation() {
        workspaceAttentionController.stopWorkspaceAgentSignalObservation()
    }

    public func refreshWorkspaceAgentSignals() {
        workspaceAttentionController.refreshWorkspaceAgentSignals()
    }

    public func codexDisplayCandidates() -> [WorkspaceAgentDisplayCandidate] {
        workspaceAttentionController.codexDisplayCandidates()
    }

    private func refreshCodexDisplayCandidates() {
        workspaceAttentionController.refreshCodexDisplayCandidates()
    }

    public func replaceWorkspaceAgentDisplayOverrides(
        _ overridesByProjectPath: [String: [String: WorkspaceAgentPresentationOverride]]
    ) {
        workspaceAttentionController.replaceWorkspaceAgentDisplayOverrides(overridesByProjectPath)
    }

    public func markWorkspaceNotificationsRead(projectPath: String, paneID: String) {
        workspaceAttentionController.markWorkspaceNotificationsRead(projectPath: projectPath, paneID: paneID)
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
        workspaceAttentionController.markWorkspaceNotificationRead(
            projectPath: normalizedProjectPath,
            notificationID: notification.id
        )
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

    private var activeWorkspaceRootRepositoryPath: String? {
        activeWorkspaceGitSelectionSnapshotCache?.gitContext.repositoryPath
    }

    private var activeWorkspaceRootRepositoryDisplayName: String? {
        activeWorkspaceGitSelectionSnapshotCache?.gitContext.selectedRepositoryFamily?.displayName
    }

    public var activeWorkspaceRootCurrentBranchName: String? {
        guard let repositoryPath = activeWorkspaceGitSelectionSnapshotCache?.gitContext.repositoryPath else {
            return nil
        }
        return currentBranchByProjectPath[repositoryPath]
            ?? currentBranchByProjectPath[normalizePathForCompare(repositoryPath)]
    }

    public var activeWorkspaceGitRepositoryContext: WorkspaceGitRepositoryContext? {
        activeWorkspaceGitSelectionSnapshotCache?.gitContext
    }

    public var activeWorkspaceCommitRepositoryContext: WorkspaceCommitRepositoryContext? {
        activeWorkspaceGitSelectionSnapshotCache?.commitContext
    }

    public var activeWorkspaceCommitViewModel: WorkspaceCommitViewModel? {
        guard let rootProjectPath = activeWorkspaceRootProjectPath else {
            return nil
        }
        return workspaceFeatureViewModelStore.commitViewModel(for: rootProjectPath)
    }

    public var activeWorkspaceGitViewModel: WorkspaceGitViewModel? {
        guard let rootProjectPath = activeWorkspaceRootProjectPath else {
            return nil
        }
        return workspaceFeatureViewModelStore.gitViewModel(for: rootProjectPath)
    }

    public var activeWorkspaceGitHubViewModel: WorkspaceGitHubViewModel? {
        guard let rootProjectPath = activeWorkspaceRootProjectPath else {
            return nil
        }
        return workspaceFeatureViewModelStore.gitHubViewModel(for: rootProjectPath)
    }

    public var activeWorkspaceState: WorkspaceSessionState? {
        activeWorkspaceController?.sessionState
    }

    public var activeWorkspaceIsStandaloneQuickTerminal: Bool {
        guard let session = activeWorkspaceSession else {
            return false
        }
        return session.isQuickTerminal && session.workspaceRootContext == nil
    }

    private func refreshActiveWorkspaceGitSelectionState() {
        let selectionSnapshot = computeActiveWorkspaceGitSelectionSnapshot()
        activeWorkspaceGitSelectionSnapshotCache = selectionSnapshot

        let nextValue = computeActiveWorkspaceGitToolWindowSupport(selectionSnapshot: selectionSnapshot)
        guard activeWorkspaceSupportsGitToolWindows != nextValue else {
            return
        }
        activeWorkspaceSupportsGitToolWindows = nextValue
    }

    private func computeActiveWorkspaceGitSelectionSnapshot() -> WorkspaceGitSelectionSnapshot? {
        guard let normalizedRootProjectPath = normalizedOptionalPathForCompare(activeWorkspaceRootProjectPath) else {
            return nil
        }
        return gitSelectionSnapshot(for: normalizedRootProjectPath)
    }

    private func computeActiveWorkspaceGitToolWindowSupport(
        selectionSnapshot: WorkspaceGitSelectionSnapshot?
    ) -> Bool {
        guard let session = activeWorkspaceSession else {
            return false
        }
        if session.isQuickTerminal && session.workspaceRootContext == nil {
            return false
        }
        return selectionSnapshot != nil
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
        return workspaceProjectTreeController.displayProjection(
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
        return workspacePresentedTabSnapshotBuilder.snapshot(
            controller: controller,
            editorTabs: workspaceEditorTabsByProjectPath[normalizedProjectPath] ?? [],
            diffTabs: workspaceDiffTabsByProjectPath[normalizedProjectPath] ?? [],
            selection: selected
        )
    }

    public func workspacePresentedTabs(for projectPath: String) -> [WorkspacePresentedTabItem] {
        workspacePresentedTabSnapshot(for: projectPath).items
    }

    public func workspaceEditorPresentationState(for projectPath: String) -> WorkspaceEditorPresentationState? {
        workspaceEditorPresentationStore.resolvedPresentation(for: normalizePathForCompare(projectPath))
    }

    public func workspaceSelectedPresentedTab(for projectPath: String) -> WorkspacePresentedTabSelection? {
        workspacePresentedTabSnapshot(for: projectPath).selection
    }

    public func workspaceDiffTabViewModel(for projectPath: String, tabID: String) -> WorkspaceDiffTabViewModel? {
        workspaceDiffViewModelStore.viewModel(
            for: projectPath,
            tabID: tabID,
            diffTabsByProjectPath: workspaceDiffTabsByProjectPath
        )
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
        workspaceEditorRuntimeCoordinator.updateRuntimeSession(session, tabID: tabID, in: resolvedProjectPath)
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
        projectCatalogSidebarProjectionBuilder.directoryRows(
            visibleProjects: visibleProjects,
            directories: snapshot.appState.directories,
            directProjectPaths: snapshot.appState.directProjectPaths
        )
    }

    public var isDirectProjectsDirectorySelected: Bool {
        if case .directProjects = selectedDirectory {
            return true
        }
        return false
    }

    public var tagRows: [TagRow] {
        projectCatalogSidebarProjectionBuilder.tagRows(
            visibleProjects: visibleProjects,
            tags: snapshot.appState.tags
        )
    }

    public var sidebarHeatmapDays: [GitHeatmapDay] {
        projectCatalogSidebarProjectionBuilder.sidebarHeatmapDays(visibleProjects: visibleProjects)
    }

    public var isHeatmapFilterActive: Bool {
        selectedHeatmapDateKey != nil
    }

    public var heatmapActiveProjects: [GitActiveProject] {
        projectCatalogSidebarProjectionBuilder.heatmapActiveProjects(
            selectedDateKey: selectedHeatmapDateKey,
            visibleProjects: visibleProjects
        )
    }

    public var selectedHeatmapSummary: String? {
        projectCatalogSidebarProjectionBuilder.selectedHeatmapSummary(
            selectedDateKey: selectedHeatmapDateKey,
            activeProjects: heatmapActiveProjects
        )
    }

    public var gitStatisticsLastUpdated: Date? {
        projectCatalogSidebarProjectionBuilder.gitStatisticsLastUpdated(visibleProjects: visibleProjects)
    }

    public var cliSessionItems: [CLISessionItem] {
        projectCatalogSidebarProjectionBuilder.cliSessionItems(
            sessions: openWorkspaceSessions,
            activeProjectPath: activeWorkspaceProjectPath
        )
    }

    public var recycleBinItems: [RecycleBinItem] {
        projectCatalogSidebarProjectionBuilder.recycleBinItems(
            recycleBin: snapshot.appState.recycleBin,
            projects: snapshot.projects
        )
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

        return GitStatisticsRefreshSummary(results: results)
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

        return GitStatisticsRefreshSummary(results: results)
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
            workspaceSidebarProjectionBuilder.groupID(for: $0) == sourceGroupID
        }
        guard !sourceSessions.isEmpty else {
            return
        }

        let remainingSessions = openWorkspaceSessions.filter {
            workspaceSidebarProjectionBuilder.groupID(for: $0) != sourceGroupID
        }
        let targetIndices = remainingSessions.enumerated().compactMap { element -> Int? in
            workspaceSidebarProjectionBuilder.groupID(for: element.element) == targetGroupID ? element.offset : nil
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
            workspaceRunController.retainConsoleState(for: openWorkspaceProjectPaths)
            syncAttentionStateWithOpenSessions()

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
        workspaceRunController.retainConsoleState(for: openWorkspaceProjectPaths)
        syncAttentionStateWithOpenSessions()

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
        workspaceRunController.retainConsoleState(for: openWorkspaceProjectPaths)
        syncAttentionStateWithOpenSessions()

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
        guard let selectionSnapshot = activeWorkspaceGitSelectionSnapshot()
        else {
            return
        }
        workspaceFeatureViewModelStore.prepareGitViewModel(for: selectionSnapshot)
    }

    public func prepareActiveWorkspaceCommitViewModel() {
        guard let repositoryContext = activeWorkspaceCommitRepositoryContext
        else {
            return
        }
        workspaceFeatureViewModelStore.prepareCommitViewModel(for: repositoryContext)
    }

    public func prepareActiveWorkspaceGitHubViewModel() {
        guard let selectionSnapshot = activeWorkspaceGitSelectionSnapshot()
        else {
            return
        }
        workspaceFeatureViewModelStore.prepareGitHubViewModel(for: selectionSnapshot)
    }

    public func prepareActiveWorkspaceProjectTreeState() {
        workspaceProjectTreeController.prepareActiveProjectTreeState()
    }

    public func refreshWorkspaceProjectTree(for projectPath: String? = nil) {
        workspaceProjectTreeController.refreshProjectTree(for: projectPath)
    }

    public func refreshWorkspaceProjectTreeNode(_ path: String?, in projectPath: String? = nil) {
        workspaceProjectTreeController.refreshProjectTreeNode(path, in: projectPath)
    }

    public func selectWorkspaceProjectTreeNode(_ path: String?, in projectPath: String? = nil) {
        workspaceProjectTreeController.selectProjectTreeNode(path, in: projectPath)
    }

    public func toggleWorkspaceProjectTreeDirectory(_ directoryPath: String, in projectPath: String? = nil) {
        workspaceProjectTreeController.toggleDirectory(directoryPath, in: projectPath)
    }

    private func scheduleWorkspaceProjectTreeRefresh(
        for projectPath: String,
        preserving state: WorkspaceProjectTreeState?,
        preferredSelectionPath: String? = nil
    ) {
        workspaceProjectTreeController.refreshProjectTree(
            for: projectPath,
            preserving: state,
            preferredSelectionPath: preferredSelectionPath
        )
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
        let tabs = workspaceEditorTabsByProjectPath[resolvedProjectPath] ?? []

        if let result = workspaceEditorTabStore.reopenExistingTab(
            filePath: normalizedFilePath,
            openingPolicy: openingPolicy,
            in: tabs
        ) {
            workspaceEditorTabsByProjectPath[resolvedProjectPath] = result.tabs
            if result.assignToActiveGroup {
                workspaceEditorPresentationCoordinator.assignTabToActiveGroup(result.openedTabID, in: resolvedProjectPath)
            }
            _ = workspaceEditorPresentationCoordinator.activateTab(result.openedTabID, in: resolvedProjectPath)
            scheduleWorkspaceRestoreAutosave()
            return
        }

        do {
            let document = try workspaceFileSystemService.loadDocument(at: normalizedFilePath)
            let result = workspaceEditorTabStore.openNewTab(
                projectPath: resolvedProjectPath,
                filePath: normalizedFilePath,
                document: document,
                openingPolicy: openingPolicy,
                in: tabs
            )
            workspaceEditorTabsByProjectPath[resolvedProjectPath] = result.tabs
            if result.resetRuntimeSession {
                workspaceEditorRuntimeCoordinator.resetRuntimeSession(result.openedTabID, in: resolvedProjectPath)
            }
            workspaceEditorRuntimeCoordinator.syncRuntimeSessions(for: resolvedProjectPath)
            workspaceEditorRuntimeCoordinator.syncDirectoryWatchers(for: resolvedProjectPath)
            if result.assignToActiveGroup {
                workspaceEditorPresentationCoordinator.assignTabToActiveGroup(result.openedTabID, in: resolvedProjectPath)
            }
            _ = workspaceEditorPresentationCoordinator.activateTab(result.openedTabID, in: resolvedProjectPath)
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
              let tabs = workspaceEditorTabsByProjectPath[resolvedProjectPath]
        else {
            return
        }

        let previousTab = tabs.first(where: { $0.id == tabID })
        let result = workspaceEditorDocumentStore.updateText(text, tabID: tabID, in: tabs)
        guard result.didMutate else {
            return
        }
        workspaceEditorTabsByProjectPath[resolvedProjectPath] = result.tabs
        let didPromotePreviewTab = previousTab?.isPreview == true
            && result.tabs.first(where: { $0.id == tabID })?.isPreview == false
        if didPromotePreviewTab {
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
            applyWorkspaceEditorDocumentMutation(
                workspaceEditorDocumentStore.applyExternalChange(
                    .removedOnDisk,
                    tabID: tabID,
                    in: workspaceEditorTabsByProjectPath[resolvedProjectPath] ?? []
                ),
                to: resolvedProjectPath
            )
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

        let changeSnapshot: WorkspaceEditorDocumentStore.ExternalChangeSnapshot = hasChangedOnDisk
            ? .modifiedOnDisk
            : .inSync
        applyWorkspaceEditorDocumentMutation(
            workspaceEditorDocumentStore.applyExternalChange(
                changeSnapshot,
                tabID: tabID,
                in: workspaceEditorTabsByProjectPath[resolvedProjectPath] ?? []
            ),
            to: resolvedProjectPath
        )
    }

    public func reloadWorkspaceEditorTab(_ tabID: String, in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath),
              let tab = workspaceEditorTabsByProjectPath[resolvedProjectPath]?.first(where: { $0.id == tabID })
        else {
            return
        }

        do {
            let document = try workspaceFileSystemService.loadDocument(at: tab.filePath)
            applyWorkspaceEditorDocumentMutation(
                workspaceEditorDocumentStore.applyReloadedDocument(
                    document,
                    tabID: tabID,
                    in: workspaceEditorTabsByProjectPath[resolvedProjectPath] ?? []
                ),
                to: resolvedProjectPath
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
            applyWorkspaceEditorDocumentMutation(
                workspaceEditorDocumentStore.applySaveBlockedByExternalChange(
                    tabID: tabID,
                    in: workspaceEditorTabsByProjectPath[resolvedProjectPath] ?? []
                ),
                to: resolvedProjectPath
            )
            errorMessage = workspaceEditorTabsByProjectPath[resolvedProjectPath]?.first(where: { $0.id == tabID })?.message
            return
        }

        applyWorkspaceEditorDocumentMutation(
            workspaceEditorDocumentStore.beginSaving(
                tabID: tabID,
                in: workspaceEditorTabsByProjectPath[resolvedProjectPath] ?? []
            ),
            to: resolvedProjectPath
        )

        do {
            let savedDocument = try workspaceFileSystemService.saveTextDocument(latestTab.text, to: latestTab.filePath)
            applyWorkspaceEditorDocumentMutation(
                workspaceEditorDocumentStore.applySavedDocument(
                    savedDocument,
                    tabID: tabID,
                    in: workspaceEditorTabsByProjectPath[resolvedProjectPath] ?? []
                ),
                to: resolvedProjectPath
            )
            refreshWorkspaceProjectTree(for: resolvedProjectPath)
            errorMessage = nil
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            applyWorkspaceEditorDocumentMutation(
                workspaceEditorDocumentStore.applySaveFailure(
                    message: message,
                    tabID: tabID,
                    in: workspaceEditorTabsByProjectPath[resolvedProjectPath] ?? []
                ),
                to: resolvedProjectPath
            )
            errorMessage = message
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
              let tabs = workspaceEditorTabsByProjectPath[resolvedProjectPath]
        else {
            return
        }

        let result = workspaceEditorTabStore.promotePreviewTabToRegular(tabID, in: tabs)
        guard result.didMutate else {
            return
        }

        workspaceEditorTabsByProjectPath[resolvedProjectPath] = result.tabs
        scheduleWorkspaceRestoreAutosave()
    }

    public func setWorkspaceEditorTabPinned(
        _ isPinned: Bool,
        tabID: String,
        in projectPath: String? = nil
    ) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath),
              let tabs = workspaceEditorTabsByProjectPath[resolvedProjectPath]
        else {
            return
        }

        let result = workspaceEditorTabStore.setTabPinned(isPinned, tabID: tabID, in: tabs)
        workspaceEditorTabsByProjectPath[resolvedProjectPath] = result.tabs
        guard result.didMutate else {
            return
        }
        scheduleWorkspaceRestoreAutosave()
    }

    public func confirmWorkspaceEditorCloseRequest() {
        guard let request = workspacePendingEditorCloseRequest else {
            return
        }
        workspacePendingEditorCloseRequest = nil
        let result = workspaceEditorCloseCoordinator.confirmCloseRequest(request)
        let resolvedProjectPath = normalizePathForCompare(result.projectPath)
        forceCloseWorkspaceEditorTab(result.tabID, in: resolvedProjectPath)
        closeWorkspaceEditorTabs(result.remainingTabIDs, in: resolvedProjectPath)
    }

    public func dismissWorkspaceEditorCloseRequest() {
        workspacePendingEditorCloseRequest = nil
        workspaceEditorCloseCoordinator.dismissCloseRequest()
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
        workspaceEditorRuntimeCoordinator.removeRuntimeSession(tabID, in: resolvedProjectPath)
        workspaceEditorRuntimeCoordinator.syncRuntimeSessions(for: resolvedProjectPath)
        workspaceEditorRuntimeCoordinator.syncDirectoryWatchers(for: resolvedProjectPath)
        workspaceEditorPresentationByProjectPath[resolvedProjectPath] = workspaceEditorPresentationCoordinator.removeTab(
            tabID,
            from: workspaceEditorPresentationStore.resolvedPresentation(for: resolvedProjectPath),
            in: resolvedProjectPath
        )
        if let treeState = workspaceProjectTreeStatesByProjectPath[resolvedProjectPath],
           treeState.selectedPath == removedTab.filePath {
            selectWorkspaceProjectTreeNode(nil, in: resolvedProjectPath)
        }

        guard isClosingSelectedTab else {
            scheduleWorkspaceRestoreAutosave()
            return
        }

        let selection = workspaceEditorCloseCoordinator.postCloseSelection(
            preferredEditorTabID: workspaceEditorPresentationCoordinator.preferredTabAfterClosing(
            removedIndex: removedIndex,
            in: resolvedProjectPath,
            remainingTabs: tabs
            ),
            diffTabs: workspaceDiffTabsByProjectPath[resolvedProjectPath] ?? [],
            terminalTabID: workspaceController(for: resolvedProjectPath)?.selectedTabId
                ?? workspaceController(for: resolvedProjectPath)?.selectedTab?.id
        )
        switch selection {
        case let .editor(nextEditorTabID):
            _ = workspaceEditorPresentationCoordinator.activateTab(nextEditorTabID, in: resolvedProjectPath)
        case let .diff(diffTabID):
            workspaceSelectedPresentedTabByProjectPath[resolvedProjectPath] = .diff(diffTabID)
            workspaceFocusedArea = .diffTab(diffTabID)
        case let .terminal(terminalTabID):
            workspaceSelectedPresentedTabByProjectPath[resolvedProjectPath] = .terminal(terminalTabID)
            workspaceFocusedArea = .terminal
        case .none:
            workspaceSelectedPresentedTabByProjectPath[resolvedProjectPath] = nil
            workspaceFocusedArea = .terminal
        }

        scheduleWorkspaceRestoreAutosave()
    }

    private func closeWorkspaceEditorTabs(_ tabIDs: [String], in resolvedProjectPath: String) {
        workspacePendingEditorCloseRequest = nil
        let displayProjectPath = workspaceSessionDisplayMapper.displayProjectPath(
            for: resolvedProjectPath,
            rootProjectPath: resolvedProjectPath,
            fallbackPath: resolvedProjectPath
        )
        let result = workspaceEditorCloseCoordinator.beginClosing(
            tabIDs,
            in: resolvedProjectPath,
            displayProjectPath: displayProjectPath,
            tabs: workspaceEditorTabsByProjectPath[resolvedProjectPath] ?? []
        )
        for tabID in result.forceCloseTabIDs {
            forceCloseWorkspaceEditorTab(tabID, in: resolvedProjectPath)
        }
        workspacePendingEditorCloseRequest = result.request
    }

    public func toggleWorkspaceToolWindow(_ kind: WorkspaceToolWindowKind) {
        workspaceToolWindowCoordinator.toggle(kind)
    }

    public func showWorkspaceSideToolWindow(_ kind: WorkspaceToolWindowKind) {
        workspaceToolWindowCoordinator.showSide(kind)
    }

    public func hideWorkspaceSideToolWindow() {
        workspaceToolWindowCoordinator.hideSide()
    }

    public func updateWorkspaceSideToolWindowWidth(_ width: Double) {
        workspaceToolWindowCoordinator.updateSideWidth(width)
    }

    public func showWorkspaceBottomToolWindow(_ kind: WorkspaceToolWindowKind) {
        workspaceToolWindowCoordinator.showBottom(kind)
    }

    public func hideWorkspaceBottomToolWindow() {
        workspaceToolWindowCoordinator.hideBottom()
    }

    public func updateWorkspaceBottomToolWindowHeight(_ height: Double) {
        workspaceToolWindowCoordinator.updateBottomHeight(height)
    }

    public func setWorkspaceFocusedArea(_ area: WorkspaceFocusedArea) {
        workspaceToolWindowCoordinator.setFocusedArea(area)
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
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath),
              workspacePresentedTabCoordinator.select(selection, in: resolvedProjectPath)
        else {
            return
        }
        scheduleWorkspaceRestoreAutosave()
    }

    public func splitWorkspaceEditorActiveGroup(
        axis: WorkspaceSplitAxis,
        in projectPath: String? = nil
    ) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath) else {
            return
        }

        let result = workspaceEditorPresentationCoordinator.splitActiveGroup(
            axis: axis,
            in: resolvedProjectPath
        )
        guard result.didMutate else {
            return
        }
        if let selectedTabID = result.selectedTabID {
            _ = workspaceEditorPresentationCoordinator.activateTab(selectedTabID, in: resolvedProjectPath)
        }
        scheduleWorkspaceRestoreAutosave()
    }

    public func selectWorkspaceEditorGroup(_ groupID: String, in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath) else {
            return
        }

        let result = workspaceEditorPresentationCoordinator.selectGroup(groupID, in: resolvedProjectPath)
        guard result.didMutate else {
            return
        }
        if let selectedTabID = result.selectedTabID {
            _ = workspaceEditorPresentationCoordinator.activateTab(selectedTabID, in: resolvedProjectPath)
        }
        scheduleWorkspaceRestoreAutosave()
    }

    public func moveWorkspaceEditorTab(
        _ tabID: String,
        toGroup groupID: String,
        in projectPath: String? = nil
    ) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath),
              workspaceEditorPresentationCoordinator.moveTab(tabID, toGroup: groupID, in: resolvedProjectPath)
        else {
            return
        }

        _ = workspaceEditorPresentationCoordinator.activateTab(tabID, in: resolvedProjectPath)
        scheduleWorkspaceRestoreAutosave()
    }

    public func closeWorkspaceEditorGroup(_ groupID: String, in projectPath: String? = nil) {
        guard let resolvedProjectPath = resolvedWorkspaceProjectPathKey(projectPath) else {
            return
        }

        let result = workspaceEditorPresentationCoordinator.closeGroup(groupID, in: resolvedProjectPath)
        guard result.didMutate else {
            return
        }
        if let selectedTabID = result.selectedTabID {
            _ = workspaceEditorPresentationCoordinator.activateTab(selectedTabID, in: resolvedProjectPath)
        }
        scheduleWorkspaceRestoreAutosave()
    }

    public func updateWorkspaceEditorSplitRatio(
        _ ratio: Double,
        in projectPath: String? = nil
    ) {
        guard let resolvedProjectPath = projectPath ?? activeWorkspaceProjectPath,
              workspaceEditorPresentationCoordinator.updateSplitRatio(ratio, in: resolvedProjectPath)
        else {
            return
        }
        scheduleWorkspaceRestoreAutosave()
    }

    public func closeWorkspaceDiffTab(_ tabID: String, in projectPath: String? = nil) {
        guard let resolvedProjectPath = projectPath ?? activeWorkspaceProjectPath
        else {
            return
        }
        _ = workspacePresentedTabCoordinator.closeDiffTab(tabID, in: resolvedProjectPath)
    }

    public func syncActiveWorkspaceToolWindowContext() {
        workspaceToolWindowCoordinator.syncVisibleContexts()
    }

    public func workspaceToolWindowKindIsSupported(_ kind: WorkspaceToolWindowKind) -> Bool {
        switch kind {
        case .project:
            return true
        case .commit, .git:
            return activeWorkspaceSupportsGitToolWindows
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

            let normalizedSessionSnapshot = workspaceSessionDisplayMapper.normalizedRestoreSnapshot(sessionSnapshot)
            let normalizedProjectPath = normalizedSessionSnapshot.projectPath
            let normalizedRootProjectPath = normalizedSessionSnapshot.rootProjectPath

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

            return workspaceSessionDisplayMapper.restoredSessionState(
                from: normalizedSessionSnapshot,
                controller: controller,
                workspaceRootContext: restoredWorkspaceRootContext
            )
        }

        guard !restoredSessions.isEmpty else {
            return
        }

        openWorkspaceSessions = restoredSessions
        syncAttentionStateWithOpenSessions()
        restoreWorkspaceEditorPresentation(from: restoredSnapshot)

        let restoreSelection = workspaceRestoreSelectionResolver.resolveSelection(
            activeProjectPathCandidate: restoredSnapshot.activeProjectPath,
            selectedProjectPathCandidate: restoredSnapshot.selectedProjectPath,
            sessions: restoredSessions,
            currentSelectedProjectPath: selectedProjectPath
        )

        activeWorkspaceProjectPath = restoreSelection.activeProjectPath
        selectedProjectPath = restoreSelection.selectedProjectPath

        if let restoredActiveProjectPath = restoreSelection.activeProjectPath,
           let paneID = workspaceController(for: restoredActiveProjectPath)?.selectedPane?.id {
            markWorkspaceNotificationsRead(projectPath: restoredActiveProjectPath, paneID: paneID)
        }
        if let restoredActiveProjectPath = restoreSelection.activeProjectPath {
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
        if normalizedPath == normalizedRootProjectPath,
           !isQuickTerminal,
           transientDisplayProject?.isDirectoryWorkspace != true {
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
        workspaceSessionPathResolver.sessionIndex(
            for: path,
            indexByNormalizedPath: workspaceSessionIndexByNormalizedPath
        )
    }

    private func workspaceSession(for path: String?) -> OpenWorkspaceSessionState? {
        workspaceSessionPathResolver.session(
            for: path,
            sessions: openWorkspaceSessions,
            indexByNormalizedPath: workspaceSessionIndexByNormalizedPath
        )
    }

    private func canonicalWorkspaceSessionPath(
        for path: String?,
        in sessions: [OpenWorkspaceSessionState]? = nil
    ) -> String? {
        if let sessions {
            return workspaceSessionPathResolver.canonicalSessionPath(
                for: path,
                sessions: sessions
            )
        }
        return workspaceSessionPathResolver.canonicalSessionPath(
            for: path,
            sessions: openWorkspaceSessions,
            indexByNormalizedPath: workspaceSessionIndexByNormalizedPath
        )
    }

    private func promoteWorkspaceSessionIfNeeded(for path: String, rootProjectPath: String) {
        guard let index = workspaceSessionIndex(for: path) else {
            return
        }
        openWorkspaceSessions[index].rootProjectPath = workspaceSessionDisplayMapper.displayProjectPath(
            for: rootProjectPath,
            rootProjectPath: rootProjectPath,
            fallbackPath: rootProjectPath
        )
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
            workspaceEditorRuntimeCoordinator.syncDirectoryWatchers(for: projectPath)
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
            presentation: workspaceEditorPresentationStore.restorePresentation(for: projectPath)
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
        workspaceEditorCloseCoordinator.reset()
        for projectPath in restoredProjectPaths {
            workspaceEditorRuntimeCoordinator.clearProjectState(projectPath)
            workspaceEditorTabsByProjectPath[projectPath] = []
            workspaceEditorPresentationByProjectPath[projectPath] = nil
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
                restoredTabs = workspaceEditorTabStore.insertRestoredTab(
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
                    in: restoredTabs
                )
            }
            workspaceEditorTabsByProjectPath[projectPath] = restoredTabs
            workspaceEditorRuntimeCoordinator.syncRuntimeSessions(for: projectPath)
            workspaceEditorRuntimeCoordinator.syncDirectoryWatchers(for: projectPath)
            workspaceEditorPresentationByProjectPath[projectPath] = workspaceEditorPresentationStore.normalizedPresentation(
                sessionSnapshot.editorPresentation
                    ?? workspaceEditorPresentationStore.defaultPresentation(tabs: restoredTabs),
                in: projectPath
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

    private func applyWorkspaceEditorDocumentMutation(
        _ result: WorkspaceEditorDocumentStore.MutationResult,
        to projectPath: String
    ) {
        guard result.didMutate else {
            return
        }
        workspaceEditorTabsByProjectPath[projectPath] = result.tabs
    }

    private func resolvedWorkspacePresentedTabSelection(
        for projectPath: String,
        controller: GhosttyWorkspaceController? = nil
    ) -> WorkspacePresentedTabSelection? {
        workspacePresentedTabCoordinator.resolvedSelection(for: projectPath, controller: controller)
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
                workspaceDiffViewModelStore.openSessionIfLoaded(
                    tabID: existing.id,
                    requestChain: requestChain
                )
            } else {
                workspaceDiffViewModelStore.updateTabIfLoaded(
                    tabID: existing.id,
                    tab: existing
                )
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

    private func defaultFocusedArea(for selection: WorkspacePresentedTabSelection) -> WorkspaceFocusedArea {
        workspacePresentedTabCoordinator.defaultFocusedArea(for: selection)
    }

    private func clearWorkspaceRuntimePresentationState(for paths: Set<String>) {
        for path in paths {
            workspaceEditorRuntimeCoordinator.removeProjectState(path)
            workspaceProjectTreeRefreshTasksByProjectPath[path]?.cancel()
            workspaceProjectTreeRefreshTasksByProjectPath[path] = nil
            workspaceProjectTreeRefreshGenerationByProjectPath[path] = nil
            workspaceProjectTreeRefreshingProjectPaths.remove(path)
            workspaceEditorTabsByProjectPath[path] = nil
            workspaceEditorPresentationByProjectPath[path] = nil
            workspaceEditorRuntimeSessionsByProjectPath[path] = nil
            workspaceDiffViewModelStore.removeTabs(workspaceDiffTabsByProjectPath[path] ?? [])
            workspaceProjectTreeStatesByProjectPath[path] = nil
            workspaceProjectTreeProjectionCacheByProjectPath[path] = nil
            workspaceDiffTabsByProjectPath[path] = nil
            workspaceSelectedPresentedTabByProjectPath[path] = nil
        }
    }

    private var activeWorkspaceSession: OpenWorkspaceSessionState? {
        workspaceProjectProjectionBuilder.activeWorkspaceSession(activeProjectPath: activeWorkspaceProjectPath)
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

    private func activeWorkspaceGitSelectionSnapshot() -> WorkspaceGitSelectionSnapshot? {
        activeWorkspaceGitSelectionSnapshotCache
    }

    private func gitSelectionSnapshot(for rootProjectPath: String) -> WorkspaceGitSelectionSnapshot? {
        workspaceGitSelectionResolver.selectionSnapshot(for: rootProjectPath)
    }

    private func syncWorkspaceGitSelectionFromProjectTreeSelectionIfNeeded(
        rootProjectPath: String,
        selectedPath: String?
    ) {
        let normalizedRootProjectPath = normalizePathForCompare(rootProjectPath)
        guard normalizedRootProjectPath == normalizePathForCompare(activeWorkspaceRootProjectPath ?? ""),
              let selection = workspaceGitSelectionResolver.selectionForProjectTreePath(
                selectedPath,
                in: normalizedRootProjectPath
              )
        else {
            return
        }

        let previousFamilyID = workspaceSelectedGitRepositoryFamilyIDByRootProjectPath[normalizedRootProjectPath]
        let previousExecutionPath = workspaceSelectedGitExecutionPathByRootProjectPath[normalizedRootProjectPath]
        guard previousFamilyID != selection.familyID || previousExecutionPath != selection.executionPath else {
            return
        }

        workspaceSelectedGitRepositoryFamilyIDByRootProjectPath[normalizedRootProjectPath] = selection.familyID
        workspaceSelectedGitExecutionPathByRootProjectPath[normalizedRootProjectPath] = selection.executionPath
        syncActiveWorkspaceToolWindowContext()
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
              !project.isTransientWorkspaceProject,
              (project.isGitRepository || liveWorkspaceRootRepositoryPath(for: normalizedRootProjectPath) != nil),
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
        try workspaceAlignmentDefinitionResolver.validate(definition, replacing: groupID)
    }

    private func buildWorkspaceAlignmentMemberAliases(
        for projectPaths: [String],
        existing: [String: String],
        projectsByNormalizedPath: [String: Project]? = nil
    ) -> [String: String] {
        workspaceAlignmentDefinitionResolver.aliases(
            for: projectPaths,
            existing: existing,
            projectsByNormalizedPath: projectsByNormalizedPath
        )
    }

    private func resolvedWorkspaceAlignmentAliases(
        for definition: WorkspaceAlignmentGroupDefinition,
        projectsByNormalizedPath: [String: Project]? = nil
    ) -> [String: String] {
        workspaceAlignmentDefinitionResolver.aliases(
            for: definition,
            projectsByNormalizedPath: projectsByNormalizedPath
        )
    }

    private func workspaceAlignmentMemberDefinition(
        for projectPath: String,
        in definition: WorkspaceAlignmentGroupDefinition
    ) -> WorkspaceAlignmentMemberDefinition? {
        workspaceAlignmentDefinitionResolver.memberDefinition(for: projectPath, in: definition)
    }

    private func normalizeWorkspaceAlignmentMemberDefinitions(
        _ members: [WorkspaceAlignmentMemberDefinition]
    ) -> [WorkspaceAlignmentMemberDefinition] {
        workspaceAlignmentDefinitionResolver.normalizedMembers(members)
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
        let status = workspaceAlignmentStatusResolver.status(from: probe)
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
        workspaceAttentionController.syncAttentionStateWithOpenSessions()
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
        workspaceRunConfigurationBuilder.configurations(
            for: projectPath,
            sessions: openWorkspaceSessions
        )
    }

    private func resolveDisplayProject(for path: String, rootProjectPath: String? = nil) -> Project? {
        workspaceDisplayProjectResolver.resolveProject(for: path, rootProjectPath: rootProjectPath)
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

struct WorkspaceGitSelectionSnapshot {
    let gitContext: WorkspaceGitRepositoryContext
    let commitContext: WorkspaceCommitRepositoryContext
}

private func normalizePathForCompare(_ path: String) -> String {
    nativeAppNormalizePathForCompare(path)
}

private func normalizePathList(_ paths: [String]) -> [String] {
    nativeAppNormalizePathList(paths)
}
