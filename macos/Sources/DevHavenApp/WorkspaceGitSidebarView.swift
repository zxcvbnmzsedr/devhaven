import SwiftUI
import DevHavenCore

struct WorkspaceGitSidebarView: View {
    @Bindable var viewModel: WorkspaceGitViewModel
    let showsExecutionWorktreeSelector: Bool

    @State private var isLocalExpanded = true
    @State private var isRemoteExpanded = true
    @State private var isTagsExpanded = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if showsExecutionWorktreeSelector {
                    executionWorktreeSection
                }

                if viewModel.section == .log {
                    logRefsTree
                } else {
                    refsSummary
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
    }

    private var executionWorktreeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("执行工作树")
            VStack(spacing: 4) {
                ForEach(viewModel.executionWorktrees) { worktree in
                    Button {
                        viewModel.selectExecutionWorktree(worktree.path)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: worktree.isRootProject ? "shippingbox" : "point.3.connected.trianglepath.dotted")
                                .font(.caption)
                                .foregroundStyle(NativeTheme.textSecondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(worktree.displayName)
                                    .font(.callout)
                                    .foregroundStyle(NativeTheme.textPrimary)
                                    .lineLimit(1)
                                if let branchName = worktree.branchName {
                                    Text(branchName)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(NativeTheme.textSecondary)
                                }
                            }
                            Spacer(minLength: 8)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selectionBackground(isSelected: viewModel.selectedExecutionWorktree?.path == worktree.path))
                        .clipShape(.rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isMutating)
                }
            }
        }
    }

    private var logRefsTree: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("引用")

            if let currentBranch = viewModel.logSnapshot.refs.localBranches.first(where: \.isCurrent) {
                revisionButton(
                    title: "HEAD（当前分支）",
                    subtitle: currentBranch.name,
                    icon: "arrow.triangle.branch",
                    revision: "HEAD",
                    isSelected: viewModel.selectedRevisionFilter == "HEAD"
                )
            }

            DisclosureGroup("本地", isExpanded: $isLocalExpanded) {
                VStack(spacing: 2) {
                    ForEach(viewModel.logSnapshot.refs.localBranches) { branch in
                        revisionButton(
                            title: branch.name,
                            subtitle: branch.isCurrent ? "当前分支" : branch.shortTrackingSubtitle,
                            icon: branch.isCurrent ? "star.fill" : "arrow.triangle.branch",
                            revision: branch.fullName,
                            isSelected: viewModel.selectedRevisionFilter == branch.fullName
                        )
                    }
                }
                .padding(.top, 4)
                .padding(.leading, 10)
            }
            .tint(NativeTheme.textSecondary)

            DisclosureGroup("远端", isExpanded: $isRemoteExpanded) {
                VStack(spacing: 2) {
                    ForEach(viewModel.logSnapshot.refs.remoteBranches) { branch in
                        revisionButton(
                            title: branch.name,
                            subtitle: nil,
                            icon: "icloud",
                            revision: branch.fullName,
                            isSelected: viewModel.selectedRevisionFilter == branch.fullName
                        )
                    }
                }
                .padding(.top, 4)
                .padding(.leading, 10)
            }
            .tint(NativeTheme.textSecondary)

            DisclosureGroup("标签", isExpanded: $isTagsExpanded) {
                VStack(spacing: 2) {
                    ForEach(viewModel.logSnapshot.refs.tags) { tag in
                        revisionButton(
                            title: tag.name,
                            subtitle: nil,
                            icon: "tag",
                            revision: "refs/tags/\(tag.name)",
                            isSelected: viewModel.selectedRevisionFilter == "refs/tags/\(tag.name)"
                        )
                    }
                }
                .padding(.top, 4)
                .padding(.leading, 10)
            }
            .tint(NativeTheme.textSecondary)
        }
        .font(.callout)
    }

    private var refsSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("引用概览")
            refSummaryGroup(title: "本地", items: viewModel.logSnapshot.refs.localBranches.map(\.name))
            refSummaryGroup(title: "远端", items: viewModel.logSnapshot.refs.remoteBranches.map(\.name))
            refSummaryGroup(title: "标签", items: viewModel.logSnapshot.refs.tags.map(\.name))
        }
    }

    private func revisionButton(
        title: String,
        subtitle: String?,
        icon: String,
        revision: String,
        isSelected: Bool
    ) -> some View {
        Button {
            viewModel.selectRevisionFilter(revision)
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
            .background(selectionBackground(isSelected: isSelected))
            .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func refSummaryGroup(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textSecondary)
            if items.isEmpty {
                Text("暂无")
                    .font(.caption2)
                    .foregroundStyle(NativeTheme.textSecondary)
            } else {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.caption.monospaced())
                        .foregroundStyle(NativeTheme.textPrimary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(NativeTheme.textSecondary)
    }

    private func selectionBackground(isSelected: Bool) -> AnyShapeStyle {
        AnyShapeStyle(isSelected ? NativeTheme.accent.opacity(0.20) : Color.clear)
    }
}

private extension WorkspaceGitBranchSnapshot {
    var shortTrackingSubtitle: String? {
        if let upstream, !upstream.isEmpty {
            return upstream
        }
        return nil
    }
}
