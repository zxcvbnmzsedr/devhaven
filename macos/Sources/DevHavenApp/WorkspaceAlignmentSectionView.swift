import SwiftUI
import DevHavenCore

struct WorkspaceAlignmentSectionView: View {
    let groups: [WorkspaceAlignmentGroupProjection]
    let onRequestCreateWorkspace: () -> Void
    let onOpenWorkspace: (String) -> Void
    let onRequestEditWorkspace: (String) -> Void
    let onRequestAddProjects: (String) -> Void
    let onRequestRecheck: (String) -> Void
    let onRequestApply: (String) -> Void
    let onRequestDelete: (String) -> Void
    let onOpenProject: (WorkspaceAlignmentMemberProjection) -> Void
    let onRequestApplyProject: (String, String) -> Void
    let onRequestRemoveProject: (String, String) -> Void

    @State private var expandedGroupIDs = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if groups.isEmpty {
                emptyState
            } else {
                ForEach(groups) { group in
                    WorkspaceAlignmentGroupCard(
                        group: group,
                        isExpanded: expandedGroupIDs.contains(group.id),
                        onOpenWorkspace: { onOpenWorkspace(group.id) },
                        onToggleExpanded: {
                            toggleExpanded(for: group.id)
                        },
                        onRequestEdit: { onRequestEditWorkspace(group.id) },
                        onRequestAddProjects: { onRequestAddProjects(group.id) },
                        onRequestRecheck: { onRequestRecheck(group.id) },
                        onRequestApply: { onRequestApply(group.id) },
                        onRequestDelete: { onRequestDelete(group.id) },
                        onOpenProject: onOpenProject,
                        onRequestApplyProject: { projectPath in
                            onRequestApplyProject(group.id, projectPath)
                        },
                        onRequestRemoveProject: { projectPath in
                            onRequestRemoveProject(group.id, projectPath)
                        }
                    )
                }
            }
        }
        .onAppear {
            if expandedGroupIDs.isEmpty {
                expandedGroupIDs = Set(groups.map(\.id))
            }
        }
        .onChange(of: groups.map(\.id)) { _, ids in
            expandedGroupIDs.formUnion(ids)
            expandedGroupIDs = expandedGroupIDs.intersection(Set(ids))
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("工作区")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textSecondary)
            Spacer(minLength: 0)
            Button(action: onRequestCreateWorkspace) {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NativeTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(NativeTheme.surface)
                    .clipShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help("新建工作区")
        }
        .padding(.horizontal, 2)
        .contextMenu {
            Button("新建工作区…", action: onRequestCreateWorkspace)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("暂无工作区")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textSecondary)
            Text("右键此区域或点击加号新建工作区，用统一规则对齐 branch / worktree。")
                .font(.caption2)
                .foregroundStyle(NativeTheme.textSecondary.opacity(0.8))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NativeTheme.elevated)
        .clipShape(.rect(cornerRadius: 10))
        .contextMenu {
            Button("新建工作区…", action: onRequestCreateWorkspace)
        }
    }

    private func toggleExpanded(for groupID: String) {
        if expandedGroupIDs.contains(groupID) {
            expandedGroupIDs.remove(groupID)
        } else {
            expandedGroupIDs.insert(groupID)
        }
    }
}

private struct WorkspaceAlignmentGroupCard: View {
    let group: WorkspaceAlignmentGroupProjection
    let isExpanded: Bool
    let onOpenWorkspace: () -> Void
    let onToggleExpanded: () -> Void
    let onRequestEdit: () -> Void
    let onRequestAddProjects: () -> Void
    let onRequestRecheck: () -> Void
    let onRequestApply: () -> Void
    let onRequestDelete: () -> Void
    let onOpenProject: (WorkspaceAlignmentMemberProjection) -> Void
    let onRequestApplyProject: (String) -> Void
    let onRequestRemoveProject: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: onToggleExpanded) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NativeTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(NativeTheme.surface)
                        .clipShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button(action: onOpenWorkspace) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.definition.name)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(NativeTheme.textPrimary)
                                .lineLimit(1)
                            Text(group.branchMetadataText)
                                .font(.caption2)
                                .foregroundStyle(NativeTheme.textSecondary.opacity(0.85))
                                .lineLimit(1)
                            Text(group.summaryText)
                                .font(.caption2)
                                .foregroundStyle(NativeTheme.textSecondary.opacity(0.85))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "terminal")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NativeTheme.accent)
                            .frame(width: 24, height: 24)
                            .background(NativeTheme.surface.opacity(0.8))
                            .clipShape(.rect(cornerRadius: 7))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NativeTheme.elevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(NativeTheme.border.opacity(0.5), lineWidth: 1)
                    )
                    .clipShape(.rect(cornerRadius: 10))
                    .contentShape(.rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .contextMenu {
                Button("进入工作区", action: onOpenWorkspace)
                Divider()
                Button("编辑工作区…", action: onRequestEdit)
                Button("添加项目…", action: onRequestAddProjects)
                Divider()
                Button("重新检查状态", action: onRequestRecheck)
                Button("应用工作区规则", action: onRequestApply)
                Divider()
                Button("删除工作区", role: .destructive, action: onRequestDelete)
            }

            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(group.members) { member in
                        WorkspaceAlignmentMemberRow(
                            group: group,
                            member: member,
                            onOpenProject: { onOpenProject(member) },
                            onRequestApply: { onRequestApplyProject(member.projectPath) },
                            onRequestRemove: { onRequestRemoveProject(member.projectPath) }
                        )
                    }
                }
                .padding(.leading, 12)
            }
        }
    }
}

private struct WorkspaceAlignmentMemberRow: View {
    let group: WorkspaceAlignmentGroupProjection
    let member: WorkspaceAlignmentMemberProjection
    let onOpenProject: () -> Void
    let onRequestApply: () -> Void
    let onRequestRemove: () -> Void

    var body: some View {
        Button(action: onOpenProject) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(NativeTheme.textSecondary.opacity(0.5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(member.alias)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NativeTheme.textPrimary)
                        .lineLimit(1)
                    Text("\(member.projectName) · \(member.branchLabel)")
                        .font(.caption2)
                        .foregroundStyle(NativeTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(member.status.displayText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(NativeTheme.border.opacity(0.4), lineWidth: 1)
            )
            .clipShape(.rect(cornerRadius: 7))
            .contentShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(member.status.detailText(targetBranch: member.targetBranch) ?? member.openTarget.path)
        .contextMenu {
            Button("打开项目", action: onOpenProject)
            Button("重新应用工作区规则", action: onRequestApply)
            Button("从工作区移除", role: .destructive, action: onRequestRemove)
        }
    }

    private var statusColor: Color {
        switch member.status {
        case .aligned:
            NativeTheme.accent
        case .currentBranch, .branchMissing, .worktreeMissing:
            NativeTheme.warning
        case .checking, .applying:
            NativeTheme.textSecondary
        case .applyFailed, .checkFailed:
            NativeTheme.danger
        }
    }
}
