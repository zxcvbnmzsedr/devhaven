import Foundation

@MainActor
final class WorkspaceDiffRequestBuilder {
    private let commitChanges: @MainActor () -> [WorkspaceCommitChange]?
    private let selectedGitCommitDetail: @MainActor () -> WorkspaceGitCommitDetail?

    private static let gitDiffTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    init(
        commitChanges: @escaping @MainActor () -> [WorkspaceCommitChange]?,
        selectedGitCommitDetail: @escaping @MainActor () -> WorkspaceGitCommitDetail?
    ) {
        self.commitChanges = commitChanges
        self.selectedGitCommitDetail = selectedGitCommitDetail
    }

    func requestChain(
        for source: WorkspaceDiffSource,
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

    func commitDiffRequestChain(
        repositoryPath: String,
        executionPath: String,
        activeFilePath: String,
        activeGroup: WorkspaceCommitChangeGroup?,
        activeStatus: WorkspaceCommitChangeStatus?,
        activeOldPath: String?,
        activePreferredTitle: String,
        preferredViewerMode: WorkspaceDiffViewerMode,
        changes: [WorkspaceCommitChange]? = nil
    ) -> WorkspaceDiffRequestChain {
        let snapshotChanges = changes ?? commitChanges()
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

    func gitLogDiffRequestChain(
        repositoryPath: String,
        commitHash: String,
        activeFilePath: String,
        activePreferredTitle: String,
        preferredViewerMode: WorkspaceDiffViewerMode
    ) -> WorkspaceDiffRequestChain {
        guard let detail = selectedGitCommitDetail(),
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

    func makeCommitPreviewOpenRequest(
        projectPath: String,
        presentedTabSelection: WorkspacePresentedTabSelection?,
        focusedArea: WorkspaceFocusedArea,
        identityOverride: String,
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
            projectPath: projectPath,
            source: activeItem.source,
            preferredTitle: activeItem.title,
            preferredViewerMode: activeItem.preferredViewerMode,
            requestChain: chain,
            identityOverride: identityOverride,
            originContext: WorkspaceDiffOriginContext(
                presentedTabSelection: presentedTabSelection,
                focusedArea: focusedArea
            )
        )
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

    private func gitDiffTimestampText(_ timestamp: TimeInterval) -> String {
        Self.gitDiffTimestampFormatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}
