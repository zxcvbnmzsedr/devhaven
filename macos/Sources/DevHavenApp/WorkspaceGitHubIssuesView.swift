import AppKit
import SwiftUI
import DevHavenCore

struct WorkspaceGitHubIssuesView: View {
    @Bindable var viewModel: WorkspaceGitHubViewModel
    let onCreateIssueWorktree: ((WorkspaceGitHubIssueDetail) throws -> Void)?
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
            issueListHeader

            Rectangle()
                .fill(NativeTheme.border)
                .frame(height: 1)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if viewModel.issues.isEmpty, !viewModel.isLoading {
                        ContentUnavailableView(
                            "暂无 Issues",
                            systemImage: "exclamationmark.circle",
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
            }
        }
        .background(NativeTheme.surface)
        .overlay {
            if viewModel.isLoading {
                WorkspaceGitHubListLoadingOverlay(title: "正在刷新 Issues…")
            }
        }
    }

    private var issueListHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text("Issues")
                    .font(.headline)
                    .foregroundStyle(NativeTheme.textPrimary)

                Text("\(viewModel.issues.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NativeTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(NativeTheme.elevated)
                    .clipShape(.capsule)

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                filterBadge(title: viewModel.issueFilter.state.title, tint: issueFilterTint)

                if let searchText = trimmedIssueSearchText {
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
            WorkspaceGitHubIssueDetailView(
                viewModel: viewModel,
                detail: detail,
                onCreateIssueWorktree: onCreateIssueWorktree
            )
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

    private var issueFilterTint: Color {
        switch viewModel.issueFilter.state {
        case .open:
            return .green
        case .closed:
            return .purple
        case .all:
            return NativeTheme.textSecondary
        }
    }

    private var trimmedIssueSearchText: String? {
        let trimmed = viewModel.issueFilter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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
