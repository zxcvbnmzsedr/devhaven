import AppKit
import SwiftUI
import DevHavenCore

struct WorkspaceGitHubPullsView: View {
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
                if viewModel.pulls.isEmpty, !viewModel.isLoading {
                    ContentUnavailableView(
                        "暂无 Pull Requests",
                        systemImage: "arrow.triangle.pull",
                        description: Text("当前仓库没有符合条件的 Pull Request。")
                    )
                    .foregroundStyle(NativeTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    ForEach(viewModel.pulls) { pull in
                        WorkspaceGitHubPullRowView(
                            pull: pull,
                            isSelected: viewModel.selectedPullNumber == pull.number,
                            onSelect: { viewModel.selectPull(number: pull.number) }
                        )
                        .contextMenu {
                            Button("在 GitHub 中打开") {
                                openURL(pull.url)
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
                WorkspaceGitHubListLoadingOverlay(title: "正在刷新 Pull Requests…")
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if viewModel.isLoadingDetail {
            ProgressView("正在加载 PR 详情…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NativeTheme.window)
        } else if let detailErrorMessage = viewModel.detailErrorMessage {
            ContentUnavailableView(
                "PR 详情加载失败",
                systemImage: "exclamationmark.triangle",
                description: Text(detailErrorMessage)
            )
            .foregroundStyle(NativeTheme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NativeTheme.window)
        } else if let detail = viewModel.selectedPullDetail {
            WorkspaceGitHubPullDetailView(detail: detail)
        } else {
            ContentUnavailableView(
                "选择一个 Pull Request",
                systemImage: "arrow.triangle.pull",
                description: Text("从左侧列表中选择一个 PR 查看详情。")
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
