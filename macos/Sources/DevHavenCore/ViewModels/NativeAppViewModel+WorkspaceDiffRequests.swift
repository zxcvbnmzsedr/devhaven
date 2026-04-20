import Foundation

extension NativeAppViewModel {
    func requestChainForActiveDiffSource(
        source: WorkspaceDiffSource,
        preferredTitle: String,
        preferredViewerMode: WorkspaceDiffViewerMode
    ) -> WorkspaceDiffRequestChain {
        workspaceDiffRequestBuilder.requestChain(
            for: source,
            preferredTitle: preferredTitle,
            preferredViewerMode: preferredViewerMode
        )
    }

    func activeWorkspaceCommitDiffPreviewRequest(
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
        return workspaceDiffRequestBuilder.makeCommitPreviewOpenRequest(
            projectPath: activeWorkspaceProjectPath,
            presentedTabSelection: workspaceSelectedPresentedTab(for: activeWorkspaceProjectPath),
            focusedArea: workspaceFocusedArea,
            identityOverride: commitPreviewIdentity(for: executionPath),
            repositoryPath: repositoryPath,
            executionPath: executionPath,
            filePath: filePath,
            group: group,
            status: status,
            oldPath: oldPath,
            allChanges: allChanges,
            preferredTitle: preferredTitle,
            preferredViewerMode: preferredViewerMode
        )
    }

    private func commitPreviewIdentity(for executionPath: String) -> String {
        "commit-preview|\(executionPath)"
    }
}
