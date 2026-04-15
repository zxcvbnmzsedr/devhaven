import Foundation
import Observation

@MainActor
@Observable
public final class WorkspaceGitViewModel {
    public struct Client: Sendable {
        public var loadRefs: @Sendable (String) throws -> WorkspaceGitRefsSnapshot
        public var loadLogSnapshot: @Sendable (String, WorkspaceGitLogQuery) throws -> WorkspaceGitLogSnapshot
        public var loadCommitSummary: @Sendable (String, String) throws -> WorkspaceGitCommitDetail
        public var loadCommitDetail: @Sendable (String, String) throws -> WorkspaceGitCommitDetail
        public var loadDiffForCommit: @Sendable (String, String) throws -> String
        public var loadDiffForCommitFile: @Sendable (String, String, String) throws -> String
        public var loadLogAuthors: @Sendable (String, Int) throws -> [String]
        public var loadChanges: @Sendable (String) throws -> WorkspaceGitWorkingTreeSnapshot
        public var loadRemotes: @Sendable (String) throws -> [WorkspaceGitRemoteSnapshot]
        public var loadAheadBehind: @Sendable (String) throws -> WorkspaceGitAheadBehindSnapshot
        public var loadOperationState: @Sendable (String) throws -> WorkspaceGitOperationState
        public var stage: @Sendable (String, [String]) throws -> Void
        public var unstage: @Sendable (String, [String]) throws -> Void
        public var stageAll: @Sendable (String) throws -> Void
        public var unstageAll: @Sendable (String) throws -> Void
        public var discard: @Sendable (String, [String]) throws -> Void
        public var commit: @Sendable (String, String) throws -> Void
        public var amend: @Sendable (String, String?) throws -> Void
        public var createBranch: @Sendable (String, String, String?) throws -> Void
        public var checkoutBranch: @Sendable (String, String) throws -> Void
        public var deleteLocalBranch: @Sendable (String, String) throws -> Void
        public var fetch: @Sendable (String) throws -> Void
        public var pull: @Sendable (String) throws -> Void
        public var push: @Sendable (String) throws -> Void
        public var abortOperation: @Sendable (String) throws -> Void

        public init(
            loadRefs: @escaping @Sendable (String) throws -> WorkspaceGitRefsSnapshot,
            loadLogSnapshot: @escaping @Sendable (String, WorkspaceGitLogQuery) throws -> WorkspaceGitLogSnapshot,
            loadCommitSummary: @escaping @Sendable (String, String) throws -> WorkspaceGitCommitDetail,
            loadCommitDetail: @escaping @Sendable (String, String) throws -> WorkspaceGitCommitDetail,
            loadDiffForCommit: @escaping @Sendable (String, String) throws -> String,
            loadDiffForCommitFile: @escaping @Sendable (String, String, String) throws -> String = { _, _, _ in "" },
            loadLogAuthors: @escaping @Sendable (String, Int) throws -> [String] = { _, _ in [] },
            loadChanges: @escaping @Sendable (String) throws -> WorkspaceGitWorkingTreeSnapshot,
            loadRemotes: @escaping @Sendable (String) throws -> [WorkspaceGitRemoteSnapshot],
            loadAheadBehind: @escaping @Sendable (String) throws -> WorkspaceGitAheadBehindSnapshot,
            loadOperationState: @escaping @Sendable (String) throws -> WorkspaceGitOperationState,
            stage: @escaping @Sendable (String, [String]) throws -> Void,
            unstage: @escaping @Sendable (String, [String]) throws -> Void,
            stageAll: @escaping @Sendable (String) throws -> Void,
            unstageAll: @escaping @Sendable (String) throws -> Void,
            discard: @escaping @Sendable (String, [String]) throws -> Void,
            commit: @escaping @Sendable (String, String) throws -> Void,
            amend: @escaping @Sendable (String, String?) throws -> Void,
            createBranch: @escaping @Sendable (String, String, String?) throws -> Void,
            checkoutBranch: @escaping @Sendable (String, String) throws -> Void,
            deleteLocalBranch: @escaping @Sendable (String, String) throws -> Void,
            fetch: @escaping @Sendable (String) throws -> Void,
            pull: @escaping @Sendable (String) throws -> Void,
            push: @escaping @Sendable (String) throws -> Void,
            abortOperation: @escaping @Sendable (String) throws -> Void
        ) {
            self.loadRefs = loadRefs
            self.loadLogSnapshot = loadLogSnapshot
            self.loadCommitSummary = loadCommitSummary
            self.loadCommitDetail = loadCommitDetail
            self.loadDiffForCommit = loadDiffForCommit
            self.loadDiffForCommitFile = loadDiffForCommitFile
            self.loadLogAuthors = loadLogAuthors
            self.loadChanges = loadChanges
            self.loadRemotes = loadRemotes
            self.loadAheadBehind = loadAheadBehind
            self.loadOperationState = loadOperationState
            self.stage = stage
            self.unstage = unstage
            self.stageAll = stageAll
            self.unstageAll = unstageAll
            self.discard = discard
            self.commit = commit
            self.amend = amend
            self.createBranch = createBranch
            self.checkoutBranch = checkoutBranch
            self.deleteLocalBranch = deleteLocalBranch
            self.fetch = fetch
            self.pull = pull
            self.push = push
            self.abortOperation = abortOperation
        }

        public static func live(service: NativeGitRepositoryService) -> Client {
            Client(
                loadRefs: { try service.loadRefs(at: $0) },
                loadLogSnapshot: { try service.loadLogSnapshot(at: $0, query: $1) },
                loadCommitSummary: { try service.loadCommitSummary(at: $0, commitHash: $1) },
                loadCommitDetail: { try service.loadCommitDetail(at: $0, commitHash: $1) },
                loadDiffForCommit: { try service.loadDiffForCommit(at: $0, commitHash: $1) },
                loadDiffForCommitFile: { try service.loadDiffForCommitFile(at: $0, commitHash: $1, filePath: $2) },
                loadLogAuthors: { try service.loadLogAuthors(at: $0, limit: $1) },
                loadChanges: { try service.loadChanges(at: $0) },
                loadRemotes: { try service.loadRemotes(at: $0) },
                loadAheadBehind: { try service.loadAheadBehind(at: $0) },
                loadOperationState: { try service.loadOperationState(at: $0) },
                stage: { try service.stage(paths: $1, at: $0) },
                unstage: { try service.unstage(paths: $1, at: $0) },
                stageAll: { try service.stageAll(at: $0) },
                unstageAll: { try service.unstageAll(at: $0) },
                discard: { try service.discard(paths: $1, at: $0) },
                commit: { try service.commit(message: $1, at: $0) },
                amend: { try service.amend(message: $1, at: $0) },
                createBranch: { try service.createBranch(name: $1, startPoint: $2, at: $0) },
                checkoutBranch: { try service.checkoutBranch(name: $1, at: $0) },
                deleteLocalBranch: { try service.deleteLocalBranch(name: $1, at: $0) },
                fetch: { try service.fetch(at: $0) },
                pull: { try service.pull(at: $0) },
                push: { try service.push(at: $0) },
                abortOperation: { try service.abortOperation(at: $0) }
            )
        }

        var logViewModelClient: WorkspaceGitLogViewModel.Client {
            WorkspaceGitLogViewModel.Client(
                loadLogSnapshot: loadLogSnapshot,
                loadCommitSummary: loadCommitSummary,
                loadFileDiffForCommit: loadDiffForCommitFile,
                loadAuthorSuggestions: loadLogAuthors
            )
        }
    }

    private enum ReadResult: Sendable {
        case log(WorkspaceGitLogSnapshot)
        case branches(WorkspaceGitRefsSnapshot)
        case operations(remotes: [WorkspaceGitRemoteSnapshot], aheadBehind: WorkspaceGitAheadBehindSnapshot, state: WorkspaceGitOperationState)
    }

    @ObservationIgnored private let client: Client
    @ObservationIgnored private var searchDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var readRevision = 0
    @ObservationIgnored private var commitDetailTask: Task<Void, Never>?
    @ObservationIgnored private var commitDetailRevision = 0
    @ObservationIgnored private var mutationRevision = 0
    @ObservationIgnored public var onRepositorySelectionChange: (@MainActor (WorkspaceGitRepositoryContext, String) -> Void)?

    private nonisolated static let diffPreviewMaxBytes = 256 * 1024
    private nonisolated static let diffPreviewMaxLines = 2_000

    public var repositoryContext: WorkspaceGitRepositoryContext
    public let logViewModel: WorkspaceGitLogViewModel
    public var executionWorktrees: [WorkspaceGitWorktreeContext]
    public var section: WorkspaceGitSection
    public var searchQuery: String
    public var debouncedSearchQuery: String
    public var pathFilterQuery: String
    public var debouncedPathFilterQuery: String
    public var selectedRevisionFilter: String?
    public var selectedAuthorFilter: String?
    public var selectedDateFilter: WorkspaceGitDateFilter
    public var selectedExecutionWorktreePath: String
    public var selectedCommitHash: String?
    public var selectedCommitDetail: WorkspaceGitCommitDetail?
    public var selectedFilePath: String?
    public var logSnapshot: WorkspaceGitLogSnapshot
    public var workingTreeSnapshot: WorkspaceGitWorkingTreeSnapshot?
    public var remotes: [WorkspaceGitRemoteSnapshot]
    public var aheadBehindSnapshot: WorkspaceGitAheadBehindSnapshot
    public var operationState: WorkspaceGitOperationState
    public var isLoading: Bool
    public var isMutating: Bool
    public var activeMutation: WorkspaceGitMutationKind?
    public var mutationErrorMessage: String?
    public var lastSuccessfulMutation: WorkspaceGitMutationKind?
    public var successfulMutationToken: Int
    public var isLoadingSelectedCommitDetail: Bool
    public var isSelectedCommitDiffTruncated: Bool
    public var selectedCommitDiffNotice: String?
    public var errorMessage: String?

    public init(
        repositoryContext: WorkspaceGitRepositoryContext,
        executionWorktrees: [WorkspaceGitWorktreeContext],
        preferredExecutionWorktreePath: String? = nil,
        section: WorkspaceGitSection = .log,
        client: Client
    ) {
        self.client = client
        self.repositoryContext = repositoryContext
        self.logViewModel = WorkspaceGitLogViewModel(
            repositoryContext: repositoryContext,
            client: client.logViewModelClient
        )
        self.executionWorktrees = executionWorktrees
        self.section = section
        self.searchQuery = ""
        self.debouncedSearchQuery = ""
        self.pathFilterQuery = ""
        self.debouncedPathFilterQuery = ""
        self.selectedRevisionFilter = nil
        self.selectedAuthorFilter = nil
        self.selectedDateFilter = .all
        self.selectedExecutionWorktreePath = Self.resolveExecutionWorktreePath(
            preferredExecutionWorktreePath,
            executionWorktrees: executionWorktrees,
            fallbackRootProjectPath: repositoryContext.rootProjectPath
        )
        self.selectedCommitHash = nil
        self.selectedCommitDetail = nil
        self.selectedFilePath = nil
        self.logSnapshot = Self.emptyLogSnapshot()
        self.workingTreeSnapshot = nil
        self.remotes = []
        self.aheadBehindSnapshot = WorkspaceGitAheadBehindSnapshot(upstream: nil, ahead: 0, behind: 0)
        self.operationState = .idle
        self.isLoading = false
        self.isMutating = false
        self.activeMutation = nil
        self.mutationErrorMessage = nil
        self.lastSuccessfulMutation = nil
        self.successfulMutationToken = 0
        self.isLoadingSelectedCommitDetail = false
        self.isSelectedCommitDiffTruncated = false
        self.selectedCommitDiffNotice = nil
        self.errorMessage = nil
    }

    deinit {
        searchDebounceTask?.cancel()
        readTask?.cancel()
        commitDetailTask?.cancel()
    }

    public var selectedExecutionWorktree: WorkspaceGitWorktreeContext? {
        executionWorktrees.first(where: { $0.path == selectedExecutionWorktreePath })
    }

    public var repositoryFamilies: [WorkspaceGitRepositoryFamilyContext] {
        repositoryContext.availableRepositoryFamilies
    }

    public var selectedRepositoryFamily: WorkspaceGitRepositoryFamilyContext? {
        repositoryContext.selectedRepositoryFamily
    }

    public var hasMultipleRepositoryFamilies: Bool {
        repositoryFamilies.count > 1
    }

    public var selectedRepositoryFamilyDisplayName: String {
        selectedRepositoryFamily?.displayName ?? repositoryContext.repositoryPath
    }

    public func updateRepositoryContext(
        _ repositoryContext: WorkspaceGitRepositoryContext,
        executionWorktrees: [WorkspaceGitWorktreeContext],
        preferredExecutionWorktreePath: String? = nil
    ) {
        let previousExecutionWorktreePath = selectedExecutionWorktreePath
        let previousRepositoryPath = self.repositoryContext.repositoryPath
        self.repositoryContext = repositoryContext
        logViewModel.updateRepositoryContext(repositoryContext)
        self.executionWorktrees = executionWorktrees
        selectedExecutionWorktreePath = Self.resolveExecutionWorktreePath(
            preferredExecutionWorktreePath ?? selectedExecutionWorktreePath,
            executionWorktrees: executionWorktrees,
            fallbackRootProjectPath: repositoryContext.rootProjectPath
        )
        let repositoryPathChanged = previousRepositoryPath != repositoryContext.repositoryPath
        let executionPathChanged = previousExecutionWorktreePath != selectedExecutionWorktreePath
        if repositoryPathChanged || executionPathChanged {
            mutationRevision += 1
        }
        if repositoryPathChanged {
            clearExecutionScopedState()
        }
        if repositoryPathChanged || (executionPathChanged && section == .operations) {
            clearExecutionScopedState()
            refreshForCurrentSection()
        }
    }

    public func updateSearchQuery(_ query: String) {
        searchQuery = query
        scheduleLogFilterDebounce()
    }

    public func updatePathFilterQuery(_ query: String) {
        pathFilterQuery = query
        scheduleLogFilterDebounce()
    }

    public func selectRevisionFilter(_ revision: String?) {
        let normalized = revision?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextRevision = normalized?.isEmpty == false ? normalized : nil
        guard selectedRevisionFilter != nextRevision else {
            return
        }
        selectedRevisionFilter = nextRevision
        refreshForCurrentSection()
    }

    public func selectAuthorFilter(_ author: String?) {
        let normalized = author?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextAuthor = normalized?.isEmpty == false ? normalized : nil
        guard selectedAuthorFilter != nextAuthor else {
            return
        }
        selectedAuthorFilter = nextAuthor
        refreshForCurrentSection()
    }

    public func selectDateFilter(_ filter: WorkspaceGitDateFilter) {
        guard selectedDateFilter != filter else {
            return
        }
        selectedDateFilter = filter
        refreshForCurrentSection()
    }

    public func setSection(_ section: WorkspaceGitSection) {
        guard self.section != section else {
            return
        }
        self.section = section
        cancelPendingReads()
        refreshForCurrentSection()
    }

    public func selectExecutionWorktree(_ path: String) {
        guard executionWorktrees.contains(where: { $0.path == path }) else {
            return
        }
        mutationRevision += 1
        selectedExecutionWorktreePath = path
        updateSelectedFamilyPreferredExecutionPath(path)
        onRepositorySelectionChange?(repositoryContext, path)
        if section == .operations {
            clearExecutionScopedState()
            refreshForCurrentSection()
        }
    }

    public func selectRepositoryFamily(_ id: String) {
        guard let family = repositoryFamilies.first(where: { $0.id == id }) else {
            return
        }
        let nextExecutionWorktrees = family.members
        let nextExecutionPath = Self.resolveExecutionWorktreePath(
            family.preferredExecutionPath,
            executionWorktrees: nextExecutionWorktrees,
            fallbackRootProjectPath: family.repositoryPath
        )
        var nextContext = repositoryContext
        nextContext.repositoryPath = family.repositoryPath
        nextContext.selectedRepositoryFamilyID = family.id
        updateRepositoryContext(
            nextContext,
            executionWorktrees: nextExecutionWorktrees,
            preferredExecutionWorktreePath: nextExecutionPath
        )
        updateSelectedFamilyPreferredExecutionPath(nextExecutionPath)
        onRepositorySelectionChange?(repositoryContext, selectedExecutionWorktreePath)
    }

    public func refreshForCurrentSection() {
        beginRead(for: section)
    }

    public func clearFilters() {
        searchDebounceTask?.cancel()
        searchQuery = ""
        debouncedSearchQuery = ""
        pathFilterQuery = ""
        debouncedPathFilterQuery = ""
        selectedRevisionFilter = nil
        selectedAuthorFilter = nil
        selectedDateFilter = .all
        refreshForCurrentSection()
    }

    public func selectCommitFile(_ path: String?) {
        let normalized = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextPath = normalized?.isEmpty == false ? normalized : nil
        guard selectedFilePath != nextPath else {
            return
        }
        selectedFilePath = nextPath
    }

    public func stage(paths: [String]) {
        performMutation(kind: .stage) { client, executionPath in
            try client.stage(executionPath, paths)
        }
    }

    public func unstage(paths: [String]) {
        performMutation(kind: .unstage) { client, executionPath in
            try client.unstage(executionPath, paths)
        }
    }

    public func stageAll() {
        performMutation(kind: .stageAll) { client, executionPath in
            try client.stageAll(executionPath)
        }
    }

    public func unstageAll() {
        performMutation(kind: .unstageAll) { client, executionPath in
            try client.unstageAll(executionPath)
        }
    }

    public func discard(paths: [String]) {
        performMutation(kind: .discard) { client, executionPath in
            try client.discard(executionPath, paths)
        }
    }

    public func commit(message: String) {
        performMutation(kind: .commit) { client, executionPath in
            try client.commit(executionPath, message)
        }
    }

    public func amend(message: String?) {
        performMutation(kind: .amend) { client, executionPath in
            try client.amend(executionPath, message)
        }
    }

    public func createBranch(name: String, startPoint: String?) {
        performMutation(kind: .createBranch) { client, executionPath in
            try client.createBranch(executionPath, name, startPoint)
        }
    }

    public func checkoutBranch(name: String) {
        performMutation(kind: .checkoutBranch) { client, executionPath in
            try client.checkoutBranch(executionPath, name)
        }
    }

    public func deleteLocalBranch(name: String) {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            mutationErrorMessage = "分支名不能为空"
            return
        }
        if logSnapshot.refs.localBranches.contains(where: { $0.name == normalizedName && $0.isCurrent }) {
            mutationErrorMessage = "不能删除当前分支：\(normalizedName)"
            return
        }
        performMutation(kind: .deleteLocalBranch) { client, executionPath in
            try client.deleteLocalBranch(executionPath, normalizedName)
        }
    }

    public func fetch() {
        performMutation(kind: .fetch) { client, executionPath in
            try client.fetch(executionPath)
        }
    }

    public func pull() {
        performMutation(kind: .pull) { client, executionPath in
            try client.pull(executionPath)
        }
    }

    public func push() {
        performMutation(kind: .push) { client, executionPath in
            try client.push(executionPath)
        }
    }

    public func abortOperation() {
        performMutation(kind: .abortOperation) { client, executionPath in
            try client.abortOperation(executionPath)
        }
    }

    public func selectCommit(_ hash: String?) {
        guard selectedCommitHash != hash else {
            return
        }
        selectedCommitHash = hash
        selectedFilePath = nil
        selectedCommitDetail = nil
        isSelectedCommitDiffTruncated = false
        selectedCommitDiffNotice = nil
        guard let hash else {
            isLoadingSelectedCommitDetail = false
            commitDetailTask?.cancel()
            return
        }
        loadCommitDetail(for: hash)
    }

    public func cancelPendingReads() {
        searchDebounceTask?.cancel()
        readTask?.cancel()
        commitDetailTask?.cancel()
        readRevision += 1
        commitDetailRevision += 1
        mutationRevision += 1
        isLoading = false
        isLoadingSelectedCommitDetail = false
    }

    private func scheduleLogFilterDebounce() {
        searchDebounceTask?.cancel()
        let nextQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextPathQuery = pathFilterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        searchDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else {
                return
            }
            self.debouncedSearchQuery = nextQuery
            self.debouncedPathFilterQuery = nextPathQuery
            self.refreshForCurrentSection()
        }
    }

    private func beginRead(for section: WorkspaceGitSection) {
        readTask?.cancel()
        readRevision += 1
        let currentRevision = readRevision
        let repositoryPath = repositoryContext.repositoryPath
        let executionPath = selectedExecutionWorktreePath
        let searchTerm = debouncedSearchQuery
        let pathFilter = debouncedPathFilterQuery
        let revisionFilter = selectedRevisionFilter
        let authorFilter = selectedAuthorFilter
        let sinceFilter = selectedDateFilter.gitSinceExpression
        isLoading = true
        errorMessage = nil

        readTask = Task { [client] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try Self.load(
                        section: section,
                        repositoryPath: repositoryPath,
                        executionPath: executionPath,
                        revisionFilter: revisionFilter,
                        authorFilter: authorFilter,
                        sinceFilter: sinceFilter,
                        pathFilter: pathFilter,
                        searchTerm: searchTerm,
                        client: client
                    )
                }.value
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { [weak self] in
                    guard let self, self.readRevision == currentRevision else {
                        return
                    }
                    self.applyReadResult(result)
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.readRevision == currentRevision else {
                        return
                    }
                    self.isLoading = false
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func applyReadResult(_ result: ReadResult) {
        switch result {
        case let .log(snapshot):
            logSnapshot = snapshot
            if !snapshot.commits.contains(where: { $0.hash == selectedCommitHash }) {
                selectCommit(snapshot.commits.first?.hash)
            }
        case let .branches(refs):
            logSnapshot = WorkspaceGitLogSnapshot(refs: refs, commits: logSnapshot.commits)
        case let .operations(remotes, aheadBehind, state):
            self.remotes = remotes
            aheadBehindSnapshot = aheadBehind
            operationState = state
        }
        isLoading = false
    }

    private func loadCommitDetail(for hash: String) {
        commitDetailTask?.cancel()
        commitDetailRevision += 1
        let currentRevision = commitDetailRevision
        let repositoryPath = repositoryContext.repositoryPath
        isLoadingSelectedCommitDetail = true

        commitDetailTask = Task { [client] in
            do {
                let detail = try await Task.detached(priority: .userInitiated) {
                    try client.loadCommitDetail(repositoryPath, hash)
                }.value
                guard !Task.isCancelled else {
                    return
                }
                let truncated = Self.truncateDiff(detail.diff)
                var detailWithPreview = detail
                detailWithPreview.diff = truncated.diff

                await MainActor.run { [weak self] in
                    guard let self,
                          self.commitDetailRevision == currentRevision,
                          self.selectedCommitHash == hash
                    else {
                        return
                    }
                    self.selectedCommitDetail = detailWithPreview
                    self.selectedFilePath = detailWithPreview.files.first?.path
                    self.isSelectedCommitDiffTruncated = truncated.truncated
                    self.selectedCommitDiffNotice = truncated.notice
                    self.isLoadingSelectedCommitDetail = false
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { [weak self] in
                    guard let self,
                          self.commitDetailRevision == currentRevision,
                          self.selectedCommitHash == hash
                    else {
                        return
                    }
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.isLoadingSelectedCommitDetail = false
                }
            }
        }
    }

    private nonisolated static func load(
        section: WorkspaceGitSection,
        repositoryPath: String,
        executionPath: String,
        revisionFilter: String?,
        authorFilter: String?,
        sinceFilter: String?,
        pathFilter: String,
        searchTerm: String,
        client: Client
    ) throws -> ReadResult {
        switch section {
        case .log:
            return .log(
                try client.loadLogSnapshot(
                    repositoryPath,
                    WorkspaceGitLogQuery(
                        revision: revisionFilter,
                        searchTerm: searchTerm.isEmpty ? nil : searchTerm,
                        author: authorFilter,
                        since: sinceFilter,
                        path: pathFilter.isEmpty ? nil : pathFilter
                    )
                )
            )
        case .branches:
            return .branches(try client.loadRefs(repositoryPath))
        case .operations:
            return .operations(
                remotes: try client.loadRemotes(repositoryPath),
                aheadBehind: try client.loadAheadBehind(executionPath),
                state: try client.loadOperationState(executionPath)
            )
        }
    }

    private static func resolveExecutionWorktreePath(
        _ candidatePath: String?,
        executionWorktrees: [WorkspaceGitWorktreeContext],
        fallbackRootProjectPath: String
    ) -> String {
        if let candidatePath,
           executionWorktrees.contains(where: { $0.path == candidatePath }) {
            return candidatePath
        }
        return executionWorktrees.first?.path ?? fallbackRootProjectPath
    }

    private static func emptyLogSnapshot() -> WorkspaceGitLogSnapshot {
        WorkspaceGitLogSnapshot(
            refs: WorkspaceGitRefsSnapshot(localBranches: [], remoteBranches: [], tags: []),
            commits: []
        )
    }

    private func clearExecutionScopedState() {
        workingTreeSnapshot = nil
        remotes = []
        aheadBehindSnapshot = WorkspaceGitAheadBehindSnapshot(upstream: nil, ahead: 0, behind: 0)
        operationState = .idle
    }

    private func updateSelectedFamilyPreferredExecutionPath(_ path: String) {
        guard let familyIndex = repositoryContext.repositoryFamilies.firstIndex(where: {
            $0.id == repositoryContext.selectedRepositoryFamilyID
        }) else {
            return
        }
        repositoryContext.repositoryFamilies[familyIndex].preferredExecutionPath = path
    }

    public var isMutatingOperations: Bool {
        switch activeMutation {
        case .fetch, .pull, .push, .abortOperation:
            return true
        default:
            return false
        }
    }

    private func performMutation(
        kind: WorkspaceGitMutationKind,
        _ mutation: @escaping @Sendable (Client, String) throws -> Void
    ) {
        guard !isMutating else {
            return
        }

        let repositoryPath = repositoryContext.repositoryPath
        let executionPath = selectedExecutionWorktreePath
        let searchTerm = debouncedSearchQuery
        let pathFilter = debouncedPathFilterQuery
        let revisionFilter = selectedRevisionFilter
        let authorFilter = selectedAuthorFilter
        let sinceFilter = selectedDateFilter.gitSinceExpression

        cancelPendingReads()
        mutationRevision += 1
        let currentMutationRevision = mutationRevision
        isMutating = true
        activeMutation = kind
        mutationErrorMessage = nil

        Task { [client] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    try mutation(client, executionPath)
                }.value

                let refreshed = try await Task.detached(priority: .userInitiated) {
                    try Self.refreshAfterMutation(
                        repositoryPath: repositoryPath,
                        executionPath: executionPath,
                        revisionFilter: revisionFilter,
                        authorFilter: authorFilter,
                        sinceFilter: sinceFilter,
                        pathFilter: pathFilter,
                        searchTerm: searchTerm,
                        client: client
                    )
                }.value

                await MainActor.run { [weak self] in
                    guard let self else {
                        return
                    }
                    guard self.mutationRevision == currentMutationRevision,
                          self.repositoryContext.repositoryPath == repositoryPath,
                          self.selectedExecutionWorktreePath == executionPath,
                          self.selectedRevisionFilter == revisionFilter,
                          self.selectedAuthorFilter == authorFilter,
                          self.selectedDateFilter.gitSinceExpression == sinceFilter,
                          self.debouncedPathFilterQuery == pathFilter,
                          self.debouncedSearchQuery == searchTerm
                    else {
                        self.isMutating = false
                        self.activeMutation = nil
                        return
                    }
                    self.logSnapshot = refreshed.logSnapshot
                    self.workingTreeSnapshot = refreshed.workingTreeSnapshot
                    self.remotes = refreshed.remotes
                    self.aheadBehindSnapshot = refreshed.aheadBehindSnapshot
                    self.operationState = refreshed.operationState
                    if !refreshed.logSnapshot.commits.contains(where: { $0.hash == self.selectedCommitHash }) {
                        self.selectCommit(refreshed.logSnapshot.commits.first?.hash)
                    }
                    self.isMutating = false
                    self.activeMutation = nil
                    self.lastSuccessfulMutation = kind
                    self.successfulMutationToken += 1
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    self?.isMutating = false
                    self?.activeMutation = nil
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else {
                        return
                    }
                    guard self.mutationRevision == currentMutationRevision else {
                        self.isMutating = false
                        self.activeMutation = nil
                        return
                    }
                    self.mutationErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.isMutating = false
                    self.activeMutation = nil
                }
            }
        }
    }

    private nonisolated static func refreshAfterMutation(
        repositoryPath: String,
        executionPath: String,
        revisionFilter: String?,
        authorFilter: String?,
        sinceFilter: String?,
        pathFilter: String,
        searchTerm: String,
        client: Client
    ) throws -> (
        logSnapshot: WorkspaceGitLogSnapshot,
        workingTreeSnapshot: WorkspaceGitWorkingTreeSnapshot,
        remotes: [WorkspaceGitRemoteSnapshot],
        aheadBehindSnapshot: WorkspaceGitAheadBehindSnapshot,
        operationState: WorkspaceGitOperationState
    ) {
        let logSnapshot = try client.loadLogSnapshot(
            repositoryPath,
            WorkspaceGitLogQuery(
                revision: revisionFilter,
                searchTerm: searchTerm.isEmpty ? nil : searchTerm,
                author: authorFilter,
                since: sinceFilter,
                path: pathFilter.isEmpty ? nil : pathFilter
            )
        )
        let workingTreeSnapshot = try client.loadChanges(executionPath)
        let remotes = try client.loadRemotes(repositoryPath)
        let aheadBehindSnapshot = try client.loadAheadBehind(executionPath)
        let operationState = try client.loadOperationState(executionPath)
        return (logSnapshot, workingTreeSnapshot, remotes, aheadBehindSnapshot, operationState)
    }

    private nonisolated static func truncateDiff(_ diff: String) -> (diff: String, truncated: Bool, notice: String?) {
        guard !diff.isEmpty else {
            return (diff, false, nil)
        }

        let byteCappedDiff: String
        let bytesWereTruncated: Bool
        if diff.utf8.count > diffPreviewMaxBytes {
            let cappedData = Data(diff.utf8.prefix(diffPreviewMaxBytes))
            byteCappedDiff = String(decoding: cappedData, as: UTF8.self)
            bytesWereTruncated = true
        } else {
            byteCappedDiff = diff
            bytesWereTruncated = false
        }

        let lines = byteCappedDiff.split(separator: "\n", omittingEmptySubsequences: false)
        let linesWereTruncated = lines.count > diffPreviewMaxLines
        let visibleLines = linesWereTruncated ? Array(lines.prefix(diffPreviewMaxLines)) : lines
        let preview = visibleLines.joined(separator: "\n")

        guard bytesWereTruncated || linesWereTruncated else {
            return (preview, false, nil)
        }

        return (
            preview,
            true,
            "Diff 已截断：最多展示 256KB 或 2000 行，请回到终端查看完整补丁。"
        )
    }

    public var selectedRevisionDisplayTitle: String {
        guard let selectedRevisionFilter else {
            return "全部提交"
        }
        return Self.displayTitle(for: selectedRevisionFilter)
    }

    public var selectedAuthorDisplayTitle: String {
        selectedAuthorFilter ?? "全部作者"
    }

    public var selectedDateDisplayTitle: String {
        selectedDateFilter.title
    }

    public var availableAuthors: [String] {
        Array(Set(logSnapshot.commits.map(\.authorName)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private nonisolated static func displayTitle(for revision: String) -> String {
        switch revision {
        case "HEAD":
            return "HEAD"
        default:
            let prefixes = [
                "refs/heads/",
                "refs/remotes/",
                "refs/tags/",
            ]
            for prefix in prefixes where revision.hasPrefix(prefix) {
                return String(revision.dropFirst(prefix.count))
            }
            return revision
        }
    }
}
