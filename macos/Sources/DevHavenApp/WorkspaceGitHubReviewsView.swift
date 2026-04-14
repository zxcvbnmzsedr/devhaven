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
        VStack(spacing: 0) {
            reviewListHeader

            Rectangle()
                .fill(NativeTheme.border)
                .frame(height: 1)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
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
            }
        }
        .background(NativeTheme.surface)
        .overlay {
            if viewModel.isLoading {
                WorkspaceGitHubListLoadingOverlay(title: "正在刷新 Reviews…")
            }
        }
    }

    private var reviewListHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text("Reviews")
                    .font(.headline)
                    .foregroundStyle(NativeTheme.textPrimary)

                Text("\(viewModel.reviewRequests.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NativeTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(NativeTheme.elevated)
                    .clipShape(.capsule)

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                filterBadge(title: viewModel.reviewFilter.state.title, tint: reviewFilterTint)
                filterBadge(title: viewModel.reviewFilter.scope.title, tint: NativeTheme.textSecondary)

                if let searchText = trimmedReviewSearchText {
                    filterBadge(title: "搜索: \(searchText)", tint: NativeTheme.textSecondary)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(NativeTheme.sidebar)
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
            WorkspaceGitHubPullDetailView(
                viewModel: viewModel,
                detail: detail,
                actionMode: .review
            )
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

    private var reviewFilterTint: Color {
        switch viewModel.reviewFilter.state {
        case .open:
            return .green
        case .closed:
            return .purple
        }
    }

    private var trimmedReviewSearchText: String? {
        let trimmed = viewModel.reviewFilter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func filterBadge(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.28), lineWidth: 1)
            )
            .clipShape(.capsule)
    }
}
