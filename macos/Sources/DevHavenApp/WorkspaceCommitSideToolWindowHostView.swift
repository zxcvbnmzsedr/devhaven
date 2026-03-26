import SwiftUI
import DevHavenCore

struct WorkspaceCommitSideToolWindowHostView: View {
    @Bindable var viewModel: NativeAppViewModel

    var body: some View {
        Group {
            if isActiveQuickTerminalSession {
                commitModeEmptyState(
                    title: "快速终端暂不支持 Commit 模式",
                    systemImage: "checkmark.circle",
                    description: "请先打开一个 Git 项目或 worktree，再使用 Commit 工具窗。"
                )
            } else if viewModel.activeWorkspaceCommitRepositoryContext == nil {
                commitModeEmptyState(
                    title: "当前项目不是 Git 仓库",
                    systemImage: "checkmark.circle",
                    description: "Commit 工具窗只会对当前 active project 所属的 root repository 生效。"
                )
            } else if let commitViewModel = viewModel.activeWorkspaceCommitViewModel {
                WorkspaceCommitRootView(viewModel: commitViewModel)
            } else {
                commitModeEmptyState(
                    title: "Commit 工具窗尚未就绪",
                    systemImage: "tray",
                    description: "请重新选择当前项目，或稍后再试。"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NativeTheme.window)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.setWorkspaceFocusedArea(.sideToolWindow(.commit))
        }
    }

    private var isActiveQuickTerminalSession: Bool {
        guard let activePath = viewModel.activeWorkspaceProjectPath else {
            return false
        }
        return viewModel.openWorkspaceSessions.first(where: { $0.projectPath == activePath })?.isQuickTerminal ?? false
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
