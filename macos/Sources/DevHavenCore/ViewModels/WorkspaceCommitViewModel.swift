import Foundation
import Observation

@MainActor
@Observable
public final class WorkspaceCommitViewModel {
    public struct Client: Sendable {
        public var loadChangesSnapshot: @Sendable (String) throws -> WorkspaceCommitChangesSnapshot
        public var loadDiffPreview: @Sendable (String, String) throws -> String
        public var executeCommit: @Sendable (String, WorkspaceCommitExecutionRequest) throws -> Void
        public var revertChanges: @Sendable (String, [String], Bool) throws -> Void

        public init(
            loadChangesSnapshot: @escaping @Sendable (String) throws -> WorkspaceCommitChangesSnapshot,
            loadDiffPreview: @escaping @Sendable (String, String) throws -> String,
            executeCommit: @escaping @Sendable (String, WorkspaceCommitExecutionRequest) throws -> Void,
            revertChanges: @escaping @Sendable (String, [String], Bool) throws -> Void = { _, _, _ in }
        ) {
            self.loadChangesSnapshot = loadChangesSnapshot
            self.loadDiffPreview = loadDiffPreview
            self.executeCommit = executeCommit
            self.revertChanges = revertChanges
        }

        public static func live(service: NativeGitRepositoryService) -> Client {
            let workflowService = NativeGitCommitWorkflowService(repositoryService: service)
            return Client(
                loadChangesSnapshot: { executionPath in
                    try workflowService.loadChangesSnapshot(at: executionPath)
                },
                loadDiffPreview: { executionPath, filePath in
                    try workflowService.loadDiffPreview(at: executionPath, filePath: filePath)
                },
                executeCommit: { executionPath, request in
                    try workflowService.executeCommit(at: executionPath, request: request)
                },
                revertChanges: { executionPath, paths, deleteLocallyAddedFiles in
                    try service.discard(
                        paths: paths,
                        at: executionPath,
                        deleteLocallyAddedFiles: deleteLocallyAddedFiles
                    )
                }
            )
        }
    }

    @ObservationIgnored private let client: Client
    @ObservationIgnored private var diffPreviewTask: Task<Void, Never>?
    @ObservationIgnored private var diffPreviewRevision = 0
    @ObservationIgnored private var changesSnapshotRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var changesSnapshotRefreshRevision = 0
    @ObservationIgnored private var revertTask: Task<Void, Never>?
    @ObservationIgnored private var revertRevision = 0
    @ObservationIgnored private var commitExecutionTask: Task<Void, Never>?
    @ObservationIgnored private var commitExecutionRevision = 0
    @ObservationIgnored public var onRepositorySelectionChange: (@MainActor (WorkspaceCommitRepositoryContext) -> Void)?

    public var repositoryContext: WorkspaceCommitRepositoryContext
    public var changesSnapshot: WorkspaceCommitChangesSnapshot?
    public var repositoryGroupSummaries: [WorkspaceCommitRepositoryGroupSummary]
    public var snapshotsByRepositoryGroupID: [String: WorkspaceCommitChangesSnapshot]
    public var includedPathsByRepositoryGroupID: [String: Set<String>]
    public var includedPaths: Set<String>
    public var selectedChangePath: String?
    public var diffPreview: WorkspaceCommitDiffPreviewState
    public var commitMessage: String
    public var options: WorkspaceCommitOptionsState
    public var isRevertingChanges: Bool
    public var executionState: WorkspaceCommitExecutionState
    public var errorMessage: String?
    public var totalChangeCount: Int {
        changesSnapshot?.changes.count ?? 0
    }
    public var includedChangeCount: Int {
        changesSnapshot?.changes.reduce(into: 0) { partialResult, change in
            if includedPaths.contains(change.path) {
                partialResult += 1
            }
        } ?? 0
    }
    public var areAllChangesIncluded: Bool {
        guard let changes = changesSnapshot?.changes, !changes.isEmpty else {
            return false
        }
        return changes.allSatisfy { includedPaths.contains($0.path) }
    }
    public var commitStatusLegend: String {
        let branch = normalizedBranchName(changesSnapshot?.branchName) ?? "detached"
        return "分支 \(branch) · 已纳入 \(totalIncludedPathCount) · \(executionState.summaryText)"
    }
    public var repositoryFamilies: [WorkspaceGitRepositoryFamilyContext] {
        repositoryContext.availableRepositoryFamilies
    }
    public var selectedRepositoryFamily: WorkspaceGitRepositoryFamilyContext? {
        repositoryContext.selectedRepositoryFamily
    }
    public var selectedRepositoryFamilyDisplayName: String {
        selectedRepositoryFamily?.displayName ?? repositoryContext.repositoryPath
    }
    public var selectedExecutionDisplayName: String {
        selectedRepositoryFamily?.members.first(where: {
            $0.path == repositoryContext.executionPath
        })?.displayName ?? repositoryContext.executionPath
    }
    public var hasMultipleRepositoryGroups: Bool {
        repositoryGroupSummaries.count > 1
    }
    public var visibleRepositoryGroupSummaries: [WorkspaceCommitRepositoryGroupSummary] {
        repositoryGroupSummaries.filter { $0.changeCount > 0 }
    }
    public var totalIncludedPathCount: Int {
        includedPathsByRepositoryGroupID.values.reduce(into: 0) { partialResult, paths in
            partialResult += paths.count
        }
    }

    public init(
        repositoryContext: WorkspaceCommitRepositoryContext,
        client: Client
    ) {
        self.repositoryContext = repositoryContext
        self.client = client
        self.changesSnapshot = nil
        self.repositoryGroupSummaries = Self.makeRepositoryGroupSummaries(
            from: repositoryContext,
            snapshotsByFamilyID: [:]
        )
        self.snapshotsByRepositoryGroupID = [:]
        self.includedPathsByRepositoryGroupID = [:]
        self.includedPaths = []
        self.selectedChangePath = nil
        self.diffPreview = .idle
        self.commitMessage = ""
        self.options = WorkspaceCommitOptionsState()
        self.isRevertingChanges = false
        self.executionState = .idle
        self.errorMessage = nil
    }

    deinit {
        diffPreviewTask?.cancel()
        changesSnapshotRefreshTask?.cancel()
        revertTask?.cancel()
        commitExecutionTask?.cancel()
    }

    public func updateRepositoryContext(_ repositoryContext: WorkspaceCommitRepositoryContext) {
        let previousContext = self.repositoryContext
        guard previousContext != repositoryContext else {
            return
        }
        let didChangeScope = Self.scopeChanged(previousContext: previousContext, nextContext: repositoryContext)
        self.repositoryContext = repositoryContext

        changesSnapshotRefreshTask?.cancel()
        changesSnapshotRefreshTask = nil
        changesSnapshotRefreshRevision += 1
        diffPreviewTask?.cancel()
        diffPreviewRevision += 1
        revertTask?.cancel()
        revertTask = nil
        revertRevision += 1
        commitExecutionTask?.cancel()
        commitExecutionTask = nil
        commitExecutionRevision += 1
        selectedChangePath = nil
        diffPreview = .idle
        if didChangeScope {
            changesSnapshot = nil
            repositoryGroupSummaries = Self.makeRepositoryGroupSummaries(
                from: repositoryContext,
                snapshotsByFamilyID: [:]
            )
            snapshotsByRepositoryGroupID = [:]
            includedPathsByRepositoryGroupID = [:]
        } else {
            repositoryGroupSummaries = Self.makeRepositoryGroupSummaries(
                from: repositoryContext,
                snapshotsByFamilyID: snapshotsByRepositoryGroupID
            )
            changesSnapshot = snapshotsByRepositoryGroupID[repositoryContext.selectedRepositoryFamilyID]
        }
        includedPaths = includedPathsByRepositoryGroupID[repositoryContext.selectedRepositoryFamilyID] ?? []
        isRevertingChanges = false
        executionState = .idle
        errorMessage = nil
        refreshChangesSnapshot(preservingUserState: !didChangeScope)
    }

    public func selectRepositoryFamily(_ id: String) {
        guard let family = repositoryContext.availableRepositoryFamilies.first(where: { $0.id == id }) else {
            return
        }
        let nextExecutionPath = Self.resolveExecutionPath(
            for: family,
            preferredExecutionPath: family.preferredExecutionPath
        )
        let nextContext = WorkspaceCommitRepositoryContext(
            rootProjectPath: repositoryContext.rootProjectPath,
            repositoryPath: family.repositoryPath,
            executionPath: nextExecutionPath,
            repositoryFamilies: repositoryContext.repositoryFamilies,
            selectedRepositoryFamilyID: family.id
        )
        updateRepositoryContext(nextContext)
        onRepositorySelectionChange?(nextContext)
    }

    public func refreshChangesSnapshot(preservingUserState: Bool = true) {
        changesSnapshotRefreshTask?.cancel()
        changesSnapshotRefreshRevision += 1
        let currentRevision = changesSnapshotRefreshRevision
        let repositoryContext = repositoryContext

        changesSnapshotRefreshTask = Task { [client] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try Self.loadSnapshots(
                        for: repositoryContext,
                        client: client
                    )
                }.value
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { [weak self] in
                    guard let self,
                          self.changesSnapshotRefreshRevision == currentRevision,
                          self.repositoryContext == repositoryContext
                    else {
                        return
                    }
                    self.changesSnapshotRefreshTask = nil
                    self.applyChangesSnapshot(
                        result.selectedSnapshot,
                        repositoryContext: repositoryContext,
                        snapshotsByFamilyID: result.snapshotsByFamilyID,
                        preservingUserState: preservingUserState
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { [weak self] in
                    guard let self,
                          self.changesSnapshotRefreshRevision == currentRevision,
                          self.repositoryContext == repositoryContext
                    else {
                        return
                    }
                    self.changesSnapshotRefreshTask = nil
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func applyChangesSnapshot(
        _ snapshot: WorkspaceCommitChangesSnapshot,
        repositoryContext: WorkspaceCommitRepositoryContext,
        snapshotsByFamilyID: [String: WorkspaceCommitChangesSnapshot],
        preservingUserState: Bool
    ) {
        let previousSnapshotsByFamilyID = snapshotsByRepositoryGroupID
        let previousIncludedPathsByFamilyID = includedPathsByRepositoryGroupID
        let previousSelectedChangePath = preservingUserState ? selectedChangePath : nil
        snapshotsByRepositoryGroupID = snapshotsByFamilyID
        includedPathsByRepositoryGroupID = repositoryContext.availableRepositoryFamilies.reduce(into: [:]) { partialResult, family in
            let nextSnapshot = snapshotsByFamilyID[family.id] ?? WorkspaceCommitChangesSnapshot(branchName: nil, changes: [])
            let previousSnapshot = previousSnapshotsByFamilyID[family.id]
            let previousIncludedPaths = previousIncludedPathsByFamilyID[family.id] ?? []
            partialResult[family.id] = mergedIncludedPaths(
                for: nextSnapshot,
                previousSnapshot: previousSnapshot,
                previousIncludedPaths: previousIncludedPaths,
                preservingUserState: preservingUserState
            )
        }
        repositoryGroupSummaries = Self.makeRepositoryGroupSummaries(
            from: repositoryContext,
            snapshotsByFamilyID: snapshotsByFamilyID
        )

        includedPaths = includedPathsByRepositoryGroupID[repositoryContext.selectedRepositoryFamilyID] ?? []
        changesSnapshot = snapshot

        if let previousSelectedChangePath,
           !snapshot.changes.contains(where: { $0.path == previousSelectedChangePath }) {
            selectedChangePath = nil
            diffPreview = .idle
        } else if let previousSelectedChangePath {
            selectChange(previousSelectedChangePath)
        } else if !preservingUserState {
            selectedChangePath = nil
            diffPreview = .idle
        }
        errorMessage = nil
    }

    public func changesSnapshot(forRepositoryGroupID id: String) -> WorkspaceCommitChangesSnapshot? {
        if id == repositoryContext.selectedRepositoryFamilyID {
            return changesSnapshot ?? snapshotsByRepositoryGroupID[id]
        }
        return snapshotsByRepositoryGroupID[id]
    }

    public func isIncluded(_ path: String, repositoryGroupID: String? = nil) -> Bool {
        let targetRepositoryGroupID = repositoryGroupID ?? repositoryContext.selectedRepositoryFamilyID
        if targetRepositoryGroupID == repositoryContext.selectedRepositoryFamilyID {
            return includedPaths.contains(path)
        }
        return includedPathsByRepositoryGroupID[targetRepositoryGroupID]?.contains(path) == true
    }

    public func setInclusion(for path: String, included: Bool) {
        setInclusion(
            for: path,
            repositoryGroupID: repositoryContext.selectedRepositoryFamilyID,
            included: included
        )
    }

    public func setInclusion(
        for path: String,
        repositoryGroupID: String,
        included: Bool
    ) {
        guard let snapshot = changesSnapshot(forRepositoryGroupID: repositoryGroupID),
              snapshot.changes.contains(where: { $0.path == path }) else {
            return
        }

        var nextIncludedPaths = includedPathsByRepositoryGroupID[repositoryGroupID] ?? []
        if included {
            nextIncludedPaths.insert(path)
        } else {
            nextIncludedPaths.remove(path)
        }
        includedPathsByRepositoryGroupID[repositoryGroupID] = nextIncludedPaths
        if repositoryGroupID == repositoryContext.selectedRepositoryFamilyID {
            includedPaths = nextIncludedPaths
        }
        clearExecutionFeedbackIfNeeded()
    }

    public func toggleInclusion(for path: String) {
        toggleInclusion(
            for: path,
            repositoryGroupID: repositoryContext.selectedRepositoryFamilyID
        )
    }

    public func toggleInclusion(for path: String, repositoryGroupID: String) {
        setInclusion(
            for: path,
            repositoryGroupID: repositoryGroupID,
            included: !isIncluded(path, repositoryGroupID: repositoryGroupID)
        )
    }

    public func toggleAllInclusion() {
        toggleAllInclusion(for: repositoryContext.selectedRepositoryFamilyID)
    }

    public func toggleAllInclusion(for repositoryGroupID: String) {
        guard let changes = changesSnapshot(forRepositoryGroupID: repositoryGroupID)?.changes,
              !changes.isEmpty else {
            return
        }

        let shouldIncludeAll = !changes.allSatisfy { isIncluded($0.path, repositoryGroupID: repositoryGroupID) }
        var nextIncludedPaths = includedPathsByRepositoryGroupID[repositoryGroupID] ?? []
        for change in changes {
            if shouldIncludeAll {
                nextIncludedPaths.insert(change.path)
            } else {
                nextIncludedPaths.remove(change.path)
            }
        }
        includedPathsByRepositoryGroupID[repositoryGroupID] = nextIncludedPaths
        if repositoryGroupID == repositoryContext.selectedRepositoryFamilyID {
            includedPaths = nextIncludedPaths
        }
        clearExecutionFeedbackIfNeeded()
    }

    public func selectChange(_ path: String?) {
        diffPreviewTask?.cancel()
        diffPreviewRevision += 1

        guard let path else {
            selectedChangePath = nil
            diffPreview = .idle
            return
        }
        guard changesSnapshot?.changes.contains(where: { $0.path == path }) == true else {
            return
        }

        selectedChangePath = path
        diffPreview = WorkspaceCommitDiffPreviewState(path: path, content: "", isLoading: true, errorMessage: nil)

        let currentRevision = diffPreviewRevision
        let executionPath = repositoryContext.executionPath
        diffPreviewTask = Task { [client] in
            do {
                let content = try await Task.detached(priority: .userInitiated) {
                    try client.loadDiffPreview(executionPath, path)
                }.value
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { [weak self] in
                    guard let self,
                          self.diffPreviewRevision == currentRevision,
                          self.selectedChangePath == path
                    else {
                        return
                    }
                    self.diffPreview = WorkspaceCommitDiffPreviewState(
                        path: path,
                        content: content,
                        isLoading: false,
                        errorMessage: nil
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { [weak self] in
                    guard let self,
                          self.diffPreviewRevision == currentRevision,
                          self.selectedChangePath == path
                    else {
                        return
                    }
                    self.diffPreview = WorkspaceCommitDiffPreviewState(
                        path: path,
                        content: "",
                        isLoading: false,
                        errorMessage: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                }
            }
        }
    }

    public func updateCommitMessage(_ message: String) {
        commitMessage = message
        clearExecutionFeedbackIfNeeded()
    }

    public func updateOptions(_ options: WorkspaceCommitOptionsState) {
        self.options = normalizeOptions(options)
        clearExecutionFeedbackIfNeeded()
    }

    public func updateOptionAmend(_ enabled: Bool) {
        options.isAmend = enabled
        clearExecutionFeedbackIfNeeded()
    }

    public func updateOptionSignOff(_ enabled: Bool) {
        options.isSignOff = enabled
        clearExecutionFeedbackIfNeeded()
    }

    public func updateOptionAuthor(_ author: String) {
        options.author = normalizeAuthor(author)
        clearExecutionFeedbackIfNeeded()
    }

    public func canRevert(paths: [String]) -> Bool {
        !normalizePaths(paths).isEmpty && !executionState.isRunning && !isRevertingChanges
    }

    public func revertChanges(paths: [String], deleteLocallyAddedFiles: Bool) {
        let normalizedPaths = normalizePaths(paths)
        guard canRevert(paths: normalizedPaths) else {
            return
        }

        revertTask?.cancel()
        revertRevision += 1
        let currentRevision = revertRevision
        let executionPath = repositoryContext.executionPath
        clearExecutionFeedbackIfNeeded()
        isRevertingChanges = true
        errorMessage = nil

        revertTask = Task { [client] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    try client.revertChanges(executionPath, normalizedPaths, deleteLocallyAddedFiles)
                }.value
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { [weak self] in
                    guard let self,
                          self.revertRevision == currentRevision,
                          self.repositoryContext.executionPath == executionPath
                    else {
                        return
                    }
                    self.revertTask = nil
                    self.isRevertingChanges = false
                    self.errorMessage = nil
                    self.refreshChangesSnapshot()
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { [weak self] in
                    guard let self,
                          self.revertRevision == currentRevision,
                          self.repositoryContext.executionPath == executionPath
                    else {
                        return
                    }
                    self.revertTask = nil
                    self.isRevertingChanges = false
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    public func canExecuteCommit(action: WorkspaceCommitAction) -> Bool {
        guard !executionState.isRunning, !isRevertingChanges else {
            return false
        }
        guard totalIncludedPathCount > 0 else {
            return false
        }

        if normalizedCommitMessage.isEmpty {
            return options.isAmend && action == .commit
        }
        return true
    }

    public func executeCommit(action: WorkspaceCommitAction) {
        guard canExecuteCommit(action: action) else {
            if executionState.isRunning {
                return
            }
            let message = "请先填写提交信息并至少纳入一个变更"
            executionState = .failed(message)
            errorMessage = message
            return
        }

        let normalizedOptions = normalizeOptions(options)
        let executionTargets = Self.makeExecutionTargets(
            repositoryContext: repositoryContext,
            includedPathsByRepositoryGroupID: includedPathsByRepositoryGroupID,
            action: action,
            message: normalizedCommitMessage,
            options: normalizedOptions
        )
        guard !executionTargets.isEmpty else {
            let message = "请至少纳入一个变更"
            executionState = .failed(message)
            errorMessage = message
            return
        }
        commitExecutionTask?.cancel()
        commitExecutionRevision += 1
        let currentRevision = commitExecutionRevision
        executionState = .running(action)
        errorMessage = nil

        commitExecutionTask = Task { [client] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    for target in executionTargets {
                        do {
                            try client.executeCommit(target.executionPath, target.request)
                        } catch {
                            throw MultiRepositoryCommitError(
                                repositoryDisplayName: target.displayName,
                                underlyingError: error
                            )
                        }
                    }
                }.value
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { [weak self] in
                    guard let self,
                          self.commitExecutionRevision == currentRevision
                    else {
                        return
                    }
                    self.commitExecutionTask = nil
                    self.executionState = .succeeded(action)
                    self.errorMessage = nil
                    self.refreshChangesSnapshot(preservingUserState: false)
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { [weak self] in
                    guard let self,
                          self.commitExecutionRevision == currentRevision
                    else {
                        return
                    }
                    self.commitExecutionTask = nil
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.executionState = .failed(message)
                    self.errorMessage = message
                }
            }
        }
    }

    private var normalizedCommitMessage: String {
        commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeOptions(_ options: WorkspaceCommitOptionsState) -> WorkspaceCommitOptionsState {
        WorkspaceCommitOptionsState(
            isAmend: options.isAmend,
            isSignOff: options.isSignOff,
            author: normalizeAuthor(options.author)
        )
    }

    private func normalizeAuthor(_ author: String?) -> String? {
        guard let author else {
            return nil
        }
        let trimmed = author.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated static func loadSnapshots(
        for repositoryContext: WorkspaceCommitRepositoryContext,
        client: Client
    ) throws -> (
        selectedSnapshot: WorkspaceCommitChangesSnapshot,
        snapshotsByFamilyID: [String: WorkspaceCommitChangesSnapshot]
    ) {
        var snapshotsByFamilyID: [String: WorkspaceCommitChangesSnapshot] = [:]
        for family in repositoryContext.availableRepositoryFamilies {
            let executionPath: String
            if family.id == repositoryContext.selectedRepositoryFamilyID {
                executionPath = repositoryContext.executionPath
            } else {
                executionPath = resolveExecutionPath(
                    for: family,
                    preferredExecutionPath: family.preferredExecutionPath
                )
            }
            snapshotsByFamilyID[family.id] = try client.loadChangesSnapshot(executionPath)
        }

        let selectedSnapshot = snapshotsByFamilyID[repositoryContext.selectedRepositoryFamilyID]
            ?? snapshotsByFamilyID.values.first
            ?? WorkspaceCommitChangesSnapshot(branchName: nil, changes: [])
        return (selectedSnapshot, snapshotsByFamilyID)
    }

    private nonisolated static func makeRepositoryGroupSummaries(
        from repositoryContext: WorkspaceCommitRepositoryContext,
        snapshotsByFamilyID: [String: WorkspaceCommitChangesSnapshot]
    ) -> [WorkspaceCommitRepositoryGroupSummary] {
        repositoryContext.availableRepositoryFamilies.map { family in
            let executionPath: String
            if family.id == repositoryContext.selectedRepositoryFamilyID {
                executionPath = repositoryContext.executionPath
            } else {
                executionPath = resolveExecutionPath(
                    for: family,
                    preferredExecutionPath: family.preferredExecutionPath
                )
            }
            let snapshot = snapshotsByFamilyID[family.id]
            return WorkspaceCommitRepositoryGroupSummary(
                id: family.id,
                displayName: family.displayName,
                branchName: snapshot?.branchName
                    ?? family.members.first(where: { $0.path == executionPath })?.branchName,
                changeCount: snapshot?.changes.count ?? 0,
                executionPath: executionPath,
                repositoryPath: family.repositoryPath,
                isSelected: family.id == repositoryContext.selectedRepositoryFamilyID
            )
        }
    }

    private nonisolated static func resolveExecutionPath(
        for family: WorkspaceGitRepositoryFamilyContext,
        preferredExecutionPath: String
    ) -> String {
        if family.members.contains(where: { $0.path == preferredExecutionPath }) {
            return preferredExecutionPath
        }
        return family.members.first?.path ?? preferredExecutionPath
    }

    private nonisolated static func scopeChanged(
        previousContext: WorkspaceCommitRepositoryContext,
        nextContext: WorkspaceCommitRepositoryContext
    ) -> Bool {
        previousContext.rootProjectPath != nextContext.rootProjectPath ||
            previousContext.availableRepositoryFamilies != nextContext.availableRepositoryFamilies
    }

    private nonisolated static func makeExecutionTargets(
        repositoryContext: WorkspaceCommitRepositoryContext,
        includedPathsByRepositoryGroupID: [String: Set<String>],
        action: WorkspaceCommitAction,
        message: String,
        options: WorkspaceCommitOptionsState
    ) -> [CommitExecutionTarget] {
        repositoryContext.availableRepositoryFamilies.compactMap { family in
            let includedPaths = (includedPathsByRepositoryGroupID[family.id] ?? []).sorted()
            guard !includedPaths.isEmpty else {
                return nil
            }

            let executionPath: String
            if family.id == repositoryContext.selectedRepositoryFamilyID {
                executionPath = repositoryContext.executionPath
            } else {
                executionPath = resolveExecutionPath(
                    for: family,
                    preferredExecutionPath: family.preferredExecutionPath
                )
            }

            return CommitExecutionTarget(
                displayName: family.displayName,
                executionPath: executionPath,
                request: WorkspaceCommitExecutionRequest(
                    action: action,
                    message: message,
                    includedPaths: includedPaths,
                    options: options
                )
            )
        }
    }

    private func normalizePaths(_ paths: [String]) -> [String] {
        Array(
            Set(
                paths
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()
    }

    private func mergedIncludedPaths(
        for snapshot: WorkspaceCommitChangesSnapshot,
        previousSnapshot: WorkspaceCommitChangesSnapshot?,
        previousIncludedPaths: Set<String>,
        preservingUserState: Bool
    ) -> Set<String> {
        guard preservingUserState, let previousSnapshot else {
            return Set(
                snapshot.changes
                    .filter(\.isIncludedByDefault)
                    .map(\.path)
            )
        }

        let previousPaths = Set(previousSnapshot.changes.map(\.path))
        return Set(snapshot.changes.compactMap { change in
            if previousPaths.contains(change.path) {
                return previousIncludedPaths.contains(change.path) ? change.path : nil
            }
            return change.isIncludedByDefault ? change.path : nil
        })
    }

    private func clearExecutionFeedbackIfNeeded() {
        guard !executionState.isRunning else {
            return
        }
        executionState = .idle
        errorMessage = nil
    }

    private func normalizedBranchName(_ branchName: String?) -> String? {
        guard let branchName else {
            return nil
        }
        let trimmed = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct CommitExecutionTarget: Sendable {
    let displayName: String
    let executionPath: String
    let request: WorkspaceCommitExecutionRequest
}

private struct MultiRepositoryCommitError: LocalizedError {
    let repositoryDisplayName: String
    let underlyingError: Error

    var errorDescription: String? {
        let underlyingMessage = (underlyingError as? LocalizedError)?.errorDescription
            ?? underlyingError.localizedDescription
        return "\(repositoryDisplayName) 提交失败：\(underlyingMessage)"
    }
}
