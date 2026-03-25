import SwiftUI
import DevHavenCore

struct WorkspaceGitIdeaLogBranchesPanelView: View {
    @Bindable var viewModel: WorkspaceGitLogViewModel
    @Binding var isVisible: Bool

    @State private var searchQuery = ""
    @State private var isLocalExpanded = true
    @State private var isRemoteExpanded = true
    @State private var isTagsExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .overlay(NativeTheme.border)

            searchField

            if hasVisibleItems {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let currentBranch {
                            currentBranchSection(currentBranch)
                        }

                        DisclosureGroup(isExpanded: $isLocalExpanded) {
                            branchGroup(localBranches, icon: "arrow.triangle.branch")
                                .padding(.top, 4)
                                .padding(.leading, 10)
                        } label: {
                            groupHeader(title: "本地", count: localBranches.count)
                        }
                        .tint(NativeTheme.textSecondary)

                        DisclosureGroup(isExpanded: $isRemoteExpanded) {
                            branchGroup(remoteBranches, icon: "icloud")
                                .padding(.top, 4)
                                .padding(.leading, 10)
                        } label: {
                            groupHeader(title: "远端", count: remoteBranches.count)
                        }
                        .tint(NativeTheme.textSecondary)

                        DisclosureGroup(isExpanded: $isTagsExpanded) {
                            VStack(spacing: 2) {
                                ForEach(tags) { tag in
                                    revisionButton(
                                        title: tag.name,
                                        subtitle: nil,
                                        icon: "tag",
                                        revision: "refs/tags/\(tag.name)"
                                    )
                                }
                            }
                            .padding(.top, 4)
                            .padding(.leading, 10)
                        } label: {
                            groupHeader(title: "标签", count: tags.count)
                        }
                        .tint(NativeTheme.textSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
            } else {
                ContentUnavailableView(
                    "没有匹配的引用",
                    systemImage: "magnifyingglass",
                    description: Text("尝试修改搜索词，或清空当前分支筛选。")
                )
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(NativeTheme.sidebar)
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("分支")
                    .font(.headline)
                    .foregroundStyle(NativeTheme.textPrimary)
                Text(selectedRevisionTitle)
                    .font(.caption2.monospaced())
                    .foregroundStyle(NativeTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if viewModel.selectedRevisionFilter != nil {
                Button("清空") {
                    clearRevisionFilter()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            Button {
                isVisible = false
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NativeTheme.textPrimary)
                    .frame(width: 24, height: 24)
                    .background(NativeTheme.elevated)
                    .clipShape(.rect(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(NativeTheme.surface)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(NativeTheme.textSecondary)
            TextField("搜索分支、远端或标签", text: $searchQuery)
                .textFieldStyle(.plain)
                .foregroundStyle(NativeTheme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(NativeTheme.elevated)
        .clipShape(.rect(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var localBranches: [WorkspaceGitBranchSnapshot] {
        filteredBranches(viewModel.logSnapshot.refs.localBranches)
    }

    private var remoteBranches: [WorkspaceGitBranchSnapshot] {
        filteredBranches(viewModel.logSnapshot.refs.remoteBranches)
    }

    private var tags: [WorkspaceGitTagSnapshot] {
        let query = normalizedSearchQuery
        guard let query else {
            return viewModel.logSnapshot.refs.tags
        }
        return viewModel.logSnapshot.refs.tags.filter { tag in
            matchesSearch(tag.name, query: query)
        }
    }

    private var currentBranch: WorkspaceGitBranchSnapshot? {
        guard let branch = viewModel.logSnapshot.refs.localBranches.first(where: \.isCurrent) else {
            return nil
        }
        guard let query = normalizedSearchQuery else {
            return branch
        }
        return matchesSearch(branch.name, query: query) ? branch : nil
    }

    private var hasVisibleItems: Bool {
        currentBranch != nil || !localBranches.isEmpty || !remoteBranches.isEmpty || !tags.isEmpty
    }

    private var normalizedSearchQuery: String? {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.localizedLowercase
    }

    private var selectedRevisionTitle: String {
        guard let revision = viewModel.selectedRevisionFilter else {
            return "全部提交"
        }
        let prefixes = ["refs/heads/", "refs/remotes/", "refs/tags/"]
        for prefix in prefixes where revision.hasPrefix(prefix) {
            return String(revision.dropFirst(prefix.count))
        }
        return revision
    }

    private func clearRevisionFilter() {
        viewModel.selectRevisionFilter(nil)
    }

    private func filteredBranches(_ branches: [WorkspaceGitBranchSnapshot]) -> [WorkspaceGitBranchSnapshot] {
        guard let query = normalizedSearchQuery else {
            return branches
        }
        return branches.filter { branch in
            matchesSearch(branch.name, query: query) || matchesSearch(branch.fullName, query: query)
        }
    }

    private func matchesSearch(_ value: String, query: String) -> Bool {
        value.localizedLowercase.contains(query)
    }

    private func currentBranchSection(_ branch: WorkspaceGitBranchSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("当前分支")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textSecondary)
            revisionButton(
                title: branch.name,
                subtitle: trackingSubtitle(for: branch),
                icon: "star.fill",
                revision: branch.fullName
            )
        }
    }

    private func groupHeader(title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textPrimary)
            Text(String(count))
                .font(.caption2.monospaced())
                .foregroundStyle(NativeTheme.textSecondary)
        }
    }

    private func branchGroup(_ branches: [WorkspaceGitBranchSnapshot], icon: String) -> some View {
        VStack(spacing: 2) {
            if branches.isEmpty {
                Text("暂无")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            } else {
                ForEach(branches) { branch in
                    revisionButton(
                        title: branch.name,
                        subtitle: branch.isCurrent ? "当前分支" : trackingSubtitle(for: branch),
                        icon: branch.isCurrent ? "star.fill" : icon,
                        revision: branch.fullName
                    )
                }
            }
        }
    }

    private func trackingSubtitle(for branch: WorkspaceGitBranchSnapshot) -> String? {
        if let upstream = branch.upstream, !upstream.isEmpty {
            return upstream
        }
        return branch.hash
    }

    private func revisionButton(
        title: String,
        subtitle: String?,
        icon: String,
        revision: String
    ) -> some View {
        let isSelected = viewModel.selectedRevisionFilter == revision
        return Button {
            viewModel.selectRevisionFilter(isSelected ? nil : revision)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(isSelected ? NativeTheme.accent : NativeTheme.textSecondary)
                    .frame(width: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout)
                        .foregroundStyle(NativeTheme.textPrimary)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(NativeTheme.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? NativeTheme.accent.opacity(0.16) : Color.clear)
            .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
