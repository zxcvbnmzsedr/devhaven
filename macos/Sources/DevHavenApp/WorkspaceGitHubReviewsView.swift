import AppKit
import SwiftUI
import DevHavenCore

struct WorkspaceGitHubReviewsView: View {
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
                if viewModel.reviewRequests.isEmpty, !viewModel.isLoading {
                    ContentUnavailableView(
                        "暂无 Reviews",
                        systemImage: "person.badge.key",
                        description: Text("当前仓库没有请求你评审的 Pull Request。")
                    )
                    .foregroundStyle(NativeTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    ForEach(viewModel.reviewRequests) { review in
                        WorkspaceGitHubReviewRowView(
                            review: review,
                            isSelected: viewModel.selectedPullNumber == review.number,
                            onSelect: { viewModel.selectPull(number: review.number) }
                        )
                        .contextMenu {
                            Button("在 GitHub 中打开") {
                                openURL(review.url)
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
                WorkspaceGitHubListLoadingOverlay(title: "正在刷新 Reviews…")
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if viewModel.isLoadingDetail {
            ProgressView("正在加载 Review 详情…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NativeTheme.window)
        } else if let detailErrorMessage = viewModel.detailErrorMessage {
            ContentUnavailableView(
                "Review 详情加载失败",
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
                "选择一个 Review",
                systemImage: "person.badge.key",
                description: Text("从左侧列表中选择一个待评审的 PR。")
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
