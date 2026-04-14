import AppKit
import SwiftUI
import DevHavenCore

struct WorkspaceGitHubIssuesView: View {
    @Bindable var viewModel: WorkspaceGitHubViewModel
    @State private var splitRatio = 0.36

    var body: some View {
        WorkspaceSplitView(
            direction: .horizontal,
            ratio: splitRatio,
            onRatioChange: { splitRatio = $0 },
            minLeadingSize: 260,
            minTrailingSize: 320,
            leading: {
                listPane
            },
            trailing: {
                detailPane
            }
        )
    }

    private var listPane: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if viewModel.issues.isEmpty, !viewModel.isLoading {
                    ContentUnavailableView(
                        "暂无 Issues",
                        systemImage: "circle.lefthalf.filled",
                        description: Text("当前仓库没有符合条件的 Issue。")
                    )
                    .foregroundStyle(NativeTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    ForEach(viewModel.issues) { issue in
                        WorkspaceGitHubIssueRowView(
                            issue: issue,
                            isSelected: viewModel.selectedIssueNumber == issue.number,
                            onSelect: { viewModel.selectIssue(number: issue.number) }
                        )
                        .contextMenu {
                            Button("在 GitHub 中打开") {
                                openURL(issue.url)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(NativeTheme.sidebar)
        .overlay {
            if viewModel.isLoading {
                WorkspaceGitHubListLoadingOverlay(title: "正在刷新 Issues…")
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if viewModel.isLoadingDetail {
            ProgressView("正在加载 Issue 详情…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NativeTheme.window)
        } else if let detailErrorMessage = viewModel.detailErrorMessage {
            ContentUnavailableView(
                "Issue 详情加载失败",
                systemImage: "exclamationmark.triangle",
                description: Text(detailErrorMessage)
            )
            .foregroundStyle(NativeTheme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NativeTheme.window)
        } else if let detail = viewModel.selectedIssueDetail {
            WorkspaceGitHubIssueDetailView(detail: detail)
        } else {
            ContentUnavailableView(
                "选择一个 Issue",
                systemImage: "circle.lefthalf.filled",
                description: Text("从左侧列表中选择一个 Issue 查看详情。")
            )
            .foregroundStyle(NativeTheme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NativeTheme.window)
        }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
