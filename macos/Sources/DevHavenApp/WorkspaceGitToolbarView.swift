import SwiftUI
import DevHavenCore

struct WorkspaceGitToolbarView: View {
    @Bindable var viewModel: WorkspaceGitViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    ForEach(WorkspaceGitSection.allCases) { section in
                        Button {
                            viewModel.setSection(section)
                        } label: {
                            Text(section.title)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(viewModel.section == section ? NativeTheme.textPrimary : NativeTheme.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(viewModel.section == section ? NativeTheme.accent.opacity(0.22) : Color.clear)
                                .clipShape(.capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if viewModel.section == .log {
                    scopeChip(
                        title: "范围",
                        value: viewModel.selectedRevisionDisplayTitle,
                        accent: viewModel.selectedRevisionFilter != nil
                    )
                }

                Spacer(minLength: 8)

                if viewModel.section == .log {
                    filterControls
                }

                Button("清空筛选") {
                    viewModel.clearFilters()
                }
                .buttonStyle(.bordered)
                .disabled(
                    viewModel.searchQuery.isEmpty
                    && viewModel.debouncedSearchQuery.isEmpty
                    && viewModel.selectedRevisionFilter == nil
                    && viewModel.selectedAuthorFilter == nil
                    && viewModel.selectedDateFilter == .all
                    && viewModel.pathFilterQuery.isEmpty
                )

                Button("刷新") {
                    viewModel.refreshForCurrentSection()
                }
                .buttonStyle(.borderedProminent)
                .tint(NativeTheme.accent)
            }

            Text(viewModel.repositoryContext.repositoryPath)
                .font(.caption2.monospaced())
                .foregroundStyle(NativeTheme.textSecondary)
                .textSelection(.enabled)
                .lineLimit(1)
        }
    }

    private func scopeChip(title: String, value: String, accent: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(NativeTheme.textSecondary)
            Text(value)
                .foregroundStyle(NativeTheme.textPrimary)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(accent ? NativeTheme.accent.opacity(0.18) : NativeTheme.elevated)
        .clipShape(.capsule)
    }

    private var filterControls: some View {
        HStack(spacing: 8) {
            searchControl
            authorMenu
            dateMenu
            pathFilterField
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(NativeTheme.elevated)
        .clipShape(.rect(cornerRadius: 10))
        .frame(maxWidth: 540)
    }

    private var searchControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(NativeTheme.textSecondary)
            TextField(
                "搜索提交主题 / SHA",
                text: Binding(
                    get: { viewModel.searchQuery },
                    set: { viewModel.updateSearchQuery($0) }
                )
            )
            .textFieldStyle(.plain)
            .foregroundStyle(NativeTheme.textPrimary)
        }
    }

    private var authorMenu: some View {
        Menu {
            Button("全部作者") {
                viewModel.selectAuthorFilter(nil)
            }
            Divider()
            ForEach(availableAuthors, id: \.self) { author in
                Button(author) {
                    viewModel.selectAuthorFilter(author)
                }
            }
        } label: {
            scopeChip(
                title: "作者",
                value: viewModel.selectedAuthorFilter ?? "全部作者",
                accent: viewModel.selectedAuthorFilter != nil
            )
        }
    }

    private var dateMenu: some View {
        Menu {
            ForEach(WorkspaceGitDateFilter.allCases) { filter in
                Button(filter.title) {
                    viewModel.selectDateFilter(filter)
                }
            }
        } label: {
            scopeChip(
                title: "时间",
                value: viewModel.selectedDateFilter.title,
                accent: viewModel.selectedDateFilter != .all
            )
        }
    }

    private var pathFilterField: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(NativeTheme.textSecondary)
            TextField("路径过滤",
                text: Binding(
                    get: { viewModel.pathFilterQuery },
                    set: { viewModel.updatePathFilterQuery($0) }
                )
            )
            .textFieldStyle(.plain)
            .foregroundStyle(NativeTheme.textPrimary)
        }
        .frame(maxWidth: 160)
    }

    private var availableAuthors: [String] {
        Array(Set(viewModel.logSnapshot.commits.map(\.authorName))).sorted()
    }
}
