import SwiftUI
import DevHavenCore

struct WorkspaceGitHubToolbarView: View {
    @Bindable var viewModel: WorkspaceGitHubViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Picker("Section", selection: sectionBinding) {
                    ForEach(WorkspaceGitHubSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                sectionStatePicker

                Spacer(minLength: 0)

                if viewModel.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("刷新中…")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NativeTheme.textPrimary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(NativeTheme.elevated)
                    .clipShape(.capsule)
                    .overlay(
                        Capsule()
                            .stroke(NativeTheme.border, lineWidth: 1)
                    )
                }

                if viewModel.isMutating {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(viewModel.activeMutation.map(gitHubMutationStatusText) ?? "正在执行 GitHub 操作…")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NativeTheme.textPrimary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(NativeTheme.elevated)
                    .clipShape(.capsule)
                    .overlay(
                        Capsule()
                            .stroke(NativeTheme.border, lineWidth: 1)
                    )
                }

                Button("刷新") {
                    viewModel.refresh()
                }
                .buttonStyle(.borderedProminent)
                .tint(NativeTheme.accent)
            }

            HStack(spacing: 12) {
                TextField(searchPrompt, text: searchBinding)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        viewModel.refresh()
                    }

                statusBadge
            }

            Text(viewModel.displayRepositoryTitle)
                .font(.caption2.monospaced())
                .foregroundStyle(NativeTheme.textSecondary)
                .lineLimit(1)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var sectionStatePicker: some View {
        switch viewModel.section {
        case .pulls:
            Picker("状态", selection: pullStateBinding) {
                ForEach(WorkspaceGitHubPullFilterState.allCases) { state in
                    Text(state.title).tag(state)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
        case .issues:
            Picker("状态", selection: issueStateBinding) {
                ForEach(WorkspaceGitHubIssueFilterState.allCases) { state in
                    Text(state.title).tag(state)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
        case .reviews:
            HStack(spacing: 8) {
                Picker("状态", selection: reviewStateBinding) {
                    ForEach(WorkspaceGitHubReviewFilterState.allCases) { state in
                        Text(state.title).tag(state)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)

                Picker("范围", selection: reviewScopeBinding) {
                    ForEach(WorkspaceGitHubReviewScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
            }
        }
    }

    private var searchBinding: Binding<String> {
        switch viewModel.section {
        case .pulls:
            Binding(
                get: { viewModel.pullFilter.searchText },
                set: { newValue in
                    var filter = viewModel.pullFilter
                    filter.searchText = newValue
                    viewModel.pullFilter = filter
                }
            )
        case .issues:
            Binding(
                get: { viewModel.issueFilter.searchText },
                set: { newValue in
                    var filter = viewModel.issueFilter
                    filter.searchText = newValue
                    viewModel.issueFilter = filter
                }
            )
        case .reviews:
            Binding(
                get: { viewModel.reviewFilter.searchText },
                set: { newValue in
                    var filter = viewModel.reviewFilter
                    filter.searchText = newValue
                    viewModel.reviewFilter = filter
                }
            )
        }
    }

    private var pullStateBinding: Binding<WorkspaceGitHubPullFilterState> {
        Binding(
            get: { viewModel.pullFilter.state },
            set: { newValue in
                guard viewModel.pullFilter.state != newValue else {
                    return
                }
                var filter = viewModel.pullFilter
                filter.state = newValue
                viewModel.pullFilter = filter
                viewModel.refresh()
            }
        )
    }

    private var issueStateBinding: Binding<WorkspaceGitHubIssueFilterState> {
        Binding(
            get: { viewModel.issueFilter.state },
            set: { newValue in
                guard viewModel.issueFilter.state != newValue else {
                    return
                }
                var filter = viewModel.issueFilter
                filter.state = newValue
                viewModel.issueFilter = filter
                viewModel.refresh()
            }
        )
    }

    private var reviewStateBinding: Binding<WorkspaceGitHubReviewFilterState> {
        Binding(
            get: { viewModel.reviewFilter.state },
            set: { newValue in
                guard viewModel.reviewFilter.state != newValue else {
                    return
                }
                var filter = viewModel.reviewFilter
                filter.state = newValue
                viewModel.reviewFilter = filter
                viewModel.refresh()
            }
        )
    }

    private var reviewScopeBinding: Binding<WorkspaceGitHubReviewScope> {
        Binding(
            get: { viewModel.reviewFilter.scope },
            set: { newValue in
                guard viewModel.reviewFilter.scope != newValue else {
                    return
                }
                var filter = viewModel.reviewFilter
                filter.scope = newValue
                viewModel.reviewFilter = filter
                viewModel.refresh()
            }
        )
    }

    private var searchPrompt: String {
        switch viewModel.section {
        case .pulls:
            return "按标题 / 作者 / 分支搜索 PR"
        case .issues:
            return "按标题 / 作者 / 标签搜索 Issue"
        case .reviews:
            return "按标题 / 作者 / 标签搜索 Review"
        }
    }

    private var sectionBinding: Binding<WorkspaceGitHubSection> {
        Binding(
            get: { viewModel.section },
            set: { viewModel.setSection($0) }
        )
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(authBadgeColor)
                .frame(width: 8, height: 8)
            Text(viewModel.authStatus.activeLogin ?? (viewModel.authStatus.isAuthenticated ? "已登录" : "未登录"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(NativeTheme.elevated)
        .overlay(
            Capsule()
                .stroke(NativeTheme.border, lineWidth: 1)
        )
        .clipShape(.capsule)
        .help(viewModel.authStatus.summaryText)
    }

    private var authBadgeColor: Color {
        switch viewModel.authStatus.state {
        case .unknown:
            return NativeTheme.textSecondary
        case .authenticated:
            return .green
        case .unauthenticated:
            return .orange
        }
    }
}
