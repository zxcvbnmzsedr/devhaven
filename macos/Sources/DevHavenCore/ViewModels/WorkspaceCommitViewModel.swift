import Foundation
import Observation

@MainActor
@Observable
public final class WorkspaceCommitViewModel {
    public struct Client: Sendable {
        public var loadChangesSnapshot: @Sendable (String) throws -> WorkspaceCommitChangesSnapshot
        public var loadDiffPreview: @Sendable (String, String) throws -> String
        public var executeCommit: @Sendable (String, WorkspaceCommitExecutionRequest) throws -> Void

        public init(
            loadChangesSnapshot: @escaping @Sendable (String) throws -> WorkspaceCommitChangesSnapshot,
            loadDiffPreview: @escaping @Sendable (String, String) throws -> String,
            executeCommit: @escaping @Sendable (String, WorkspaceCommitExecutionRequest) throws -> Void
        ) {
            self.loadChangesSnapshot = loadChangesSnapshot
            self.loadDiffPreview = loadDiffPreview
            self.executeCommit = executeCommit
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
                }
            )
        }
    }

    @ObservationIgnored private let client: Client
    @ObservationIgnored private var diffPreviewTask: Task<Void, Never>?
    @ObservationIgnored private var diffPreviewRevision = 0

    public var repositoryContext: WorkspaceCommitRepositoryContext
    public var changesSnapshot: WorkspaceCommitChangesSnapshot?
    public var includedPaths: Set<String>
    public var selectedChangePath: String?
    public var diffPreview: WorkspaceCommitDiffPreviewState
    public var commitMessage: String
    public var options: WorkspaceCommitOptionsState
    public var executionState: WorkspaceCommitExecutionState
    public var errorMessage: String?
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
        self.executionState = .idle
        self.errorMessage = nil
    }

    deinit {
        diffPreviewTask?.cancel()
    }

    public func updateRepositoryContext(_ repositoryContext: WorkspaceCommitRepositoryContext) {
        self.repositoryContext = repositoryContext
    }

    public func refreshChangesSnapshot() {
        do {
            let snapshot = try client.loadChangesSnapshot(repositoryContext.executionPath)
            changesSnapshot = snapshot
            includedPaths = Set(
                snapshot.changes
                    .filter(\.isIncludedByDefault)
                    .map(\.path)
            )
            if let selectedChangePath,
               !snapshot.changes.contains(where: { $0.path == selectedChangePath }) {
                self.selectedChangePath = nil
                diffPreview = .idle
            } else if let selectedChangePath {
                selectChange(selectedChangePath)
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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

    public func canExecuteCommit(action: WorkspaceCommitAction) -> Bool {
        guard !executionState.isRunning else {
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
        executionState = .running(action)
        do {
            try client.executeCommit(repositoryContext.executionPath, request)
            executionState = .succeeded(action)
            errorMessage = nil
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            executionState = .failed(message)
            errorMessage = message
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
