import SwiftUI
import DevHavenCore

struct WorkspaceGitIdeaLogToolbarView: View {
    @Bindable var viewModel: WorkspaceGitLogViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                searchField
                authorFilterMenu
                dateFilterMenu
                pathFilterField

                Spacer(minLength: 8)

                Button("刷新") {
                    viewModel.refresh()
                }
                .buttonStyle(.borderedProminent)
                .tint(NativeTheme.accent)
            }

            Text(viewModel.repositoryContext.repositoryPath)
                .font(.caption2.monospaced())
                .foregroundStyle(NativeTheme.textSecondary)
                .lineLimit(1)
                .textSelection(.enabled)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(NativeTheme.textSecondary)
            TextField(
                "搜索提交、哈希或消息",
                text: Binding(
                    get: { viewModel.searchQuery },
                    set: { viewModel.updateSearchQuery($0) }
                )
            )
            .textFieldStyle(.plain)
            .foregroundStyle(NativeTheme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: 260)
        .background(NativeTheme.elevated)
        .clipShape(.rect(cornerRadius: 10))
    }

    private var authorFilterMenu: some View {
        Menu {
            Button("全部作者") {
                viewModel.selectAuthorFilter(nil)
            }
            Divider()
            ForEach(viewModel.availableAuthors, id: \.self) { author in
                Button(author) {
                    viewModel.selectAuthorFilter(author)
                }
            }
        } label: {
            filterChip(title: "作者", value: viewModel.selectedAuthorFilter ?? "全部作者")
        }
    }

    private var dateFilterMenu: some View {
        Menu {
            ForEach(WorkspaceGitDateFilter.allCases) { filter in
                Button(filter.title) {
                    viewModel.selectDateFilter(filter)
                }
            }
        } label: {
            filterChip(title: "日期", value: viewModel.selectedDateFilter.title)
        }
    }

    private var pathFilterField: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(NativeTheme.textSecondary)
            TextField(
                "路径过滤",
                text: Binding(
                    get: { viewModel.pathFilterQuery },
                    set: { viewModel.updatePathFilterQuery($0) }
                )
            )
            .textFieldStyle(.plain)
            .foregroundStyle(NativeTheme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: 180)
        .background(NativeTheme.elevated)
        .clipShape(.rect(cornerRadius: 10))
    }

    private func filterChip(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(NativeTheme.textSecondary)
            Text(value)
                .foregroundStyle(NativeTheme.textPrimary)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(NativeTheme.elevated)
        .clipShape(.capsule)
    }
}
