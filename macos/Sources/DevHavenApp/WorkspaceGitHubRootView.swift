import SwiftUI
import DevHavenCore

struct WorkspaceGitHubRootView: View {
    @Bindable var viewModel: WorkspaceGitHubViewModel
    let onCreateIssueWorktree: ((WorkspaceGitHubIssueDetail) throws -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceGitHubToolbarView(viewModel: viewModel)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(NativeTheme.surface)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(NativeTheme.border)
                        .frame(height: 1)
                }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(NativeTheme.warning)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NativeTheme.warning.opacity(0.12))
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(NativeTheme.window)
        .onAppear {
            viewModel.refreshIfNeeded()
        }
        .onChange(of: viewModel.repositoryContext) { _, _ in
            viewModel.refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading, !hasAnyLoadedItems {
            ProgressView("正在加载 GitHub 协作信息…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.gitHubContext == nil {
            ContentUnavailableView(
                viewModel.errorMessage == nil ? "未解析到远端仓库" : "GitHub 仓库上下文不可用",
                systemImage: "link.badge.plus",
                description: Text(
                    viewModel.errorMessage == nil
                        ? "请确认当前项目配置了可解析的 GitHub 远端。"
                        : "请先处理上方错误信息，然后重新刷新。"
                )
            )
            .foregroundStyle(NativeTheme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !viewModel.authStatus.isAuthenticated {
            ContentUnavailableView(
                "GitHub 未登录",
                systemImage: "person.crop.circle.badge.exclamationmark",
                description: Text(viewModel.authStatus.summaryText)
            )
            .foregroundStyle(NativeTheme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch viewModel.section {
            case .pulls:
                WorkspaceGitHubPullsView(viewModel: viewModel)
            case .issues:
                WorkspaceGitHubIssuesView(
                    viewModel: viewModel,
                    onCreateIssueWorktree: onCreateIssueWorktree
                )
            case .reviews:
                WorkspaceGitHubReviewsView(viewModel: viewModel)
            }
        }
    }

    private var hasAnyLoadedItems: Bool {
        !viewModel.pulls.isEmpty || !viewModel.issues.isEmpty || !viewModel.reviewRequests.isEmpty
    }
}
