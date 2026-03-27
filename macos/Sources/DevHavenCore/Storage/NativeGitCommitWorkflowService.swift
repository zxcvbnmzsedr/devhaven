import Foundation

public struct NativeGitCommitWorkflowService: Sendable {
    private let repositoryService: NativeGitRepositoryService

    public init(repositoryService: NativeGitRepositoryService = NativeGitRepositoryService()) {
        self.repositoryService = repositoryService
    }

    public func loadChangesSnapshot(at executionPath: String) throws -> WorkspaceCommitChangesSnapshot {
        let snapshot = try repositoryService.loadChanges(at: executionPath)
        return WorkspaceCommitChangesSnapshot.fromGitWorkingTree(snapshot)
    }

    public func loadDiffPreview(at executionPath: String, filePath: String) throws -> String {
        try repositoryService.loadWorkingTreeDiff(at: executionPath, filePath: filePath)
    }

    public func executeCommit(at executionPath: String, request: WorkspaceCommitExecutionRequest) throws {
        let includedPaths = normalizePaths(request.includedPaths)
        guard !includedPaths.isEmpty else {
            throw WorkspaceGitCommandError.operationRejected("included paths 不能为空")
        }

        let snapshot = try repositoryService.loadChanges(at: executionPath)
        let availablePaths = Set(
            snapshot.staged.map(\.path)
                + snapshot.unstaged.map(\.path)
                + snapshot.untracked.map(\.path)
                + snapshot.conflicted.map(\.path)
        )
        let selectedPaths = Set(includedPaths.filter { availablePaths.contains($0) })
        guard !selectedPaths.isEmpty else {
            throw WorkspaceGitCommandError.operationRejected("included paths 未命中当前工作区变更")
        }

        let conflictedPaths = Set(snapshot.conflicted.map(\.path))
        if !selectedPaths.isDisjoint(with: conflictedPaths) {
            throw WorkspaceGitCommandError.interactionRequired(
                command: "git commit",
                reason: "included paths 包含冲突文件，请先解决冲突后再提交"
            )
        }

        let stagedPaths = Set(snapshot.staged.map(\.path))
        let pathsToUnstage = stagedPaths.subtracting(selectedPaths).sorted()
        if !pathsToUnstage.isEmpty {
            try repositoryService.unstage(paths: pathsToUnstage, at: executionPath)
        }

        let pathsToStage = selectedPaths.sorted()
        try repositoryService.stage(paths: pathsToStage, at: executionPath)

        if request.options.isAmend {
            let amendedMessage = request.message.trimmingCharacters(in: .whitespacesAndNewlines)
            try repositoryService.amend(
                message: amendedMessage.isEmpty ? nil : amendedMessage,
                at: executionPath
            )
        } else {
            try repositoryService.commit(message: request.message, at: executionPath)
        }

        if request.action == .commitAndPush {
            try repositoryService.push(at: executionPath)
        }
    }

    private func normalizePaths(_ paths: [String]) -> [String] {
        paths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
