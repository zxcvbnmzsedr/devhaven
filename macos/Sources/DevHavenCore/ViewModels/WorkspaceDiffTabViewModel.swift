import Foundation
import Observation

@MainActor
@Observable
public final class WorkspaceDiffTabViewModel {
    public struct Client: Sendable {
        public var loadGitLogCommitFileDiff: @Sendable (String, String, String) throws -> String
        public var loadWorkingTreeDiff: @Sendable (String, String) throws -> String

        public init(
            loadGitLogCommitFileDiff: @escaping @Sendable (String, String, String) throws -> String,
            loadWorkingTreeDiff: @escaping @Sendable (String, String) throws -> String
        ) {
            self.loadGitLogCommitFileDiff = loadGitLogCommitFileDiff
            self.loadWorkingTreeDiff = loadWorkingTreeDiff
        }

        public static func live(
            repositoryService: NativeGitRepositoryService = NativeGitRepositoryService(),
            commitWorkflowService: NativeGitCommitWorkflowService? = nil
        ) -> Client {
            let workflowService = commitWorkflowService ?? NativeGitCommitWorkflowService(repositoryService: repositoryService)
            return Client(
                loadGitLogCommitFileDiff: { repositoryPath, commitHash, filePath in
                    try repositoryService.loadDiffForCommitFile(at: repositoryPath, commitHash: commitHash, filePath: filePath)
                },
                loadWorkingTreeDiff: { executionPath, filePath in
                    try workflowService.loadDiffPreview(at: executionPath, filePath: filePath)
                }
            )
        }
    }

    @ObservationIgnored private let client: Client
    @ObservationIgnored private let parser: @Sendable (String) -> WorkspaceDiffParsedDocument
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var loadRevision = 0

    public var tab: WorkspaceDiffTabState
    public var documentState: WorkspaceDiffDocumentState

    public init(
        tab: WorkspaceDiffTabState,
        client: Client,
        parser: @escaping @Sendable (String) -> WorkspaceDiffParsedDocument = WorkspaceDiffPatchParser.parse
    ) {
        self.tab = tab
        self.client = client
        self.parser = parser
        self.documentState = WorkspaceDiffDocumentState(
            title: tab.title,
            viewerMode: tab.viewerMode
        )
    }

    deinit {
        loadTask?.cancel()
    }

    public func updateViewerMode(_ mode: WorkspaceDiffViewerMode) {
        guard documentState.viewerMode != mode else {
            return
        }
        tab.viewerMode = mode
        documentState.viewerMode = mode
    }

    public func refresh() {
        loadTask?.cancel()
        loadRevision += 1
        let currentRevision = loadRevision
        documentState.loadState = .loading

        let source = tab.source
        let parser = self.parser
        loadTask = Task { [client] in
            do {
                let diff = try await Task.detached(priority: .userInitiated) {
                    switch source {
                    case let .gitLogCommitFile(repositoryPath, commitHash, filePath):
                        return try client.loadGitLogCommitFileDiff(repositoryPath, commitHash, filePath)
                    case let .workingTreeChange(_, executionPath, filePath):
                        return try client.loadWorkingTreeDiff(executionPath, filePath)
                    }
                }.value
                guard !Task.isCancelled else {
                    return
                }
                let parsed = parser(diff)
                await MainActor.run { [weak self] in
                    guard let self, self.loadRevision == currentRevision else {
                        return
                    }
                    self.documentState.loadState = .loaded(parsed)
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.loadRevision == currentRevision else {
                        return
                    }
                    self.documentState.loadState = .failed(
                        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                }
            }
        }
    }
}
