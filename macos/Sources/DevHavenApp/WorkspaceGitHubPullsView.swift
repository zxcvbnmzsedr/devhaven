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
        VStack(spacing: 0) {
            pullListHeader

            Rectangle()
                .fill(NativeTheme.border)
                .frame(height: 1)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
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
            }
        }
        .background(NativeTheme.surface)
        .overlay {
            if viewModel.isLoading {
                WorkspaceGitHubListLoadingOverlay(title: "正在刷新 Pull Requests…")
            }
        }
    }

    private var pullListHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text("Pull requests")
                    .font(.headline)
                    .foregroundStyle(NativeTheme.textPrimary)

                Text("\(viewModel.pulls.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NativeTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(NativeTheme.elevated)
                    .clipShape(.capsule)

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                filterBadge(title: viewModel.pullFilter.state.title, tint: pullFilterTint)

                if let searchText = trimmedPullSearchText {
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
            WorkspaceGitHubPullDetailView(
                viewModel: viewModel,
                detail: detail,
                actionMode: .pull
            )
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

    private var pullFilterTint: Color {
        switch viewModel.pullFilter.state {
        case .open:
            return .green
        case .closed:
            return .red
        case .merged:
            return .purple
        case .all:
            return NativeTheme.textSecondary
        }
    }

    private var trimmedPullSearchText: String? {
        let trimmed = viewModel.pullFilter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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
