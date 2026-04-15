import SwiftUI
import DevHavenCore

struct WorkspaceCommitSideToolWindowHostView: View {
    @Bindable var viewModel: NativeAppViewModel

    var body: some View {
        content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NativeTheme.window)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.setWorkspaceFocusedArea(.sideToolWindow(.commit))
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.activeWorkspaceIsStandaloneQuickTerminal {
            commitModeEmptyState(
                title: "快速终端暂不支持 Commit 模式",
                systemImage: "checkmark.circle",
                description: "请先打开一个 Git 项目或 worktree，再使用 Commit 工具窗。"
            )
        } else if viewModel.activeWorkspaceCommitRepositoryContext == nil {
            commitModeEmptyState(
                title: "当前工作区未发现 Git 仓库",
                systemImage: "checkmark.circle",
                description: "Commit 工具窗会复用 Git 面板当前选中的仓库族与执行仓库。"
            )
        } else if let commitViewModel = viewModel.activeWorkspaceCommitViewModel {
            WorkspaceCommitRootView(
                viewModel: commitViewModel,
                onSyncDiffIfNeeded: { change in
                    syncCommitDiffIfNeeded(commitViewModel: commitViewModel, change: change)
                },
                onOpenDiff: { change in
                    openCommitDiff(commitViewModel: commitViewModel, change: change)
                }
            )
        } else {
            commitModeEmptyState(
                title: "Commit 工具窗尚未就绪",
                systemImage: "tray",
                description: "请重新选择当前项目，或稍后再试。"
            )
        }
    }

    private func syncCommitDiffIfNeeded(
        commitViewModel: WorkspaceCommitViewModel,
        change: WorkspaceCommitChange
    ) {
        viewModel.syncActiveWorkspaceCommitDiffPreviewIfNeeded(
            repositoryPath: commitViewModel.repositoryContext.repositoryPath,
            executionPath: commitViewModel.repositoryContext.executionPath,
            filePath: change.path,
            group: change.group,
            status: change.status,
            oldPath: change.oldPath,
            allChanges: commitViewModel.changesSnapshot?.changes,
            preferredTitle: "Changes: \(commitDiffTitle(for: change))"
        )
    }

    private func openCommitDiff(
        commitViewModel: WorkspaceCommitViewModel,
        change: WorkspaceCommitChange
    ) {
        viewModel.openActiveWorkspaceCommitDiffPreview(
            repositoryPath: commitViewModel.repositoryContext.repositoryPath,
            executionPath: commitViewModel.repositoryContext.executionPath,
            filePath: change.path,
            group: change.group,
            status: change.status,
            oldPath: change.oldPath,
            allChanges: commitViewModel.changesSnapshot?.changes,
            preferredTitle: "Changes: \(commitDiffTitle(for: change))"
        )
    }

    private func commitDiffTitle(for change: WorkspaceCommitChange) -> String {
        let fileName = (change.path as NSString).lastPathComponent
        return fileName.isEmpty ? change.path : fileName
    }

    private func commitModeEmptyState(title: String, systemImage: String, description: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
        .foregroundStyle(NativeTheme.textSecondary)
    }
}
