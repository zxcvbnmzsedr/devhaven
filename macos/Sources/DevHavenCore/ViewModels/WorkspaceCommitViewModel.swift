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
            Client(
                loadChangesSnapshot: { executionPath in
                    let snapshot = try service.loadChanges(at: executionPath)
                    return WorkspaceCommitChangesSnapshot.fromGitWorkingTree(snapshot)
                },
                loadDiffPreview: { _, _ in
                    ""
                },
                executeCommit: { executionPath, request in
                    if request.options.isAmend {
                        let trimmed = request.message.trimmingCharacters(in: .whitespacesAndNewlines)
                        try service.amend(message: trimmed.isEmpty ? nil : trimmed, at: executionPath)
                    } else {
                        try service.commit(message: request.message, at: executionPath)
                    }
                    if request.action == .commitAndPush {
                        try service.push(at: executionPath)
                    }
                }
            )
        }
    }

    @ObservationIgnored private let client: Client

    public var repositoryContext: WorkspaceCommitRepositoryContext
    public var changesSnapshot: WorkspaceCommitChangesSnapshot?
    public var includedPaths: Set<String>
    public var selectedChangePath: String?
    public var diffPreview: WorkspaceCommitDiffPreviewState
    public var commitMessage: String
    public var options: WorkspaceCommitOptionsState
    public var executionState: WorkspaceCommitExecutionState
    public var errorMessage: String?

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
        do {
            let content = try client.loadDiffPreview(repositoryContext.executionPath, path)
            diffPreview = WorkspaceCommitDiffPreviewState(path: path, content: content, isLoading: false, errorMessage: nil)
        } catch {
            diffPreview = WorkspaceCommitDiffPreviewState(
                path: path,
                content: "",
                isLoading: false,
                errorMessage: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    public func updateCommitMessage(_ message: String) {
        commitMessage = message
    }

    public func updateOptions(_ options: WorkspaceCommitOptionsState) {
        self.options = options
    }

    public func executeCommit(action: WorkspaceCommitAction) {
        let request = WorkspaceCommitExecutionRequest(
            action: action,
            message: commitMessage,
            includedPaths: includedPaths.sorted(),
            options: options
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
}
