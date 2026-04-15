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

    public var repositoryContext: WorkspaceCommitRepositoryContext
    public var changesSnapshot: WorkspaceCommitChangesSnapshot?
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
        return "分支 \(branch) · Included \(includedPaths.count) · \(executionState.summaryText)"
    }

    public init(
        repositoryContext: WorkspaceCommitRepositoryContext,
        client: Client
    ) {
        self.repositoryContext = repositoryContext
        self.client = client
        self.changesSnapshot = nil
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
        let pathChanged = self.repositoryContext.repositoryPath != repositoryContext.repositoryPath
            || self.repositoryContext.executionPath != repositoryContext.executionPath
        self.repositoryContext = repositoryContext
        guard pathChanged else {
            return
        }

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
        changesSnapshot = nil
        includedPaths = []
        isRevertingChanges = false
        executionState = .idle
        errorMessage = nil
        refreshChangesSnapshot(preservingUserState: false)
    }

    public func refreshChangesSnapshot(preservingUserState: Bool = true) {
        changesSnapshotRefreshTask?.cancel()
        changesSnapshotRefreshRevision += 1
        let currentRevision = changesSnapshotRefreshRevision
        let executionPath = repositoryContext.executionPath

        changesSnapshotRefreshTask = Task { [client] in
            do {
                let snapshot = try await Task.detached(priority: .userInitiated) {
                    try client.loadChangesSnapshot(executionPath)
                }.value
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { [weak self] in
                    guard let self,
                          self.changesSnapshotRefreshRevision == currentRevision,
                          self.repositoryContext.executionPath == executionPath
                    else {
                        return
                    }
                    self.changesSnapshotRefreshTask = nil
                    self.applyChangesSnapshot(snapshot, preservingUserState: preservingUserState)
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { [weak self] in
                    guard let self,
                          self.changesSnapshotRefreshRevision == currentRevision,
                          self.repositoryContext.executionPath == executionPath
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
        preservingUserState: Bool
    ) {
        let previousSnapshot = changesSnapshot
        let previousIncludedPaths = includedPaths
        let previousSelectedChangePath = preservingUserState ? selectedChangePath : nil

        guard snapshot != previousSnapshot else {
            errorMessage = nil
            return
        }

        changesSnapshot = snapshot
        includedPaths = mergedIncludedPaths(
            for: snapshot,
            previousSnapshot: previousSnapshot,
            previousIncludedPaths: previousIncludedPaths,
            preservingUserState: preservingUserState
        )
        if let previousSelectedChangePath,
           !snapshot.changes.contains(where: { $0.path == previousSelectedChangePath }) {
            selectedChangePath = nil
            diffPreview = .idle
        } else if let previousSelectedChangePath {
            selectChange(previousSelectedChangePath)
        }
        errorMessage = nil
    }

    public func setInclusion(for path: String, included: Bool) {
        guard let snapshot = changesSnapshot,
              snapshot.changes.contains(where: { $0.path == path }) else {
            return
        }
        if included {
            includedPaths.insert(path)
        } else {
            includedPaths.remove(path)
        }
    }

    public func toggleInclusion(for path: String) {
        setInclusion(for: path, included: !includedPaths.contains(path))
    }

    public func toggleAllInclusion() {
        guard let changes = changesSnapshot?.changes, !changes.isEmpty else {
            return
        }

        if areAllChangesIncluded {
            for change in changes {
                includedPaths.remove(change.path)
            }
        } else {
            for change in changes {
                includedPaths.insert(change.path)
            }
        }
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
        guard !includedPaths.isEmpty else {
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

        let request = WorkspaceCommitExecutionRequest(
            action: action,
            message: normalizedCommitMessage,
            includedPaths: includedPaths.sorted(),
            options: normalizeOptions(options)
        )
        commitExecutionTask?.cancel()
        commitExecutionRevision += 1
        let currentRevision = commitExecutionRevision
        let executionPath = repositoryContext.executionPath
        executionState = .running(action)
        errorMessage = nil

        commitExecutionTask = Task { [client] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    try client.executeCommit(executionPath, request)
                }.value
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { [weak self] in
                    guard let self,
                          self.commitExecutionRevision == currentRevision,
                          self.repositoryContext.executionPath == executionPath
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
                          self.commitExecutionRevision == currentRevision,
                          self.repositoryContext.executionPath == executionPath
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
