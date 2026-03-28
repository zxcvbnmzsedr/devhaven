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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NativeTheme.accent)
                Text("暂无工作区")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NativeTheme.textPrimary)
            }

            Text("工作区是一个虚拟框，里面可以放多个项目，并统一对齐 branch / worktree。")
                .font(.caption2)
                .foregroundStyle(NativeTheme.textSecondary.opacity(0.85))

            WorkspaceAlignmentBadge(
                title: "点击加号新建第一个工作区",
                systemImage: "plus",
                tone: .neutral
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NativeTheme.elevated)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(NativeTheme.border.opacity(0.65), lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 12))
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

    private var outlineColor: Color {
        let metrics = group.summaryMetrics
        if metrics.failed > 0 {
            return NativeTheme.danger.opacity(0.55)
        }
        if metrics.processing > 0 || metrics.drifted > 0 {
            return NativeTheme.warning.opacity(0.45)
        }
        if metrics.aligned > 0 {
            return NativeTheme.accent.opacity(0.45)
        }
        return NativeTheme.border.opacity(0.75)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded {
                Rectangle()
                    .fill(NativeTheme.border.opacity(0.8))
                    .frame(height: 1)

                memberList
            }
        }
        .background(NativeTheme.elevated)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(outlineColor, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.16), value: isExpanded)
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
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
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
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.definition.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(NativeTheme.textPrimary)
                        .lineLimit(1)

                    WorkspaceAlignmentBadge(
                        title: group.definition.targetBranch,
                        systemImage: "arrow.triangle.branch",
                        tone: .neutral,
                        monospaced: true
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }

    private var memberList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if group.members.isEmpty {
                Text("右键工作区卡片即可添加项目，也可以在项目卡片里直接加入该工作区。")
                    .font(.caption2)
                    .foregroundStyle(NativeTheme.textSecondary.opacity(0.82))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(group.members.enumerated()), id: \.element.id) { index, member in
                        if index > 0 {
                            Rectangle()
                                .fill(NativeTheme.border.opacity(0.6))
                                .frame(height: 1)
                                .padding(.horizontal, 12)
                        }

                        WorkspaceAlignmentMemberRow(
                            member: member,
                            onOpenProject: { onOpenProject(member) },
                            onRequestApply: { onRequestApplyProject(member.projectPath) },
                            onRequestRemove: { onRequestRemoveProject(member.projectPath) }
                        )
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 6)
            }
        }
    }
}

private struct WorkspaceAlignmentMemberRow: View {
    let member: WorkspaceAlignmentMemberProjection
    let onOpenProject: () -> Void
    let onRequestApply: () -> Void
    let onRequestRemove: () -> Void

    @State private var isHovering = false

    private var statusTone: WorkspaceAlignmentBadgeTone {
        switch member.status {
        case .aligned:
            .accent
        case .currentBranch, .branchMissing, .worktreeMissing:
            .warning
        case .checking, .applying:
            .neutral
        case .applyFailed, .checkFailed:
            .danger
        }
    }

    private var titleText: String {
        member.alias
    }

    private var subtitleText: String {
        var segments: [String] = []
        if member.projectName != member.alias {
            segments.append(member.projectName)
        }
        segments.append(openTargetText)
        return segments.joined(separator: " · ")
    }

    private var openTargetText: String {
        switch member.openTarget {
        case let .project(projectPath):
            return URL(fileURLWithPath: projectPath).lastPathComponent
        case let .worktree(_, worktreePath):
            return URL(fileURLWithPath: worktreePath).lastPathComponent
        }
    }

    var body: some View {
        Button(action: onOpenProject) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: memberIconName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text(titleText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NativeTheme.textPrimary)
                        .lineLimit(1)

                    Text(subtitleText)
                        .font(.caption2)
                        .foregroundStyle(NativeTheme.textSecondary.opacity(0.88))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 6) {
                    WorkspaceAlignmentBadge(
                        title: member.status.displayText,
                        tone: statusTone
                    )

                    if !member.branchLabel.isEmpty {
                        WorkspaceAlignmentBadge(
                            title: member.branchLabel,
                            systemImage: "arrow.triangle.branch",
                            tone: .neutral,
                            monospaced: true
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? NativeTheme.surface.opacity(0.92) : Color.clear)
            .clipShape(.rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .padding(.horizontal, 6)
        .help(member.status.detailText(targetBranch: member.targetBranch) ?? member.openTarget.path)
        .contextMenu {
            Button("打开项目", action: onOpenProject)
            Button("重新应用工作区规则", action: onRequestApply)
            Button("从工作区移除", role: .destructive, action: onRequestRemove)
        }
    }

    private var memberIconName: String {
        switch member.openTarget {
        case .project:
            "folder"
        case .worktree:
            "square.split.bottomrightquarter"
        }
    }

    private var iconColor: Color {
        switch member.openTarget {
        case .project:
            NativeTheme.textSecondary.opacity(0.9)
        case .worktree:
            NativeTheme.accent.opacity(0.95)
        }
    }
}

private enum WorkspaceAlignmentBadgeTone {
    case neutral
    case accent
    case warning
    case danger
}

private struct WorkspaceAlignmentBadge: View {
    let title: String
    var systemImage: String? = nil
    var tone: WorkspaceAlignmentBadgeTone = .neutral
    var monospaced = false

    private var backgroundColor: Color {
        switch tone {
        case .neutral:
            NativeTheme.surface.opacity(0.95)
        case .accent:
            NativeTheme.accent.opacity(0.18)
        case .warning:
            NativeTheme.warning.opacity(0.18)
        case .danger:
            NativeTheme.danger.opacity(0.18)
        }
    }

    private var foregroundColor: Color {
        switch tone {
        case .neutral:
            NativeTheme.textSecondary
        case .accent:
            NativeTheme.accent
        case .warning:
            NativeTheme.warning
        case .danger:
            NativeTheme.danger
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }

            Text(title)
                .font(monospaced ? .caption2.monospaced() : .caption2.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .clipShape(.rect(cornerRadius: 6))
    }
}
